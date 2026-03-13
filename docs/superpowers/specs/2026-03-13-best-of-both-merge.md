# Best-of-Both Script Merge — Design Spec

## Goal

Rewrite xgh's core shell scripts by combining the structural wins from the Copilot branch (`origin/copilot/update-readme-positioning`) with the functional wins from our branch (`origin/feat/initial-release`). All skills, commands, config, and agents remain untouched.

## Background

Two parallel implementations of xgh Plans 1-7 exist:

- **Copilot branch:** Better architecture — sourceable library pattern, flat manifest schema, structured JSON hook output, intent-detecting prompt-submit hook
- **Our branch:** Better functionality — hysteresis scoring, dual BM25+Cipher search, field-weighted BM25, XGH_BRIEFING trigger, 13.9x more complete skills, all 540 tests passing

This spec defines a clean rewrite of 7 shell scripts, 2 hooks, and 1 configure script that takes the best of both.

## Architecture

### Pattern: Sourceable Shell Libraries

All `ct-*.sh` scripts become sourceable libraries with a `BASH_SOURCE[0]` CLI guard at the bottom. `context-tree.sh` sources them all and exposes the public CLI.

```
context-tree.sh (public API + CLI dispatcher)
  ├── ct-frontmatter.sh  (no deps)
  ├── ct-scoring.sh      (depends on ct-frontmatter)
  ├── ct-manifest.sh     (depends on ct-frontmatter)
  ├── ct-archive.sh      (depends on ct-frontmatter, ct-manifest)
  ├── ct-search.sh       (depends on bm25.py)
  └── ct-sync.sh         (depends on all above)
```

### Environment

- `XGH_CONTEXT_TREE` — context tree root (default: `.xgh/context-tree`). Used consistently across all scripts. No `CT_DIR` / `CT_ROOT` / `XGH_CONTEXT_TREE_DIR` / `XGH_CONTEXT_TREE_PATH` / `XGH_CONTEXT_PATH` inconsistency.
- Inside `context-tree.sh`, the resolved value is stored in `CT_ROOT`: `CT_ROOT=${XGH_CONTEXT_TREE:-.xgh/context-tree}`. All subcommand descriptions below reference `$CT_ROOT`.

## Public API

### context-tree.sh (CLI dispatcher)

```bash
context-tree.sh init
context-tree.sh create <rel-path> <title> [content]
context-tree.sh read <rel-path>
context-tree.sh update <rel-path> <content>
context-tree.sh delete <rel-path>
context-tree.sh list
context-tree.sh search <query> [top]
context-tree.sh score <rel-path> [search-hit|update|manual]
context-tree.sh archive
context-tree.sh restore <archived-full-file>
context-tree.sh sync <curate|query|refresh> [args...]
context-tree.sh manifest <init|rebuild|update-indexes>
```

Sources all `ct-*.sh` libraries and dispatches to their functions.

**Subcommand details:**
- `init` — calls `ct_manifest_init "$CT_ROOT"` then `ct_manifest_update_indexes "$CT_ROOT"`. Creates `$CT_ROOT` dir if missing.
- `create` — creates file at `$CT_ROOT/<rel-path>`, writes frontmatter (title, defaults), appends content. Calls `ct_score_recalculate` and `ct_manifest_add`. Fails if file exists.
- `read` — cats file, increments accessCount via `ct_frontmatter_increment_int`, bumps importance +3 via `ct_score_apply_event <file> search-hit`.
- `update` — appends `## Update <timestamp>` + content to file. Bumps importance +5 via `ct_score_apply_event <file> update`. Resets recency to 1.0.
- `delete` — removes file. Also removes `_archived/<path>.stub.md` and `_archived/<path>.full.md` if they exist. Cleans empty parent dirs up to `$CT_ROOT`. Calls `ct_manifest_remove`.
- `list` — `find` all `.md` files excluding `_index.md`, `_archived/`, `*.stub.md`, and `context.md`, print with maturity and importance.
- `search` — delegates to `ct_search_run "$CT_ROOT" "$query" "${top:-10}"`.
- `score` — delegates to `ct_score_apply_event "$CT_ROOT/$rel_path" "${event:-update}"`.
- `archive` — delegates to `ct_archive_run "$CT_ROOT"`.
- `restore` — delegates to `ct_archive_restore "$CT_ROOT" "$archived_full"`. The argument is a path relative to `$CT_ROOT/_archived/` (e.g., `backend/auth/jwt-patterns.full.md`).
- `sync` — delegates to `ct_sync_*` functions.
- `manifest` — delegates to `ct_manifest_init`, `ct_manifest_rebuild`, or `ct_manifest_update_indexes`.

### ct-frontmatter.sh (YAML frontmatter parser)

Source: Copilot's AWK-based implementation with our field set.

```bash
ct_frontmatter_has <file>                    # returns 0 if file has ---...--- block
ct_frontmatter_get <file> <key>              # extract single field value
ct_frontmatter_set <file> <key> <value>      # update or insert field (auto-updates updatedAt)
ct_frontmatter_increment_int <file> <key>    # atomically increment integer field
```

