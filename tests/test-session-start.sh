#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS + 1)); else echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL + 1)); fi
}
assert_not_contains() {
  if ! grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS + 1)); else echo "FAIL: $1 should not contain '$2'"; FAIL=$((FAIL + 1)); fi
}

HOOK="hooks/session-start.sh"

echo "── Session-start hook ──"

# Gap 1: No env var gates
assert_not_contains "$HOOK" 'XGH_SCHEDULER'
assert_not_contains "$HOOK" 'XGH_BRIEFING'

# Gap 1: Always emits scheduler on
assert_contains "$HOOK" 'scheduler-paused'
assert_contains "$HOOK" 'schedulerTrigger'

# Gap 5: Retention cleanup
assert_contains "$HOOK" 'find.*inbox/processed.*-delete'
assert_contains "$HOOK" 'find.*digests.*-delete'
assert_contains "$HOOK" 'find.*logs.*-delete'

# Gap 7: Custom jobs support
assert_contains "$HOOK" 'schedulerCustomJobs'
assert_contains "$HOOK" 'schedule.jobs'

assert_contains "$HOOK" "retrieve-all.sh"

echo ""
echo "Session-start test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
