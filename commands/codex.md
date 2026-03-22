---
name: codex
description: "Dispatch tasks to Codex CLI for parallel implementation or code review"
usage: "/xgh-codex [exec|review] <prompt>"
aliases: ["cdx"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh codex`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-codex

Run the `xgh:codex` skill to dispatch implementation tasks or code reviews to OpenAI's Codex CLI.

## Usage

```
/xgh-codex exec "Add unit tests for the auth module"
/xgh-codex review --base main
/xgh-codex exec --model gpt-5.4 --effort high "Refactor connection pooling"
/xgh-codex review --uncommitted --thinking xhigh
/xgh-codex exec --add-dir /path/to/repo "Fix lint warnings in src/utils/"
```
