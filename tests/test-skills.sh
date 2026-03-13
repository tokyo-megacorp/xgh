#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_dir_exists() { if [ -d "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }
assert_frontmatter() {
  # Check file starts with --- and has a closing ---
  if head -1 "$1" | grep -q "^---" && awk 'NR>1' "$1" | grep -q "^---"; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 missing YAML frontmatter"
    FAIL=$((FAIL+1))
  fi
}

# --- Skill directory structure ---
SKILLS=(continuous-learning curate-knowledge query-strategies context-tree-maintenance memory-verification)
for skill in "${SKILLS[@]}"; do
  assert_dir_exists "skills/${skill}"
  assert_file_exists "skills/${skill}/${skill}.md"
  assert_frontmatter "skills/${skill}/${skill}.md"
done

# --- continuous-learning skill ---
CL="skills/continuous-learning/continuous-learning.md"
assert_contains "$CL" "name: continuous-learning"
assert_contains "$CL" "IRON LAW"
assert_contains "$CL" "cipher_memory_search"
assert_contains "$CL" "cipher_extract_and_operate_memory"
assert_contains "$CL" "Rationalization Table"
assert_contains "$CL" "Simple change"

# --- curate-knowledge skill ---
CK="skills/curate-knowledge/curate-knowledge.md"
assert_contains "$CK" "name: curate-knowledge"
assert_contains "$CK" "domain"
assert_contains "$CK" "frontmatter"
assert_contains "$CK" "tags"
assert_contains "$CK" "importance"
assert_contains "$CK" "maturity"

# --- query-strategies skill ---
QS="skills/query-strategies/query-strategies.md"
assert_contains "$QS" "name: query-strategies"
assert_contains "$QS" "cipher_memory_search"
assert_contains "$QS" "BM25"
assert_contains "$QS" "semantic"
assert_contains "$QS" "refinement"

# --- context-tree-maintenance skill ---
CT="skills/context-tree-maintenance/context-tree-maintenance.md"
assert_contains "$CT" "name: context-tree-maintenance"
assert_contains "$CT" "importance"
assert_contains "$CT" "maturity"
assert_contains "$CT" "archive"
assert_contains "$CT" "draft"
assert_contains "$CT" "validated"
assert_contains "$CT" "core"

# --- memory-verification skill ---
MV="skills/memory-verification/memory-verification.md"
assert_contains "$MV" "name: memory-verification"
assert_contains "$MV" "verify"
assert_contains "$MV" "cipher_memory_search"
assert_contains "$MV" "retrieve"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
