---
name: xgh:todo-killer
description: "This skill should be used when the user runs /xgh-todo-killer or asks to 'kill todos', 'fix todos', 'clean up comments'. Systematically finds and fixes TODOs, FIXMEs, HACKs, and deprecated comments in the codebase — turns them into structured migration signals and resolves them highest impact first."
---

# xgh:todo-killer — Systematic TODO Resolution

Find every TODO/FIXME/HACK/DEPRECATED comment in the codebase, turn them into structured migration signals, and fix them — highest impact first.

## Arguments

- `--mode scan|fix|both` — `scan` only harvests signals into `patterns.yaml`, `fix` works through items without updating patterns, `both` (default) does both
- `--filter TODO|FIXME|HACK|DEPRECATED|NOTE|all` — default: `all`
- `--glob <pattern>` — scope to specific files, e.g. `"Sources/**/*.swift"`
- `--priority high|medium|low|all` — default: `all`
- `--dry-run` — show what would be fixed without changing files

## Phase 1: Scan

### 1a. Harvest all comment markers

```bash
# Find all markers with file + line context
grep -rn --include="*.swift" \
  -E "(TODO|FIXME|HACK|NOTE|DEPRECATED|XXX|WORKAROUND)(\(.*\))?:" \
  . 2>/dev/null
```

Adapt glob per detected stack:
- Swift: `*.swift`
- JS/TS: `*.js,*.ts,*.tsx`
- Python: `*.py`
- Go: `*.go`
- Any: `*` (filter by common comment syntax)

### 1b. Enrich with git blame

For each hit, get age and author:
```bash
git blame -L <line>,<line> --porcelain <file> | grep "^author\|^summary\|^committer-time"
```

Old TODOs (>6 months, never touched) → `priority: high` — they've been ignored long enough.

### 1c. Cluster by theme

Group comments that reference the same concept:
- 12 files with `TODO: migrate to async/await` → one cluster, `files_affected: 12`
- 3 files with `HACK: CoreData thread safety` → one cluster, `files_affected: 3`

Cluster size + age = priority score:
```
priority = (cluster_size × 2) + (age_months / 3)
high ≥ 10 | medium 4–9 | low < 4
```

### 1d. Write to patterns.yaml

For each cluster, emit a `detected` entry. Respect merge rules — never overwrite human edits:

```yaml
- id: async-await-migration        # slugified from cluster theme
  source: auto
  status: detected                 # human promotes to deprecated/experimental/etc.
  pattern: "completion handler / callback-based async"
  replace_with: "async/await"
  glob: "**/*.swift"
  detected_by: xgh-todo-killer
  detected_at: 2026-03-16
  files_affected: 12
  sample_comments:
    - "Sources/Auth/LoginService.swift:47 — TODO: migrate to async/await"
    - "Sources/Network/APIClient.swift:103 — TODO: replace callback with async"
```

Read existing `patterns.yaml` first. Only add entries with `id` not already present. Only update `files_affected` for existing `source: auto` entries.

## Phase 2: Fix

Work through items in priority order. For each TODO:

### 2a. Read context

Read the file. Understand what the TODO is asking — don't fix blindly.

```
File: Sources/Auth/LoginService.swift:47
TODO: migrate to async/await — callback hell
Context: 30 lines around the comment
```

Before fixing, also run [SEARCH] → call `magi_query('TODO context: <todo text>')` — check if this has been attempted before or if there's a known pattern for the migration.

### 2b. Classify fixability

Use this decision tree:

| Type | Action |
|------|--------|
| Clear and self-contained | Fix now |
| Needs design decision | Skip — add to `.xgh/specs/` as open question |
| Part of larger migration | Fix if `status: active` in patterns.yaml, skip if `planned` |
| Already fixed (stale TODO) | Remove comment only |
| Needs external context (ticket, PR) | Skip — note in output |
| Blocked by another TODO in same cluster | Fix the blocker first |
| Requires touching >3 unrelated files | Mark `complex` — flag for separate PR |

### 2c. Fix — HOW to fix by TODO type

**Missing implementation:** Write the implementation inline. If non-trivial, write a minimal version that passes tests, then note what remains.

**Temporary workaround:** Find the root cause. If fixable in <30 min: fix it. If not: add a comment explaining why it's not trivially fixable and what the proper fix would require.

**Deprecated API usage:** Check if a newer API exists. If yes: migrate the callsite. If no replacement exists: mark as `needs-decision` and skip.

**Missing error handling:** Add the error case. Pattern: check → log → return safe default or raise.

```
// BEFORE
// TODO: handle empty response
const data = response.json()

// AFTER
const data = response.json()
if (!data || Object.keys(data).length === 0) {
  console.warn('Empty response from', url)
  return null
}
```

**Multi-file fix:** If fixing one TODO requires changes across multiple files, fix them all atomically in the same commit. Do not leave a partial fix in place.

After each fix: remove the TODO comment, run relevant tests (`swift test`, `npm test`, `pytest`, etc.), verify tests pass before moving to the next item.

### 2d. Commit per logical group

Don't batch unrelated fixes into one commit. Group by theme (cluster from 1c):

```bash
git commit -m "refactor: migrate LoginService + UserService to async/await (resolves 3 TODOs)"
```

If a TODO was classified as not fixable, document why in the commit message or skip it and include in the report's Skipped section.

## Phase 3: Report

After scan+fix, output a summary:

```
🐴 TODO Killer Report

  Scanned: 847 files
  Found: 34 markers across 19 files

  Fixed (12):
    ✅ async/await migration    — 7 TODOs resolved (LoginService, APIClient, ...)
    ✅ stale comments removed   — 3 TODOs (already fixed, comment left behind)
    ✅ force unwrap → safe      — 2 FIXMEs resolved

  Skipped (22):
    ⚠️  CoreData thread safety  — needs architecture decision (.xgh/specs/ entry created)
    ⚠️  SwiftUI migration       — status: planned in patterns.yaml, not active yet
    ⚠️  Missing ticket context  — 8 items reference PROJ-XXX tickets

  patterns.yaml: 4 new entries added (status: detected)

  Run /xgh-index --depth full to re-score after fixes.
```

## Integration with patterns.yaml

- `todo-killer` is a **producer** of `detected` entries — it surfaces signals
- `/xgh-index` is also a producer — both write `source: auto`, `status: detected`
- Humans are **promoters** — they set `deprecated`, `experimental`, `stable`
- `convention-guardian` + `prompt-submit` hook are **consumers** — they read the file

Never write `status: deprecated` or higher directly — that's human intent.

## Deduplication

Before writing to `patterns.yaml`, check MAGI memory for existing knowledge about the same pattern:

```
magi_query("TODO migration async/await [REPO]")
```

If MAGI already has this as a team decision, use that context to set richer metadata.

## When to Skip

- `// TODO(someuser): personal reminder` — skip, not a pattern signal
- `// TODO: https://github.com/...` — external blocker, skip
- `// FIXME: compiler bug` — skip, not actionable by agent
- Generated files (`*.generated.swift`, `build/`) — skip entirely
