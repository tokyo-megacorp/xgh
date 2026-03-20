#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "providers/_template/spec.md"
assert_contains "providers/_template/spec.md" "provider.yaml"
assert_contains "providers/_template/spec.md" "fetch.sh"
assert_contains "providers/_template/spec.md" "cursor"
assert_contains "providers/_template/spec.md" "tokens.env"
assert_contains "providers/_template/spec.md" "inbox"
assert_contains "providers/_template/spec.md" "urgency_keywords"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
