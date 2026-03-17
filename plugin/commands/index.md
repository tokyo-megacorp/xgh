---
name: xgh-index
description: Index a codebase into lossless-claude memory. Extracts architecture, modules, patterns, navigation flows, and naming conventions. Supports quick (~5 min) and full (~30 min) modes.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh index`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-index — Codebase Indexing

Run the `xgh:index` skill to extract architecture knowledge from a repository.

## Usage

```
/xgh-index [path] [--depth quick|full]
```

**Examples:**
```
/xgh-index
/xgh-index ~/code/my-ios-app
/xgh-index . --depth full
/xgh-index ~/code/acme-ios --depth quick
```

- `path` — optional (defaults to current directory)
- `--depth quick` — structure scan, 10–15 memories (~5 min)
- `--depth full` — comprehensive extraction, 30–50 memories (~20–30 min)
