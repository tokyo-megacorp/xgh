---
name: xgh:retrieve
description: >
  Headless retrieval loop. Scans configured Slack channels, follows links 1-hop to
  Jira/Confluence/GitHub/Figma, stashes raw content to ~/.xgh/inbox/, and detects urgency.
  Invoked via /xgh-retrieve command by CronCreate every 5 minutes.
type: rigid
triggers:
  - when invoked via /xgh-retrieve command
  - when invoked by CronCreate (session scheduler, always-on)
mcp_dependencies:
  - mcp__claude_ai_Slack__slack_read_channel
  - mcp__claude_ai_Atlassian__getJiraIssue
  - mcp__claude_ai_Atlassian__getConfluencePage
  - mcp__claude_ai_Figma__get_metadata
---

## Architecture Note

Retrieval operates in three lanes:

1. **CLI/API providers (automated)** — `retrieve-all.sh` runs `mode: cli/api` provider `fetch.sh`
   scripts via CronCreate. Pure bash, no Claude needed. 1 CronCreate turn.

2. **MCP providers (automated)** — A lightweight CronCreate prompt calls MCP tools for
   `mode: mcp` providers (OAuth-gated services). 2-3 CronCreate turns.

3. **Interactive** — `/xgh-retrieve` invoked manually triggers the full Claude-powered skill
   for one-off deep scans or when providers aren't configured yet.

The automated paths (1 + 2) handle 95% of retrieval. The interactive path is a fallback
providing richer analysis (urgency scoring, thread following, link enrichment).


# xgh:retrieve — Retrieval Loop

Invoked by CronCreate:
```
  prompt: /xgh-retrieve
  cron: */5 * * * *
  recurring: true
```


## Guard checks (run before anything else)

1. If `~/.xgh/ingest.yaml` does not exist: `echo "ERROR: ~/.xgh/ingest.yaml not found. Run /xgh-track."` and exit.
2. Check daily token cap: source `~/.xgh/lib/usage-tracker.sh`; if `xgh_usage_check_cap` returns non-zero, log and exit.
3. Check quiet hours/days from `schedule.quiet_hours` and `schedule.quiet_days`. If now is in a quiet period, exit silently.

## Step 0 — Detect project scope

Determine which projects to retrieve for:

1. Run `bash ~/.xgh/scripts/detect-project.sh` and read `XGH_PROJECT` and `XGH_PROJECT_SCOPE`
2. If `XGH_PROJECT` is non-empty:
   - Log: `Scoped to project: $XGH_PROJECT (+ dependencies: ...)`
   - In Step 1, filter `ingest.yaml` projects to only those in `XGH_PROJECT_SCOPE`
3. If `XGH_PROJECT` is empty:
   - Log: `All-projects mode (no git project detected)`
   - Proceed with all active projects (current behavior)

This scoping applies to all subsequent steps — Slack channels, link following, GitHub scans,
and inbox stashing are limited to the in-scope projects only.

## Step 1 — Load config and cursors

Read `~/.xgh/ingest.yaml`. Collect projects where `status: active`. If `XGH_PROJECT_SCOPE` is set, filter to only projects in that scope.

Read `~/.xgh/inbox/.cursors.json` (JSON: `{"#channel-name": "last_iso_timestamp"}`). If missing, initialize to `{}`.

## Step 2 — Scan Slack channels

> **Access level guard:** Before scanning, check `providers.slack.access` for this project (default: `read`). If `read`, only fetch data — never write back to Slack. If `ask` or `auto`, write actions (e.g., posting digests, reacting) may be performed in later steps.

For each active project, for each Slack channel in its `slack:` list:

1. Call `slack_read_channel` with the channel name
2. Filter messages newer than the cursor timestamp for that channel (or last `retriever.max_messages_per_channel` if no cursor)
3. For each message, score urgency (Step 4)
4. Stash all messages scoring ≥ `urgency.thresholds.log` (default 0 — everything)

**Rate limiting:** On 429 or timeout, back off (2s → 4s → 8s) up to `retriever.max_retries` times, then skip the channel and note it in the log.

**Thread reply pass** (runs after the main channel scan, for each channel):

After scanning new messages, perform a thread reply pass to catch replies on recently-active threads:

