---
name: xgh-babysit-prs
description: Watch a batch of GitHub PRs through Copilot review cycles until all are merged — polls status, dispatches fix agents, merges when clean
usage: "/xgh-babysit-prs <start|poll-once> <PR> [<PR>...] [--repo owner/repo] [--interval 5m] [--merge-method squash] [--post-merge-hook '<cmd>'] | /xgh-babysit-prs <status|stop> [--repo owner/repo]"
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh babysit-prs`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. Keep per-poll output terse.

# /xgh-babysit-prs

Run the `xgh:babysit-prs` skill to shepherd multiple PRs through GitHub Copilot review cycles until all are merged.

## Usage

```
/xgh-babysit-prs start 28 29 [--interval 5m] [--merge-method squash] [--post-merge-hook 'make deploy']
/xgh-babysit-prs poll-once 28 29
/xgh-babysit-prs status
/xgh-babysit-prs stop
```
