---
name: xgh-index
description: Raw codebase inventory — extracts module list, key files, and naming conventions into MAGI memory.
---

ARGUMENTS: $ARGUMENTS

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh index`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-index — Codebase Inventory

Run the `xgh:index` skill to extract a raw inventory of modules, key files, and naming conventions from a repository.

## Usage

```
/xgh-index [path]
```

**Examples:**
```
/xgh-index
/xgh-index ~/code/my-ios-app
```

- `path` — optional (defaults to current directory)
