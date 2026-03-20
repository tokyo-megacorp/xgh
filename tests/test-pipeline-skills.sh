#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -qF -- "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "skills/track/track.md"
assert_file_exists "skills/doctor/doctor.md"
assert_file_exists "skills/index/index.md"
assert_file_exists "skills/calibrate/calibrate.md"
assert_file_exists "commands/track.md"
assert_file_exists "commands/doctor.md"
assert_file_exists "commands/index.md"
assert_file_exists "commands/calibrate.md"

assert_contains "skills/track/track.md"       "xgh:track"
assert_contains "skills/track/track.md"       "initial backfill"
assert_contains "skills/track/track.md"       "ingest.yaml"
assert_contains "skills/doctor/doctor.md"     "xgh:doctor"
assert_contains "skills/index/index.md" "quick"
assert_contains "skills/index/index.md" "full"
assert_contains "skills/calibrate/calibrate.md"   "dedup_threshold"
assert_contains "skills/calibrate/calibrate.md"   "F1"
assert_contains "skills/calibrate/calibrate.md"   "--auto"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
