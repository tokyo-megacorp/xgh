#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 does not exist"
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 does not contain '$2'"
    FAIL=$((FAIL+1))
  fi
}

assert_section() {
  if grep -q "^## $2" "$1" 2>/dev/null || grep -q "^### $2" "$1" 2>/dev/null; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 missing section '$2'"
    FAIL=$((FAIL+1))
  fi
}

echo "=== Team Collaboration Skills Tests ==="

# ── pr-context-bridge ──────────────────────────────────
echo ""
echo "--- pr-context-bridge ---"
SKILL="skills/pr-context-bridge/pr-context-bridge.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_contains "$SKILL" "Rationalization Table"
assert_section "$SKILL" "Author Flow"
assert_section "$SKILL" "Reviewer Flow"
assert_contains "$SKILL" "cipher_store_reasoning_memory"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "thread"
assert_contains "$SKILL" "type: context"
assert_contains "$SKILL" "tradeoff"

# ── knowledge-handoff ──────────────────────────────────
echo ""
echo "--- knowledge-handoff ---"
SKILL="skills/knowledge-handoff/knowledge-handoff.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_contains "$SKILL" "Rationalization Table"
assert_section "$SKILL" "Handoff Summary Structure"
assert_section "$SKILL" "Trigger"
assert_contains "$SKILL" "cipher_extract_and_operate_memory"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "scope: handoff"
assert_contains "$SKILL" "gotcha"
assert_contains "$SKILL" "pattern"

# ── convention-guardian ────────────────────────────────
echo ""
echo "--- convention-guardian ---"
SKILL="skills/convention-guardian/convention-guardian.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_contains "$SKILL" "Rationalization Table"
assert_section "$SKILL" "Convention Storage Format"
assert_section "$SKILL" "Query Process"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "type: convention"
assert_contains "$SKILL" "scope: team"
assert_contains "$SKILL" "maturity: core"
assert_contains "$SKILL" "history"

# ── cross-team-pollinator ─────────────────────────────
echo ""
echo "--- cross-team-pollinator ---"
SKILL="skills/cross-team-pollinator/cross-team-pollinator.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_section "$SKILL" "Promotion Rules"
assert_section "$SKILL" "Query Merging"
assert_contains "$SKILL" "_shared/"
assert_contains "$SKILL" "scope: org"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "cipher_store_reasoning_memory"

# ── subagent-pair-programming ─────────────────────────
echo ""
echo "--- subagent-pair-programming ---"
SKILL="skills/subagent-pair-programming/subagent-pair-programming.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_contains "$SKILL" "Rationalization Table"
assert_section "$SKILL" "Spec Writer"
assert_section "$SKILL" "Implementer"
assert_section "$SKILL" "Orchestrator"
assert_contains "$SKILL" "cipher_store_reasoning_memory"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "thread"
assert_contains "$SKILL" "type: test-spec"
assert_contains "$SKILL" "status: RED"
assert_contains "$SKILL" "status: GREEN"

# ── onboarding-accelerator ────────────────────────────
echo ""
echo "--- onboarding-accelerator ---"
SKILL="skills/onboarding-accelerator/onboarding-accelerator.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_section "$SKILL" "Knowledge Categories"
assert_section "$SKILL" "Onboarding Session Flow"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "architecture"
assert_contains "$SKILL" "convention"
assert_contains "$SKILL" "gotcha"
assert_contains "$SKILL" "incident"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
