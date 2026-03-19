---
name: xgh:deep-retrieve
description: >
  Hourly deep scan for Slack thread activity on old messages. Detects new replies on threads
  regardless of parent message age — including threads created on previously-clean messages.
  Complements xgh:retrieve (fast, cursor-based). Invoked by CronCreate every hour.
type: rigid
triggers:
  - when invoked via /xgh-deep-retrieve command
  - when invoked by CronCreate (session scheduler, always-on)
mcp_dependencies:
  - mcp__claude_ai_Slack__slack_read_channel
  - mcp__claude_ai_Slack__slack_read_thread
---
> **Context-mode:** Use `ctx_execute_file` for analysis reads; `Read` only for files you will
> Edit within 1-2 tool calls. Use `ctx_batch_execute` for multi-command research. Full routing
> rules: `plugin/references/context-mode-routing.md`


# xgh:deep-retrieve — Deep Thread Scan

Invoked by CronCreate:
```
  prompt: /xgh-deep-retrieve
  cron: 0 * * * *
  recurring: true
```

Complements `xgh:retrieve`. The fast retrieve (every 5 min) catches new channel messages and
thread replies on messages up to `thread_lookback_hours` old. This scan catches new replies on
ANY message regardless of age — including the first-ever reply to an old message that converts
it into a thread.

## Why this exists

`conversations.history` sorts by message creation time (`ts`), not by latest thread activity.
The fast scan's lookback window misses:
1. New replies on thread parents older than `thread_lookback_hours`
2. First-ever replies to old messages (new threads on previously-clean messages)

This scan re-reads channel history and compares each message's live `latest_reply` against
`last_scan_ts` to detect both cases.

## Context window management

All Bash/Python processing MUST be routed through `ctx_execute` or `ctx_batch_execute` when
context-mode is available. Never print raw message bodies.

## Guard checks

1. If `~/.xgh/ingest.yaml` does not exist: `echo "ERROR: ~/.xgh/ingest.yaml not found."` and exit.
2. Check daily token cap: source `~/.xgh/lib/usage-tracker.sh`; if `xgh_usage_check_cap` returns non-zero, log and exit.
3. Check quiet hours/days from `schedule.quiet_hours` and `schedule.quiet_days`.

## Step 1 — Load config and state

Read `~/.xgh/ingest.yaml`. Collect all projects where `status: active`.

Read `~/.xgh/inbox/.cursors.json` — main per-channel cursors (from fast retrieve).

Read `~/.xgh/inbox/.deep_scan.json` — per-channel last deep scan timestamps:
```json
{"#channel-name": "2026-03-18T09:00:00Z"}
```
If missing, initialize to `{}`. If a channel has no entry, treat `last_scan_ts` as
`now - thread_lookback_days × 24h` (first run: scan the entire lookback window).

## Step 2 — Deep scan per channel

For each active project, for each Slack channel:

**Determine the scan window:**
- `scan_start = now - (retriever.thread_lookback_days × 24h)` (default: 7 days)
- `scan_end = cursors[channel]` (main cursor — don't overlap with what fast retrieve just fetched)
- `last_scan_ts = deep_scan[channel] ?? scan_start`

If `last_scan_ts >= scan_end`, there is nothing new to check — skip this channel.

**Paginate through channel history:**

1. Call `slack_read_channel(channel, oldest=scan_start, latest=scan_end)` — returns up to
   `max_messages_per_channel` (100) messages, newest first
2. For each message in the batch where `latest_reply` exists and `latest_reply > last_scan_ts`:
   - Call `slack_read_thread(channel_id, message_ts)`
   - Filter replies to only `ts > last_scan_ts`
   - For each qualifying reply: dedup check (Step 2a), then stash (Step 2b)
3. **Pagination:** If the batch returned exactly `max_messages_per_channel` messages AND the
   oldest message in the batch has `ts > scan_start`:
   - More messages exist — call again with `latest = oldest_ts_in_batch`
   - Cap at `retriever.deep_scan_max_pages` pages per channel (default: 5) to stay within
     turn budget. Log a warning if the cap is hit.
4. Stop when batch size < `max_messages_per_channel`, OR oldest message `ts ≤ scan_start`,
   OR page cap reached

**Rate limiting:** Apply the same back-off rules as fast retrieve (2s → 4s → 8s, up to
`retriever.max_retries`). On persistent failure, skip the channel and log.

### Step 2a — Dedup check

Before stashing a thread reply, check if it already exists in `~/.xgh/inbox/`. The fast
retrieve's thread reply pass may have already stashed recent replies. Use:

```bash
ls ~/.xgh/inbox/ | grep "_slack_thread_" | grep "<reply_ts_normalized>"
```

Where `reply_ts_normalized` is the reply's `ts` with `.` replaced by `-`. If a match exists,
skip this reply.

### Step 2b — Stash new replies

Write one `.md` file per reply to `~/.xgh/inbox/`:

**Filename:** `{YYYY-MM-DDThh-mm-ss}_slack_thread_{channel_slug}_{reply_ts_norm}.md`

Example: `2026-03-18T10-00-00_slack_thread_general_1710756000-123456.md`

**File content:**
```markdown
---
type: inbox_item
source_type: slack_thread
source_channel: "#channel-name"
source_ts: <reply_ts_iso>
thread_parent_ts: <parent_ts_iso>
project: <project-key>
urgency_score: <N>
processed: false
awaiting_direction: null
links_followed: []
---

**Thread context (parent message):**
<parent message text, max 300 chars>

---

**New reply:**
<reply text>
```

Score each reply through the urgency pipeline (same as `xgh:retrieve` Step 4). Only stash
replies scoring ≥ `urgency.thresholds.log` (default: 0 — everything).

For critical replies (score ≥ 80), follow the DM notification logic from `xgh:retrieve` Step 7.

## Step 3 — Update deep scan state

For each channel that completed without error, update `~/.xgh/inbox/.deep_scan.json`:

```json
{
  "#channel-a": "2026-03-18T10:00:00Z",
  "#channel-b": "2026-03-18T09:00:00Z"
}
```

Merge with existing entries — only update channels that completed successfully. If a channel
failed, leave its `last_scan_ts` unchanged so the next run retries from the correct position.

## Step 4 — Log completion

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) deep-retriever: N channels, M threads checked, K new replies stashed" \
  >> ~/.xgh/logs/retriever.log
source ~/.xgh/lib/usage-tracker.sh
xgh_usage_log "deep-retriever" "$(actual turns used)" 0
```

## Output discipline

End every run with exactly one summary line:
```
Deep-retrieve complete: <N> threads checked, <M> new replies stashed, <K> channels covered.
```

## Scheduler nudge (manual runs only)

If invoked manually (not by CronCreate), check for an active CronCreate job with prompt
`/xgh-deep-retrieve`. If not found, append:

```
⚠️ Running manually — enable background scheduling: /xgh-schedule resume deep-retrieve
```
