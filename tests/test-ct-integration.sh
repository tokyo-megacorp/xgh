#!/usr/bin/env bash
set -euo pipefail

# Integration test — exercises the full context-tree lifecycle via the CLI.
# ~30 assertions covering init, create, read, update, score, search,
# sync (curate/query/refresh), archive, restore, delete, list.

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CT="${SCRIPT_DIR}/scripts/context-tree.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XGH_CONTEXT_TREE="$TMP"

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $label — expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $label — expected to find '$needle' in output"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $label — file does not exist: $path"
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $label — file should not exist: $path"
  fi
}

get_field() {
  local file="$1" key="$2"
  bash "${SCRIPT_DIR}/scripts/ct-frontmatter.sh" get "$file" "$key" 2>/dev/null || echo ""
}

count_manifest_entries() {
  python3 -c "
import json
with open('${TMP}/_manifest.json') as f:
    m = json.load(f)
print(len(m.get('entries', [])))
"
}

# ========== 1. Init ==========
echo "--- 1. Init ---"
INIT_OUT=$(bash "$CT" init)
assert_contains "init output" "$INIT_OUT" "Initialized"
assert_file_exists "manifest created" "$TMP/_manifest.json"

# Verify flat entries[] schema with lastRebuilt field
SCHEMA_OK=$(python3 -c "
import json
with open('${TMP}/_manifest.json') as f:
    m = json.load(f)
assert 'entries' in m and isinstance(m['entries'], list), 'no flat entries[]'
assert 'lastRebuilt' in m, 'no lastRebuilt'
print('ok')
")
assert_eq "flat schema with lastRebuilt" "ok" "$SCHEMA_OK"

# ========== 2. Create 4 entries across 2 domains ==========
echo "--- 2. Create entries ---"
bash "$CT" create "auth/jwt-patterns.md" "JWT Patterns" "JSON Web Token best practices."
bash "$CT" create "auth/oauth-flows.md" "OAuth Flows" "OAuth 2.0 authorization code flow."
bash "$CT" create "api/error-handling.md" "Error Handling" "Standardized error envelope."
bash "$CT" create "api/pagination.md" "Pagination" "Cursor-based pagination for lists."

ENTRY_COUNT=$(count_manifest_entries)
assert_eq "4 entries in manifest" "4" "$ENTRY_COUNT"

# ========== 3. Verify manifest flat schema ==========
echo "--- 3. Manifest schema ---"
MANIFEST_CHECK=$(python3 -c "
import json
with open('${TMP}/_manifest.json') as f:
    m = json.load(f)
assert 'lastRebuilt' in m
assert all('path' in e for e in m['entries'])
print('ok')
")
assert_eq "manifest entries have path field" "ok" "$MANIFEST_CHECK"

# ========== 4. Verify _index.md per domain ==========
echo "--- 4. Domain indexes ---"
# create doesn't auto-update indexes; rebuild manifest to generate them
bash "$CT" manifest update-indexes
assert_file_exists "auth _index.md" "$TMP/auth/_index.md"
assert_file_exists "api _index.md" "$TMP/api/_index.md"

# ========== 5. Read — verify accessCount incremented, importance bumped ==========
echo "--- 5. Read entry ---"
ACCESS_BEFORE=$(get_field "$TMP/auth/jwt-patterns.md" "accessCount")
IMP_BEFORE=$(get_field "$TMP/auth/jwt-patterns.md" "importance")
bash "$CT" read "auth/jwt-patterns.md" > /dev/null
ACCESS_AFTER=$(get_field "$TMP/auth/jwt-patterns.md" "accessCount")
IMP_AFTER=$(get_field "$TMP/auth/jwt-patterns.md" "importance")

assert_eq "accessCount incremented" "$((ACCESS_BEFORE + 1))" "$ACCESS_AFTER"
# search-hit event adds +3
EXPECTED_IMP=$((IMP_BEFORE + 3))
assert_eq "importance bumped by read (+3)" "$EXPECTED_IMP" "$IMP_AFTER"

# ========== 6. Update — verify updateCount incremented, importance bumped ==========
echo "--- 6. Update entry ---"
UPDATE_BEFORE=$(get_field "$TMP/auth/jwt-patterns.md" "updateCount")
IMP_BEFORE2=$(get_field "$TMP/auth/jwt-patterns.md" "importance")
bash "$CT" update "auth/jwt-patterns.md" "Added refresh token rotation guidance."
UPDATE_AFTER=$(get_field "$TMP/auth/jwt-patterns.md" "updateCount")
IMP_AFTER2=$(get_field "$TMP/auth/jwt-patterns.md" "importance")

assert_eq "updateCount incremented" "$((UPDATE_BEFORE + 1))" "$UPDATE_AFTER"
# update event adds +5
EXPECTED_IMP2=$((IMP_BEFORE2 + 5))
assert_eq "importance bumped by update (+5)" "$EXPECTED_IMP2" "$IMP_AFTER2"

# ========== 7. Score — maturity promotion draft→validated at 65+ ==========
echo "--- 7. Score / maturity promotion ---"
# jwt-patterns currently at 50+3+5=58. Need 65+ for validated.
# manual event adds +10, so 58+10=68 → should promote to validated.
bash "$CT" score "auth/jwt-patterns.md" "manual"
IMP_AFTER_SCORE=$(get_field "$TMP/auth/jwt-patterns.md" "importance")
MAT_AFTER_SCORE=$(get_field "$TMP/auth/jwt-patterns.md" "maturity")

assert_eq "importance after manual score" "68" "$IMP_AFTER_SCORE"
assert_eq "maturity promoted to validated" "validated" "$MAT_AFTER_SCORE"

# ========== 8. Search — verify results returned and scored ==========
echo "--- 8. Search ---"
SEARCH_JSON=$(bash "$CT" search "JWT token patterns" 5)
SEARCH_COUNT=$(echo "$SEARCH_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
SEARCH_TOP=$(echo "$SEARCH_JSON" | python3 -c "import json,sys; r=json.load(sys.stdin); print(r[0]['path'] if r else '')")

# Should have at least 1 result
assert_eq "search returns results" "true" "$([ "$SEARCH_COUNT" -ge 1 ] && echo true || echo false)"
assert_contains "top result is jwt-patterns" "$SEARCH_TOP" "jwt-patterns"

# ========== 9. Sync curate — create entry via sync layer ==========
echo "--- 9. Sync curate ---"
CURATE_OUT=$(bash "$CT" sync curate "$TMP" "infra" "docker" "Docker Compose Tips" "Use multi-stage builds for smaller images.")
assert_contains "sync curate returns path" "$CURATE_OUT" "infra/docker/docker-compose-tips.md"
assert_file_exists "sync curated file exists" "$TMP/infra/docker/docker-compose-tips.md"

ENTRY_COUNT2=$(count_manifest_entries)
assert_eq "5 entries after sync curate" "5" "$ENTRY_COUNT2"

# ========== 10. Sync query — search via sync layer ==========
echo "--- 10. Sync query ---"
QUERY_JSON=$(bash "$CT" sync query "docker compose" "" 5)
QUERY_COUNT=$(echo "$QUERY_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
assert_eq "sync query returns results" "true" "$([ "$QUERY_COUNT" -ge 1 ] && echo true || echo false)"

# ========== 11. Sync refresh — rebuild manifest + indexes ==========
echo "--- 11. Sync refresh ---"
bash "$CT" sync refresh
# After refresh, manifest should still have 5 entries and lastRebuilt should be updated
ENTRY_COUNT3=$(count_manifest_entries)
assert_eq "5 entries after refresh" "5" "$ENTRY_COUNT3"
assert_file_exists "infra _index.md after refresh" "$TMP/infra/_index.md"

# ========== 12. Archive — low-importance drafts archived ==========
echo "--- 12. Archive ---"
# Set api/pagination.md to low importance so it gets archived (draft + importance < 35)
bash "${SCRIPT_DIR}/scripts/ct-frontmatter.sh" set "$TMP/api/pagination.md" importance 10
ARCHIVE_OUT=$(bash "$CT" archive)
assert_contains "archive output mentions archived" "$ARCHIVE_OUT" "Archived"

# Pagination should be archived (stub + full in _archived/)
assert_file_exists "archived full copy" "$TMP/_archived/api/pagination.full.md"
assert_file_exists "archived stub" "$TMP/_archived/api/pagination.stub.md"
assert_file_not_exists "original removed after archive" "$TMP/api/pagination.md"

# ========== 13. Restore — file restored from archive ==========
echo "--- 13. Restore ---"
bash "$CT" restore "api/pagination.full.md"
assert_file_exists "restored file exists" "$TMP/api/pagination.md"
assert_file_not_exists "archive full removed" "$TMP/_archived/api/pagination.full.md"

# ========== 14. Delete — file removed, archived counterparts cleaned ==========
echo "--- 14. Delete ---"
bash "$CT" delete "api/pagination.md"
assert_file_not_exists "deleted file gone" "$TMP/api/pagination.md"

# Manifest should no longer include it
MANIFEST_LIST=$(bash "${SCRIPT_DIR}/scripts/ct-manifest.sh" list "$TMP")
PAGINATION_IN_MANIFEST=$(echo "$MANIFEST_LIST" | grep -c "pagination" || true)
assert_eq "pagination removed from manifest" "0" "$PAGINATION_IN_MANIFEST"

# ========== 15. List — verify remaining entries ==========
echo "--- 15. List ---"
LIST_OUT=$(bash "$CT" list)
assert_contains "list includes jwt-patterns" "$LIST_OUT" "jwt-patterns"
assert_contains "list includes oauth-flows" "$LIST_OUT" "oauth-flows"
assert_contains "list includes error-handling" "$LIST_OUT" "error-handling"
assert_contains "list includes docker-compose" "$LIST_OUT" "docker-compose-tips"

# Final count: should be 4 entries (jwt-patterns, oauth-flows, error-handling, docker-compose-tips)
FINAL_COUNT=$(count_manifest_entries)
assert_eq "4 entries remaining" "4" "$FINAL_COUNT"

# ========== Summary ==========
echo ""
echo "Integration tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
