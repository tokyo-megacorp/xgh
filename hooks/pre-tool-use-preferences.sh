#!/usr/bin/env bash
# hooks/pre-tool-use-preferences.sh — PreToolUse preference validation hook
#
# Phase 2: 5 severity-aware checks (block or warn per config).
# Reads stdin JSON: { tool_name, tool_input: { command } }
# Block: { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "..." } }
# Warn:  { hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: "..." } }
# Any failure = silent pass-through (exit 0, no output).
set -euo pipefail

# ── Read stdin ──────────────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# ── Fast exit: only Bash tool ───────────────────────────────────────────
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ "$TOOL_NAME" = "Bash" ] || exit 0

# ── Extract command ─────────────────────────────────────────────────────
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0

# ── Resolve repo root and source libraries ──────────────────────────────
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
PROJECT_YAML="${REPO_ROOT}/config/project.yaml"
[ -f "$PROJECT_YAML" ] || exit 0

# Source preference read layer and severity resolver
# shellcheck source=../lib/preferences.sh
source "${REPO_ROOT}/lib/preferences.sh" 2>/dev/null || exit 0
# shellcheck source=../lib/severity.sh
source "${REPO_ROOT}/lib/severity.sh" 2>/dev/null || exit 0

# ── Output helpers ──────────────────────────────────────────────────────
_emit_block() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

_emit_warn() {
  local msg="$1"
  jq -n --arg msg "$msg" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": $msg
    }
  }'
}

_emit() {
  local severity="$1" message="$2"
  if [[ "$severity" == "block" ]]; then
    _emit_block "$message"
  else
    _emit_warn "$message"
  fi
}

# ── Check 1: gh pr merge — merge method validation ─────────────────────
if echo "$COMMAND" | grep -q 'gh pr merge'; then
  CMD_METHOD=""
  if echo "$COMMAND" | grep -qE -- '--squash'; then
    CMD_METHOD="squash"
  elif echo "$COMMAND" | grep -qE -- '--merge'; then
    CMD_METHOD="merge"
  elif echo "$COMMAND" | grep -qE -- '--rebase'; then
    CMD_METHOD="rebase"
  fi
  [ -n "$CMD_METHOD" ] || exit 0

  # Determine target branch
  PR_NUMBER=$(echo "$COMMAND" | grep -oE 'gh pr merge[[:space:]]+([0-9]+)' | grep -oE '[0-9]+' || true)
  # Fail-open: PR number not parseable from command — skip validation
  [ -n "$PR_NUMBER" ] || exit 0
  TARGET_BRANCH=$(gh pr view "$PR_NUMBER" --json baseRefName -q .baseRefName 2>/dev/null || true)
  # TARGET_BRANCH may be empty if gh fails; validate against global config in that case

  CONFIGURED_METHOD=$(load_pr_pref "merge_method" "" "$TARGET_BRANCH")
  [ -n "$CONFIGURED_METHOD" ] || exit 0

  if [ "$CMD_METHOD" != "$CONFIGURED_METHOD" ]; then
    BRANCH_MSG=""
    [ -n "$TARGET_BRANCH" ] && BRANCH_MSG=" for branch ${TARGET_BRANCH}"
    severity=$(_severity_resolve "pr" "merge_method")
    _emit "$severity" "[xgh] Merge method mismatch: command uses --${CMD_METHOD} but config/project.yaml specifies ${CONFIGURED_METHOD}${BRANCH_MSG}. Use --${CONFIGURED_METHOD} instead."
  fi
  exit 0
fi

# ── Check 2: git push --force on protected branches ────────────────────
if echo "$COMMAND" | grep -qE 'git push.*(--force|[ ]-f[ ]|[ ]-f$)'; then
  # Tokenize git push args into an array for robust parsing
  PUSH_BRANCH=""
  read -ra _PUSH_TOKENS <<< "$COMMAND"
  _IN_PUSH=0
  _REMOTE_SEEN=0
  for _tok in "${_PUSH_TOKENS[@]}"; do
    if [[ "$_tok" == "push" && "$_IN_PUSH" -eq 0 ]]; then
      _IN_PUSH=1
      continue
    fi
    [[ "$_IN_PUSH" -eq 0 ]] && continue
    # Skip flags
    [[ "$_tok" == --force* || "$_tok" == --force-with-lease* || "$_tok" == --no-verify || "$_tok" == -f || "$_tok" == -u || "$_tok" == --set-upstream ]] && continue
    if [[ "$_REMOTE_SEEN" -eq 0 ]]; then
      # First non-flag token after "push" is the remote
      _REMOTE_SEEN=1
      continue
    fi
    # Second non-flag token is the refspec; handle src:dst form
    if [[ "$_tok" == *:* ]]; then
      PUSH_BRANCH="${_tok##*:}"
    else
      PUSH_BRANCH="$_tok"
    fi
    break
  done
  [ -z "$PUSH_BRANCH" ] && PUSH_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -n "$PUSH_BRANCH" ] || exit 0

  IS_PROTECTED=$(_pref_read_branch "vcs" "$PUSH_BRANCH" "protected")
  # Also check pr.branches for backward compat
  if [[ "$IS_PROTECTED" != "true" ]]; then
    IS_PROTECTED=$(_pref_read_branch "pr" "$PUSH_BRANCH" "protected")
  fi

  if [[ "$IS_PROTECTED" == "true" ]]; then
    severity=$(_severity_resolve "vcs" "force_push")
    _emit "$severity" "[xgh] Force-push to protected branch '${PUSH_BRANCH}'. config/project.yaml marks this branch as protected."
  fi
  exit 0
