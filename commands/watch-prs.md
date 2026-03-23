---
name: xgh-watch-prs
description: Passively monitor PRs — surfaces review changes, new comments, CI status, and merge-readiness without touching anything. Never merges, never fixes, never requests reviews.
usage: "/xgh-watch-prs <start|poll-once> <PR> [<PR>...] [--repo owner/repo] [--interval 3m] [--reviewer <login>] | /xgh-watch-prs <status|stop>"
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh watch-prs`. Use markdown tables for state snapshots. Use ✅ ⚠️ ❌ for status. Keep per-poll output terse.

# /xgh-watch-prs

Run the `xgh:watch-prs` skill to passively observe PRs and surface changes between polls. Read-only — never merges, fixes comments, or requests reviews. Use `/xgh-ship-prs` to actively drive PRs to merge.

## Usage

```
/xgh-watch-prs start 28 29 [--interval 3m] [--reviewer <login>]
/xgh-watch-prs poll-once 28 29
/xgh-watch-prs status
/xgh-watch-prs stop
```

