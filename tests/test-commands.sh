#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

# --- Command files exist ---
COMMANDS=(query curate status)
for cmd in "${COMMANDS[@]}"; do
  assert_file_exists "commands/${cmd}.md"
done

# --- query command ---
Q="commands/query.md"
assert_contains "$Q" "cipher_memory_search"
assert_contains "$Q" "context tree"
assert_contains "$Q" "ranked"

# --- curate command ---
C="commands/curate.md"
assert_contains "$C" "cipher_extract_and_operate_memory"
assert_contains "$C" "context tree"
assert_contains "$C" "frontmatter"
assert_contains "$C" "_manifest.json"

# --- status command ---
S="commands/status.md"
assert_contains "$S" "context tree"
assert_contains "$S" "health"
assert_contains "$S" "_manifest.json"
assert_contains "$S" "maturity"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
