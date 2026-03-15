#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "skills/ingest-retrieve/ingest-retrieve.md"
assert_file_exists "commands/ingest-retrieve.md"
assert_file_exists "scripts/schedulers/com.xgh.retriever.plist"
assert_file_exists "scripts/schedulers/com.xgh.analyzer.plist"
assert_file_exists "scripts/ingest-schedule.sh"

assert_contains "skills/ingest-retrieve/ingest-retrieve.md" "xgh:ingest-retrieve"
assert_contains "skills/ingest-retrieve/ingest-retrieve.md" "ingest.yaml"
assert_contains "skills/ingest-retrieve/ingest-retrieve.md" ".cursors.json"
assert_contains "skills/ingest-retrieve/ingest-retrieve.md" "urgency_score"
assert_contains "skills/ingest-retrieve/ingest-retrieve.md" ".enrichments.json"
assert_contains "skills/ingest-retrieve/ingest-retrieve.md" "slack_read_channel"
assert_contains "skills/ingest-retrieve/ingest-retrieve.md" ".urgent"
assert_contains "commands/ingest-retrieve.md" "xgh-retrieve"
assert_contains "scripts/schedulers/com.xgh.retriever.plist" "com.xgh.retriever"
assert_contains "scripts/schedulers/com.xgh.retriever.plist" "300"
assert_contains "scripts/schedulers/com.xgh.analyzer.plist" "1800"
assert_contains "scripts/ingest-schedule.sh" "launchctl"
assert_contains "scripts/ingest-schedule.sh" "crontab"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
