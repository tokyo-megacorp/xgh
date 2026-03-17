#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then ((PASS++)) || true; else echo "FAIL: $1 missing '$2'"; ((FAIL++)) || true; fi; }
assert_file_exists() { if [ -f "$1" ]; then ((PASS++)) || true; else echo "FAIL: $1 missing"; ((FAIL++)) || true; fi; }

assert_file_exists "techpack.yaml"
assert_contains "techpack.yaml" "schemaVersion: 1"
assert_contains "techpack.yaml" "identifier: xgh"
assert_contains "techpack.yaml" "displayName:"
assert_contains "techpack.yaml" "description:"
assert_contains "techpack.yaml" "components:"
assert_contains "techpack.yaml" "id: vllm-mlx"
assert_contains "techpack.yaml" "id: lossless-claude"
assert_contains "techpack.yaml" "id: settings"
assert_contains "techpack.yaml" "id: gitignore"
assert_contains "techpack.yaml" "hookEvent: SessionStart"
assert_contains "techpack.yaml" "hookEvent: UserPromptSubmit"
assert_contains "techpack.yaml" "templates:"
assert_contains "techpack.yaml" "prompts:"
assert_contains "techpack.yaml" "TEAM_NAME"
assert_contains "techpack.yaml" "configureProject:"
assert_file_exists "scripts/configure.sh"

echo ""; echo "Techpack test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
