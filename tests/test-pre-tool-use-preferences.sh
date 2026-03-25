#!/usr/bin/env bash
# tests/test-pre-tool-use-preferences.sh — Tests for PreToolUse preference validation hook
#
# Run: bash tests/test-pre-tool-use-preferences.sh
set -euo pipefail

HOOK="hooks/pre-tool-use-preferences.sh"
PASS=0
FAIL=0

# ── Helpers ─────────────────────────────────────────────────────────────

assert_empty() {
  local desc="$1" output="$2"
  if [ -z "$output" ] || [ "$output" = "{}" ] || [ "$output" = "null" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — expected empty/no output, got: $output"
  fi
}

assert_contains() {
  local desc="$1" output="$2" needle="$3"
  if echo "$output" | grep -q "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — expected to contain '$needle', got: $output"
  fi
}

assert_not_contains() {
  local desc="$1" output="$2" needle="$3"
  if ! echo "$output" | grep -q "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — expected NOT to contain '$needle', got: $output"
  fi
}

assert_valid_json() {
  local desc="$1" output="$2"
  if [ -z "$output" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc (empty output is valid)"
    return
  fi
  if echo "$output" | jq . >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — invalid JSON: $output"
  fi
}

run_hook() {
  local input="$1"
  echo "$input" | bash "$HOOK" 2>/dev/null || true
}

echo "=== PreToolUse Preferences Hook Tests ==="
echo ""

# ── Fast-exit tests ─────────────────────────────────────────────────────

echo "--- Fast-exit tests ---"

OUT=$(run_hook '{"tool_name": "Read", "tool_input": {"file_path": "/foo"}}')
assert_empty "Non-Bash tool exits silently" "$OUT"

OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "ls -la"}}')
assert_empty "Bash without gh pr merge exits silently" "$OUT"

OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "git status"}}')
assert_empty "git status exits silently" "$OUT"

OUT=$(run_hook '{}')
assert_empty "Empty JSON exits silently" "$OUT"

OUT=$(run_hook '')
assert_empty "Empty input exits silently" "$OUT"

OUT=$(run_hook 'not json')
assert_empty "Invalid JSON exits silently" "$OUT"

echo ""

# ── Merge method tests ──────────────────────────────────────────────────
# Note: These tests depend on config/project.yaml having:
#   preferences.pr.merge_method: squash
#   preferences.pr.branches.main.merge_method: merge
#   preferences.pr.branches.develop.merge_method: squash

echo "--- Merge method mismatch tests ---"

# Test: --merge on a repo with default squash (no PR number = no branch lookup, uses default)
OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge --merge"}}')
assert_valid_json "Mismatch output is valid JSON" "$OUT"
assert_contains "Default squash vs --merge warns" "$OUT" "mismatch"
assert_contains "Warning mentions configured method" "$OUT" "squash"
assert_not_contains "Never blocks" "$OUT" "decision"

# Test: --squash on default (should match, no output)
OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge --squash"}}')
assert_empty "Default squash vs --squash passes silently" "$OUT"

# Test: --rebase on default (mismatch)
OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42 --rebase"}}')
assert_valid_json "Rebase mismatch is valid JSON" "$OUT"
assert_contains "Rebase vs squash warns" "$OUT" "mismatch"

# Test: no merge flag specified (should pass through)
OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42"}}')
assert_empty "No merge flag passes silently" "$OUT"

echo ""

# ── Force-push tests ────────────────────────────────────────────────────

echo "--- Force-push tests ---"

# Note: force-push warnings depend on branches having protected: true in config.
# Default project.yaml does NOT have protected: true, so these should pass silently.

OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "git push --force origin feature-branch"}}')
assert_empty "Force-push to unprotected branch passes silently" "$OUT"

OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "git push -f origin feature-branch"}}')
assert_empty "Short -f to unprotected branch passes silently" "$OUT"

OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "git push origin main"}}')
assert_empty "Non-force push to main passes silently" "$OUT"

echo ""

# ── Output format validation ────────────────────────────────────────────

echo "--- Output format tests ---"

OUT=$(run_hook '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge --rebase"}}')
if [ -n "$OUT" ]; then
  HAS_HOOK_EVENT=$(echo "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null || true)
  if [ "$HAS_HOOK_EVENT" = "PreToolUse" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: hookEventName is PreToolUse"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: hookEventName should be PreToolUse, got: $HAS_HOOK_EVENT"
  fi

  HAS_CONTEXT=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
  if [ -n "$HAS_CONTEXT" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: additionalContext is present"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: additionalContext should be present"
  fi
else
  FAIL=$((FAIL + 2))
  echo "  FAIL: Expected mismatch output for --rebase"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
