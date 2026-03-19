---
name: xgh-schedule
description: Manage xgh background scheduler — list, pause, resume, or run retrieve/analyze jobs. Also manage per-skill execution mode preferences.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh schedule`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status.

# /xgh-schedule — Scheduler Control Panel

Run the `xgh:schedule` skill to manage the session scheduler and skill execution preferences.

## Usage

```
/xgh-schedule                        # show active jobs
/xgh-schedule pause retrieve         # pause retrieve job
/xgh-schedule pause analyze          # pause analyze job
/xgh-schedule resume retrieve        # resume retrieve job
/xgh-schedule resume analyze         # resume analyze job
/xgh-schedule run retrieve           # fire retrieve immediately
/xgh-schedule run analyze            # fire analyze immediately
/xgh-schedule off                    # cancel all xgh jobs this session
/xgh-schedule prefs                  # show skill mode preferences
/xgh-schedule prefs reset <skill>    # clear saved preference for a skill
```

## Scheduler behavior

The scheduler is always-on — jobs are auto-created at each session start. To pause, create `~/.xgh/scheduler-paused`. To resume, run `/xgh-schedule resume` (which removes the pause file).
