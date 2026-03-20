#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "skills/analyze/analyze.md"
assert_file_exists "commands/analyze.md"

assert_contains "skills/analyze/analyze.md" "xgh:analyze"
assert_contains "skills/analyze/analyze.md" "dedup_threshold"
assert_contains "skills/analyze/analyze.md" "xgh_schema_version"
assert_contains "skills/analyze/analyze.md" "processed/"
assert_contains "skills/analyze/analyze.md" "digests/"
assert_contains "skills/analyze/analyze.md" "xgh_status: decayed"
assert_contains "skills/analyze/analyze.md" ".enrichments.json"
assert_contains "skills/analyze/analyze.md" "promote_to"
assert_contains "commands/analyze.md" "xgh-analyze"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