1. Call `slack_read_channel` again for the same channel with:
   - `oldest` = cursor minus `retriever.thread_lookback_hours` hours (default: 24) — to look back at recent threads
   - `latest` = cursor — so only messages older than the cursor (already-indexed ones) are returned
2. For each message returned that has a `latest_reply` field where `latest_reply > cursor`:
   - Call `slack_read_thread(channel_id, message_ts)` to fetch the full thread
   - Filter replies to only those with `ts > cursor` (new replies only)
   - Process each new reply through the urgency scoring pipeline (Step 4)
   - Stash as inbox items with `source_type: slack_thread`; include the parent message text as context in the stashed content
3. Count thread-reply items as additional items stashed in the Step 10 log line

> **Config:** `retriever.thread_lookback_hours` (default: `24`) controls how far back to look for threads with new replies.

> **Coverage note:** This pass covers threads whose parent is within the last `thread_lookback_hours`. Threads on older messages — including messages that had no replies when first seen — are handled by `xgh:deep-retrieve`, which runs hourly and scans the full `thread_lookback_days` window. Dedup between these two passes is filename-based: inbox filenames encode the reply `ts`, so a reply stashed here will not be re-stashed by the deep scan.

**Rate limiting:** Apply the same back-off rules (2s → 4s → 8s, up to `retriever.max_retries`) for this pass as for the main channel scan.

**Cursor update (per channel):** After each channel completes successfully (main scan + thread pass), update its cursor immediately:
```bash
bash scripts/update-cursor.sh "<channel-id>" "<latest-message-timestamp>"
```
This runs inside the per-channel loop — not deferred to Step 9 — so a mid-run failure on channel 3 does not roll back cursors for channels 1 and 2.

## Step 2b — MCP Provider Dispatch (generic)

For each provider in `~/.xgh/user_providers/` with `mode: mcp` in `provider.yaml`:

1. Read `provider.yaml` to get the `tools:` section and `cursor_strategy`. Accepted values:
   - `iso8601` — cursor is an ISO 8601 timestamp string; substitute into `{cursor}` param (used by Jira, Slack)
   - `offset` — cursor is an integer page/offset; increment after each page fetch
   - `id` — cursor is the ID (string or integer) of the last-seen item; substitute into `{cursor}` param
2. Read the cursor file (`~/.xgh/user_providers/<name>/cursor`) — if missing, use default lookback
3. For each tool role declared in `tools:`:
   - `channels` → Run channel scan pass (fetch messages since cursor for each configured channel)
   - `threads` → Run thread reply pass (for messages with latest_reply > cursor, fetch full thread)
   - `search` → Run search queries for mentions, keywords
   - `list` → Fetch items updated since cursor
   - `comments` → Fetch new comments on tracked items
   - `files` → Fetch recently modified files/designs
   - `alerts` → Fetch new errors/incidents
   - `feeds` → Fetch notification/activity stream
   - Other roles: call the declared MCP tool with cursor-substituted params
4. For each tool call:
   - Substitute `{cursor}` in params with the current cursor value
   - Call the MCP tool
   - Parse results into inbox items (standard YAML frontmatter + markdown body)
   - Write to `~/.xgh/inbox/` with dedup by filename
5. Update the cursor file with the timestamp of the most recent item
6. **Enrichment queue:** For any item that references a URL matching a known provider type (Jira, Confluence, GitHub, Figma) that is **not already in `~/.xgh/ingest.yaml`** for the project, add it to the enrichment queue (same format as Step 8). This mirrors the link-following enrichment in Step 3 for MCP-sourced content.

> **Enrichment TTL:** Items in `.enrichments.json` older than `enrichment.max_queue_age` (default: 48h) are discarded by the analyzer on its next run to prevent unbounded queue growth. If enrichment of a discovered URL is not completed within 48h, the item is not re-queued automatically.

This replaces the hardcoded per-service tool calls. The retrieve skill no longer needs to know
about specific services — it reads what tools are available from the provider config.

## Step 3 — Follow links 1-hop

> **Access level guard:** Before following links, check the relevant `providers.<type>.access` level for the target provider (jira, confluence, github, figma). If `read`, only fetch data. If `ask` or `auto`, write actions (e.g., transitioning Jira tickets, posting PR comments) may be performed in later steps.

