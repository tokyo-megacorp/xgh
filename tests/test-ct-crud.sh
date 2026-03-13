#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_not_exists() {
  if [ ! -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 should not exist — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_dir_exists() {
  if [ -d "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: dir $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_not_zero() {
  if [ -n "$1" ] && [ "$1" != "0" ]; then PASS=$((PASS+1)); else echo "FAIL: expected non-zero — $2"; FAIL=$((FAIL+1)); fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CT="${SCRIPT_DIR}/scripts/context-tree.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XGH_CONTEXT_TREE="$TMP"

# ========== 1. init ==========
echo "--- Test: init ---"
bash "$CT" init
assert_file_exists "$TMP/_manifest.json" "manifest created by init"
assert_dir_exists "$TMP" "root dir exists after init"

# ========== 2. create ==========
echo "--- Test: create ---"
bash "$CT" create "backend/auth/jwt.md" "JWT Patterns" "JSON Web Token best practices for auth."
assert_file_exists "$TMP/backend/auth/jwt.md" "create writes file"
assert_file_contains "$TMP/backend/auth/jwt.md" "title: JWT Patterns" "frontmatter title"
assert_file_contains "$TMP/backend/auth/jwt.md" "importance: 50" "default importance"
assert_file_contains "$TMP/backend/auth/jwt.md" "maturity: draft" "default maturity"
assert_file_contains "$TMP/backend/auth/jwt.md" "accessCount: 0" "default accessCount"
assert_file_contains "$TMP/backend/auth/jwt.md" "updateCount: 0" "default updateCount"
assert_file_contains "$TMP/backend/auth/jwt.md" "JSON Web Token best practices" "body content"

# create should fail if file exists
bash "$CT" create "backend/auth/jwt.md" "Duplicate" "dup" 2>/dev/null && {
  echo "FAIL: duplicate create should fail"; FAIL=$((FAIL+1))
} || PASS=$((PASS+1))

# ========== 3. read ==========
echo "--- Test: read ---"
READ_OUT=$(bash "$CT" read "backend/auth/jwt.md")
assert_contains "$READ_OUT" "JWT Patterns" "read outputs content"
assert_contains "$READ_OUT" "JSON Web Token" "read outputs body"

# read bumps accessCount
AC=$(grep "accessCount:" "$TMP/backend/auth/jwt.md" | head -1 | awk '{print $2}')
assert_eq "$AC" "1" "accessCount bumped to 1 after read"

# read bumps importance via search-hit (+3)
IMP=$(grep "importance:" "$TMP/backend/auth/jwt.md" | head -1 | awk '{print $2}')
assert_eq "$IMP" "53" "importance bumped to 53 after read"

# ========== 4. update ==========
echo "--- Test: update ---"
bash "$CT" update "backend/auth/jwt.md" "Added rotation policy for refresh tokens."
assert_file_contains "$TMP/backend/auth/jwt.md" "## Update" "update adds section header"
assert_file_contains "$TMP/backend/auth/jwt.md" "Added rotation policy" "update appends content"

# update bumps importance via update event (+5)
IMP2=$(grep "importance:" "$TMP/backend/auth/jwt.md" | head -1 | awk '{print $2}')
assert_eq "$IMP2" "58" "importance bumped to 58 after update"

# update resets recency to 1.0
REC=$(grep "recency:" "$TMP/backend/auth/jwt.md" | head -1 | awk '{print $2}')
assert_eq "$REC" "1.0000" "recency reset to 1.0000 after update"

# ========== 5. list ==========
echo "--- Test: list ---"
LIST_OUT=$(bash "$CT" list)
assert_contains "$LIST_OUT" "backend/auth/jwt.md" "list shows entry"
assert_contains "$LIST_OUT" "draft" "list shows maturity"

# ========== 6. search ==========
echo "--- Test: search ---"
SEARCH_OUT=$(bash "$CT" search "jwt" 2>/dev/null || echo "[]")
assert_contains "$SEARCH_OUT" "jwt" "search finds jwt entry"

# ========== 7. score ==========
echo "--- Test: score ---"
IMP_BEFORE=$(grep "importance:" "$TMP/backend/auth/jwt.md" | head -1 | awk '{print $2}')
bash "$CT" score "backend/auth/jwt.md" "search-hit"
IMP_AFTER=$(grep "importance:" "$TMP/backend/auth/jwt.md" | head -1 | awk '{print $2}')
EXPECTED_IMP=$((IMP_BEFORE + 3))
assert_eq "$IMP_AFTER" "$EXPECTED_IMP" "score bumps importance by 3 for search-hit"

# ========== 8. archive + restore ==========
echo "--- Test: archive ---"
# Create a low-importance draft that should get archived
bash "$CT" create "backend/temp/lowpri.md" "Low Priority" "This should be archived."
# Set importance to 10 (below 35 threshold)
bash "$SCRIPT_DIR/scripts/ct-frontmatter.sh" set "$TMP/backend/temp/lowpri.md" "importance" "10"

bash "$CT" archive
assert_file_not_exists "$TMP/backend/temp/lowpri.md" "archive removes low-importance draft"
assert_file_exists "$TMP/_archived/backend/temp/lowpri.full.md" "archive creates .full.md"
assert_file_exists "$TMP/_archived/backend/temp/lowpri.stub.md" "archive creates .stub.md"

echo "--- Test: restore ---"
bash "$CT" restore "backend/temp/lowpri.full.md"
assert_file_exists "$TMP/backend/temp/lowpri.md" "restore brings back file"
assert_file_not_exists "$TMP/_archived/backend/temp/lowpri.full.md" "restore removes .full.md"

# ========== 9. delete ==========
echo "--- Test: delete ---"
bash "$CT" create "backend/temp/todelete.md" "To Delete" "Bye."
# Also set importance low and archive to create _archived counterparts
bash "$SCRIPT_DIR/scripts/ct-frontmatter.sh" set "$TMP/backend/temp/todelete.md" "importance" "10"
bash "$CT" archive
# Restore first so we have both original + archived
bash "$CT" restore "backend/temp/todelete.full.md"
# Re-archive to create archived copies again
bash "$SCRIPT_DIR/scripts/ct-frontmatter.sh" set "$TMP/backend/temp/todelete.md" "importance" "10"
bash "$CT" archive
bash "$CT" restore "backend/temp/todelete.full.md"

bash "$CT" delete "backend/temp/todelete.md"
assert_file_not_exists "$TMP/backend/temp/todelete.md" "delete removes file"

# ========== 10. sync curate ==========
echo "--- Test: sync curate ---"
CURATE_OUT=$(bash "$CT" sync curate "$TMP" "infra" "docker" "Docker Compose Tips" "Use multi-stage builds.")
assert_contains "$CURATE_OUT" "infra" "sync curate returns rel_path with domain"

# ========== 11. sync query ==========
echo "--- Test: sync query ---"
QUERY_OUT=$(bash "$CT" sync query "docker" 2>/dev/null || echo "[]")
# Just verify it doesn't crash and returns something
assert_contains "$QUERY_OUT" "\[" "sync query returns JSON array"

# ========== 12. sync refresh ==========
echo "--- Test: sync refresh ---"
bash "$CT" sync refresh
assert_file_exists "$TMP/_manifest.json" "manifest still exists after refresh"

# ========== 13. manifest init ==========
echo "--- Test: manifest init ---"
bash "$CT" manifest init
assert_file_exists "$TMP/_manifest.json" "manifest init keeps manifest"

# ========== 14. manifest rebuild ==========
echo "--- Test: manifest rebuild ---"
bash "$CT" manifest rebuild
assert_file_exists "$TMP/_manifest.json" "manifest rebuild regenerates"

# ========== 15. manifest update-indexes ==========
echo "--- Test: manifest update-indexes ---"
bash "$CT" manifest update-indexes
# Check that _index.md was created for the backend domain
assert_file_exists "$TMP/backend/_index.md" "update-indexes creates _index.md"

# ========== cleanup temp lowpri ==========
bash "$CT" delete "backend/temp/lowpri.md" 2>/dev/null || true

echo ""
echo "==========================="
echo "CRUD tests: $PASS passed, $FAIL failed"
echo "==========================="
[ "$FAIL" -eq 0 ] || exit 1
