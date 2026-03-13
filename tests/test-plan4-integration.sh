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

assert_dir_exists() {
  if [ -d "$1" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: directory $1 does not exist"
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

echo "=== Plan 4: Team Collaboration Integration Test ==="

# ── Skill directories exist ───────────────────────────
echo ""
echo "--- Skill directories ---"
assert_dir_exists "skills/pr-context-bridge"
assert_dir_exists "skills/knowledge-handoff"
assert_dir_exists "skills/convention-guardian"
assert_dir_exists "skills/cross-team-pollinator"
assert_dir_exists "skills/subagent-pair-programming"
assert_dir_exists "skills/onboarding-accelerator"

# ── Skill files exist ─────────────────────────────────
echo ""
echo "--- Skill files ---"
assert_file_exists "skills/pr-context-bridge/pr-context-bridge.md"
assert_file_exists "skills/knowledge-handoff/knowledge-handoff.md"
assert_file_exists "skills/convention-guardian/convention-guardian.md"
assert_file_exists "skills/cross-team-pollinator/cross-team-pollinator.md"
assert_file_exists "skills/subagent-pair-programming/subagent-pair-programming.md"
assert_file_exists "skills/onboarding-accelerator/onboarding-accelerator.md"

# ── Command file exists ───────────────────────────────
echo ""
echo "--- Command file ---"
assert_file_exists "commands/collaborate.md"

# ── Agent file exists ─────────────────────────────────
echo ""
echo "--- Agent file ---"
assert_file_exists "agents/collaboration-dispatcher.md"

# ── All skills have Iron Law ──────────────────────────
echo ""
echo "--- Iron Law in all skills ---"
for skill in pr-context-bridge knowledge-handoff convention-guardian cross-team-pollinator subagent-pair-programming onboarding-accelerator; do
  assert_contains "skills/$skill/$skill.md" "Iron Law"
done

# ── All skills reference Cipher tools ─────────────────
echo ""
echo "--- Cipher tool references ---"
for skill in pr-context-bridge knowledge-handoff convention-guardian cross-team-pollinator subagent-pair-programming onboarding-accelerator; do
  assert_contains "skills/$skill/$skill.md" "cipher_memory_search"
done

# ── All skills have Composability section ─────────────
echo ""
echo "--- Composability sections ---"
for skill in pr-context-bridge knowledge-handoff convention-guardian cross-team-pollinator subagent-pair-programming onboarding-accelerator; do
  assert_contains "skills/$skill/$skill.md" "Composability"
done

# ── Command has workflow templates ────────────────────
echo ""
echo "--- Workflow templates in command ---"
assert_contains "commands/collaborate.md" "plan-review"
assert_contains "commands/collaborate.md" "parallel-impl"
assert_contains "commands/collaborate.md" "validation"
assert_contains "commands/collaborate.md" "security-review"

# ── Agent has dispatch loop ───────────────────────────
echo ""
echo "--- Agent dispatch loop ---"
assert_contains "agents/collaboration-dispatcher.md" "Dispatch Loop"
assert_contains "agents/collaboration-dispatcher.md" "Message Protocol"

# ── Cross-references between skills ───────────────────
echo ""
echo "--- Skill cross-references ---"
assert_contains "skills/pr-context-bridge/pr-context-bridge.md" "convention-guardian"
assert_contains "skills/pr-context-bridge/pr-context-bridge.md" "knowledge-handoff"
assert_contains "skills/knowledge-handoff/knowledge-handoff.md" "pr-context-bridge"
assert_contains "skills/knowledge-handoff/knowledge-handoff.md" "onboarding-accelerator"
assert_contains "skills/convention-guardian/convention-guardian.md" "cross-team-pollinator"
assert_contains "skills/cross-team-pollinator/cross-team-pollinator.md" "onboarding-accelerator"
assert_contains "skills/subagent-pair-programming/subagent-pair-programming.md" "convention-guardian"
assert_contains "skills/onboarding-accelerator/onboarding-accelerator.md" "convention-guardian"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
