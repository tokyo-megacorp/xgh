#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected '$2', got '$1'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS + 1)); else echo "FAIL: $1 missing"; FAIL=$((FAIL + 1)); fi
}

assert_dir_exists() {
  if [ -d "$1" ]; then PASS=$((PASS + 1)); else echo "FAIL: dir $1 missing"; FAIL=$((FAIL + 1)); fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS + 1)); else echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL + 1)); fi
}

assert_executable() {
  if [ -x "$1" ]; then PASS=$((PASS + 1)); else echo "FAIL: $1 not executable"; FAIL=$((FAIL + 1)); fi
}

# Setup temp project dir
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
cd "$TMPDIR"
git init --quiet

# Override HOME so global settings go into temp dir
export HOME="$TMPDIR"
mkdir -p "${HOME}/.claude"

# Run install in dry-run mode (skips brew/vllm-mlx, uses local files)
export XGH_DRY_RUN=1
export XGH_TEAM="test-team"
export XGH_CONTEXT_PATH=".xgh/context-tree"
export XGH_HOOKS_SCOPE="project"
export XGH_LOCAL_PACK="$(cd - >/dev/null && pwd)"

bash "${XGH_LOCAL_PACK}/install.sh"

# Verify .claude directory structure
assert_dir_exists ".claude"
assert_dir_exists ".claude/hooks"

# Plugin structure (checked in source pack, not install destination)
assert_file_exists "${XGH_LOCAL_PACK}/plugin/gemini-extension.json"
assert_file_exists "${XGH_LOCAL_PACK}/plugin/README.md"
assert_dir_exists  "${XGH_LOCAL_PACK}/plugin/skills"
assert_dir_exists  "${XGH_LOCAL_PACK}/plugin/commands"
assert_dir_exists  "${XGH_LOCAL_PACK}/plugin/hooks"
assert_dir_exists  "${XGH_LOCAL_PACK}/plugin/agents"
assert_file_exists "${XGH_LOCAL_PACK}/plugin/skills/init/init.md"
assert_file_exists "${XGH_LOCAL_PACK}/plugin/commands/init.md"
assert_file_exists "${XGH_LOCAL_PACK}/plugin/hooks/session-start.sh"
assert_file_exists "${XGH_LOCAL_PACK}/plugin/agents/collaboration-dispatcher.md"
assert_file_exists "${XGH_LOCAL_PACK}/plugin/agents/code-reviewer.md"
assert_contains    "${XGH_LOCAL_PACK}/plugin/gemini-extension.json" '"name": "xgh"'
assert_contains    "${XGH_LOCAL_PACK}/plugin/gemini-extension.json" '"version"'

# Verify MCP config (global: ~/.claude.json)
# lossless-claude registers its MCP during `lossless-claude install`, which is
# skipped in dry-run mode. We only assert the file exists (written by Claude CLI).
assert_file_exists "${HOME}/.claude.json"

# Verify hooks installed
assert_file_exists ".claude/hooks/xgh-session-start.sh"
assert_file_exists ".claude/hooks/xgh-prompt-submit.sh"
assert_executable ".claude/hooks/xgh-session-start.sh"
assert_executable ".claude/hooks/xgh-prompt-submit.sh"

# Verify settings
assert_file_exists ".claude/settings.local.json"
assert_contains ".claude/settings.local.json" "SessionStart"

# Verify context tree initialized
assert_dir_exists ".xgh/context-tree"
assert_file_exists ".xgh/context-tree/_manifest.json"
assert_contains ".xgh/context-tree/_manifest.json" "test-team"

# Verify CLAUDE.local.md
assert_file_exists "CLAUDE.local.md"
assert_contains "CLAUDE.local.md" "xgh"
assert_contains "CLAUDE.local.md" "test-team"

# Verify .gitignore updated
assert_file_exists ".gitignore"
assert_contains ".gitignore" ".xgh/local/"

# Plugin registration (after install)
PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"
assert_file_exists "$PLUGINS_JSON"
assert_contains    "$PLUGINS_JSON" '"xgh@ipedro"'
assert_contains    "$PLUGINS_JSON" '"scope": "user"'
assert_dir_exists  "${HOME}/.claude/plugins/cache/ipedro/xgh"
assert_file_exists "${HOME}/.claude/plugins/cache/ipedro/xgh/1.0.0/gemini-extension.json"
assert_dir_exists  "${HOME}/.claude/plugins/cache/ipedro/xgh/1.0.0/skills"
assert_dir_exists  "${HOME}/.claude/plugins/cache/ipedro/xgh/1.0.0/commands"

echo ""
echo "Install test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
