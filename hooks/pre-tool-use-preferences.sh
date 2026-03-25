#!/usr/bin/env bash
# hooks/pre-tool-use-preferences.sh — PreToolUse preference validation hook
#
# Epic 0.3: Validates merge methods and force-push on protected branches.
# Reads stdin JSON: { tool_name, tool_input: { command } }
# Outputs: JSON with additionalContext warning on mismatch, empty otherwise.
#
# Contract: NEVER blocks — only warns via additionalContext.
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

# ── Resolve repo root and source config reader ─────────────────────────
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CONFIG_READER="${REPO_ROOT}/lib/config-reader.sh"
PROJECT_YAML="${REPO_ROOT}/config/project.yaml"

# ── Check 1: gh pr merge — merge method validation ─────────────────────
if echo "$COMMAND" | grep -q 'gh pr merge'; then

  # Extract merge method from command flags
  CMD_METHOD=""
  if echo "$COMMAND" | grep -qE -- '--squash'; then
    CMD_METHOD="squash"
  elif echo "$COMMAND" | grep -qE -- '--merge'; then
    CMD_METHOD="merge"
  elif echo "$COMMAND" | grep -qE -- '--rebase'; then
    CMD_METHOD="rebase"
  fi
  # If no flag specified, we can't determine intent — pass through
  [ -n "$CMD_METHOD" ] || exit 0

  # Extract PR number from command (gh pr merge <number> or gh pr merge <url>)
  PR_NUMBER=$(echo "$COMMAND" | grep -oE 'gh pr merge[[:space:]]+([0-9]+)' | grep -oE '[0-9]+' || true)

  # Determine target branch
  TARGET_BRANCH=""
  if [ -n "$PR_NUMBER" ]; then
    TARGET_BRANCH=$(gh pr view "$PR_NUMBER" --json baseRefName -q .baseRefName 2>/dev/null || true)
  fi

  # Load configured merge method via config-reader.sh
  CONFIGURED_METHOD=""
  if [ -f "$CONFIG_READER" ] && [ -f "$PROJECT_YAML" ]; then
    # shellcheck source=lib/config-reader.sh
    source "$CONFIG_READER"
    CONFIGURED_METHOD=$(load_pr_pref "merge_method" "" "$TARGET_BRANCH" 2>/dev/null || true)
  fi

  # If we couldn't determine the configured method, pass through
  [ -n "$CONFIGURED_METHOD" ] || exit 0

  # Compare
  if [ "$CMD_METHOD" != "$CONFIGURED_METHOD" ]; then
    BRANCH_MSG=""
    if [ -n "$TARGET_BRANCH" ]; then
      BRANCH_MSG=" for branch ${TARGET_BRANCH}"
    fi

    WARNING="[xgh] WARNING: merge method mismatch. Command uses --${CMD_METHOD} but config/project.yaml specifies ${CONFIGURED_METHOD}${BRANCH_MSG}. Consider using --${CONFIGURED_METHOD} instead."

    jq -n --arg warning "$WARNING" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": $warning
      }
    }'
    exit 0
  fi

  # Match — pass through silently
  exit 0
fi

# ── Check 2: git push --force on protected branches ────────────────────
if echo "$COMMAND" | grep -qE 'git push.*(--force|-f)'; then

  # Extract target branch from push command
  # Patterns: git push origin main --force, git push -f origin main, git push --force
  PUSH_BRANCH=""

  # Try to extract remote and branch from the command
  # Remove flags to find positional args: git push [remote] [refspec]
  PUSH_ARGS=$(echo "$COMMAND" | sed 's/git push//' | sed 's/--force-with-lease//g' | sed 's/--force//g' | sed 's/-f//g' | sed 's/--no-verify//g' | xargs)

  if [ -n "$PUSH_ARGS" ]; then
    # Second positional arg is typically the branch (first is remote)
    PUSH_BRANCH=$(echo "$PUSH_ARGS" | awk '{print $2}')
    # Handle refspec like main:main
    PUSH_BRANCH=$(echo "$PUSH_BRANCH" | sed 's/:.*//')
  fi

  # If no branch specified, try current branch
  if [ -z "$PUSH_BRANCH" ]; then
    PUSH_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  fi

  [ -n "$PUSH_BRANCH" ] || exit 0

  # Check if branch is protected in project.yaml
  if [ -f "$PROJECT_YAML" ] && command -v python3 >/dev/null 2>&1; then
    IS_PROTECTED=$(python3 -c "
import yaml, sys
branch = sys.argv[1]
with open(sys.argv[2]) as f:
    d = yaml.safe_load(f) or {}
v = d.get('preferences',{}).get('pr',{}).get('branches',{}).get(branch,{}).get('protected', False)
print(str(v).lower())
" "$PUSH_BRANCH" "$PROJECT_YAML" 2>/dev/null || echo "false")

    if [ "$IS_PROTECTED" = "true" ]; then
      WARNING="[xgh] WARNING: force-push to protected branch '${PUSH_BRANCH}'. config/project.yaml marks this branch as protected. Consider using a non-force push or targeting a different branch."

      jq -n --arg warning "$WARNING" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "additionalContext": $warning
        }
      }'
      exit 0
    fi
  fi

  exit 0
fi

# ── No checks matched — silent pass-through ─────────────────────────────
exit 0
