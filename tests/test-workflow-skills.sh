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

assert_file_exists "skills/investigate/investigate.md"
assert_file_exists "skills/implement-design/implement-design.md"
assert_file_exists "skills/implement-ticket/implement-ticket.md"

assert_contains "skills/investigate/investigate.md" "MCP"
assert_contains "skills/investigate/investigate.md" "investigate"
assert_contains "skills/implement-design/implement-design.md" "design"
assert_contains "skills/implement-ticket/implement-ticket.md" "ticket"

assert_file_exists "commands/investigate.md"
assert_file_exists "commands/implement-design.md"
assert_file_exists "commands/implement.md"

assert_contains "commands/investigate.md" "/xgh investigate"
assert_contains "commands/implement-design.md" "/xgh implement-design"
assert_contains "commands/implement.md" "/xgh implement"


echo ""
echo "Workflow skills test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
