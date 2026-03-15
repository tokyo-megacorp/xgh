# Code Review: xgh-ingest Full Implementation

**Reviewer:** Claude Opus 4.6
**Date:** 2026-03-15
**Scope:** 25 files, ~1582 lines (commits 581bb56..0e3688e)
**Verdict:** Solid architecture with 3 critical bugs, 4 important issues, 5 suggestions

---

## What Was Done Well

- Clean dual-loop separation: retriever (fast, external I/O) vs analyzer (Cipher writes) is a sound architectural decision
- Skills are comprehensive, internally consistent, and well-structured with proper frontmatter
- Config template (`ingest-template.yaml`) is thorough with sensible defaults for all subsystems
- Install.sh integration is clean: idempotent (skips existing files), correct directory creation
- Test coverage exists for all layers (foundation, retrieve, analyze, skills) and all 68 assertions pass
- Usage tracker with daily cap and quiet hours shows good operational discipline

---

## CRITICAL Issues (must fix)

### C1. workspace-write.js reads `embedding.endpoint` but cipher.yml has `baseURL`

**File:** `/Users/pedro/Developer/tr-xgh/lib/workspace-write.js` line 68

```javascript
const embeddingEndpoint = cipherCfg?.embedding?.endpoint || 'http://localhost:11434/v1';
```

The live `~/.cipher/cipher.yml` uses `baseURL`, not `endpoint`. The parse result confirms `embedding.endpoint` is `undefined`, so it **always falls back to the hardcoded default**. This works today only because the default matches the real URL. If the user changes their port or host, workspace-write.js will silently ignore it and hit the wrong endpoint.

**Fix:** Change to `cipherCfg?.embedding?.baseURL || cipherCfg?.embedding?.endpoint || 'http://localhost:11434/v1'`

### C2. YAML parser comment-stripping regex corrupts values containing `#`

**File:** `/Users/pedro/Developer/tr-xgh/lib/workspace-write.js` line 15

```javascript
const line = raw.replace(/#.*$/, '');
```

Verified empirically:
- `url: https://example.com/path#fragment` parses as `url: "https://example.com/path"` (fragment stripped)
- `channel: #engineering` parses as `channel: {}` (entire value destroyed, becomes an empty parent object)
- `color: #ff0000` parses as `color: {}` (same)

The current cipher.yml does not contain hash values, so this is not biting you today. But the ingest config template references Slack channels with `#` prefixes, and any future config with URL fragments, color codes, or anchor references will silently corrupt.

**Fix:** Only strip comments after unquoted whitespace: `raw.replace(/\s+#.*$/, '')` or better, only strip `#` preceded by space that is not inside quotes.

### C3. YAML parser treats `mcpServers: {}` as string value `"{}"`

**File:** `/Users/pedro/Developer/tr-xgh/lib/workspace-write.js` line 22-29

The parser does not understand YAML inline collections. `mcpServers: {}` is parsed as `mcpServers: "{}"` (a string). This is not currently causing a runtime error because nothing reads `mcpServers` from the parsed config, but it means the parser is semantically incorrect for any inline object/array YAML syntax.

**Fix:** Add a special case: if `val` matches `{}` or `[]`, treat as empty object/array respectively.

---

## IMPORTANT Issues (should fix)

### I1. sed replacement in ingest-schedule.sh fails with `&` in paths

**File:** `/Users/pedro/Developer/tr-xgh/scripts/ingest-schedule.sh` line 18-21

```bash
sed -e "s|XGH_HOME|${HOME}|g"
```

Verified: `&` in the replacement string is a sed backreference. A `HOME` path like `/Users/pedro&sons` renders `XGH_HOME` as `/Users/pedroXGH_HOMEsons`. While uncommon on macOS, this is a correctness bug.

**Fix:** Escape `&` in the variable: `sed -e "s|XGH_HOME|${HOME//&/\\&}|g"` or use `envsubst` or a safer templating approach.

### I2. config-reader.sh has no fallback when PyYAML is unavailable

**File:** `/Users/pedro/Developer/tr-xgh/lib/config-reader.sh` line 11

If `python3` is present but `PyYAML` is not installed, the heredoc python script fails silently (the `except` block prints the default). But if `python3` itself is missing, the function produces an error to stderr and returns the default. This is acceptable but fragile.