Frontmatter fields:
```yaml
---
title: "Entry Title"
tags: [auth, jwt]
keywords: [token, refresh]
importance: 50
recency: 1.0000
maturity: draft
accessCount: 0
updateCount: 0
createdAt: 2026-03-13T00:00:00Z
updatedAt: 2026-03-13T00:00:00Z
---
```

### ct-scoring.sh (importance/recency/maturity)

Source: Our implementation, adapted to Copilot's function naming.

**Named constants (top of file):**
```bash
HALF_LIFE_DAYS=21
PROMOTE_VALIDATED=65
PROMOTE_CORE=85
DEMOTE_CORE_THRESHOLD=25
DEMOTE_VALIDATED_THRESHOLD=30
IMPORTANCE_SEARCH_HIT=3
IMPORTANCE_UPDATE=5
IMPORTANCE_MANUAL_CURATE=10
```

**Functions:**
```bash
ct_score_recency <updated_at>                # returns float 0.0-1.0 (exponential decay)
ct_score_maturity <importance> <current_maturity>  # returns new maturity with hysteresis
ct_score_recalculate <file>                  # recalculate recency + maturity from current fields
ct_score_apply_event <file> <event>          # bump importance by event type, recalculate maturity. Does NOT update updatedAt or recency — those only change on content writes (create/update), not on reads/searches.
```

**Recency formula:** `e^(-ln(2) × days / HALF_LIFE_DAYS)`

**Hysteresis rules:**
- draft → validated: importance ≥ 65
- validated → core: importance ≥ 85
- core → validated: importance < 25 (not 65 — prevents flapping)
- validated → draft: importance < 30 (not 65 — prevents flapping)

### ct-manifest.sh (flat manifest)

Source: Copilot's flat schema, our index generation.

**Schema:**
```json
{
  "version": "1.0.0",
  "team": "my-team",
  "created": "2026-03-13T00:00:00Z",
  "lastRebuilt": "2026-03-13T00:00:00Z",
  "entries": [
    {
      "path": "backend/auth/jwt-patterns.md",
      "title": "JWT Patterns",
      "maturity": "core",
      "importance": 92,
      "tags": ["auth", "jwt"],
      "updatedAt": "2026-03-13T00:00:00Z"
    }
  ]
}
```

**Functions:**
```bash
ct_manifest_init <root>                      # create manifest if missing, validate if exists
ct_manifest_add <root> <rel-path>            # upsert entry (reads frontmatter from file)
ct_manifest_remove <root> <rel-path>         # delete entry
ct_manifest_rebuild <root>                   # scan filesystem, rebuild from scratch
ct_manifest_list <root>                      # output entry paths
ct_manifest_update_indexes <root>            # generate _index.md per domain directory
```

### ct-archive.sh (archival)

Source: Copilot's sourceable pattern, our delete-cascade logic.

**Functions:**
```bash
ct_archive_run <root>                        # archive draft entries with importance < 35
ct_archive_restore <root> <archived-full>    # restore from _archived/*.full.md
```

**Archival format:**
- `_archived/<rel-path>.full.md` — complete original file
- `_archived/<rel-path>.stub.md` — metadata + pointer

**Delete in context-tree.sh** also checks `_archived/` for stub/full counterparts (our fix from Plan 2).

### ct-search.sh (dual-mode search)

Source: Our dual-mode scoring, Copilot's library pattern.

**Functions:**
```bash
ct_search_run <root> <query> [top]           # BM25-only mode (top defaults to 10)
ct_search_with_cipher <root> <query> <cipher_json> [top]  # merged mode (top defaults to 10)
```

**BM25-only formula:** `(0.6 × bm25 + 0.2 × importance/100 + 0.2 × recency) × maturityBoost`
**Cipher-merged formula:** `(0.5 × cipher + 0.3 × bm25 + 0.1 × importance/100 + 0.1 × recency) × maturityBoost`

Where `maturityBoost = 1.15` for core entries, `1.0` otherwise.

### bm25.py (field-weighted search)

Source: Our implementation (unchanged).

**Field weights:** title×3, tags×2, keywords×2, body×1
**BM25 params:** k1=1.5, b=0.75
**Score filter:** results with bm25_score < 0.01 are excluded

### ct-sync.sh (orchestration)

Source: Copilot's sourceable pattern, our curate/query/score/archive actions.

**Functions:**
```bash
ct_sync_curate <root> <domain> <topic> <title> <content> [tags] [keywords] [source] [from_agent]
# Note: subtopic and related are intentionally dropped. Subtopic is expressed
# in the filesystem path (domain/topic/subtopic/title.md). Related entries are
# managed via tags/keywords rather than explicit links.
ct_sync_query <root> <query> [cipher_json] [top]  # top defaults to 10
ct_sync_refresh <root>                       # rebuild manifest + update indexes
ct_sync_slugify <string>                     # kebab-case conversion
```

### configure.sh (post-install manifest setup)

Source: Rewritten to produce flat `entries[]` manifest schema.

