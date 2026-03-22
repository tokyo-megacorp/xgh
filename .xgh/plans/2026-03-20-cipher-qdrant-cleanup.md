# Cipher/Qdrant Structural Cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all dead Cipher/Qdrant/BYOP references from live code — lossless-claude (pure SQLite + FTS5) is the only memory backend.

**Architecture:** Pure removal/update across ~25 files. No new features. Tests updated alongside code to stay green. Each task is independently committable.

**Tech Stack:** Bash, Markdown, YAML, JSON

**Spec:** `.xgh/specs/2026-03-20-cipher-qdrant-cleanup-design.md`

---

### Task 1: Delete BYOP presets + configuration reference

**Files:**
- Delete: `config/presets/local.yaml`
- Delete: `config/presets/local-light.yaml`
- Delete: `config/presets/openai.yaml`
- Delete: `config/presets/anthropic.yaml`
- Delete: `config/presets/cloud.yaml`
- Delete: `config/presets/` (directory)
- Delete: `docs/configuration-reference.md`
- Modify: `tests/test-config.sh`

- [ ] **Step 1: Update test-config.sh — remove preset assertions**

Remove lines 7-26 (preset existence, required fields, local defaults, cloud API keys). Keep lines 1-6 (header/helpers) and lines 28-41 (plugin subdirs check). The resulting file should be:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

