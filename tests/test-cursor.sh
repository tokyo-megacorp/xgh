#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS + 1)); else echo "FAIL: expected '$2', got '$1'"; FAIL=$((FAIL + 1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS + 1)); else echo "FAIL: $1 missing"; FAIL=$((FAIL + 1)); fi
}
assert_executable() {
  if [ -x "$1" ]; then PASS=$((PASS + 1)); else echo "FAIL: $1 not executable"; FAIL=$((FAIL + 1)); fi
}
assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS + 1)); else echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL + 1)); fi
}

SCRIPT="plugin/scripts/update-cursor.sh"
echo "── Cursor update ──"

# Script exists and is executable
assert_file_exists "$SCRIPT"
assert_executable "$SCRIPT"

# Functional test with temp dir
TMPDIR_TEST=$(mktemp -d)
mkdir -p "${TMPDIR_TEST}/.xgh/inbox"

# Test 1: Creates file if missing, stores cursor
HOME="$TMPDIR_TEST" bash "$SCRIPT" "C123" "1710000000.000000"
RESULT=$(jq -r '.C123' "${TMPDIR_TEST}/.xgh/inbox/.cursors.json" 2>/dev/null || echo "MISSING")
assert_eq "$RESULT" "1710000000.000000"

# Test 2: Adds second channel, preserves first
HOME="$TMPDIR_TEST" bash "$SCRIPT" "C456" "1710000001.000000"
RESULT_C123=$(jq -r '.C123' "${TMPDIR_TEST}/.xgh/inbox/.cursors.json" 2>/dev/null || echo "MISSING")
RESULT_C456=$(jq -r '.C456' "${TMPDIR_TEST}/.xgh/inbox/.cursors.json" 2>/dev/null || echo "MISSING")
assert_eq "$RESULT_C123" "1710000000.000000"
assert_eq "$RESULT_C456" "1710000001.000000"

# Test 3: Updates existing channel
HOME="$TMPDIR_TEST" bash "$SCRIPT" "C123" "1710000002.000000"
RESULT_UPDATED=$(jq -r '.C123' "${TMPDIR_TEST}/.xgh/inbox/.cursors.json" 2>/dev/null || echo "MISSING")
assert_eq "$RESULT_UPDATED" "1710000002.000000"

rm -rf "$TMPDIR_TEST"

# Retrieve skill references the script
assert_contains "plugin/skills/retrieve/retrieve.md" 'update-cursor.sh'

echo ""
echo "Cursor test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
