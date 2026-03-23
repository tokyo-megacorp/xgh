---
name: coding-agents
description: "List and manage AI coding CLI agents (Codex, OpenCode, Gemini) and their model capabilities"
usage: "/xgh-coding-agents [agent] [--refresh]"
aliases: ["ca"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh coding-agents`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-coding-agents

Run the `xgh:coding-agents` skill to list available coding agents and their model capabilities.

## Usage

```
/xgh-coding-agents                    # List all agents + their models
/xgh-coding-agents opencode           # Show OpenCode details
/xgh-coding-agents --refresh          # Re-probe all agents
/xgh-coding-agents opencode --refresh # Re-probe just OpenCode
```