For each message containing a URL, up to `retriever.max_links_to_follow` per cycle. If the cap is reached, log one line per skipped link to `~/.xgh/logs/retriever.log`:
```
[SKIPPED LINK] <url> — cap reached (max_links_to_follow=N) — source: <channel>/<ts>
```
Retry of skipped links is handled by `xgh:deep-retrieve` on its next hourly run.

| Link matches | Tool | Extract |
|---|---|---|
| Jira ticket (e.g. `PTECH-123`) | `getJiraIssue` | title, status, assignee, description, latest 3 comments |
| Confluence page URL | `getConfluencePage` | title, first 2000 chars of body, last modified |
| GitHub PR/issue URL | `Bash: gh pr view <url> --json title,state,body,reviews` | title, status, body excerpt |
| Figma URL | `get_metadata` | last modified, file name |

If a linked Jira key, Confluence space, or GitHub repo is **not already in `ingest.yaml`** for the project, add it to the enrichment queue (Step 7).

## Step 4 — Urgency scoring

For each message:

1. **Base score** — highest matching category from the table below
2. **Multipliers** — multiply all applicable factors together
3. **Composite** = `min(base × product_of_multipliers, 100)`
4. **Role relevance** — detect platform signals in message text + linked ticket labels/repo names:
   - matches `profile.platforms` → ×2.0
   - matches `profile.squad` → ×1.5
   - matches `profile.also_monitor` → ×1.0
   - other platform → ×0.3 | other squad → ×0.5
5. **Final** = `min(composite × relevance_multiplier, 100)`

**Base scores:**
- Blocker keywords (hotfix, release blocker, P0, rollback): 90
- Deadline pressure (EOD, code freeze, ship date): 80
- Scope change (requirement changed, pivot, new approach): 75
- Status change (revert, fallback): 70
- Decision (launch date shift, confirmed approach): 65
- Environment incident (restarting pods, broken in beta): 60
- Action request with @-mention: 50
- Cross-team dependency (team X is blocked): 45
- Risk mitigation (rollback plan, minimize risk): 40
- Status update (merged, deployed): 30
- Availability notice (OOO, partially off): 20

**Multipliers:**
- Contains `@here` or `@channel`: ×1.5
- Contains P0/critical/blocker: ×1.4
- Outside business hours (before 9am or after 6pm): ×1.3
- Contains "before we can go live" or similar: ×1.3
- Weekend message: ×1.3
- Thread with >10 replies: ×1.2
- >2 @-mentions: ×1.2
- Contains Jira or Confluence links: ×1.1

For `awaiting_my_reply`/`awaiting_their_reply` type items, apply aging boost:
- < 2h: +0 | 2–8h: +15 | 8–24h: +30 | 24–48h: +50 | 48h+: +70 (then cap at 100)

## Step 4b: Fast-path trigger evaluation

Evaluate triggers where urgency warrants immediate action — before analyze runs.

**Skip this step entirely if:**
- `~/.xgh/triggers.yaml` does not exist or has `enabled: false`
- `~/.xgh/triggers.yaml` has `fast_path: false`
- No `~/.xgh/triggers/*.yaml` files have `path: fast`

**Procedure:**

1. Read only triggers with `path: fast` from `~/.xgh/triggers/*.yaml`.
   Skip `source: local` and `source: schedule` triggers.
2. For each newly scored inbox item with `urgency_score >= 70`:
   For each fast-path trigger:
   a. **Match check:**
      - `source:` matches item's `source:` field
      - `when.urgency_score:` threshold — evaluate if specified (e.g., `>= 90`)
      - `match:` keyword patterns on item title/content (regex)
      - NOTE: `when.type:` is NOT checked — classification has not run yet
   b. **Cooldown + dedup check:** same logic as standard path (see xgh:trigger skill).
   c. **Execute steps:** same execution as standard path.
   d. **Update state.**
3. Log: `Fast-path triggers: N evaluated, K fired`

Fast-path triggers should use `when.match:` patterns and `when.urgency_score:` thresholds,
NOT `when.type:` (type is only available after analyze classification).

> **Note:** Items that also qualify for the critical-urgency interrupt (Step 7, score >= 80) will still be evaluated here — the two paths are independent.

## Step 5 — Detect awaiting-reply items

