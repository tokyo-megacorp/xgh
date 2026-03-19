---
name: xgh-analyze
description: Run the xgh context analysis loop. Reads ~/.xgh/inbox/, classifies and extracts structured memories, writes to lossless-claude workspace, and generates a daily digest. Invoked by the scheduler every 30 minutes.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh analyze`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-analyze — Context Analysis Loop

Run the `xgh:analyze` skill to process all queued inbox items.

## Usage

```
/xgh-analyze
```

No arguments. All configuration comes from `~/.xgh/ingest.yaml`.

## Notes

- Invoked automatically each Claude session via CronCreate (scheduler is always-on; pause with `~/.xgh/scheduler-paused`).
- Also triggered immediately when the retriever detects a critical urgency item.
- Run `/xgh-doctor` to check pipeline freshness and workspace stats.