The real concern: on a fresh macOS, `python3` exists but PyYAML may not be pre-installed (it is on macOS 15 via system Python, but not guaranteed). The install.sh script does not install PyYAML as a dependency.

**Fix:** Add a quick `python3 -c "import yaml" 2>/dev/null` check at the top of `xgh_config_get`, or have install.sh ensure `pip3 install pyyaml` or `uv pip install pyyaml`.

### I3. usage-tracker.sh does not sanitize CSV fields

**File:** `/Users/pedro/Developer/tr-xgh/lib/usage-tracker.sh` line 14

```bash
echo "$(date ...),${run_name},${turns},${tokens_estimate}" >> "$log_file"
```

If `run_name` or any field contains a comma, the CSV structure breaks and the awk parser in `xgh_usage_check_cap` reads wrong columns. While the current callers pass controlled values like `"retriever"` and `"analyzer"`, this is defensive programming 101.

**Fix:** Quote the fields or validate that they contain no commas.

### I4. Qdrant collection name inconsistency

workspace-write.js reads `xghCfg?.cipher?.workspace_collection` which defaults to `xgh-workspace` (line 71), but install.sh creates collections named `knowledge_memory`, `workspace_memory`, and `reflection_memory` (line 458). The ingest config template sets `workspace_collection: xgh-workspace`. These are different namespaces -- writes go to `xgh-workspace` while the pre-created collections are the `*_memory` ones from Cipher.

This is not necessarily wrong (xgh uses its own collection), but the collection `xgh-workspace` is never pre-created by install.sh. The first write will fail unless Qdrant auto-creates it (it does not by default).

**Fix:** Either add `xgh-workspace` to the `ensure_qdrant_collections` list in install.sh, or have workspace-write.js auto-create the collection on first use.

---

## Suggestions (nice to have)

### S1. Plist templates should use `$HOME` expansion or `envsubst` instead of sed

The current sed approach with placeholder tokens (`XGH_LOG_DIR`, `XGH_HOME`, `XGH_CLAUDE_BIN`) works but is fragile. Consider using `envsubst` which is available on macOS via `gettext`.

### S2. workspace-write.js should validate embedding dimensions

The embedding API returns vectors, but workspace-write.js does not check that the returned vector length matches the Qdrant collection's configured dimensions (768). A dimension mismatch produces a cryptic Qdrant error. A pre-flight check or at least a better error message would help.

### S3. Tests are assertion-only, no functional integration tests

All 4 test files use `assert_file_exists` and `assert_contains` (string matching). The only functional test is the config-reader roundtrip in test-ingest-foundation.sh. Consider adding:
- A `--dry-run` test for workspace-write.js that verifies the payload structure
- An awk parsing test for usage-tracker.sh with sample CSV data

### S4. Analyzer skill references Qdrant REST directly for dedup updates

In `skills/ingest-analyze/ingest-analyze.md` Step 5, the skill instructs Claude to use raw `curl` against Qdrant for payload updates. This duplicates the Qdrant URL resolution logic that lives in workspace-write.js. Consider adding an `--update` mode to workspace-write.js.

### S5. ingest-template.yaml `urgency.relevance` keys are abstract

`my_platform`, `my_squad`, `other_platform` etc. are placeholder labels. The retriever skill explains how to map them, but the config itself could be clearer with comments explaining these are multiplier values applied based on message context matching.

---

## Plan Alignment

The implementation matches the dual-loop architecture from the design spec. All 6 planned skills and commands are present. The TTL lifecycle, urgency scoring, and content type taxonomy from the spec are faithfully implemented in the skill definitions. The install.sh integration correctly copies all files to `~/.xgh/`. The techpack.yaml has entries for all 15 new components.

One deviation: the spec mentions Gmail integration for design review tracking (Proposals 1, 3, 4 in the design proposals doc), but this was not implemented. This appears intentional -- the proposals doc is aspirational (future feature ideas), not the implementation spec.

---

## Test Results

All existing tests pass:
- `test-ingest-foundation.sh`: 17/17
- `test-ingest-retrieve.sh`: 18/18
- `test-ingest-analyze.sh`: 13/13
- `test-ingest-skills.sh`: 20/20
