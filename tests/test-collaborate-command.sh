#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 does not exist"
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 does not contain '$2'"
    FAIL=$((FAIL+1))
  fi
}

assert_section() {
  if grep -q "^## $2" "$1" 2>/dev/null || grep -q "^### $2" "$1" 2>/dev/null; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 missing section '$2'"
    FAIL=$((FAIL+1))
  fi
}

echo "=== Collaborate Command Tests ==="

CMD="commands/collaborate.md"
assert_file_exists "$CMD"
assert_contains "$CMD" "/xgh-collaborate"
assert_contains "$CMD" "plan-review"
assert_contains "$CMD" "parallel-impl"
assert_contains "$CMD" "validation"
assert_contains "$CMD" "security-review"
assert_contains "$CMD" "cipher_store_reasoning_memory"
assert_contains "$CMD" "cipher_memory_search"
assert_section "$CMD" "Usage"
assert_section "$CMD" "Workflow Templates"
assert_contains "$CMD" "thread"
assert_contains "$CMD" "from_agent"
assert_contains "$CMD" "for_agent"
assert_contains "$CMD" "status"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
