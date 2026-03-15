---
name: xgh:ingest-retrieve
description: >
  Headless retrieval loop. Scans configured Slack channels, follows links 1-hop to
  Jira/Confluence/GitHub/Figma, stashes raw content to ~/.xgh/inbox/, and detects urgency.
  Invoked via /xgh-retrieve command by launchd/cron every 5 minutes.
type: rigid
triggers:
  - when invoked via /xgh-retrieve command
  - when invoked headlessly by launchd or cron
mcp_dependencies:
  - mcp__claude_ai_Slack__slack_read_channel
  - mcp__claude_ai_Atlassian__getJiraIssue
  - mcp__claude_ai_Atlassian__getConfluencePage
  - mcp__claude_ai_Figma__get_metadata
---

# xgh:ingest-retrieve — Retrieval Loop

Invoked headlessly:
```
claude -p "/xgh-retrieve" \
  --allowedTools "mcp__claude_ai_Slack__*,mcp__claude_ai_Atlassian__*,mcp__claude_ai_Figma__*,Bash,Read,Write,Glob" \
  --max-turns 3
```

## Guard checks (run before anything else)

1. If `~/.xgh/ingest.yaml` does not exist: `echo "ERROR: ~/.xgh/ingest.yaml not found. Run /xgh-track."` and exit.
2. Check daily token cap: source `~/.xgh/lib/usage-tracker.sh`; if `xgh_usage_check_cap` returns non-zero, log and exit.
3. Check quiet hours/days from `schedule.quiet_hours` and `schedule.quiet_days`. If now is in a quiet period, exit silently.

## Step 1 — Load config and cursors

Read `~/.xgh/ingest.yaml`. Collect all projects where `status: active`.

Read `~/.xgh/inbox/.cursors.json` (JSON: `{"#channel-name": "last_iso_timestamp"}`). If missing, initialize to `{}`.

## Step 2 — Scan Slack channels

For each active project, for each Slack channel in its `slack:` list:

1. Call `slack_read_channel` with the channel name
2. Filter messages newer than the cursor timestamp for that channel (or last `retriever.max_messages_per_channel` if no cursor)
3. For each message, score urgency (Step 4)
4. Stash all messages scoring ≥ `urgency.thresholds.log` (default 0 — everything)

**Rate limiting:** On 429 or timeout, back off (2s → 4s → 8s) up to `retriever.max_retries` times, then skip the channel and note it in the log.

## Step 3 — Follow links 1-hop

For each message containing a URL, up to `retriever.max_links_to_follow` per cycle:

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

## Step 7 — Handle critical urgency (score ≥ 80)

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

## Step 9 — Update cursors

Write `~/.xgh/inbox/.cursors.json` with the latest message timestamp per channel scanned.

## Step 10 — Log completion

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: N channels, M items stashed, K urgent" \
  >> ~/.xgh/logs/retriever.log
source ~/.xgh/lib/usage-tracker.sh
xgh_usage_log "retriever" "$(actual turns used)" 0
```