**Behavior:** Called by `install.sh` after context tree directory is created. Initializes `_manifest.json` with the flat schema (version, team, created, entries: []). If manifest already exists, validates and migrates from `domains[]` to `entries[]` if needed.

### mcp-detect.sh

Source: Our implementation (unchanged). Already sourceable.

## Hooks

### session-start.sh

Source: Copilot's pure-Python structured JSON output + our XGH_BRIEFING trigger.

**Output format:**
```json
{
  "result": "xgh: session-start loaded 5 context files",
  "contextFiles": [
    {
      "path": "backend/auth/jwt-patterns.md",
      "title": "JWT Patterns",
      "importance": 92,
      "maturity": "core",
      "excerpt": "First 3 lines of body..."
    }
  ],
  "decisionTable": [
    "Before writing code: run cipher_memory_search first.",
    "After significant work: run cipher_extract_and_operate_memory.",
    "For architectural choices: store rationale with cipher_store_reasoning_memory."
  ],
  "briefingTrigger": "full|compact|off"
}
```

**Implementation:** Single Python heredoc. This is a full rewrite — the current manifest-dependent text-blob output is replaced entirely. The new version walks the context tree directory directly via `rglob("*.md")` (no manifest dependency for entry selection — reads frontmatter from each file and scores by `maturity_rank × 100 + importance`). Reads `XGH_CONTEXT_TREE` env var with fallback walk-up from `pwd`. Reads `XGH_BRIEFING` env var (off|compact|auto|1). Excludes `_index.md` and `_archived/` entries.

### prompt-submit.sh

Source: Copilot's intent-detecting implementation.

**Output format:**
```json
{
  "result": "xgh: prompt-submit decision table injected",
  "promptIntent": "code-change|general",
  "requiredActions": ["Run cipher_memory_search before writing code.", "..."],
  "toolHints": ["cipher_memory_search", "cipher_extract_and_operate_memory", "cipher_store_reasoning_memory"]
}
```

**Implementation:** Python heredoc with regex intent detection (`implement|refactor|fix|build|code|write|change|feature|bug` → code-change).

## Modified Files (light touch)

These files require small, targeted updates but are NOT full rewrites:

- **install.sh** — update manifest initialization to flat `entries[]` schema (replace `"domains": []` with `"entries": []`), rename `XGH_CONTEXT_PATH` to `XGH_CONTEXT_TREE`
- **uninstall.sh** — update any `context-tree.sh` invocations to new API if needed
- **commands/query.md** — rename `XGH_CONTEXT_TREE_PATH` → `XGH_CONTEXT_TREE`
- **commands/status.md** — rename `XGH_CONTEXT_TREE_PATH` → `XGH_CONTEXT_TREE`

## Unchanged Files

The following are NOT modified by this spec:

- **All 17 skills/** — production-ready workflows
- **All other commands/** — complete with usage examples
- **config/agents.yaml** — agent registry
- **config/workflows/*.yaml** — 4 workflow templates
- **agents/collaboration-dispatcher.md** — multi-agent orchestrator
- **scripts/mcp-detect.sh** — MCP capability detection
- **scripts/bm25.py** — field-weighted BM25 engine
- **techpack.yaml** — pack configuration

## Test Strategy

### Rewrite (8 files)

These test the script API directly and must be rewritten for the new positional-arg library pattern:

| Test File | Tests | What Changes |
|-----------|-------|-------------|
| `test-ct-crud.sh` | ~23 | New positional-arg API, source library directly |
| `test-ct-frontmatter.sh` | ~14 | New function names (`ct_frontmatter_get` etc.) |
| `test-ct-scoring.sh` | ~11 | Source library, test hysteresis with new functions |
| `test-ct-manifest.sh` | ~14 | Flat `entries[]` schema, new function names |
| `test-ct-archive.sh` | ~15 | Sourceable library API |
| `test-ct-search.sh` | ~6 | Library functions, dual-mode |
| `test-ct-sync.sh` | ~11 | Library functions |
| `test-ct-integration.sh` | ~25 | End-to-end with new API, flat manifest |
| `test-ct-core.sh` | ~6 | Merge into `test-ct-crud.sh` or delete (overlapping coverage) |

### Update (1 file)

| Test File | Tests | What Changes |
|-----------|-------|-------------|
| `test-hooks.sh` | ~15 | Validate new JSON structure (contextFiles[], decisionTable[]) |

### Unchanged (13 files)

All static tests (skills, commands, config, multi-agent, team-skills, workflow-skills, briefing, install, techpack, uninstall, plan4-integration, collaborate-command, collaboration-agent) — no changes needed.

## Success Criteria

1. All rewritten scripts follow the sourceable library pattern with `BASH_SOURCE[0]` guard
2. All function names use `ct_` prefix consistently
3. Manifest uses flat `entries[]` schema
4. Scoring preserves hysteresis and named constants
5. Search preserves dual BM25+Cipher mode with field weighting
6. Hooks output structured JSON
7. All ~540 tests pass (rewritten + unchanged)
8. `context-tree.sh` CLI works as both sourced library and standalone script
