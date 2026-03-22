# Structural Cipher/Qdrant Cleanup — Design Spec

**Date:** 2026-03-20
**Status:** Approved
**Goal:** Remove the entire dead Cipher/Qdrant/BYOP layer from live code. lossless-claude (pure SQLite + FTS5) is the only memory backend.

---

## Context

xgh originally used Cipher MCP (with Qdrant vector store) for persistent memory. This was replaced by lossless-claude, which uses SQLite with FTS5 full-text search — no vector store, no embeddings, no Qdrant. The migration happened incrementally, leaving stale references throughout live code.

The BYOP (Bring Your Own Provider) preset system configured LLM providers, embedding models, and Qdrant vector stores. None of this is relevant anymore — lossless-claude handles everything internally with its `claude-process` summarizer.

## Scope

**In scope:** All live code (skills, scripts, hooks, tests, config, README, AGENTS.md)
**Out of scope:** Historical docs (`.xgh/context-tree/` content, `docs/plans/`, `docs/superpowers/`, `.xgh/plans/`, `.xgh/specs/`, `docs/research/`, `docs/reviews/`, `docs/audit-skills-hooks.md`)

## Changes

### Delete (entire files)

| Path | Reason |
|------|--------|
| `config/presets/local.yaml` | BYOP preset — dead stack |
| `config/presets/local-light.yaml` | BYOP preset — dead stack |
| `config/presets/openai.yaml` | BYOP preset — dead stack |
| `config/presets/anthropic.yaml` | BYOP preset — dead stack |
| `config/presets/cloud.yaml` | BYOP preset — dead stack |
| `config/presets/` directory | Empty after preset deletion |
| `docs/configuration-reference.md` | Entirely about Cipher env vars, Qdrant, cipher-post-hook |

Delete the `config/presets/` directory after removing all preset files. `config/` itself stays — it still contains `agents.yaml` and `ingest-template.yaml`.

### Gut (remove dead sections from files)

#### `skills/doctor/doctor.md`
- Remove Qdrant health check (curl to localhost:6333)
- Remove WAL diagnostics table and fix commands
- Remove Qdrant collection stats query
- Remove Qdrant from example output (both passing and failing)

#### `skills/analyze/analyze.md`
- Remove Qdrant REST PATCH call for dedup (lines ~136-151)
- Remove Qdrant TTL decay logic

#### `skills/ask/ask.md`
- Remove "ECONNREFUSED on Qdrant connection" from error patterns

#### `scripts/mcp-detect.sh`
- Remove `xgh_has_cipher()` function (lines ~90+)
- Remove cipher comment (line ~11)

#### `scripts/ct-search.sh`
- Remove `ct_search_with_cipher` function entirely
- Update file header comment (remove "dual-mode BM25+Cipher")

#### `scripts/ct-sync.sh`
- Remove cipher branch from `ct_sync_query` — always call `ct_search_run`
- Remove cipher parameter from function signature

#### `.claude/hooks/xgh-prompt-submit.sh`
- Remove "cipher memory decision table" reference from header comment

#### `config/workflows/*.yaml` (4 files)
- Replace "Cipher" with "lossless-claude" in `output:` strings and `completion.summary`
- Keep the workflow structure intact (roles, steps, dependencies are still valid)

### Update (modify references)

#### `commands/xgh-collaborate.md`
- No changes needed — references `config/workflows/` directory generically, which still exists

#### `agents/collaboration-dispatcher.md`
- No changes needed — references `config/workflows/` generically

#### `agents/code-reviewer.md`
- No changes needed — references `config/workflows/` generically

#### `README.md`
- Remove entire BYOP section (presets table, platform matrix, env var override, config reference link)
- Remove Qdrant from architecture diagram (`│  │  (Qdrant)  │`)
- Update tech stack table: remove "Vector memory | lossless-claude (SQLite + optional Qdrant)" → "Persistent memory | lossless-claude (SQLite + FTS5)"
- Remove "(BYOP)" from `LLM / embeddings` tech stack row
- Update Plan 1 description: remove "BYOP config" → "one-liner installer"
- Remove Plan 8 cipher.yml reference from implementation status
- Remove cipher post-hook reference from file structure
- Update "No vendor lock-in" trust bullet: remove BYOP reference, keep the open/swappable message

#### `AGENTS.md`
- Remove "optional Qdrant (semantic)" from lossless-claude description
- Remove "Dual-engine search" bullet or rewrite to "FTS5 full-text search"
- Remove BYOP bullet from overview list
- Remove Qdrant presets from file structure listing
- Update tech stack: remove Qdrant line, remove "(BYOP)" from LLM/embeddings row, update Config row to remove "(presets)"
- Remove "Adding a new BYOP preset" subsection
- Remove Plan 8 cipher.yml reference
- Remove entire `docs/configuration-reference.md` link and surrounding paragraph (file is being deleted)
- Remove or rewrite Key Design Decision #3 "BYOP architecture"

#### Tests
- `tests/test-config.sh` — remove entire preset section (lines 7-26: preset existence, required fields, local defaults, cloud API keys). Keep lines 28-37 (plugin subdirs check).
- `tests/test-analyze.sh` — remove `assert_contains "skills/analyze/analyze.md" "cipher_memory_search"`
- `tests/test-brief.sh` — remove `assert_contains "$REPO_ROOT/scripts/mcp-detect.sh" "xgh_has_cipher"`
- `tests/test-briefing.sh` — remove cipher/cipher_memory_search assertions
- `tests/test-ct-search.sh` — remove tests 6-8 (cipher merge, cipher_similarity field, cipher sorted)
- `tests/test-ct-sync.sh` — rename `cipher-agent` to `test-agent` in the from_agent test (the test validates from_agent frontmatter storage, which is still a live feature)
- `tests/test-multi-agent.sh` — no changes needed (workflow files are kept, assertions contain no Cipher/Qdrant refs)
- `tests/test-pipeline-skills.sh` — remove `assert_contains "skills/doctor/doctor.md" "Qdrant"` and `assert_contains "skills/index/index.md" "cipher_extract_and_operate_memory"`
- `tests/test-plan4-integration.sh` — remove "Cipher tool references" section

#### `.xgh/context-tree/_manifest.json`
- Remove "byop" and "cipher" from `tags` arrays where they appear
- Leave `title` fields unchanged even if they reference Cipher — they describe historical decision documents whose content is out of scope

## Non-goals

- Rewriting historical documents in `.xgh/context-tree/`, `docs/plans/`, etc.
- Removing the `docs/research/cipher-mcp-deep-dive.md` research artifact
- Changing lossless-claude's own config (that's env cleanup, not codebase)
- Adding new features — this is purely removal

## Testing

After all changes, run the full test suite:
```bash
for t in tests/test-*.sh; do echo -n "$(basename $t): "; bash "$t" 2>&1 | tail -1; done
```

All tests must pass. No test should assert the existence of Cipher, Qdrant, or BYOP presets.

## Risk

Low. This is removing dead code. The only functional code being modified is:
- `ct-search.sh` (removing unused function)
- `ct-sync.sh` (removing unused code path)
- `mcp-detect.sh` (removing unused function)

None of these cipher code paths are called by any live skill or hook.
