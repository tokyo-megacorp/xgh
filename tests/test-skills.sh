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

assert_file_exists "skills/curate/curate.md"
assert_file_exists "skills/ask/ask.md"
assert_file_exists "docs/context-tree-rules.md"
assert_file_exists "skills/opencode/opencode.md"
assert_file_exists "skills/seed/seed.md"

assert_contains "skills/curate/curate.md" "frontmatter"
assert_contains "skills/curate/curate.md" "verification"
assert_contains "skills/ask/ask.md" "semantic"
assert_contains "docs/context-tree-rules.md" "archive"
assert_contains "skills/opencode/opencode.md" "xgh:opencode"
assert_contains "skills/opencode/opencode.md" "opencode run"
assert_contains "skills/seed/seed.md" "xgh:seed"
assert_contains "skills/seed/seed.md" "detect-agents"

# --- Dispatch router skill ---
assert_file_exists "skills/dispatch/dispatch.md"
assert_contains "skills/dispatch/dispatch.md" "xgh:dispatch"
assert_contains "skills/dispatch/dispatch.md" "model-profiles"
assert_contains "skills/dispatch/dispatch.md" "archetype"

# --- All dispatch skills have observation write ---
assert_contains "skills/codex/codex.md" "model-profiles.yaml"
assert_contains "skills/gemini/gemini.md" "model-profiles.yaml"
assert_contains "skills/opencode/opencode.md" "model-profiles.yaml"

echo ""
echo "Skills test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
