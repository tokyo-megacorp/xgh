---
name: xgh-retrieve
description: Run the xgh context retrieval loop. Scans configured Slack channels, follows links to Jira/Confluence/GitHub/Figma, and stashes raw content to ~/.xgh/inbox/. Invoked by the scheduler every 5 minutes.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh retrieve`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-retrieve — Context Retrieval Loop

Run the `xgh:retrieve` skill to scan all active projects for new messages and linked resources.

## Usage

```
/xgh-retrieve
```

No arguments. All configuration comes from `~/.xgh/ingest.yaml`.

## Notes

- Invoked automatically each Claude session via CronCreate (scheduler is always-on; pause with `~/.xgh/scheduler-paused`). Also run manually to test.
- Critical items (urgency ≥ 80) trigger an immediate Slack DM.
- Run `/xgh-doctor` to check pipeline freshness.
