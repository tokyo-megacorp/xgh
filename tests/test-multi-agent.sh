#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_dir_exists() { if [ -d "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }
assert_valid_yaml() {
  if python3 -c "import yaml; yaml.safe_load(open('$1'))" 2>/dev/null; then
    PASS=$((PASS+1))
  elif python3 -c "import sys; open('$1').read()" 2>/dev/null; then
    # yaml module may not be available — just check file is readable
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 is not valid YAML"; FAIL=$((FAIL+1))
  fi
}

# ── Agent Registry ──────────────────────────────────────────
assert_file_exists "config/agents.yaml"
assert_contains "config/agents.yaml" "agents:"
assert_contains "config/agents.yaml" "claude-code:"
assert_contains "config/agents.yaml" "type: primary"
assert_contains "config/agents.yaml" "capabilities:"
assert_contains "config/agents.yaml" "integration:"
assert_contains "config/agents.yaml" "codex:"
assert_contains "config/agents.yaml" "cursor:"
assert_contains "config/agents.yaml" "custom:"
assert_contains "config/agents.yaml" "type: extensible"

# ── Workflow Templates ──────────────────────────────────────
assert_dir_exists "config/workflows"
assert_file_exists "config/workflows/plan-review.yaml"
assert_file_exists "config/workflows/parallel-impl.yaml"
assert_file_exists "config/workflows/validation.yaml"
assert_file_exists "config/workflows/security-review.yaml"

# Workflow required fields
for wf in config/workflows/*.yaml; do
  assert_contains "$wf" "name:"
  assert_contains "$wf" "description:"
  assert_contains "$wf" "roles:"
  assert_contains "$wf" "steps:"
done

# plan-review specifics
assert_contains "config/workflows/plan-review.yaml" "plan-review"
assert_contains "config/workflows/plan-review.yaml" "type: plan"
assert_contains "config/workflows/plan-review.yaml" "type: review"

# parallel-impl specifics
assert_contains "config/workflows/parallel-impl.yaml" "parallel-impl"
assert_contains "config/workflows/parallel-impl.yaml" "parallel: true"

# security-review specifics
assert_contains "config/workflows/security-review.yaml" "security-review"
assert_contains "config/workflows/security-review.yaml" "security"

# ── Skill ───────────────────────────────────────────────────
assert_dir_exists "skills/agent-collaboration"
assert_file_exists "skills/agent-collaboration/instructions.md"
assert_contains "skills/agent-collaboration/instructions.md" "Message Protocol"
assert_contains "skills/agent-collaboration/instructions.md" "type:"
assert_contains "skills/agent-collaboration/instructions.md" "status:"
assert_contains "skills/agent-collaboration/instructions.md" "from_agent:"
assert_contains "skills/agent-collaboration/instructions.md" "for_agent:"
assert_contains "skills/agent-collaboration/instructions.md" "thread_id:"
assert_contains "skills/agent-collaboration/instructions.md" "priority:"
assert_contains "skills/agent-collaboration/instructions.md" "cipher_memory_search"
assert_contains "skills/agent-collaboration/instructions.md" "cipher_extract_and_operate_memory"

# ── Dispatcher Agent ────────────────────────────────────────
assert_file_exists "agents/collaboration-dispatcher.md"
assert_contains "agents/collaboration-dispatcher.md" "collaboration-dispatcher"
assert_contains "agents/collaboration-dispatcher.md" "config/agents.yaml"
assert_contains "agents/collaboration-dispatcher.md" "config/workflows"
assert_contains "agents/collaboration-dispatcher.md" "cipher"
assert_contains "agents/collaboration-dispatcher.md" "thread_id"

# ── Command ─────────────────────────────────────────────────
assert_file_exists "commands/xgh-collaborate.md"
assert_contains "commands/xgh-collaborate.md" "xgh-collaborate"
assert_contains "commands/xgh-collaborate.md" "workflow"
assert_contains "commands/xgh-collaborate.md" "agents"
assert_contains "commands/xgh-collaborate.md" "thread"
assert_contains "commands/xgh-collaborate.md" "collaboration-dispatcher"

echo ""; echo "Multi-agent test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
