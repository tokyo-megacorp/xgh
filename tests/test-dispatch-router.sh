#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if grep -qi -- "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 missing '$2'"
    FAIL=$((FAIL + 1))
  fi
}

# --- File existence ---
assert_file_exists "skills/dispatch/dispatch.md"
assert_file_exists "commands/dispatch.md"
assert_file_exists "tests/skill-triggering/prompts/dispatch.txt"

# --- Skill: all 8 archetypes ---
assert_contains "skills/dispatch/dispatch.md" "brainstorming"
assert_contains "skills/dispatch/dispatch.md" "planning"
assert_contains "skills/dispatch/dispatch.md" "implementation"
assert_contains "skills/dispatch/dispatch.md" "code-review"
assert_contains "skills/dispatch/dispatch.md" "debugging"
assert_contains "skills/dispatch/dispatch.md" "refactoring"
assert_contains "skills/dispatch/dispatch.md" "documentation"
assert_contains "skills/dispatch/dispatch.md" "quick-task"

# --- Skill: profile lookup ---
assert_contains "skills/dispatch/dispatch.md" "model-profiles.yaml"

# --- Skill: override flags ---
assert_contains "skills/dispatch/dispatch.md" "--model"
assert_contains "skills/dispatch/dispatch.md" "--agent"

# --- Skill: cold start fallback ---
assert_contains "skills/dispatch/dispatch.md" "CLI default"

# --- Skill: agent-specific flag awareness ---
assert_contains "skills/dispatch/dispatch.md" "OpenCode has no effort flag"

# --- Skill: model prefix routing ---
assert_contains "skills/dispatch/dispatch.md" "gpt-"
assert_contains "skills/dispatch/dispatch.md" "gemini-"

# --- Skill: dispatches to known agents ---
assert_contains "skills/dispatch/dispatch.md" "xgh-codex"
assert_contains "skills/dispatch/dispatch.md" "xgh-gemini"
assert_contains "skills/dispatch/dispatch.md" "xgh-opencode"

# --- Skill: observation write ---
assert_contains "skills/dispatch/dispatch.md" "observation"
assert_contains "skills/dispatch/dispatch.md" "accepted"

# --- Command file ---
assert_contains "commands/dispatch.md" "xgh:dispatch"
assert_contains "commands/dispatch.md" "/xgh-dispatch"
assert_contains "commands/dispatch.md" "exec"
assert_contains "commands/dispatch.md" "--model"
assert_contains "commands/dispatch.md" "--agent"

echo ""
echo "Dispatch router test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
