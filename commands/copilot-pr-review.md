---
name: copilot-pr-review
description: "Manage GitHub Copilot PR code reviews — request, re-review, status, comments, reply, delegate"
usage: "/xgh-copilot-pr-review <command> <PR> [args] [--repo owner/repo]"
aliases: ["cpr"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh copilot-pr-review`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-copilot-pr-review

Run the `xgh:copilot-pr-review` skill to manage GitHub Copilot PR code reviews from the CLI.

## Usage

```
/xgh-copilot-pr-review request 42
/xgh-copilot-pr-review re-review 42
/xgh-copilot-pr-review status 42
/xgh-copilot-pr-review comments 42
/xgh-copilot-pr-review reply 42 <comment_id> "Your reply here"
/xgh-copilot-pr-review delegate 42 "Fix the auth bug"
```
