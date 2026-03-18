---
title: Ingest Pipeline — Retrieve → Analyze → Store
type: architecture
status: validated
importance: 90
tags: [architecture, pipeline, ingest]
keywords: [retrieve, analyze, store, scheduler, launchd, inbox, digest]
created: 2026-03-16
updated: 2026-03-16
---

# Ingest Pipeline

## Flow

```
Sources (Slack, GitHub, Jira, Confluence, Figma)
  → Retrieve (every 5 min) → ~/.xgh/inbox/
  → Analyze (every 30 min) → Cipher workspace + Context Tree
  → Digest (daily at 08:30) → Summary for session briefing
```

## Retrieve Loop (`/xgh-retrieve`)
- Scans configured sources per project in `~/.xgh/ingest.yaml`
- Follows links (depth 1) to linked resources
- Stashes raw content to `~/.xgh/inbox/`
- Budget: max 3 turns, 60s timeout, haiku model

## Analyze Loop (`/xgh-analyze`)
- Reads `~/.xgh/inbox/`, classifies content types
- Extracts structured memories (decisions, specs, WIP, requests)
- Dedup via similarity threshold (default 0.85)
- Stores to Cipher workspace + context tree
- Budget: max 10 turns, 300s timeout, sonnet model

## Scheduler
- Session scheduler via CronCreate (`XGH_SCHEDULER=on`). Managed via `/xgh-schedule`.
- Quiet hours: 22:00–07:00, weekends off

## Content Types

| Type | TTL | Promotes To | Description |
|------|-----|-------------|-------------|
| decision | ∞ | workspace | Locked-in architectural choice |
| spec_change | ∞ | workspace | Requirement modification |
| p0 | ∞ | workspace | Critical/blocking (urgency ≥ 90) |
| p1 | ∞ | workspace | High priority (urgency ≥ 65) |
| wip | ∞ | workspace | Actively being worked on |
| awaiting_my_reply | 7d | personal | Someone needs my input |
| awaiting_their_reply | 14d | personal | Blocked on someone |
| status_update | 3d | workspace | Deploy/merge notifications |
