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
# Proof methodology: we install a sentinel `gh` stub that writes a marker to
# a side-file whenever it is invoked.  The false-positive tests then assert
# both that hook output is empty AND that the side-file remained empty,
# proving the trigger function itself did not call gh — not just that the
# hook happened to return nothing via fail-open.

echo "--- Regression #228: semantic trigger (sentinel gh stub) ---"

SENTINEL_BIN=$(mktemp -d)
SENTINEL_FILE=$(mktemp)
trap 'rm -rf "$EARLY_STUB" "$FP_BIN" "$MOCK_BIN" "$SENTINEL_BIN"; rm -f "$SENTINEL_FILE"' EXIT

cat > "$SENTINEL_BIN/gh" << SENTINELSTUB
#!/usr/bin/env bash
# Sentinel: record every invocation so tests can detect spurious gh calls.
echo "CALLED: \$*" >> "$SENTINEL_FILE"
# For pr view / pr list return empty so fail-open still works if trigger
# somehow fires; this makes the sentinel test stricter (tests the trigger,
# not just the downstream bail-out).
exit 0
SENTINELSTUB
chmod +x "$SENTINEL_BIN/gh"

assert_gh_not_called() {
  local desc="$1"
  if [ -s "$SENTINEL_FILE" ]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — sentinel gh was called: $(cat "$SENTINEL_FILE")"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc (trigger correctly skipped — gh never called)"
  fi
  # Reset for next test
  > "$SENTINEL_FILE"
}

run_hook_sentinel() {
  local input="$1"
  > "$SENTINEL_FILE"
  echo "$input" | PATH="$SENTINEL_BIN:$PATH" bash "$HOOK" 2>/dev/null || true
}

# git commit whose -m value contains 'gh pr merge 123 --merge' in a heredoc-style
# quoted string — the actual command is `git commit`, NOT `gh pr merge`.
OUT=$(run_hook_sentinel '{"tool_name": "Bash", "tool_input": {"command": "git commit -m \"$(cat <<EOF\ngh pr merge 123 --merge\nEOF\n)\""}}')
assert_empty "#228: gh pr merge inside heredoc body — output must be empty" "$OUT"
assert_gh_not_called "#228: gh pr merge inside heredoc body — trigger must NOT call gh"

# git commit with literal text in a simple quoted -m arg
OUT=$(run_hook_sentinel '{"tool_name": "Bash", "tool_input": {"command": "git commit -m \"gh pr merge 123 --merge\""}}')
assert_empty "#228: gh pr merge inside quoted -m — output must be empty" "$OUT"
assert_gh_not_called "#228: gh pr merge inside quoted -m — trigger must NOT call gh"

# gh issue create whose body contains a URL with pull/999
OUT=$(run_hook_sentinel '{"tool_name": "Bash", "tool_input": {"command": "gh issue create --body \"see https://github.com/owner/repo/pull/999 and gh pr merge 999 --squash\""}}')
assert_empty "#228: gh pr merge URL inside --body — output must be empty" "$OUT"
assert_gh_not_called "#228: gh pr merge URL inside --body — trigger must NOT call gh"

# ── True positives: trigger must fire for real invocations ─────────────

# Real `gh pr merge 42 --squash` at start of command — must enter Check 1
# (sentinel fires, output empty only because gh returns empty base ref).
OUT=$(run_hook_sentinel '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42 --squash"}}')
if [ -s "$SENTINEL_FILE" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: #228 positive: gh pr merge at start — trigger correctly entered (gh called)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: #228 positive: gh pr merge at start — trigger did NOT enter (gh never called)"
fi
> "$SENTINEL_FILE"

# Real `gh pr merge 42 --squash` after `&&` separator — must also enter Check 1
OUT=$(run_hook_sentinel '{"tool_name": "Bash", "tool_input": {"command": "git fetch && gh pr merge 42 --squash"}}')
if [ -s "$SENTINEL_FILE" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: #228 positive: gh pr merge after && — trigger correctly entered (gh called)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: #228 positive: gh pr merge after && — trigger did NOT enter (gh never called)"
fi
> "$SENTINEL_FILE"

# Mocked gh confirms true-positive output for real invocations
OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42 --squash"}}')
assert_contains "#228 positive: gh pr merge at start — warns for main (prefers merge)" "$OUT" "mismatch"

OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "git fetch && gh pr merge 42 --squash"}}')
assert_contains "#228 positive: gh pr merge after && separator — warns for main" "$OUT" "mismatch"

