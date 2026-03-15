---
name: xgh-analyze
description: Run the xgh context analysis loop. Reads ~/.xgh/inbox/, classifies and extracts structured memories, writes to Cipher workspace, and generates a daily digest. Invoked by the scheduler every 30 minutes.
---

# /xgh-analyze — Context Analysis Loop

Run the `xgh:ingest-analyze` skill to process all queued inbox items.

## Usage

```
/xgh-analyze
```

No arguments. All configuration comes from `~/.xgh/ingest.yaml`.

## Notes

- Invoked automatically by the scheduler (launchd/cron).
- Also triggered immediately when the retriever detects a critical urgency item.
- Run `/xgh-doctor` to check pipeline freshness and workspace stats.
