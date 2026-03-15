#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -qF -- "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "skills/ingest-track/ingest-track.md"
assert_file_exists "skills/ingest-doctor/ingest-doctor.md"
assert_file_exists "skills/ingest-index-repo/ingest-index-repo.md"
assert_file_exists "skills/ingest-calibrate/ingest-calibrate.md"
assert_file_exists "commands/ingest-track.md"
assert_file_exists "commands/ingest-doctor.md"
assert_file_exists "commands/ingest-index-repo.md"
assert_file_exists "commands/ingest-calibrate.md"

assert_contains "skills/ingest-track/ingest-track.md"       "xgh:ingest-track"
assert_contains "skills/ingest-track/ingest-track.md"       "initial backfill"
assert_contains "skills/ingest-track/ingest-track.md"       "ingest.yaml"
assert_contains "skills/ingest-doctor/ingest-doctor.md"     "xgh:ingest-doctor"
assert_contains "skills/ingest-doctor/ingest-doctor.md"     "launchctl"
assert_contains "skills/ingest-doctor/ingest-doctor.md"     "Qdrant"
assert_contains "skills/ingest-index-repo/ingest-index-repo.md" "quick"
assert_contains "skills/ingest-index-repo/ingest-index-repo.md" "full"
assert_contains "skills/ingest-index-repo/ingest-index-repo.md" "cipher_extract_and_operate_memory"
assert_contains "skills/ingest-calibrate/ingest-calibrate.md"   "dedup_threshold"
assert_contains "skills/ingest-calibrate/ingest-calibrate.md"   "F1"
assert_contains "skills/ingest-calibrate/ingest-calibrate.md"   "--auto"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
