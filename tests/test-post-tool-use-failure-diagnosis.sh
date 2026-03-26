#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/post-tool-use-failure-preferences.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-post-tool-use-failure-diagnosis ==="

# --- Test 1: Merge method mismatch ---
echo "--- 1. Merge method mismatch ---"
input='{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --merge"},"tool_response":{"stderr":"merge_method is not allowed for this repository"}}'
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  if [[ "$ctx" == *"merge_method"* ]] || [[ "$ctx" == *"Merge failed"* ]] || [[ "$ctx" == *"merge method"* ]]; then
    pass "merge method mismatch diagnosed"
  else
    fail "expected merge method diagnosis. Got: $ctx"
  fi
else
  fail "merge method mismatch should produce diagnosis. Output: $output"
fi

# --- Test 2: Stale reviewer ---
echo "--- 2. Stale reviewer ---"
input='{"tool_name":"Bash","tool_input":{"command":"gh pr edit 42 --add-reviewer someone"},"tool_response":{"stderr":"Could not resolve to a User"}}'
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  if [[ "$ctx" == *"reviewer"* ]] || [[ "$ctx" == *"Reviewer"* ]]; then
    pass "stale reviewer diagnosed"
  else
    fail "expected reviewer diagnosis. Got: $ctx"
  fi
else
  fail "stale reviewer should produce diagnosis. Output: $output"
fi

# --- Test 3: Wrong repo ---
echo "--- 3. Wrong repo ---"
input='{"tool_name":"Bash","tool_input":{"command":"gh pr list"},"tool_response":{"stderr":"Could not resolve to a Repository with the name"}}'
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  if [[ "$ctx" == *"repo"* ]] || [[ "$ctx" == *"Repository"* ]]; then
    pass "wrong repo diagnosed"
  else
    fail "expected repo diagnosis. Got: $ctx"
  fi
else
  fail "wrong repo should produce diagnosis. Output: $output"
fi

# --- Test 4: Auth required ---
echo "--- 4. Auth required ---"
input='{"tool_name":"Bash","tool_input":{"command":"gh pr list"},"tool_response":{"stderr":"authentication required, please run gh auth login"}}'
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  if [[ "$ctx" == *"auth"* ]] || [[ "$ctx" == *"Auth"* ]]; then
    pass "auth required diagnosed"
  else
    fail "expected auth diagnosis. Got: $ctx"
  fi
else
  fail "auth required should produce diagnosis. Output: $output"
fi

# --- Test 5: Dual-match — command without gh ---
echo "--- 5. Non-gh command → silent ---"
input='{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_response":{"stderr":"No such file or directory"}}'
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if [[ -z "$output" ]]; then
  pass "non-gh command → silent"
else
  fail "non-gh command should be silent. Output: $output"
fi

# --- Test 6: gh command with unrecognized error → fail-open ---
echo "--- 6. Unrecognized gh error → fail-open ---"
input='{"tool_name":"Bash","tool_input":{"command":"gh api /repos/foo/bar"},"tool_response":{"stderr":"rate limit exceeded"}}'
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if [[ -z "$output" ]]; then
  pass "unrecognized gh error → fail-open (silent)"
else
  fail "unrecognized error should be silent. Output: $output"
fi

# --- Test 7: hookEventName is PostToolUseFailure ---
echo "--- 7. hookEventName correct ---"
input='{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --merge"},"tool_response":{"stderr":"merge_method is not allowed"}}'
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUseFailure"' >/dev/null 2>&1; then
  pass "hookEventName is PostToolUseFailure"
else
  fail "hookEventName should be PostToolUseFailure. Output: $output"
fi

# --- Test 8: Dual-match — stderr without command context ---
echo "--- 8. Dual-match: reviewer error without --add-reviewer → silent ---"
input='{"tool_name":"Bash","tool_input":{"command":"gh pr list"},"tool_response":{"stderr":"Could not resolve to a User"}}'
output=$(cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null || true)
if [[ -z "$output" ]]; then
  pass "reviewer error without --add-reviewer → silent"
else
  fail "should require --add-reviewer in command for reviewer diagnosis. Output: $output"
fi

# --- Summary ---
echo ""
echo "PostToolUseFailure diagnosis: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
