#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "skills/retrieve/retrieve.md"
assert_file_exists "commands/retrieve.md"
assert_contains "skills/retrieve/retrieve.md" "xgh:retrieve"
assert_contains "skills/retrieve/retrieve.md" "ingest.yaml"
assert_contains "skills/retrieve/retrieve.md" ".cursors.json"
assert_contains "skills/retrieve/retrieve.md" "urgency_score"
assert_contains "skills/retrieve/retrieve.md" ".enrichments.json"
assert_contains "skills/retrieve/retrieve.md" "slack_read_channel"
assert_contains "skills/retrieve/retrieve.md" ".urgent"
assert_contains "commands/retrieve.md" "xgh-retrieve"
echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
