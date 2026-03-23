---
name: xgh-watch-prs
description: Watch a batch of GitHub PRs through Copilot review cycles until all are merged — polls status, dispatches fix agents, merges when clean (GitHub-only; uses gh CLI + GitHub APIs)
usage: "/xgh-watch-prs <start|poll-once> <PR> [<PR>...] [--repo owner/repo] [--interval 3m] [--merge-method merge|squash|rebase] [--reviewer <login>] [--accept-suggestion-commits] [--require-resolved-threads] [--post-merge-hook '<cmd>'] | /xgh-watch-prs <status|stop> [--repo owner/repo]"
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh watch-prs`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. Keep per-poll output terse.

# /xgh-watch-prs

Run the `xgh:watch-prs` skill to shepherd multiple PRs through GitHub Copilot review cycles until all are merged.

## Usage

```
/xgh-watch-prs start 28 29 [--interval 3m] [--merge-method squash] [--post-merge-hook 'make deploy']
/xgh-watch-prs poll-once 28 29
/xgh-watch-prs status
/xgh-watch-prs stop
```

