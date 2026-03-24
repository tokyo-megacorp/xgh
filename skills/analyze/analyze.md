---
name: xgh:analyze
description: "This skill should be used when the user runs /xgh-analyze, when invoked by the CronCreate scheduler, or when ~/.xgh/inbox/.urgent exists. Headless analyzer loop — reads ~/.xgh/inbox/, classifies content types, extracts structured memories, deduplicates against lossless-claude, writes to workspace or personal collection, manages TTL, and generates Obsidian-compatible daily digest."
---

# xgh:analyze — Analysis Loop

Invoked by CronCreate:
```
  prompt: /xgh-analyze
  cron: */30 * * * *
  recurring: true
```


## Guard checks

**1. lossless-claude availability** — Check if the `mcp__lossless-claude__lcm_search` tool is available in the current tool list. If the tool is present and callable → lossless-claude ✓. If the tool is absent → skip all lossless-claude steps (Steps 5–8) and log a warning. Print `lossless-claude ✓ available` or `lossless-claude ⚠ not available — skipping vector ops`.

**2. Config** — `~/.xgh/ingest.yaml` exists and parses.

**3. Daily cap** — Check via `~/.xgh/lib/usage-tracker.sh`.

## Step 1 — Read inbox

List all `.md` files in `~/.xgh/inbox/` that are NOT in `processed/` and do NOT start with `.`.

Parse YAML frontmatter from each file to get `urgency_score` and `project`.

Sort by urgency_score descending (process high urgency first). If `.urgent` file exists, move those items to the front.

Cap at `analyzer.max_inbox_items` (default 50) — overflow waits for the next run.

## Step 2 — Merge enrichments

If `~/.xgh/inbox/.enrichments.json` exists:
1. Read `pending` array
2. For each entry, update the corresponding project in `~/.xgh/ingest.yaml` using python3:
   - Add Jira key to `projects.<project>.jira` if not present
   - Add GitHub repo to `projects.<project>.github` list if not present
   - Add Confluence path to `projects.<project>.confluence` list if not present
3. Delete the `.enrichments.json` file

## Step 3 — Classify each item

Assign a `content_type` for each inbox item by analyzing the content:

| Signal | Content type |
|---|---|
| Decision language: "we decided", "going with X", "confirmed approach" | `decision` |
| Spec modification: "requirement changed", "spec updated", "new approach" | `spec_change` |
| P0/critical/release-blocker keyword | `p0` |
| P1/high priority keyword | `p1` |
| Active work in progress (PR merged, task started, bug being fixed) | `wip` |
| @mention with question or request directed at the user | `awaiting_my_reply` |
| User sent a question, thread has no reply | `awaiting_their_reply` |
| Informal Slack ask not yet in Jira | `informal_request` |
| QA/tester reporting a bug in chat | `qa_feedback` |
| Acknowledged issue, not yet prioritized | `known_issue` |
| Deploy, merge, status notification | `status_update` |

**Auto-promotion rules:**
- `wip` + blocker keywords → upgrade to `p0`
- `informal_request` + Jira ticket reference found → link and upgrade to ticket type
- `awaiting_my_reply` + response detected from user in thread → mark `completed`

## Step 4 — Extract structured memory payload

For each classified item, build this payload:

```json
{
  "text": "<concise 1-3 sentence summary capturing the key decision/change/action>",
  "teamMember": "<profile.name from ingest.yaml>",
  "domain": "<profile.platforms[0]>",
  "project": "<project key from inbox frontmatter>",
  "progressStatus": "<content_type>",
  "bugs": [],
  "workContext": {
    "jiraTicket": "<ticket key if linked>",
    "repository": "<github repo if linked>",
    "branch": "<branch if detectable>"
  },
  "xgh_content_type": "<content_type>",
  "xgh_urgency_score": 45,
  "xgh_ttl": null,
  "xgh_source": "slack:#channel/thread-ts",
  "xgh_timestamp": "<original message ISO timestamp>",
  "xgh_schema_version": 1,
  "xgh_status": "active"
}
```

`xgh_ttl`: look up `content_types.<type>.ttl` in `ingest.yaml`. `null` = permanent; otherwise compute ISO datetime = now + TTL duration.

## Step 5 — Deduplicate

Before writing each payload:
1. Call `lcm_search(query)` with the summary text as query
2. If any result has similarity score ≥ `analyzer.dedup_threshold` (default 0.85):
   - Skip writing a new entry (the existing memory covers this content)
3. If no near-duplicate, proceed to Step 6

## Step 6 — TTL management (every 5 runs)

Track run count in `~/.xgh/logs/.analyzer-run-count` (increment each run, reset at 100).

When count mod 5 == 0:
1. Search lossless-claude for memories with `xgh_status: active` and non-null `xgh_ttl`
2. For each where `xgh_ttl` < now: mark as `xgh_status: decayed` in the next digest
3. Check if any current inbox items reference the same project/topic as decayed memories — if so, reset their TTL to now + original duration

## Step 7 — Write to lossless-claude

> **Note:** lossless-claude writes are always allowed regardless of provider access levels. lossless-claude is internal memory, not an external provider — the `providers.<type>.access` setting only governs writes back to external services (Slack, Jira, Confluence, GitHub, Figma).

Route based on `content_types.<type>.promote_to` from `ingest.yaml`:

**workspace** → Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and tags: ["workspace"]. Do not pass raw conversation content to lcm_store.

```
lcm_store("<summary>", ["workspace"])
```

**personal** → Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store. Use tags: ["session"].

```
lcm_store("<summary>", ["session"])
```

Cap total writes at `analyzer.max_memories_per_run`. If cap reached, leave remaining inbox files for the next run.

