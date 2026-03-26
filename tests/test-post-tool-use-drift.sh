#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/post-tool-use-preferences.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-post-tool-use-drift ==="

# --- Test 1: Non-project.yaml file → silent exit ---
echo "--- 1. Non-project.yaml file ---"
output=$(cd "$REPO_ROOT" && echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/something.txt"}}' | bash "$HOOK" 2>/dev/null || true)
if [[ -z "$output" ]]; then
  pass "non-project.yaml → silent exit"
else
  fail "non-project.yaml should be silent. Output: $output"
fi

# --- Test 2: Missing snapshot → initialization message ---
echo "--- 2. Missing snapshot → init ---"
test_session="drift-test-$(date +%s)"
snapshot="${REPO_ROOT}/.xgh/run/xgh-${test_session}-project-yaml.yaml"
rm -f "$snapshot"
proj_yaml_abs="${REPO_ROOT}/config/project.yaml"
input="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"${proj_yaml_abs}\"},\"session_id\":\"${test_session}\"}"
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  if [[ "$ctx" == *"snapshot initialized"* ]]; then
    pass "missing snapshot → initialization message"
  else
    fail "expected 'snapshot initialized' in context. Got: $ctx"
  fi
else
  fail "missing snapshot should emit init message. Output: $output"
fi
# Verify snapshot was created
if [[ -f "$snapshot" ]]; then
  pass "snapshot file created"
else
  fail "snapshot file should be created at $snapshot"
fi
rm -f "$snapshot"

# --- Test 3: Snapshot exists, no changes → silent ---
echo "--- 3. No changes → silent ---"
mkdir -p "${REPO_ROOT}/.xgh/run" 2>/dev/null || true
cp "$proj_yaml_abs" "$snapshot"
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if [[ -z "$output" ]]; then
  pass "no changes → silent"
else
  # Some implementations may still emit empty context
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)
  if [[ -z "$ctx" ]]; then
    pass "no changes → no meaningful output"
  else
    fail "no changes should be silent. Output: $output"
  fi
fi
rm -f "$snapshot"

# --- Test 4: hookEventName is PostToolUse ---
echo "--- 4. hookEventName correct ---"
rm -f "$snapshot"
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1; then
  pass "hookEventName is PostToolUse"
else
  fail "hookEventName should be PostToolUse. Output: $output"
fi
rm -f "$snapshot"

# --- Test 5: Snapshot exists with different values → reports changes ---
echo "--- 5. Value change detected ---"
mkdir -p "${REPO_ROOT}/.xgh/run" 2>/dev/null || true
cp "$proj_yaml_abs" "$snapshot"
# Change merge_method from squash to rebase in the snapshot (so current file looks "changed")
if command -v sed >/dev/null 2>&1; then
  sed -i.bak 's/merge_method: squash/merge_method: rebase/' "$snapshot" 2>/dev/null || true
  rm -f "${snapshot}.bak"
fi
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  if [[ "$ctx" == *"changed"* ]] || [[ "$ctx" == *"merge_method"* ]]; then
    pass "value change detected and reported"
  else
    fail "expected change report mentioning merge_method. Got: $ctx"
  fi
else
  fail "value change should produce report. Output: $output"
fi
rm -f "$snapshot"

# --- Summary ---
echo ""
echo "PostToolUse drift: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
