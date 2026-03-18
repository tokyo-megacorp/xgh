---
name: xgh-command-center
description: Global orchestrator view — cross-project briefing, triage, and dispatch
---

# /xgh-command-center — Global Orchestrator

Invoke the `xgh:command-center` skill.

## Usage

```
/xgh-command-center           # full command center (global briefing + triage)
/xgh-command-center morning   # morning ritual mode (full briefing, then await)
/xgh-command-center pulse     # compact status across all projects
/xgh-command-center dispatch  # list in-flight subagents + their status
```

## What it does

- Loads all `status: active` projects from `~/.xgh/ingest.yaml` — no project scoping
- Runs `xgh:briefing` logic across **all** projects simultaneously
- Labels every item with its project: `[context-mode] Issue #143 — urgency 60`
- Triages NEEDS-YOU-NOW items via in-session background Agents
- Dispatches implement work to named `claude` sessions in the right project directory
- Sets up pulse (every 15 min) and morning briefing (8am weekdays) cron jobs

## Dispatch modes

| Mode | Behaviour |
|------|-----------|
| `alert_only` | Show items, ask user what to do |
| `auto_triage` (default) | Background Agent investigates each item, posts recommendation |
| `auto_dispatch` | After triage, launches `claude` in project dir with dispatch context file |

Configure in `~/.xgh/ingest.yaml` under `command_center.dispatch_mode`.

## Session naming

Launched sessions are named using `command_center.session_name_template` (default: `"{project}: {action} {ref}"`):
- `"context-mode: implement #143"`
- `"xgh: investigate PR #18"`

## Context handoff

When launching a new session, writes `~/.xgh/inbox/.dispatch.md` with action, ref, and triage context. The target session's session-start hook detects this file and injects it as priority context.

## Examples

```
/xgh-command-center           → full briefing across all 4 projects + triage
/xgh-command-center pulse     → 🐴🤖 pulse — context-mode: 2 new · xgh: quiet
/xgh-command-center morning   → full briefing then await-commands loop
/xgh-command-center dispatch  → table of in-flight background agents
```
