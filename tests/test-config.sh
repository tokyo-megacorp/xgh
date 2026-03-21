#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

# Plugin subdirs (agents, skills, commands, hooks live at root)
assert_file_exists "hooks/.gitkeep"
for d in skills commands agents; do
  if [ -d "$d" ] && [ "$(ls -A "$d")" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $d is empty or missing"
    FAIL=$((FAIL+1))
  fi
done


# --- agents.yaml: opencode entry ---
assert_contains "config/agents.yaml" "opencode:"
assert_contains "config/agents.yaml" "opencode run"
assert_contains "config/agents.yaml" "auto_detect: opencode"

# --- agents.yaml: registry fields on codex + gemini ---
assert_contains "config/agents.yaml" "skill_dir:"
assert_contains "config/agents.yaml" "rules_file:"
assert_contains "config/agents.yaml" "auto_detect:"
assert_contains "config/agents.yaml" "auto_detect: codex"
assert_contains "config/agents.yaml" "auto_detect: gemini"

assert_file_exists "config/project.yaml"
assert_contains "config/project.yaml" "name: xgh"
assert_contains "config/project.yaml" "xgh: Claude on the fastlane"
assert_contains "config/project.yaml" "tech_stack:"
assert_contains "config/project.yaml" "install:"
assert_contains "config/project.yaml" "key_design_decisions:"
assert_contains "config/project.yaml" "lossless-claude"
assert_contains "config/project.yaml" "BM25"
assert_contains "config/project.yaml" "vllm-mlx"

assert_file_exists "config/team.yaml"
assert_contains "config/team.yaml" "conventions:"
assert_contains "config/team.yaml" "iron_laws:"
assert_contains "config/team.yaml" "pitfalls:"
assert_contains "config/team.yaml" "Never skip the test"
assert_contains "config/team.yaml" "lower_snake_case"

assert_file_exists "config/workflow.yaml"
assert_contains "config/workflow.yaml" "phases:"
assert_contains "config/workflow.yaml" "defaults:"
assert_contains "config/workflow.yaml" "test_commands:"
assert_contains "config/workflow.yaml" "superpowers_table:"
assert_contains "config/workflow.yaml" "feat/, fix/, docs/"

assert_file_exists "config/triggers.yaml"
assert_contains "config/triggers.yaml" "triggers:"
assert_contains "config/triggers.yaml" "installed_by: xgh"
assert_contains "config/triggers.yaml" "pr-opened"
assert_contains "config/triggers.yaml" "digest-ready"
assert_contains "config/triggers.yaml" "security-alert"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
