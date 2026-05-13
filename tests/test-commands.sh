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

assert_not_contains() {
  if grep -qi "$2" "$1" 2>/dev/null; then
    echo "FAIL: $1 contains stale '$2'"
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
}

commands=(
  analyze
  brief
  briefing
  calibrate
  command-center
  config
  doctor
  help
  init
  init-providers
  retrieve
  schedule
  seed
  status
  token-window
  track
  trigger
)

for command in "${commands[@]}"; do
  assert_file_exists "commands/${command}.md"
  assert_contains "commands/${command}.md" "/xgh-${command}"
done

assert_contains "commands/seed.md" "xgh:seed"
assert_contains "commands/status.md" "Memory"

# Active command references should list only currently shipped command wrappers, not legacy stubs.
stale_command_refs=$(grep -RniE '/xgh-(ask|curate|opencode|implement|investigate|design|index|profile|setup|collab|dispatch|codex|gemini|glm|watch-prs|ship-prs)' README.md commands 2>/dev/null || true)
if [[ -z "$stale_command_refs" ]]; then
  PASS=$((PASS + 1))
else
  echo "FAIL: active docs reference unshipped command wrappers"
  echo "$stale_command_refs"
  FAIL=$((FAIL + 1))
fi


echo ""
echo "Commands test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