# Plugin subdirs (agents, skills, commands, hooks live at root)
assert_file_exists "hooks/.gitkeep"
for d in skills commands agents; do
  if [ -d "$d" ] && [ "$(ls -A "$d")" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $d is empty or missing"
    FAIL=$((FAIL+1))
  fi
done


echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Delete preset files and directory**

```bash
rm -rf config/presets/
```

- [ ] **Step 3: Delete configuration reference**

```bash
rm docs/configuration-reference.md
```

- [ ] **Step 4: Run test to verify**

```bash
bash tests/test-config.sh
```
Expected: PASS (4 passed, 0 failed)

- [ ] **Step 5: Commit**

```bash
git add -u config/presets/ docs/configuration-reference.md tests/test-config.sh
git commit -m "chore: remove BYOP presets and configuration reference (dead Cipher/Qdrant stack)"
```

---

### Task 2: Update workflow YAMLs (Cipher → lossless-claude)

**Files:**
- Modify: `config/workflows/plan-review.yaml`
- Modify: `config/workflows/parallel-impl.yaml`
- Modify: `config/workflows/validation.yaml`
- Modify: `config/workflows/security-review.yaml`

- [ ] **Step 1: Replace "Cipher" with "lossless-claude" in all workflow files**

In each of the 4 files, replace every occurrence of "Cipher" (case-sensitive) with "lossless-claude" in `output:` strings and `completion.summary`. Use `sed` or Edit tool with `replace_all`.

Affected strings (across all 4 files):
- `"Store plan in Cipher workspace with type=plan"` → `"Store plan in lossless-claude with type=plan"`
- `"Store review in Cipher workspace with type=review"` → `"Store review in lossless-claude with type=review"`
- `"Store implementation in Cipher with type=result"` → `"Store implementation in lossless-claude with type=result"`
- `"Store fixes in Cipher with type=result, reference original findings"` → `"Store fixes in lossless-claude with type=result, reference original findings"`
- `"Store task breakdown in Cipher with type=plan, one message per subtask"` → `"Store task breakdown in lossless-claude with type=plan, one message per subtask"`
- `"Store workflow summary in Cipher with thread_id for future reference"` → `"Store workflow summary in lossless-claude with thread_id for future reference"`
- `"Store final plan with type=decision, status=completed"` — no Cipher ref, leave as-is
- `"Store implementation result with type=result, status=completed"` — no Cipher ref, leave as-is
- `"Store fix in Cipher with type=result"` → `"Store fix in lossless-claude with type=result"`

- [ ] **Step 2: Verify no Cipher references remain**

```bash
grep -ri "cipher" config/workflows/ && echo "FAIL: cipher refs remain" || echo "PASS: clean"
```
Expected: PASS: clean

- [ ] **Step 3: Commit**

```bash
git add config/workflows/
git commit -m "chore: update workflow YAMLs — Cipher → lossless-claude"
```

---

### Task 3: Clean scripts (mcp-detect.sh, ct-search.sh, ct-sync.sh)

**Files:**
- Modify: `scripts/mcp-detect.sh`
- Modify: `scripts/ct-search.sh`
- Modify: `scripts/ct-sync.sh`
- Modify: `tests/test-brief.sh`
- Modify: `tests/test-briefing.sh`
- Modify: `tests/test-ct-search.sh`
- Modify: `tests/test-ct-sync.sh`

- [ ] **Step 1: Update test-brief.sh — remove xgh_has_cipher assertion**

Remove line 30: `assert_contains "$REPO_ROOT/scripts/mcp-detect.sh" "xgh_has_cipher"`

Replace with: `assert_contains "$REPO_ROOT/scripts/mcp-detect.sh" "xgh_has_lossless_claude"`

- [ ] **Step 2: Update test-briefing.sh — remove cipher assertions**

Remove line 24: `assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "cipher"`

Replace with: `assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "lossless_claude"`

Remove line 36: `assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "cipher_memory_search"`

Replace with: `assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "lcm_search"`

- [ ] **Step 3: Update test-ct-search.sh — remove cipher tests 6-8**

Remove lines 131-158 (Test 6: cipher merge, Test 7: cipher_similarity field, Test 8: cipher sorted). Keep Test 9 (empty query) and Test 10 (database excluded) intact.

- [ ] **Step 4: Update test-ct-sync.sh — rename cipher-agent to test-agent**

On line 104, change `"cipher-agent"` to `"test-agent"`.
On line 111, change `"cipher-agent"` to `"test-agent"`.

- [ ] **Step 5: Clean mcp-detect.sh**

Remove the comment on line 11: `#   xgh_has_cipher   && echo "Cipher available"`

Remove lines 89-92 (the `xgh_has_cipher()` backwards-compat alias):
```bash
# Backwards-compat alias
xgh_has_cipher() {
  xgh_has_lossless_claude
}
```

- [ ] **Step 6: Clean ct-search.sh**

Update line 2 header: `# ct-search.sh — BM25 search library` (remove "dual-mode BM25+Cipher")

Update line 3: `# Sourceable library providing ct_search_run function.` (remove "and ct_search_with_cipher")

Remove lines 44-105 entirely (the `ct_search_with_cipher` function).

- [ ] **Step 7: Clean ct-sync.sh**

Replace lines 89-101 (`ct_sync_query` function) with:

```bash
# ct_sync_query <root> <query> [top]
ct_sync_query() {
  local root="${1:?root required}"
  local query="${2:-}"
  local top="${3:-10}"

  ct_search_run "$root" "$query" "$top"
}
```

Note: the cipher_json parameter is removed from the signature.

- [ ] **Step 8: Run tests to verify**

```bash
bash tests/test-brief.sh && bash tests/test-briefing.sh && bash tests/test-ct-search.sh && bash tests/test-ct-sync.sh
```
Expected: All pass

- [ ] **Step 9: Commit**

```bash
git add scripts/mcp-detect.sh scripts/ct-search.sh scripts/ct-sync.sh tests/test-brief.sh tests/test-briefing.sh tests/test-ct-search.sh tests/test-ct-sync.sh
git commit -m "chore: remove Cipher refs from scripts and their tests"
```

---

### Task 4: Clean skills (doctor.md, analyze.md, ask.md)

**Files:**
- Modify: `skills/doctor/doctor.md`
- Modify: `skills/analyze/analyze.md`
- Modify: `skills/ask/ask.md`
- Modify: `tests/test-analyze.sh`
- Modify: `tests/test-pipeline-skills.sh`

- [ ] **Step 1: Update test-analyze.sh — remove cipher assertion**

Remove line 12: `assert_contains "skills/analyze/analyze.md" "cipher_memory_search"`

(This test is already failing — the skill was cleaned in a previous session but the test wasn't updated.)

- [ ] **Step 2: Update test-pipeline-skills.sh — remove Qdrant and cipher assertions**

Remove line 20: `assert_contains "skills/doctor/doctor.md"     "Qdrant"`

Remove line 23: `assert_contains "skills/index/index.md" "cipher_extract_and_operate_memory"`

(Both assertions are already failing — skills were cleaned previously.)

- [ ] **Step 3: Clean doctor.md — remove Qdrant sections**

Remove lines 53-70 (Qdrant health check, deeper diagnosis, WAL diagnostics table):
Starting from `Qdrant: \`curl -sf http://localhost:6333/healthz\`` through the `| Binary missing |` table row.

Remove lines 188-192 (Check 5 — Workspace stats section entirely):
```
## Check 5 — Workspace stats

Query Qdrant collection stats:
...
Show: exists ✓/✗, vector count, approximate size.
```

Renumber Check 6 → Check 5, Check 7 → Check 6.

In the output format section, remove line 246: `  ✓ Qdrant: localhost:6333 responding`

Remove lines 254-255 (Qdrant failure example):
```
  ✗ Qdrant: not responding — WAL lock detected
    Fix: pkill -f qdrant && rm -f ...
```

Remove lines 294-295 (Workspace section from output):
```
Workspace
  ✓ Collection "xgh-workspace" exists (142 vectors)
```

- [ ] **Step 4: Clean analyze.md — remove Qdrant dedup and TTL**

In Step 5 (Deduplicate), remove lines 136-142 (the Qdrant REST PATCH call and "either way, skip" logic). Replace with:

```markdown
   - Skip writing a new entry (the existing memory covers this content)
```

So the full Step 5 reads: search lcm_search → if similarity ≥ threshold → skip → else proceed to Step 6.

In Step 6 (TTL management), remove lines 150-152 that reference Qdrant:
```
1. Search lossless-claude for memories with `xgh_status: active` and non-null `xgh_ttl`
2. For each where `xgh_ttl` < now: update Qdrant payload to `xgh_status: decayed`
```

Replace with:
```
1. Search lossless-claude for memories with `xgh_status: active` and non-null `xgh_ttl`
2. For each where `xgh_ttl` < now: mark as decayed in the next digest
```

- [ ] **Step 5: Clean ask.md — remove Qdrant error example**

On line 81, change `- "ECONNREFUSED on Qdrant connection"` to `- "Connection refused on external service"`

Also update the Scoring Formula section (lines 139-151). Remove `lcm_similarity` vector cosine reference since lossless-claude uses FTS5 not vectors. Replace:

```markdown
score = (0.5 * lcm_similarity + 0.3 * bm25_score + 0.1 * importance + 0.1 * recency) * maturityBoost
```

With:

```markdown
score = (0.6 * bm25_score + 0.2 * importance + 0.2 * recency) * maturityBoost
```

Update the bullet list to:
- `bm25_score`: 0-1, keyword match score from context tree
- `importance`: 0-100 normalized to 0-1
- `recency`: 0-1, exponential decay with ~21-day half-life
- `maturityBoost`: core = 1.15, all others = 1.0

(Note: the actual `ct_search_run` implementation uses `1.0` for everything except core — there is no separate draft penalty.)

- [ ] **Step 6: Run tests to verify**

```bash
bash tests/test-analyze.sh && bash tests/test-pipeline-skills.sh
```
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add skills/doctor/doctor.md skills/analyze/analyze.md skills/ask/ask.md tests/test-analyze.sh tests/test-pipeline-skills.sh
git commit -m "chore: remove Qdrant/Cipher refs from doctor, analyze, and ask skills"
```

---

### Task 5: Clean hook + remaining test

**Files:**
- Modify: `.claude/hooks/xgh-prompt-submit.sh`
- Modify: `tests/test-plan4-integration.sh`

- [ ] **Step 1: Update test-plan4-integration.sh — remove Cipher tool references section**

Remove lines 73-78 (the "All skills reference Cipher tools" section):
```bash
# ── All skills reference Cipher tools ─────────────────
echo ""
echo "--- Cipher tool references ---"
for skill in pr-context-bridge knowledge-handoff convention-guardian cross-team-pollinator subagent-pair-programming onboarding-accelerator; do
  assert_contains "skills/$skill/$skill.md" "cipher_memory_search"
done
```

- [ ] **Step 2: Clean xgh-prompt-submit.sh header**

Change line 3 from:
```bash
# Detects prompt intent and injects cipher memory decision table as additionalContext.
```
To:
```bash
# Detects prompt intent and injects memory decision table as additionalContext.
```

- [ ] **Step 3: Run test to verify**

```bash
bash tests/test-plan4-integration.sh
```
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add .claude/hooks/xgh-prompt-submit.sh tests/test-plan4-integration.sh
git commit -m "chore: remove Cipher refs from prompt-submit hook and plan4 tests"
```

---

### Task 6: Clean README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Remove BYOP section**

Remove lines 141-190 (the entire `<details><summary><b>BYOP — Bring Your Own Provider</b></summary>` block including its nested `<details>` for Configuration Reference and its closing `</details>` tags).

- [ ] **Step 2: Update architecture diagram**

Replace lines 209-212:
```
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Vector DB │  │  SQLite    │  │  LLM + Emb │            │
│  │  (Qdrant)  │  │ (sessions) │  │  (BYOP)    │            │
│  └────────────┘  └────────────┘  └────────────┘            │
```

With:
```
│  ┌──────────────────────────────┐                           │
│  │  SQLite + FTS5 (lossless-claude)                         │
│  └──────────────────────────────┘                           │
```

- [ ] **Step 3: Update tech stack table**

Replace:
```
| Vector memory | lossless-claude (SQLite + optional Qdrant) |
```
With:
```
| Persistent memory | lossless-claude (SQLite + FTS5) |
```

Replace:
```
| Config | YAML (presets), JSON (settings) |
```
With:
```
| Config | YAML, JSON (settings) |
```

Remove row:
```
| Model server | vllm-mlx, Ollama, or remote URL |
```

Replace:
```
| LLM / embeddings | vllm-mlx, Ollama, OpenAI, Anthropic, OpenRouter (BYOP) |
```
With:
```
| LLM | claude-process (via lossless-claude) |
```

- [ ] **Step 4: Update implementation status**

Change Plan 1 description:
```
| 1 — Foundation | Scaffold, BYOP config, one-liner installer | Done |
```
To:
```
| 1 — Foundation | Scaffold, one-liner installer | Done |
```

Change Plan 8 description:
```
| 8 — Ollama / Linux | Ollama backend, backend-aware cipher.yml + MCP env vars | Done |
```
To:
```
| 8 — Ollama / Linux | Ollama backend, cross-platform support | Done |
```

- [ ] **Step 5: Update Trust & Privacy section**

Replace line 287:
```
- **No vendor lock-in.** BYOP: swap backends and providers without reinstalling.
```
With:
```
- **No vendor lock-in.** Swap providers without reinstalling. Open standards, no proprietary formats.
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: remove BYOP/Qdrant/Cipher refs from README"
```

---

### Task 7: Clean AGENTS.md

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Update "What is xgh?" section**

Replace line 12:
```
- **lossless-claude** — persistent memory via SQLite (episodic) and optional Qdrant (semantic) for storing and querying past decisions, reasoning chains, and patterns
```
With:
```
- **lossless-claude** — persistent memory via SQLite + FTS5 for storing and querying past decisions, reasoning chains, and patterns
```

Replace line 14:
```
- **Dual-engine search** — lossless-claude vector similarity + BM25 keyword search merged with a scored ranking formula
```
With:
```
- **Context search** — BM25 keyword search over the context tree with scored ranking (importance, recency, maturity)
```

Remove line 17 entirely:
```
- **BYOP (Bring Your Own Provider)** — presets for OpenAI, Anthropic, OpenRouter, or cloud Qdrant (separate from the inference backend)
```

- [ ] **Step 2: Update Tech Stack table**

Replace line 33: `| Config | YAML (presets), JSON (settings) |` → `| Config | YAML, JSON (settings) |`

Replace line 36: `| Vector memory | lossless-claude (SQLite + optional Qdrant) |` → `| Persistent memory | lossless-claude (SQLite + FTS5) |`

Replace line 39: `| LLM / embeddings | vllm-mlx, Ollama, OpenAI, Anthropic, or OpenRouter (BYOP) |` → `| LLM | claude-process (via lossless-claude) |`

- [ ] **Step 3: Update Repository Structure**

Remove lines 51-57 (the `config/presets/` tree):
```
├── config/
│   └── presets/                     # BYOP provider presets
│       ├── local.yaml               # vllm-mlx + local Qdrant (default)
│       ├── local-light.yaml         # vllm-mlx + in-memory vectors
│       ├── openai.yaml              # OpenAI GPT-4o-mini + Qdrant
│       ├── anthropic.yaml           # Claude Haiku + Qdrant
│       └── cloud.yaml               # OpenRouter + Qdrant Cloud
```

Replace with:
```
├── config/
│   ├── agents.yaml                  # Agent registry
│   ├── ingest-template.yaml         # Ingest config template
│   └── workflows/                   # Multi-agent workflow templates
```

- [ ] **Step 4: Remove BYOP preset subsection**

Remove lines 131-136 (the "Adding a new BYOP preset" section):
```
### Adding a new BYOP preset

1. Copy an existing preset from `config/presets/` as a starting point
2. Update `vector_store.type`, `vector_store.url`, `llm.*`, and `embeddings.*` fields
3. Add a test in `tests/test-config.sh`
```

- [ ] **Step 5: Update Implementation Status**

Change Plan 1 (line 151): remove "BYOP config, " from description.

Change Plan 8 (line 160):
```
| Plan 8 | Ollama / Linux Support — Ollama backend, backend-aware cipher.yml + MCP env vars | ✅ Complete |
```
To:
```
| Plan 8 | Ollama / Linux Support — Ollama backend, cross-platform support | ✅ Complete |
```

Remove line 165 entirely:
```
For the full env var reference, backend/MCP matrix, and cipher post-hook behavior see [`docs/configuration-reference.md`](docs/configuration-reference.md).
```

- [ ] **Step 6: Update Key Design Decisions**

Replace line 195:
```
1. **Dual-engine search** — lossless-claude vectors (semantic) + BM25 (keyword) in parallel; results merged with weighted scoring
```
With:
```
1. **Context tree search** — BM25 keyword search with scored ranking (importance, recency, maturity boost)
```

Replace line 197:
```
3. **BYOP architecture** — presets abstract provider details; the installer and lossless-claude are provider-agnostic
```
With:
```
3. **Provider framework** — modular bash/MCP providers for external services; lossless-claude handles memory internally
```

- [ ] **Step 7: Commit**

```bash
git add AGENTS.md
git commit -m "docs: remove BYOP/Qdrant/Cipher refs from AGENTS.md"
```

---

### Task 8: Clean manifest tags

**Files:**
- Modify: `.xgh/context-tree/_manifest.json`

- [ ] **Step 1: Remove stale tags from manifest**

Read `_manifest.json` and remove `"byop"` and `"cipher"` from any `tags` arrays. Leave `title` fields unchanged (they describe historical documents).

Use python3 to do this safely:

```python
import json

with open('.xgh/context-tree/_manifest.json') as f:
    manifest = json.load(f)

stale_tags = {'byop', 'cipher'}
for entry in manifest.get('entries', []):
    if 'tags' in entry:
        entry['tags'] = [t for t in entry['tags'] if t.lower() not in stale_tags]

with open('.xgh/context-tree/_manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')
```

- [ ] **Step 2: Verify no stale tags remain**

```bash
grep -i '"byop"\|"cipher"' .xgh/context-tree/_manifest.json && echo "FAIL" || echo "PASS: clean"
```
Expected: PASS: clean (title fields may still contain "Cipher" — that's intentional)

- [ ] **Step 3: Commit**

```bash
git add .xgh/context-tree/_manifest.json
git commit -m "chore: remove stale byop/cipher tags from context tree manifest"
```

---

### Task 9: Full test suite verification

- [ ] **Step 1: Run all tests**

```bash
for t in tests/test-*.sh; do echo -n "$(basename $t): "; bash "$t" 2>&1 | tail -1; done
```

Expected: All tests pass, 0 failures.

- [ ] **Step 2: Verify no Cipher/Qdrant/BYOP in live code**

```bash
# Check live code only (exclude docs/, .xgh/context-tree/ content, .xgh/plans/, .xgh/specs/)
grep -ri "cipher\|qdrant\|byop" \
  skills/ scripts/ hooks/ .claude/hooks/ tests/ config/ commands/ agents/ \
  README.md AGENTS.md CLAUDE.md \
  --include="*.sh" --include="*.md" --include="*.yaml" --include="*.json" \
  | grep -v "lossless-claude" \
  | grep -v "test-multi-agent" \
  | grep -v "_manifest.json"
```

Expected: No output (clean). The `lossless-claude` exclusion filters the workflow YAML updates. Manifest titles referencing Cipher are acceptable (historical).

- [ ] **Step 3: Run doctor smoke test (if available)**

```bash
bash tests/test-pipeline-skills.sh
```
Expected: All pass

---

## Summary of changes

| Category | Files deleted | Files modified |
|----------|-------------|---------------|
| Config/presets | 6 (5 YAML + directory) | 0 |
| Config/workflows | 0 | 4 |
| Docs | 1 | 2 (README, AGENTS) |
| Scripts | 0 | 3 |
| Skills | 0 | 3 |
| Hooks | 0 | 1 |
| Tests | 0 | 8 |
| Manifest | 0 | 1 |
| **Total** | **7** | **22** |
