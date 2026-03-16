#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 missing '$2'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists "skills/pr-context-bridge/pr-context-bridge.md"
assert_file_exists "skills/knowledge-handoff/knowledge-handoff.md"
assert_file_exists "skills/convention-guardian/convention-guardian.md"
assert_file_exists "skills/cross-team-pollinator/cross-team-pollinator.md"
assert_file_exists "skills/subagent-pair-programming/subagent-pair-programming.md"
assert_file_exists "skills/onboarding-accelerator/onboarding-accelerator.md"

assert_contains "skills/pr-context-bridge/pr-context-bridge.md" "PR"
assert_contains "skills/knowledge-handoff/knowledge-handoff.md" "handoff"
assert_contains "skills/convention-guardian/convention-guardian.md" "convention"
assert_contains "skills/cross-team-pollinator/cross-team-pollinator.md" "cross-team"
assert_contains "skills/subagent-pair-programming/subagent-pair-programming.md" "TDD"
assert_contains "skills/onboarding-accelerator/onboarding-accelerator.md" "onboarding"

echo ""
echo "Team skills test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
