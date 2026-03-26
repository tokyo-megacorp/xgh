#!/usr/bin/env bash
# hooks/post-tool-use-failure-preferences.sh — PostToolUseFailure diagnosis
#
# Phase 2 Epic 2.3: Parse gh CLI stderr on failure and inject targeted fix suggestions.
# Matcher: Bash
#
# Stdin: { tool_name, tool_input: { command }, tool_response: { stderr?, output? } }
# Output: hookSpecificOutput with additionalContext on match, silent otherwise.
# Dual-match: both command context AND stderr signal must match.
set -euo pipefail

# ── Read stdin ──────────────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# ── Extract command ─────────────────────────────────────────────────────
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0

# ── Check if gh appears in command ──────────────────────────────────────
echo "$COMMAND" | grep -qwE 'gh' || exit 0

# ── Defensive stderr extraction ─────────────────────────────────────────
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null) || STDERR=""
if [[ -z "$STDERR" ]]; then
  STDERR=$(echo "$INPUT" | jq -r '.tool_response.output // empty' 2>/dev/null) || STDERR=""
fi
if [[ -z "$STDERR" ]]; then
  STDERR=$(echo "$INPUT" | jq -r '.tool_response // empty' 2>/dev/null) || STDERR=""
fi
[ -n "$STDERR" ] || exit 0

# ── Resolve repo root for preference reads ──────────────────────────────
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
PREFS="${REPO_ROOT}/lib/preferences.sh"
if [[ -f "$PREFS" ]]; then
  # shellcheck source=../lib/preferences.sh
  source "$PREFS" 2>/dev/null || true
fi

# ── Output helper ──────────────────────────────────────────────────────
_emit_diagnosis() {
  local msg="$1"
  jq -n --arg msg "$msg" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUseFailure",
      "additionalContext": $msg
    }
  }'
}

# ── Pattern 1: Merge method mismatch ───────────────────────────────────
# Command: gh pr merge  |  Stderr: "merge_method"
if echo "$COMMAND" | grep -q 'gh pr merge'; then
  if echo "$STDERR" | grep -qi 'merge_method'; then
    CONFIGURED=""
    if declare -f load_pr_pref >/dev/null 2>&1; then
      CONFIGURED=$(load_pr_pref "merge_method" "" "" 2>/dev/null || true)
    fi
    HINT=""
    [[ -n "$CONFIGURED" ]] && HINT=" Check preferences.pr.merge_method (currently: ${CONFIGURED})."
    _emit_diagnosis "[xgh] Merge failed — repo requires a different merge method than the command used.${HINT}"
    exit 0
  fi
fi

# ── Pattern 2: Stale/wrong reviewer ────────────────────────────────────
# Command: --add-reviewer in command  |  Stderr: "Could not resolve"
if echo "$COMMAND" | grep -q '\-\-add-reviewer'; then
  if echo "$STDERR" | grep -qi 'could not resolve'; then
    REVIEWER=""
    if declare -f load_pr_pref >/dev/null 2>&1; then
      REVIEWER=$(load_pr_pref "reviewer" "" "" 2>/dev/null || true)
    fi
    HINT=""
    [[ -n "$REVIEWER" ]] && HINT=" Current config: ${REVIEWER}."
    _emit_diagnosis "[xgh] Reviewer not found — verify preferences.pr.reviewer and bot installation.${HINT}"
    exit 0
  fi
fi

# ── Pattern 3: Wrong repo/fork ─────────────────────────────────────────
# Command: any gh command  |  Stderr: "Could not resolve to a Repository"
if echo "$STDERR" | grep -qi 'could not resolve to a repository'; then
  REPO=""
  if declare -f load_pr_pref >/dev/null 2>&1; then
    REPO=$(load_pr_pref "repo" "" "" 2>/dev/null || true)
  fi
  HINT=""
  [[ -n "$REPO" ]] && HINT=" Check preferences.pr.repo (currently: ${REPO})."
  _emit_diagnosis "[xgh] Repository not found — verify preferences.pr.repo matches remote.${HINT}"
  exit 0
fi

# ── Pattern 4: Auth required ───────────────────────────────────────────
# Command: any gh command  |  Stderr: "authentication" or "auth login"
if echo "$STDERR" | grep -qiE 'authentication|auth login'; then
  _emit_diagnosis "[xgh] GitHub auth required — run 'gh auth login' or check your token."
  exit 0
fi

# ── No match → fail-open ───────────────────────────────────────────────
exit 0
