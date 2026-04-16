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

# ── Regression #229: --no-force and --force-with-lease must NOT warn ────
# These use mock-python3 to force IS_PROTECTED=true for 'main' so that, if the
# trigger fires, the warning would be emitted.  The test verifies no warning is
# emitted — confirming the trigger correctly skips safe flags.

echo "--- Regression #229: false-positive protection ---"

FP_BIN=$(mktemp -d)

# python3 stub: always returns "true" (branch is protected).
# If the trigger fires for a false-positive flag, the warning would appear.
cat > "$FP_BIN/python3" << 'PYSTUB'
#!/usr/bin/env bash
# Stub: pretend every branch is protected
echo "true"
PYSTUB
chmod +x "$FP_BIN/python3"

run_hook_protected() {
  local input="$1"
  echo "$input" | PATH="$FP_BIN:$PATH" bash "$HOOK" 2>/dev/null || true
}

OUT=$(run_hook_protected '{"tool_name": "Bash", "tool_input": {"command": "git push --force-with-lease origin main"}}')
assert_empty "#229: --force-with-lease must NOT warn (not a destructive force-push)" "$OUT"

OUT=$(run_hook_protected '{"tool_name": "Bash", "tool_input": {"command": "git push --no-force origin main"}}')
assert_empty "#229: --no-force must NOT warn (negating flag)" "$OUT"

# True positives: --force and -f to a protected branch SHOULD warn
OUT=$(run_hook_protected '{"tool_name": "Bash", "tool_input": {"command": "git push --force origin main"}}')
assert_contains "#229: --force to protected branch SHOULD warn" "$OUT" "WARNING"

OUT=$(run_hook_protected '{"tool_name": "Bash", "tool_input": {"command": "git push -f origin main"}}')
assert_contains "#229: -f to protected branch SHOULD warn" "$OUT" "WARNING"

echo ""

# ── Regression #230: combined short flags must resolve branch correctly ──
echo "--- Regression #230: combined short flags ---"

OUT=$(run_hook_protected '{"tool_name": "Bash", "tool_input": {"command": "git push -fu origin main"}}')
assert_contains "#230: -fu origin main — warning should mention 'main' not 'u' or 'origin'" "$OUT" "main"

OUT=$(run_hook_protected '{"tool_name": "Bash", "tool_input": {"command": "git push -uf origin main"}}')
assert_contains "#230: -uf origin main — warning should mention 'main' not 'u' or 'origin'" "$OUT" "main"

echo ""

# ── Regression #231: HEAD:main refspec resolves to remote branch ─────────
echo "--- Regression #231: HEAD:main refspec ---"

OUT=$(run_hook_protected '{"tool_name": "Bash", "tool_input": {"command": "git push --force origin HEAD:main"}}')
assert_contains "#231: HEAD:main refspec — warning should mention 'main' not 'HEAD'" "$OUT" "main"
assert_not_contains "#231: HEAD:main refspec — warning should NOT mention 'HEAD'" "$OUT" "'HEAD'"

echo ""

# ── Branch-override and output format tests (mock gh) ──────────────────
# These tests stub `gh` on PATH so we can control what baseRefName is returned
# without relying on live PRs.  The stub is created in a temp dir and cleaned up.

echo "--- Branch-override + output format tests (mock gh) ---"

MOCK_BIN=$(mktemp -d)
trap 'rm -rf "$EARLY_STUB" "$FP_BIN" "$MOCK_BIN"' EXIT

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

# ── URL-selector coverage (codex review round 2) ─────────────────────────
# `gh pr merge` accepts <number> | <url> | <branch>. The URL form must also
# be treated as an explicit selector — no current-branch fallback.

# URL form resolves to main via pr view — --merge is correct for main (no warn)
write_gh_stub "main"
OUT=$(echo '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge https://github.com/tokyo-megacorp/xgh/pull/223 --merge"}}' | PATH="$MOCK_BIN:$PATH" bash "$HOOK" 2>/dev/null || true)
assert_empty "URL selector: --merge to main passes silently" "$OUT"

# URL form resolves to develop — --merge mismatches (develop prefers squash)
write_gh_stub "develop"
OUT=$(echo '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge https://github.com/tokyo-megacorp/xgh/pull/10 --merge"}}' | PATH="$MOCK_BIN:$PATH" bash "$HOOK" 2>/dev/null || true)
assert_contains "URL selector: --merge to develop warns (true positive)" "$OUT" "mismatch"

# URL form but pr view fails; pr list would return a different base — must bail silently
write_gh_view_fail_stub "main"
OUT=$(echo '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge https://github.com/tokyo-megacorp/xgh/pull/999 --squash"}}' | PATH="$MOCK_BIN:$PATH" bash "$HOOK" 2>/dev/null || true)
assert_empty "URL selector with failed pr view bails silently (no misbinding)" "$OUT"

# Malformed URL (no numeric pull id) — treated as explicit selector, bails silently
write_gh_view_fail_stub "main"
OUT=$(echo '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge https://github.com/tokyo-megacorp/xgh/pull/abc --merge"}}' | PATH="$MOCK_BIN:$PATH" bash "$HOOK" 2>/dev/null || true)
assert_empty "malformed URL bails silently (no current-branch fallback)" "$OUT"

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

# ── Regression #228: embedded `gh pr merge` must NOT trigger Check 1 ────
# The trigger grep used to be unanchored, so literal text appearing inside
# quoted strings, heredoc bodies, or argument values would fire Check 1 and
# — if a number was also present — emit a spurious warning.

echo "--- Regression #228: anchored trigger grep ---"

# git commit whose -m value contains 'gh pr merge 123 --merge' in a heredoc-style
# quoted string — the actual command is `git commit`, NOT `gh pr merge`.
OUT=$(run_hook_empty_gh '{"tool_name": "Bash", "tool_input": {"command": "git commit -m \"$(cat <<EOF\ngh pr merge 123 --merge\nEOF\n)\""}}')
assert_empty "#228: gh pr merge inside heredoc body must NOT trigger (actual cmd is git commit)" "$OUT"

# git commit with literal text in a simple quoted -m arg
OUT=$(run_hook_empty_gh '{"tool_name": "Bash", "tool_input": {"command": "git commit -m \"gh pr merge 123 --merge\""}}')
assert_empty "#228: gh pr merge inside quoted -m must NOT trigger" "$OUT"

# gh issue create whose body contains a URL with pull/999
OUT=$(run_hook_empty_gh '{"tool_name": "Bash", "tool_input": {"command": "gh issue create --body \"see https://github.com/owner/repo/pull/999 — gh pr merge 999 --squash\""}}')
assert_empty "#228: gh pr merge URL inside quoted body must NOT trigger" "$OUT"

# Real `gh pr merge 42 --squash` at start of command still triggers
# (gh stub returns empty base ref → silent bail, but Check 1 must have entered)
# We verify by checking that a properly mocked gh DOES produce output for this form.
OUT=$(run_hook_mocked "develop" '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42 --squash"}}')
assert_empty "#228 positive: gh pr merge 42 --squash targeting develop with squash configured passes silently" "$OUT"

OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42 --squash"}}')
assert_contains "#228 positive: gh pr merge 42 --squash at start of command triggers (main prefers merge)" "$OUT" "mismatch"

# Real `&& gh pr merge 42 --merge` — after a separator — must still trigger
OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "git fetch && gh pr merge 42 --squash"}}')
assert_contains "#228 positive: gh pr merge after && separator triggers correctly" "$OUT" "mismatch"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