| Platform | Detection |
|---|---|
| Slack | User's `slack_id` in @mention; DM containing `?` or request language; `@here`/`@channel` in tracked channel |
| GitHub | PR review requested from user; comments on user's open PRs |
| Jira | Ticket assigned to user; user mentioned in comment |
| Confluence | @mention in page or comment |
| Figma | Comment @mention via `get_metadata` |

Tag each with `awaiting_direction: my_reply` or `their_reply`.

## Step 6 — Stash to inbox

Write one `.md` file per item to `~/.xgh/inbox/`:

**Filename:** `{YYYY-MM-DDThh-mm-ss}_{source_type}_{identifier}.md`
Example: `2026-03-15T14-30-00_slack_ptech-31204-eng_msg123.md`

**File content:**
```markdown
---
type: inbox_item
source_type: slack
source_channel: "#ptech-31204-engineering"
source_ts: 2026-03-15T14:30:00Z
project: passcode-feature
urgency_score: 75
raw_score: 142
processed: false
awaiting_direction: null
links_followed:
  - jira:PTECH-31204
---

[Raw message text]

---

## Linked content

### PTECH-31204: [Title]
Status: In Progress | Assignee: lucas
[Description excerpt, max 500 chars]
```

`raw_score` is the pre-cap composite value (base × multipliers × relevance, before the `min(..., 100)` clamp). It is **informational only** — do not use it for threshold comparisons. Its value is tied to the scoring formula at the time it was written; if multipliers change, stored `raw_score` values from older runs are not comparable.

## Step 7 — Handle critical urgency (score ≥ 80)

0. **Flush stale queue entries:** Before sending any DM, read `~/.xgh/logs/dm-queue.json` (if it exists). Discard any entries older than `notifications.max_queue_age` (default: 4h) — log them to `~/.xgh/logs/retriever.log` as `[DM EXPIRED]` but do not send them. Update `dm-queue.json` with only the remaining (non-expired) entries, and write `queue_flushed_at: <current-iso-timestamp>` to `~/.xgh/logs/last-dm.txt`.
1. Check `~/.xgh/logs/last-dm.txt` for last DM timestamp. If within `notifications.dm_cooldown` (default 15min), add to batch queue `~/.xgh/logs/dm-queue.json` instead.
2. If not in cooldown (or cooldown passed), send Slack DM to `profile.slack_id` via `slack_send_message`:
   ```
   🚨 xgh [score: N]: {one-line summary}
   Source: {channel or ticket ID}
   ```
   If `notifications.dm_batch: true`, include all queued items in one message.
3. Write `~/.xgh/inbox/.urgent` marker file (touch it).
4. Update `~/.xgh/logs/last-dm.txt` with current timestamp.

## Step 8 — Queue enrichments

If new external refs were discovered, write/append to `~/.xgh/inbox/.enrichments.json`:
```json
{
  "pending": [
    {"type": "jira", "key": "PTECH-456", "project": "passcode-feature", "discovered_from": "slack:#ptech-31204-engineering"}
  ]
}
```
If the file exists, merge into the `pending` array. The analyzer reads and clears this.

## Step 9 — Verify cursors

Cursors are updated per-channel inside Step 2. This step is a no-op for Slack channels.

For MCP providers (Step 2b), confirm each provider's cursor file was updated after its run. If a provider exited early due to an error, its cursor file should not have been advanced — this is the correct outcome and requires no remediation.

## Step 10 — Log completion

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: N channels, M items stashed, K urgent" \
  >> ~/.xgh/logs/retriever.log
source ~/.xgh/lib/usage-tracker.sh
xgh_usage_log "retriever" "$(actual turns used)" 0
```

## Output discipline

This skill runs in the main session turn (triggered by CronCreate or manually). To preserve context:

1. Never print raw inbox content, message bodies, or full API responses to the session.
2. **End every run with exactly one summary line:**
   ```
   Retrieve complete: <N> new items stashed, <M> critical, <K> channels scanned.
   ```

## Scheduler nudge (manual runs only)

If this skill was invoked manually (not by CronCreate), check after the summary line:

Call CronList and look for jobs with prompt `/xgh-retrieve` or `/xgh-analyze`.

If no active CronCreate jobs found, append:

```
⚠️ Running manually — scheduler is paused or not started.
   /xgh-schedule resume    (enable for this session and future sessions)
```
