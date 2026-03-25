#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_true() {
  local label="$1" result="$2"
  if [[ "$result" == "true" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains_str() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected to contain '$needle', got '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

# --- Resolve settings.json path ---
REPO_ROOT="$(git rev-parse --show-toplevel)"
SETTINGS="$REPO_ROOT/.claude/settings.json"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed"
  exit 1
fi

if [[ ! -f "$SETTINGS" ]]; then
  echo "ERROR: $SETTINGS not found"
  exit 1
fi

# --- PreToolUse: first Bash-matcher hook must be pre-tool-use-preferences ---
pre_count=$(jq '.hooks.PreToolUse | length // 0' "$SETTINGS")
if [[ "$pre_count" -gt 0 ]]; then
  # Find the first entry whose matcher contains "Bash"
  first_bash_cmd=$(jq -r '
    .hooks.PreToolUse[]
    | select(.matcher | test("Bash"; "i"))
    | .hooks[0].command
    // ""
  ' "$SETTINGS" | head -1)

  assert_contains_str \
    "PreToolUse: first Bash-matcher hook command contains 'pre-tool-use-preferences'" \
    "$first_bash_cmd" \
    "pre-tool-use-preferences"

  # Verify it really is the FIRST entry with a Bash matcher (index 0)
  first_bash_index=$(jq '
    .hooks.PreToolUse
    | to_entries[]
    | select(.value.matcher | test("Bash"; "i"))
    | .key
  ' "$SETTINGS" | head -1)

  first_bash_cmd_at_index=$(jq -r \
    --argjson idx "$first_bash_index" \
    '.hooks.PreToolUse[$idx].hooks[0].command // ""' \
    "$SETTINGS")

  assert_contains_str \
    "PreToolUse: Bash-matcher hook at index $first_bash_index is pre-tool-use-preferences (ordering)" \
    "$first_bash_cmd_at_index" \
    "pre-tool-use-preferences"
else
  echo "NOTE: No PreToolUse hooks registered — skipping PreToolUse ordering check"
fi

# --- SessionStart: last hook entry must be session-start-preferences ---
session_count=$(jq '.hooks.SessionStart | length // 0' "$SETTINGS")
if [[ "$session_count" -gt 0 ]]; then
  last_session_cmd=$(jq -r '.hooks.SessionStart[-1].hooks[-1].command // ""' "$SETTINGS")

  assert_contains_str \
    "SessionStart: last hook command contains 'session-start-preferences'" \
    "$last_session_cmd" \
    "session-start-preferences"
else
  echo "NOTE: No SessionStart hooks registered — skipping SessionStart ordering check"
fi

# --- PostToolUse: (future) last hook must be post-tool-use-preferences ---
post_count=$(jq '.hooks.PostToolUse | length // 0' "$SETTINGS")
if [[ "$post_count" -gt 0 ]]; then
  last_post_cmd=$(jq -r '.hooks.PostToolUse[-1].hooks[-1].command // ""' "$SETTINGS")
  if [[ "$last_post_cmd" == *"post-tool-use-preferences"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: PostToolUse: last hook command should contain 'post-tool-use-preferences', got '$last_post_cmd'"
    FAIL=$((FAIL + 1))
  fi
else
  echo "NOTE: No PostToolUse hooks registered — skipping PostToolUse ordering check (future)"
fi

# --- Stop: (future) last hook must be stop-preferences ---
stop_count=$(jq '.hooks.Stop | length // 0' "$SETTINGS")
if [[ "$stop_count" -gt 0 ]]; then
  last_stop_cmd=$(jq -r '.hooks.Stop[-1].hooks[-1].command // ""' "$SETTINGS")
  if [[ "$last_stop_cmd" == *"stop-preferences"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: Stop: last hook command should contain 'stop-preferences', got '$last_stop_cmd'"
    FAIL=$((FAIL + 1))
  fi
else
  echo "NOTE: No Stop hooks registered — skipping Stop ordering check (future)"
fi

echo ""
echo "Hook ordering: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