# ── Regression: env-prefix KEY=VAR before gh pr merge must trigger correctly ──
# `GH_TOKEN=abc gh pr merge 42 --squash` — first token is KEY=VAR, which awk
# correctly skips to find `gh` as the real command.  The previous grep anchor
# `'^(\\)?gh pr merge'` ran against the raw segment starting with `GH_TOKEN=…`
# and rejected it, causing a false-negative (enforcement gap).
OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "GH_TOKEN=abc gh pr merge 42 --squash"}}')
assert_contains "#228 env-prefix: GH_TOKEN=abc gh pr merge 42 --squash — must warn (true positive)" "$OUT" "mismatch"

echo ""

# ── AR Finding 1: quoted separators must NOT split segments ─────────────
# Codex AR Finding 1 (HIGH): `_command_segments` must not split on separators
# that appear inside quoted argument values.
# `gh issue create --body "note; gh pr merge 999 --squash"` — the `;` is
# inside a double-quoted string; only ONE segment must be produced, and it
# must NOT look like a `gh pr merge` invocation at the shell level.

echo "--- AR Finding 1: separators inside quoted strings ---"

# False-positive guard: the `;` inside the --body value must NOT split the
# command into two segments.  The hook should see only one segment whose
# first real token is `gh issue create`, not `gh pr merge`.
# Sentinel gh: if trigger fires, the sentinel file is written.
OUT=$(run_hook_sentinel '{"tool_name": "Bash", "tool_input": {"command": "gh issue create --body \"note; gh pr merge 999 --squash\""}}')
assert_empty "AR-F1: semicolon inside --body quoted string — output must be empty (no false positive)" "$OUT"
assert_gh_not_called "AR-F1: semicolon inside --body quoted string — trigger must NOT call gh"

# True-positive: `gh pr merge 42 --squash && echo done` — the `&&` is OUTSIDE
# any quotes; the second segment IS a real `gh pr merge`.  Trigger must fire.
OUT=$(run_hook_sentinel '{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 42 --squash && echo done"}}')
if [ -s "$SENTINEL_FILE" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: AR-F1: real gh pr merge before && — trigger correctly entered (gh called)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AR-F1: real gh pr merge before && — trigger did NOT enter (gh never called)"
fi
> "$SENTINEL_FILE"

echo ""

# ── AR Finding 2: lowercase env-var prefixes must not suppress trigger ───
# Codex AR Finding 2 (MEDIUM): `_strip_env_prefix` previously only matched
# UPPERCASE identifiers; shell allows lowercase too.
# `foo=1 gh pr merge 42 --squash` — `foo=1` is a lowercase env assignment;
# after stripping it, the real command is `gh pr merge`.

echo "--- AR Finding 2: lowercase env-var prefix ---"

OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "foo=1 gh pr merge 42 --squash"}}')
assert_contains "AR-F2: foo=1 gh pr merge 42 --squash — must warn (lowercase env stripped)" "$OUT" "mismatch"

echo ""

# ── AR Finding 3: quoted heredoc markers must NOT suppress real commands ─
# Codex AR Finding 3 (MEDIUM): `_strip_heredocs` must not treat `<<EOF`
# inside a quoted string as a heredoc opener.
# `printf "<<EOF"; gh pr merge 42 --squash` — the `<<EOF` is inside quotes;
# the real merge command on the second segment must NOT be suppressed.

echo "--- AR Finding 3: quoted heredoc marker does not suppress real command ---"

OUT=$(run_hook_sentinel '{"tool_name": "Bash", "tool_input": {"command": "printf \"<<EOF\"; gh pr merge 42 --squash"}}')
if [ -s "$SENTINEL_FILE" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: AR-F3: quoted <<EOF does not suppress real gh pr merge — trigger entered (gh called)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AR-F3: quoted <<EOF suppressed real gh pr merge — trigger did NOT enter"
fi
> "$SENTINEL_FILE"

# Mocked gh confirms warning is produced (trigger fires and evaluates branch)
OUT=$(run_hook_mocked "main" '{"tool_name": "Bash", "tool_input": {"command": "printf \"<<EOF\"; gh pr merge 42 --squash"}}')
assert_contains "AR-F3: quoted <<EOF — real gh pr merge warns for main (true positive)" "$OUT" "mismatch"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