## Step 7b: Standard-path trigger evaluation

After classification and memory storage, evaluate standard-path triggers.

**Skip this step entirely if:**
- `~/.xgh/triggers.yaml` does not exist (triggers not configured)
- `~/.xgh/triggers.yaml` has `enabled: false`
- No files exist in `~/.xgh/triggers/` (no triggers defined)

**Procedure:**

1. Read `~/.xgh/triggers.yaml` (global config). Note `action_level`, `cooldown`, `fast_path`.
2. Read all `~/.xgh/triggers/*.yaml` files (skip `.state.json`).
   Filter to triggers where `path: standard` OR `path:` is not set (default = standard).
   Skip `source: schedule` triggers (handled by schedule skill).
3. Read `~/.xgh/triggers/.state.json` (or `{}` if missing).
4. For each classified inbox item:
   For each standard-path trigger:
   a. **Match check:** Evaluate all `when:` fields against the item.
      - `source:` matches item frontmatter `source:` field (`*` = any)
      - `type:` matches item frontmatter `type:` from classification (`*` = any)
      - `project:` matches item frontmatter `project:` (`*` = any). If item has no `project:` field, treat as `project: *` — any trigger matches unless it specifies a non-wildcard project.
      - `match:` regex patterns on item fields — `!` prefix means exclude
   b. **Cooldown check:** See xgh:trigger evaluation logic (cooldown / backoff / dedup checks).
      If any check fails → skip.
   c. **Dedup check:** If item filename in `fired_items` array → skip.
   d. **Execute steps:** For each `then:` step, enforce action_level cap, then execute.
      Use declarative actions (notify, create_issue, dispatch) via appropriate MCP tools.
      Inline `run:` blocks: execute via Bash with all `$ITEM_*` env vars set.
   e. **Update state:** Write updated `.state.json` after each trigger fires.
5. Log: `Trigger engine: evaluated N triggers against M items — K fired`

## Step 8 — Session tracking

If any inbox item contains a pattern like `Session [a-f0-9]{8,}` or a `/xgh-implement TICKET-123` invocation:
1. Extract session ID and ticket association
2. Write a session index entry:
```
lcm_store("Claude session <id> worked on <tickets>: <one-line summary>", ["workspace"])
```

## Step 9 — Move processed files

```bash
mv ~/.xgh/inbox/*.md ~/.xgh/inbox/processed/ 2>/dev/null || true
rm -f ~/.xgh/inbox/.urgent
```

## Step 10 — Generate/append digest

Append to `~/.xgh/digests/$(date +%Y-%m-%d).md`. Create with YAML frontmatter if new:

```markdown
---
date: 2026-03-15
type: digest
projects: [passcode-feature]
open_replies: 3
urgency_peak: 82
tags: [digest, daily]
---

# Digest — 2026-03-15

## [[passcode-feature|Passcode Feature]]
- **[SPEC_CHANGE]** PIN entry now requires biometric fallback (14:30) #spec-change
- **[DECISION]** Going with approach B for token storage (11:15) #decision

## Awaiting Your Reply (N)
- 🔴 <item> (31h) #awaiting-reply
- 🟡 <item> (6h) #awaiting-reply
- 🟢 <item> (1h) #awaiting-reply
```

Urgency emoji: 🔴 (>50h old), 🟡 (8–50h), 🟢 (<8h). Update `open_replies` and `urgency_peak` counts.

> **Auto-post:** If `providers.slack.access` is `auto` and `notifications.digest_channel` is set, post the digest summary to that Slack channel automatically. If `ask`, propose the post and wait for user confirmation. If `read` (default), only write the local file.

## Step 11 — Log and track usage

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) analyzer: N items, M written, K duped, P decayed" \
  >> ~/.xgh/logs/analyzer.log
source ~/.xgh/lib/usage-tracker.sh
xgh_usage_log "analyzer" "<actual turns>" 0
```

## Common Mistakes

### Misclassifying multi-type items
Items that carry signals for multiple categories (e.g., both a spec and a design decision) often get classified as one or the other. When signals conflict, prefer the higher-specificity type: `decision` > `pattern` > `convention` > `discovery`. If genuinely ambiguous, use the type that matches the item's actionability.

### Dedup false positives
Two items with similar wording but different scopes (e.g., "auth token rotation" for iOS vs. web) may incorrectly match above the similarity threshold. If the same concept appears twice with divergent context tags or project assignments, keep both — tag divergence signals an intentional distinction.

### Skipping TTL refresh on updated items
If a source item's timestamp is newer than the memory's `created_at`, recalculate TTL from the new source date — not the original curation date. Forgetting this causes stale memories to survive past their correct expiry.

### Creating duplicates instead of updating
When an inbox item supersedes an existing memory, update the lossless-claude entry in place using `lcm_store` with the same title. Do not append a new entry — duplicates degrade retrieval quality and inflate dedup false-positive rates.

### Filing items with no project match
If an inbox item cannot be mapped to an active project in `ingest.yaml`, log `WARN: no project match for <item>` and skip it. Do not file it under a random or fallback project — misattributed memories are worse than no memory.

---

## Output discipline

1. Never dump raw inbox content into session context.
2. **End every run with exactly one summary line:**
   ```
   Analyze complete: <N> items processed, <M> stored, <K> duplicates skipped.
   ```

## Scheduler nudge (manual runs only)

If this skill was invoked manually (not by CronCreate), check after the summary line:

Call CronList and look for jobs with prompt `/xgh-retrieve` or `/xgh-analyze`.

If no active CronCreate jobs found, append:

```
⚠️ Running manually — scheduler is paused or not started.
   /xgh-schedule resume    (enable for this session and future sessions)
```
