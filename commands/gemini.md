---
name: gemini
description: "Dispatch tasks to Gemini CLI for parallel implementation or code review"
usage: "/xgh-gemini [exec|review] <prompt>"
aliases: ["gem"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh gemini`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-gemini

Run the `xgh:gemini` skill to dispatch implementation tasks or code reviews to Google's Gemini CLI.

## Usage

```
/xgh-gemini exec "Add unit tests for the auth module"
/xgh-gemini review "Check for security issues in the latest changes"
/xgh-gemini exec --model gemini-2.5-flash --effort high "Fix lint warnings in src/utils/"
/xgh-gemini exec --same-dir --thinking xhigh "Add missing docstrings"
```