fi

# ── Check 3: Branch naming convention ───────────────────────────────────
if echo "$COMMAND" | grep -qE 'git (checkout -b|switch -c)'; then
  # Extract branch name (last argument after -b or -c)
  BRANCH_NAME=$(echo "$COMMAND" | grep -oE '(checkout -b|switch -c)[[:space:]]+([^ ]+)' | awk '{print $NF}')
  [ -n "$BRANCH_NAME" ] || exit 0

  PATTERN=$(_pref_read_yaml "preferences.vcs.branch_naming")
  [ -n "$PATTERN" ] || exit 0

  if ! echo "$BRANCH_NAME" | grep -qE "$PATTERN" 2>/dev/null; then
    severity=$(_severity_resolve "vcs" "branch_naming")
    _emit "$severity" "[xgh] Branch name '${BRANCH_NAME}' does not match convention: ${PATTERN}. Check preferences.vcs.branch_naming."
  fi
  exit 0
fi

# ── Check 4: Commit on protected branch ─────────────────────────────────
if echo "$COMMAND" | grep -qE 'git commit'; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -n "$CURRENT_BRANCH" ] || exit 0

  IS_PROTECTED=$(_pref_read_branch "vcs" "$CURRENT_BRANCH" "protected")
  if [[ "$IS_PROTECTED" != "true" ]]; then
    IS_PROTECTED=$(_pref_read_branch "pr" "$CURRENT_BRANCH" "protected")
  fi

  if [[ "$IS_PROTECTED" == "true" ]]; then
    severity=$(_severity_resolve "vcs" "protected_branch")
    _emit "$severity" "[xgh] Direct commit on protected branch '${CURRENT_BRANCH}'. Use a feature branch instead."
    exit 0
  fi

  # ── Check 5: Commit format (only if not on protected branch) ──────────
  COMMIT_MSG=""
  if echo "$COMMAND" | grep -qE -- '-m[[:space:]]'; then
    # Try quoted first, then unquoted single-token fallback
    COMMIT_MSG=$(echo "$COMMAND" | sed -n "s/.*-m[[:space:]]*['\"]\\(.*\\)['\"].*/\\1/p")
    if [ -z "$COMMIT_MSG" ]; then
      COMMIT_MSG=$(echo "$COMMAND" | sed -n "s/.*-m[[:space:]]\+\([^[:space:]'\"]\+\).*/\1/p")
    fi
  elif echo "$COMMAND" | grep -qE -- '--message[[:space:]]'; then
    COMMIT_MSG=$(echo "$COMMAND" | sed -n "s/.*--message[[:space:]]*['\"]\\(.*\\)['\"].*/\\1/p")
    if [ -z "$COMMIT_MSG" ]; then
      COMMIT_MSG=$(echo "$COMMAND" | sed -n "s/.*--message[[:space:]]\+\([^[:space:]'\"]\+\).*/\1/p")
    fi
  fi
  [ -n "$COMMIT_MSG" ] || exit 0

  # Skip validation if the message is a shell substitution — can't inspect at hook time
  [[ "$COMMIT_MSG" == \$\(* ]] && exit 0

  FORMAT_REGEX=$(_pref_read_yaml "preferences.vcs.commit_format")
  [ -n "$FORMAT_REGEX" ] || exit 0

  if ! echo "$COMMIT_MSG" | grep -qE "$FORMAT_REGEX" 2>/dev/null; then
    severity=$(_severity_resolve "vcs" "commit_format")
    _emit "$severity" "[xgh] Commit message does not match format: ${FORMAT_REGEX}. Check preferences.vcs.commit_format."
  fi
  exit 0
fi

# ── No checks matched — silent pass-through ─────────────────────────────
exit 0
