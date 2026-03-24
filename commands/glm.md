---
name: glm
description: "Dispatch tasks to Z.AI GLM models via OpenCode CLI for parallel implementation or code review"
usage: "/xgh-glm [exec|review] <prompt>"
aliases: ["glm"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh glm`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-glm

Run the `xgh:glm` skill to dispatch implementation tasks or code reviews to Z.AI GLM models via OpenCode CLI.

## Usage

```
/xgh-glm exec "Add unit tests for the auth module"
/xgh-glm review "Focus on error handling"
/xgh-glm exec --effort high "Refactor connection pooling"
/xgh-glm exec --same-dir "Fix lint warnings in src/utils/"
```
