---
name: xgh-briefing
description: Session briefing — aggregates Slack, Jira, GitHub, and team memory into a prioritized summary
---

# /xgh-briefing — Session Briefing

Invoke the `xgh:briefing` skill.

## Usage

```
/xgh-briefing              # Full briefing (all sources, all sections)
/xgh-briefing compact      # One-line summary + suggested focus
/xgh-briefing focus        # Just the suggested focus, nothing else
/xgh-briefing meeting NAME # Filter briefing for a specific meeting
```

## Auto-trigger

The briefing is always available. Run it manually at session start or combine with `/xgh-brief` for a quick summary.

## Output sections

Full mode produces up to 6 sections (omitting empty ones):
1. **NEEDS YOU NOW** — urgent items requiring action
2. **IN PROGRESS** — work you were doing last session
3. **INCOMING** — items arriving soon
4. **TEAM PULSE** — team updates and convention changes
5. **TODAY** — calendar events
6. **SUGGESTED FOCUS** — single recommended task with rationale

## Examples

```
/xgh-briefing           → full briefing with all available data
/xgh-briefing compact   → 🐴🤖 2 need attention · 3 in flight · focus: fix auth bug
/xgh-briefing focus     → 🐴🤖 Focus: fix auth bug — it's blocking QA
```
