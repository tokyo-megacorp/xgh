---
name: xgh-seed
description: Seed xgh context into detected secondary AI coding tools such as Codex, Gemini, OpenCode, Cursor, Aider, and Continue.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh seed`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-seed — Seed Secondary Agent Context

Run the `xgh:seed` skill to converge project context into detected secondary AI tool directories.

## Usage

```
/xgh-seed
```

No arguments. The skill detects available tools and writes the appropriate xgh context files.

## Notes

- Safe to rerun after config or context changes.
- Writes generated context into tool-specific local directories when those tools are detected.
- Use `/xgh-doctor` if seeded tools do not appear to pick up the refreshed context.
