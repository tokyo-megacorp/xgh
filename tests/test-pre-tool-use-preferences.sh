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

# Without a resolvable PR number or open head-branch PR, TARGET_BRANCH stays empty
# and the hook exits silently (fail-open contract; no false positives — see #223).
#
# These tests stub gh early so they do not depend on the live test runner's
# checked-out branch (which could otherwise match an open PR and skew results).

EARLY_STUB=$(mktemp -d)
trap 'rm -rf "$EARLY_STUB"' EXIT
cat > "$EARLY_STUB/gh" << 'EARLYSTUB'
#!/usr/bin/env bash
# Return empty for any pr view / pr list — keeps TARGET_BRANCH empty.
if [[ "$*" == *"pr view"* ]] || [[ "$*" == *"pr list"* ]]; then
  exit 0
fi
exec $(command -v gh) "$@"
EARLYSTUB
chmod +x "$EARLY_STUB/gh"

run_hook_empty_gh() {
  local input="$1"
  echo "$input" | PATH="$EARLY_STUB:$PATH" bash "$HOOK" 2>/dev/null || true
}

# Test: --merge with no PR number — TARGET_BRANCH unresolvable → silent pass-through
OUT=$(run_hook_empty_gh '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge --merge"}}')
assert_empty "No PR number --merge exits silently (no false positive)" "$OUT"

# Test: --squash with no PR number — also silent
OUT=$(run_hook_empty_gh '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge --squash"}}')
assert_empty "No PR number --squash exits silently" "$OUT"

# Test: PR number that gh cannot resolve — TARGET_BRANCH empty → silent pass-through
OUT=$(run_hook_empty_gh '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42 --rebase"}}')
assert_empty "Unresolvable PR number exits silently (no false positive)" "$OUT"

# Test: no merge flag specified (should pass through regardless)
OUT=$(run_hook_empty_gh '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42"}}')
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

# ── Branch-override and output format tests (mock gh) ──────────────────
# These tests stub `gh` on PATH so we can control what baseRefName is returned
# without relying on live PRs.  The stub is created in a temp dir and cleaned up.

echo "--- Branch-override + output format tests (mock gh) ---"

MOCK_BIN=$(mktemp -d)
trap 'rm -rf "$EARLY_STUB" "$MOCK_BIN"' EXIT

# Helper: write a gh stub that returns a fixed baseRefName for `gh pr view`
# and an empty list for `gh pr list`.
write_gh_stub() {
  local base_ref="$1"
  cat > "$MOCK_BIN/gh" << STUB
#!/usr/bin/env bash
if [[ "\$*" == *"pr view"* ]]; then
  echo "${base_ref}"
  exit 0
fi
if [[ "\$*" == *"pr list"* ]]; then
  echo ""
  exit 0
fi
exec \$(command -v gh) "\$@"
STUB
  chmod +x "$MOCK_BIN/gh"
}

# Helper: run hook with mock gh injected
run_hook_mocked() {
  local base_ref="$1" input="$2"
  write_gh_stub "$base_ref"
  echo "$input" | PATH="$MOCK_BIN:$PATH" bash "$HOOK" 2>/dev/null || true
}

# ── Regression test #223: --merge targeting main should NOT warn ─────────
# config/project.yaml: branches.main.merge_method = merge (overrides default squash)
OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 223 --merge"}}')
assert_empty "regression #223: --merge to main passes silently (branch override respected)" "$OUT"

# ── Sanity: --squash targeting main SHOULD warn (main prefers merge) ─────
OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 223 --squash"}}')
assert_valid_json "mocked main --squash: warning is valid JSON" "$OUT"
assert_contains "mocked main --squash: warns about mismatch" "$OUT" "mismatch"
assert_contains "mocked main --squash: names the configured method" "$OUT" "merge"
assert_contains "mocked main --squash: includes branch name" "$OUT" "main"

# ── Sanity: --rebase targeting develop SHOULD warn (develop prefers squash) ─
OUT=$(run_hook_mocked "develop" '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 10 --rebase"}}')
assert_valid_json "mocked develop --rebase: warning is valid JSON" "$OUT"
assert_contains "mocked develop --rebase: warns about mismatch" "$OUT" "mismatch"

# ── Misbinding guard (codex review #227): explicit PR number must not fall back ──
# If `gh pr view <N>` fails, we must NOT infer target from `gh pr list --head
# <current-branch>` — doing so could bind the command to a different PR open on
# the current branch. Explicit PR number → trust pr view only → bail silently.
write_gh_view_fail_stub() {
  local list_base_ref="$1"
  cat > "$MOCK_BIN/gh" << STUB
#!/usr/bin/env bash
if [[ "\$*" == *"pr view"* ]]; then
  # Simulate a failure (e.g. closed/missing PR, auth issue)
  exit 1
fi
if [[ "\$*" == *"pr list"* ]]; then
  # A DIFFERENT PR is open on the current branch targeting \${list_base_ref}.
  # If the hook wrongly falls back to this, the test will observe a warning
  # driven by the wrong branch's merge_method.
  echo "${list_base_ref}"
  exit 0
fi
exec \$(command -v gh) "\$@"
STUB
  chmod +x "$MOCK_BIN/gh"
}

# Setup: pr view fails for explicit PR 999, but pr list would return "develop".
# If the fallback fires, the develop branch override (squash) would trigger a
# mismatch warning against the --merge flag. Correct behavior: silent bail.
write_gh_view_fail_stub "develop"
OUT=$(echo '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 999 --merge"}}' | PATH="$MOCK_BIN:$PATH" bash "$HOOK" 2>/dev/null || true)
assert_empty "explicit PR number with failed pr view bails silently (no misbinding)" "$OUT"

# ── Output format: warning has correct JSON shape ────────────────────────
OUT=$(run_hook_mocked "develop" '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 10 --merge"}}')
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
  echo "  FAIL: Expected mismatch output for develop --merge"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
