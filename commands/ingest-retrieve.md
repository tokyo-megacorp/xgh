---
name: xgh-retrieve
description: Run the xgh context retrieval loop. Scans configured Slack channels, follows links to Jira/Confluence/GitHub/Figma, and stashes raw content to ~/.xgh/inbox/. Invoked by the scheduler every 5 minutes.
---

# /xgh-retrieve — Context Retrieval Loop

Run the `xgh:ingest-retrieve` skill to scan all active projects for new messages and linked resources.

## Usage

```
/xgh-retrieve
```

No arguments. All configuration comes from `~/.xgh/ingest.yaml`.

## Notes

- Invoked automatically by the scheduler (launchd/cron). You can also run it manually to test.
- Critical items (urgency ≥ 80) trigger an immediate Slack DM.
- Run `/xgh-doctor` to check pipeline freshness.
