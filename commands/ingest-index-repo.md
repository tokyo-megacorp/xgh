---
name: xgh-index-repo
description: Index a codebase into Cipher memory. Extracts architecture, modules, patterns, navigation flows, and naming conventions. Supports quick (~5 min) and full (~30 min) modes.
---

# /xgh-index-repo — Codebase Indexing

Run the `xgh:ingest-index-repo` skill to extract architecture knowledge from a repository.

## Usage

```
/xgh-index-repo [path] [--depth quick|full]
```

**Examples:**
```
/xgh-index-repo
/xgh-index-repo ~/code/my-ios-app
/xgh-index-repo . --depth full
/xgh-index-repo ~/code/acme-ios --depth quick
```

- `path` — optional (defaults to current directory)
- `--depth quick` — structure scan, 10–15 memories (~5 min)
- `--depth full` — comprehensive extraction, 30–50 memories (~20–30 min)
