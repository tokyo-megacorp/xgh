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
  if grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 missing '$2'"
    FAIL=$((FAIL + 1))
  fi
}

# --- File existence ---
assert_file_exists "skills/codex/codex.md"
assert_file_exists "commands/codex.md"
assert_file_exists "tests/skill-triggering/prompts/codex.txt"

# --- Skill: spawning management flags ---
assert_contains "skills/codex/codex.md" "full-auto"
assert_contains "skills/codex/codex.md" "Working directory"
assert_contains "skills/codex/codex.md" "Capture final output"
assert_contains "skills/codex/codex.md" "read-only"

# --- Skill: dispatch types ---
assert_contains "skills/codex/codex.md" "codex exec"
assert_contains "skills/codex/codex.md" "codex review"

# --- Skill: isolation modes ---
assert_contains "skills/codex/codex.md" "worktree"
assert_contains "skills/codex/codex.md" "same-dir"

# --- Skill: effort/thinking translation ---
assert_contains "skills/codex/codex.md" "effort"
assert_contains "skills/codex/codex.md" "thinking"
assert_contains "skills/codex/codex.md" "model_reasoning_effort"
assert_contains "skills/codex/codex.md" "xhigh"

# --- Skill: model reference ---
assert_contains "skills/codex/codex.md" "gpt-5.4"

# --- Skill: passthrough flags ---
assert_contains "skills/codex/codex.md" "search"
assert_contains "skills/codex/codex.md" "ephemeral"
assert_contains "skills/codex/codex.md" "add-dir"

# --- Skill: background dispatch ---
assert_contains "skills/codex/codex.md" "run_in_background"

# --- Skill: curate/memory ---
assert_contains "skills/codex/codex.md" "lossless-claude"
assert_contains "skills/codex/codex.md" "lcm_store"

# --- Skill: preamble ---
assert_contains "skills/codex/codex.md" "prefs.json"

# --- Command content ---
assert_contains "commands/codex.md" "xgh:codex"
assert_contains "commands/codex.md" "/xgh-codex"
assert_contains "commands/codex.md" "exec"
assert_contains "commands/codex.md" "review"
assert_contains "commands/codex.md" "effort"
assert_contains "commands/codex.md" "thinking"

# --- Agents.yaml codex entry ---
assert_contains "config/agents.yaml" "codex:"
assert_contains "config/agents.yaml" "exec:"
assert_contains "config/agents.yaml" "review:"
assert_contains "config/agents.yaml" "full-auto"

# --- Help command references codex ---
assert_contains "commands/help.md" "/xgh-codex"

# --- Skill: curate observation write ---
assert_contains "skills/codex/codex.md" "model-profiles.yaml"
assert_contains "skills/codex/codex.md" "observation"
assert_contains "skills/codex/codex.md" "archetype"
assert_contains "skills/codex/codex.md" "accepted"

echo ""
echo "Codex dispatch test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
