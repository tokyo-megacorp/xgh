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

assert_file_exists "config/agents.yaml"
assert_contains "config/agents.yaml" "claude-code"
assert_contains "config/agents.yaml" "codex"
assert_contains "config/agents.yaml" "cursor"

assert_file_exists "config/workflows/plan-review.yaml"
assert_file_exists "config/workflows/parallel-impl.yaml"
assert_file_exists "config/workflows/validation.yaml"
assert_file_exists "config/workflows/security-review.yaml"

assert_contains "config/workflows/plan-review.yaml" "plan-review"
assert_contains "config/workflows/parallel-impl.yaml" "parallel-impl"
assert_contains "config/workflows/validation.yaml" "validation"
assert_contains "config/workflows/security-review.yaml" "security-review"

assert_file_exists "skills/agent-collaboration/agent-collaboration.md"
assert_contains "skills/agent-collaboration/agent-collaboration.md" "message protocol"

assert_file_exists "agents/collaboration-dispatcher.md"
assert_contains "agents/collaboration-dispatcher.md" "dispatch"

assert_file_exists "commands/xgh-collaborate.md"
assert_contains "commands/xgh-collaborate.md" "/xgh-collaborate"


echo ""
echo "Multi-agent test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
