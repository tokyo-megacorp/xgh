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

echo "=== Collaboration Dispatcher Agent Tests ==="

AGENT="agents/collaboration-dispatcher.md"
assert_file_exists "$AGENT"
assert_contains "$AGENT" "collaboration-dispatcher"
assert_contains "$AGENT" "cipher_memory_search"
assert_contains "$AGENT" "cipher_store_reasoning_memory"
assert_section "$AGENT" "Role"
assert_section "$AGENT" "Message Protocol"
assert_section "$AGENT" "Dispatch Loop"
assert_contains "$AGENT" "thread"
assert_contains "$AGENT" "from_agent"
assert_contains "$AGENT" "for_agent"
assert_contains "$AGENT" "pending"
assert_contains "$AGENT" "completed"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
