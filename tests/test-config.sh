#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

# Presets exist
for p in local local-light openai anthropic cloud; do
  assert_file_exists "config/presets/${p}.yaml"
done

# All presets have required fields
for preset in config/presets/*.yaml; do
  assert_contains "$preset" "provider:"
  assert_contains "$preset" "model:"
done

# Local preset defaults
assert_contains "config/presets/local.yaml" "provider: openai"
assert_contains "config/presets/local.yaml" "model: mlx-community/Llama-3.2-3B-Instruct-4bit"
assert_contains "config/presets/local.yaml" "model: mlx-community/nomicai-modernbert-embed-base-8bit"
assert_contains "config/presets/local.yaml" "type: qdrant"

# Cloud presets require API keys
assert_contains "config/presets/openai.yaml" "OPENAI_API_KEY"
assert_contains "config/presets/anthropic.yaml" "ANTHROPIC_API_KEY"

# Placeholder dirs
for d in hooks skills commands agents; do
  assert_file_exists "${d}/.gitkeep"
done

# Settings files
assert_file_exists "config/settings.json"
assert_file_exists "config/hooks-settings.json"

# settings.json valid JSON
if python3 -c "import json; json.load(open('config/settings.json'))" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: settings.json invalid JSON"; FAIL=$((FAIL+1)); fi

# hooks-settings registers events
assert_contains "config/hooks-settings.json" "SessionStart"
assert_contains "config/hooks-settings.json" "UserPromptSubmit"
assert_contains "config/hooks-settings.json" "xgh-session-start.sh"
assert_contains "config/hooks-settings.json" "xgh-prompt-submit.sh"

# Template
assert_file_exists "templates/instructions.md"
assert_contains "templates/instructions.md" "xgh"
assert_contains "templates/instructions.md" "cipher_memory_search"
assert_contains "templates/instructions.md" "cipher_extract_and_operate_memory"
assert_contains "templates/instructions.md" "__TEAM_NAME__"
assert_contains "templates/instructions.md" "__CONTEXT_TREE_PATH__"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
