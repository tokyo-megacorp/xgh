---
name: xgh-schedule
description: Manage xgh background scheduler — list, pause, resume, or run retrieve/analyze jobs. Also manage per-skill execution mode preferences.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh schedule`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status.

# /xgh-schedule — Scheduler Control Panel

Run the `xgh:schedule` skill to manage the session scheduler and skill execution preferences.

## Usage

```
/xgh-schedule [status | pause <job> | resume <job> | run <job> | off | prefs | add "<skill>" "<cron>"]
```
