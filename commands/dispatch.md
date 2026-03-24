---
name: dispatch
description: "Auto-route tasks to the best agent + model + effort based on learned performance"
usage: "/xgh-dispatch [exec|review] [--agent <name>] [--model <name>] <prompt>"
aliases: ["route"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh dispatch`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-dispatch

Run the `xgh:dispatch` skill to automatically select the optimal agent, model, and effort level for a task.

## Usage

```
/xgh-dispatch "Add unit tests for the auth module"
/xgh-dispatch exec "Refactor connection pooling"
/xgh-dispatch review --base main
/xgh-dispatch --agent codex "Fix the flaky test"
/xgh-dispatch --model gpt-5.4-mini "Rename the variable"
/xgh-dispatch --agent gemini --model gemini-2.5-flash "Quick docs update"
```
