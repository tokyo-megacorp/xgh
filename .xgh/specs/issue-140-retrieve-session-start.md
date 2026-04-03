---
title: "Investigation: xgh retrieve session-start trigger"
status: completed
date: 2026-03-27
owner: "xgh Team Lead"
sprint: sp2
github_issue: "#140"
---

# Investigation: xgh retrieve on session start

## Root cause

`xgh retrieve` was not running on session start because:

1. The SessionStart hook (`~/.claude/hooks/session-start-xgh.sh`) only injected the token budget — no retrieve call
2. The background cron (`schedule.retriever: '*/5 * * * *'` in `ingest.yaml`) requires the xgh scheduler to be running
3. If the scheduler is paused or the session starts before the first cron tick, context is stale at session open

## Intended design

`ingest.yaml` declares:
```yaml
schedule:
  retriever: '*/5 * * * *'
```
But this cron fires via an external scheduler — it does NOT trigger on session start.
The session-start hook was wired only for budget injection.

## Fix implemented

Modified `~/.claude/hooks/session-start-xgh.sh` to call
`~/.xgh/scripts/retrieve-all.sh` in background (non-blocking) at session start:

```sh
RETRIEVE_SCRIPT="$HOME/.xgh/scripts/retrieve-all.sh"
if [ -x "$RETRIEVE_SCRIPT" ]; then
  "$RETRIEVE_SCRIPT" >> "$HOME/.xgh/logs/retriever.log" 2>&1 &
fi
```

`retrieve-all.sh` already handles:
- Quiet hours / quiet days
- Pause file (`~/.xgh/scheduler-paused`)
- Daily token cap

So no additional guards are needed in the hook.

## Result

- On every claudinho session start: retrieve fires immediately in background
- Every 5 minutes thereafter: retrieve fires via ingest.yaml cron
- Both satisfy UNBREAKABLE_RULES §2 (≥5min interval for background crons — the session-start trigger is one-shot, not recurring)

## Commit

- `~/.claude` repo: `fix(hooks): trigger xgh retrieve on session start (tokyo-megacorp/xgh#140)`
