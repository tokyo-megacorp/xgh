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

# --- Gitignore includes model-profiles ---
assert_contains ".gitignore" "model-profiles.yaml"

# --- Observation schema documented in router skill ---
assert_contains "skills/dispatch/dispatch.md" "agent"
assert_contains "skills/dispatch/dispatch.md" "model"
assert_contains "skills/dispatch/dispatch.md" "effort"
assert_contains "skills/dispatch/dispatch.md" "archetype"
assert_contains "skills/dispatch/dispatch.md" "accepted"
assert_contains "skills/dispatch/dispatch.md" "ts"

echo ""
echo "Model profiles test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
