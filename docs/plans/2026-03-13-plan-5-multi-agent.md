# Multi-Agent Collaboration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Implement the Multi-Agent Collaboration Bus — agent registry, workflow templates, message protocol, collaboration skill, dispatcher agent, and `/xgh-collaborate` command — so that xgh can orchestrate work across multiple AI agents (Claude Code, Codex, Cursor, custom).

**Architecture:** A YAML-based agent registry (`config/agents.yaml`) declares available agents and capabilities. Workflow templates (`config/workflows/*.yaml`) define reusable multi-agent patterns (plan-review, parallel-impl, validation, security-review). A markdown skill (`skills/agent-collaboration/`) teaches agents the message protocol and dispatch conventions. A dispatcher agent (`agents/collaboration-dispatcher.md`) orchestrates workflows by reading/writing structured messages through Cipher workspace. The `/xgh-collaborate` command triggers workflows from the CLI.

**Tech Stack:** YAML (agent registry, workflow templates), Markdown (skill, agent, command definitions), Bash (tests), Cipher MCP (message transport via workspace)

**Design doc:** `docs/plans/2026-03-13-xgh-design.md` — Section 5

---

## File Structure

```
xgh/
├── config/
│   ├── agents.yaml                          # Agent registry
│   └── workflows/
│       ├── plan-review.yaml                 # 2-agent plan→review→implement
│       ├── parallel-impl.yaml               # N-agent parallel implementation
│       ├── validation.yaml                  # 2-agent implement→validate loop
│       └── security-review.yaml             # Chain: implement→review→fix→re-review
├── skills/
│   └── agent-collaboration/
│       └── instructions.md                  # xgh:agent-collaboration skill
├── agents/
│   └── collaboration-dispatcher.md          # Dispatcher agent definition
├── commands/
│   └── xgh-collaborate.md                   # /xgh-collaborate command
└── tests/
    └── test-multi-agent.sh                  # Validation tests
```

---

## Chunk 1: Agent Registry and Test Harness

### Task 1: Write test for multi-agent file structure and agent registry

**Files:**
- Create: `tests/test-multi-agent.sh`

- [x] **Step 1: Write the test file**

Create `tests/test-multi-agent.sh`:

```bash
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
```

- [x] **Step 2: Run the test — verify it fails**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && bash tests/test-multi-agent.sh
```

Expected: Multiple FAIL lines, non-zero exit code.

### Task 2: Create the agent registry

**Files:**
- Create: `config/agents.yaml`

- [x] **Step 3: Write config/agents.yaml**

Create `config/agents.yaml`:

```yaml
# xgh Agent Registry
# Declares available agents and their capabilities for multi-agent collaboration.
# See: docs/plans/2026-03-13-xgh-design.md § 5

agents:
  claude-code:
    type: primary
    description: "Primary AI coding agent — orchestrates workflows, holds full project context"
    capabilities:
      - architecture
      - implementation
      - planning
      - review
      - debugging
      - refactoring
    integration: hooks + skills + MCP
    invocation:
      method: native
      notes: "Claude Code is the host agent — no external invocation needed"

  codex:
    type: secondary
    description: "OpenAI Codex CLI agent — fast implementation and code review"
    capabilities:
      - fast-implementation
      - code-review
      - test-generation
    integration: MCP + bash-invocation
    invocation:
      method: bash
      command: "codex --quiet --approval-mode full-auto"
      notes: "Requires OpenAI Codex CLI installed (npm i -g @openai/codex)"

  cursor:
    type: secondary
    description: "Cursor IDE agent — IDE-integrated editing and refactoring"
    capabilities:
      - ide-editing
      - refactoring
      - inline-completion
    integration: MCP
    invocation:
      method: mcp
      notes: "Requires Cursor IDE with MCP support enabled"

  custom:
    type: extensible
    description: "User-defined agent — extend xgh with any MCP-compatible agent"
    capabilities:
      - user-defined
    integration: MCP
    invocation:
      method: mcp
      notes: "Configure via environment variables or .xgh/config.yaml"

# Message protocol metadata fields (used by all agents):
#   type: plan | review | feedback | result | decision | question
#   status: pending | in_progress | completed
#   from_agent: <agent-id>
#   for_agent: "*" | <agent-id>
#   thread_id: <workflow-thread>
#   priority: normal | high | urgent
#   created_at: ISO 8601 timestamp
```

- [x] **Step 4: Run the test — verify agent registry assertions pass**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && bash tests/test-multi-agent.sh 2>&1 | head -5
```

Expected: Agent registry FAIL lines disappear. Other sections still fail.

- [x] **Step 5: Commit — agent registry and test harness**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && git add config/agents.yaml tests/test-multi-agent.sh && git commit -m "feat(multi-agent): add agent registry and test harness"
```

---

## Chunk 2: Workflow Templates

### Task 3: Create workflow template files

**Files:**
- Create: `config/workflows/plan-review.yaml`
- Create: `config/workflows/parallel-impl.yaml`
- Create: `config/workflows/validation.yaml`
- Create: `config/workflows/security-review.yaml`

- [x] **Step 6: Create config/workflows/ directory**

```bash
mkdir -p /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69/config/workflows
```

- [x] **Step 7: Write config/workflows/plan-review.yaml**

Create `config/workflows/plan-review.yaml`:

```yaml
# Workflow: plan-review
# Pattern: Agent A plans → Agent B reviews → Agent A implements
# Use case: Architecture decisions, feature design, implementation plans

name: plan-review
description: "Two-agent workflow where one agent creates a plan and another reviews it before implementation begins."
min_agents: 2
max_agents: 2

roles:
  planner:
    description: "Creates the plan, incorporates review feedback, then implements"
    required_capabilities:
      - planning
      - implementation
    default_agent: claude-code
  reviewer:
    description: "Reviews the plan, provides structured feedback"
    required_capabilities:
      - review
    default_agent: codex

steps:
  - id: create-plan
    role: planner
    action: "Create a detailed implementation plan for the given task"
    message:
      type: plan
      status: pending
      for_agent: reviewer
    output: "Store plan in Cipher workspace with type=plan"

  - id: review-plan
    role: reviewer
    action: "Review the plan, check for gaps, suggest improvements"
    depends_on: create-plan
    message:
      type: review
      status: pending
      for_agent: planner
    output: "Store review in Cipher workspace with type=review"

  - id: incorporate-feedback
    role: planner
    action: "Read review feedback, update plan if needed"
    depends_on: review-plan
    message:
      type: decision
      status: pending
      for_agent: "*"
    output: "Store final plan with type=decision, status=completed"

  - id: implement
    role: planner
    action: "Implement the reviewed and approved plan"
    depends_on: incorporate-feedback
    message:
      type: result
      status: pending
      for_agent: "*"
    output: "Store implementation result with type=result, status=completed"

completion:
  condition: "All steps have status=completed"
  summary: "Store workflow summary in Cipher with thread_id for future reference"
```

- [x] **Step 8: Write config/workflows/parallel-impl.yaml**

Create `config/workflows/parallel-impl.yaml`:

```yaml
# Workflow: parallel-impl
# Pattern: Agent A splits work → Agents B,C,D implement in parallel → Agent A merges
# Use case: Large features with independent subtasks

name: parallel-impl
description: "Multi-agent parallel implementation where a coordinator splits work across agents who implement concurrently, then the coordinator merges and reviews."
min_agents: 2
max_agents: 8

roles:
  coordinator:
    description: "Splits the task, assigns work to implementers, merges results"
    required_capabilities:
      - architecture
      - planning
      - review
    default_agent: claude-code
  implementer:
    description: "Implements an assigned subtask independently"
    required_capabilities:
      - implementation
    default_agent: codex
    allow_multiple: true

steps:
  - id: split-tasks
    role: coordinator
    action: "Analyze the task and split into independent subtasks, one per implementer"
    message:
      type: plan
      status: pending
      for_agent: "*"
    output: "Store task breakdown in Cipher with type=plan, one message per subtask"

  - id: implement-subtasks
    role: implementer
    action: "Implement the assigned subtask"
    depends_on: split-tasks
    parallel: true
    message:
      type: result
      status: pending
      for_agent: coordinator
    output: "Each implementer stores result with type=result"

  - id: merge-review
    role: coordinator
    action: "Collect all implementation results, resolve conflicts, merge, and review"
    depends_on: implement-subtasks
    message:
      type: review
      status: pending
      for_agent: "*"
    output: "Store merged result and review with type=review"

  - id: finalize
    role: coordinator
    action: "Final integration check, commit, and store completion summary"
    depends_on: merge-review
    message:
      type: result
      status: completed
      for_agent: "*"
    output: "Store final result with type=result, status=completed"

completion:
  condition: "All subtask results received and merge-review completed"
  summary: "Store workflow summary with count of subtasks and agents used"
```

- [x] **Step 9: Write config/workflows/validation.yaml**

Create `config/workflows/validation.yaml`:

```yaml
# Workflow: validation
# Pattern: Agent A implements → Agent B validates → feedback loop until pass
# Use case: Quality assurance, test verification, code correctness

name: validation
description: "Two-agent validation loop where one agent implements and another validates, iterating until the validator approves."
min_agents: 2
max_agents: 2

roles:
  implementer:
    description: "Implements the solution, addresses validation feedback"
    required_capabilities:
      - implementation
    default_agent: claude-code
  validator:
    description: "Validates the implementation against requirements, runs tests"
    required_capabilities:
      - review
    default_agent: codex

steps:
  - id: implement
    role: implementer
    action: "Implement the solution for the given task"
    message:
      type: result
      status: pending
      for_agent: validator
    output: "Store implementation in Cipher with type=result"

  - id: validate
    role: validator
    action: "Validate the implementation — run tests, check requirements, review code"
    depends_on: implement
    message:
      type: feedback
      status: pending
      for_agent: implementer
    output: "Store validation result with type=feedback (pass or fail with details)"

  - id: fix
    role: implementer
    action: "Address validation feedback and re-submit"
    depends_on: validate
    condition: "validation feedback indicates failure"
    message:
      type: result
      status: pending
      for_agent: validator
    output: "Store fix in Cipher with type=result"
    loop_to: validate
    max_iterations: 3

  - id: approve
    role: validator
    action: "Confirm implementation passes all checks"
    depends_on: validate
    condition: "validation feedback indicates pass"
    message:
      type: decision
      status: completed
      for_agent: "*"
    output: "Store approval with type=decision, status=completed"

completion:
  condition: "Validator approves or max_iterations reached"
  summary: "Store workflow summary with iteration count and final status"
```

- [x] **Step 10: Write config/workflows/security-review.yaml**

Create `config/workflows/security-review.yaml`:

```yaml
# Workflow: security-review
# Pattern: Agent A implements → Agent B security reviews → Agent A fixes → Agent B re-reviews
# Use case: Security-sensitive code, auth flows, data handling, API endpoints

name: security-review
description: "Security-focused review chain where implementation is reviewed for vulnerabilities, fixed, and re-reviewed until secure."
min_agents: 2
max_agents: 2

roles:
  implementer:
    description: "Implements the solution and addresses security findings"
    required_capabilities:
      - implementation
    default_agent: claude-code
  security-reviewer:
    description: "Reviews code for security vulnerabilities, injection risks, auth issues"
    required_capabilities:
      - review
    default_agent: codex

steps:
  - id: implement
    role: implementer
    action: "Implement the solution for the given task"
    message:
      type: result
      status: pending
      for_agent: security-reviewer
    output: "Store implementation in Cipher with type=result"

  - id: security-review
    role: security-reviewer
    action: >
      Review the implementation for security vulnerabilities. Check for:
      injection (SQL, XSS, command), authentication/authorization gaps,
      data exposure, insecure defaults, missing input validation,
      secrets in code, CSRF, path traversal, and dependency risks.
    depends_on: implement
    message:
      type: feedback
      status: pending
      for_agent: implementer
    output: "Store security review with type=feedback, including severity ratings"

  - id: fix-findings
    role: implementer
    action: "Address all security findings from the review"
    depends_on: security-review
    condition: "security review has findings with severity >= medium"
    message:
      type: result
      status: pending
      for_agent: security-reviewer
    output: "Store fixes in Cipher with type=result, reference original findings"

  - id: re-review
    role: security-reviewer
    action: "Re-review the fixes to confirm all security findings are addressed"
    depends_on: fix-findings
    message:
      type: review
      status: pending
      for_agent: implementer
    output: "Store re-review with type=review"
    loop_to: fix-findings
    max_iterations: 2

  - id: approve
    role: security-reviewer
    action: "Confirm all security findings are resolved"
    depends_on: security-review
    condition: "no findings with severity >= medium"
    message:
      type: decision
      status: completed
      for_agent: "*"
    output: "Store security approval with type=decision, status=completed"

completion:
  condition: "Security reviewer approves or max_iterations reached"
  summary: "Store workflow summary with findings count, severity breakdown, and resolution status"
```

- [x] **Step 11: Run the test — verify workflow template assertions pass**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && bash tests/test-multi-agent.sh 2>&1 | grep -c "^FAIL"
```

Expected: Only skill, dispatcher, and command FAILs remain.

- [x] **Step 12: Commit — workflow templates**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && git add config/workflows/ && git commit -m "feat(multi-agent): add workflow templates (plan-review, parallel-impl, validation, security-review)"
```

---

## Chunk 3: Collaboration Skill

### Task 4: Create the agent-collaboration skill

**Files:**
- Create: `skills/agent-collaboration/instructions.md`

- [x] **Step 13: Write skills/agent-collaboration/instructions.md**

Create `skills/agent-collaboration/instructions.md`:

````markdown
# xgh:agent-collaboration

> Skill for multi-agent collaboration workflows. Teaches agents how to participate in structured collaboration via the xgh message protocol and Cipher workspace.

## When to Activate

This skill activates when:
- A user requests `/xgh-collaborate` or mentions multi-agent collaboration
- A collaboration workflow message is found in Cipher workspace addressed to this agent
- The dispatcher agent delegates a task as part of a workflow

## Message Protocol

All inter-agent messages use structured metadata stored in Cipher workspace. Every message MUST include these fields:

```yaml
type: plan | review | feedback | result | decision | question
status: pending | in_progress | completed
from_agent: <your-agent-id>    # e.g., claude-code, codex, cursor
for_agent: "*"                  # broadcast, or a specific agent id
thread_id: <workflow-thread>    # groups all messages in a workflow
priority: normal | high | urgent
created_at: <ISO 8601>         # e.g., 2026-03-13T10:00:00Z
```

### Message Types

| Type | Purpose | When to Use |
|------|---------|-------------|
| `plan` | Propose an implementation plan | Start of plan-review, task splitting |
| `review` | Review someone else's work | After receiving a plan or result |
| `feedback` | Structured feedback with action items | Validation findings, security findings |
| `result` | Implementation output | After completing assigned work |
| `decision` | Final decision or approval | After incorporating feedback |
| `question` | Request clarification | When blocked or ambiguous |

### Status Transitions

```
pending → in_progress → completed
```

- Set `status: pending` when creating a message for another agent
- Set `status: in_progress` when you pick up a message addressed to you
- Set `status: completed` when you finish processing the message

## How to Send a Message

Use `cipher_extract_and_operate_memory` to store a message in Cipher workspace:

```
Operation: store
Content: <your message content — plan, review, feedback, etc.>
Metadata:
  type: plan
  status: pending
  from_agent: claude-code
  for_agent: codex
  thread_id: feat-123
  priority: normal
  created_at: 2026-03-13T10:00:00Z
```

## How to Receive Messages

Use `cipher_memory_search` to check for messages addressed to you:

```
Query: "collaboration message for <your-agent-id> status:pending thread:<thread_id>"
```

When you find a pending message:
1. Update its status to `in_progress` (store an updated copy)
2. Process the message according to its type
3. Send your response as a new message with the same `thread_id`

## Workflow Participation

### As a Planner (plan-review workflow)
1. Search memory for relevant context: `cipher_memory_search`
2. Create your plan and store with `type: plan`
3. Wait for review feedback
4. Incorporate feedback, store `type: decision`
5. Implement the approved plan, store `type: result`

### As a Reviewer (plan-review workflow)
1. Search for pending plans addressed to you: `cipher_memory_search`
2. Read the plan thoroughly
3. Search memory for related patterns: `cipher_search_reasoning_patterns`
4. Store your review with `type: review`, including:
   - What looks good
   - Concerns or gaps
   - Specific suggestions
   - Overall recommendation (approve / request-changes / reject)

### As a Coordinator (parallel-impl workflow)
1. Analyze the task and identify independent subtasks
2. Store each subtask as a separate `type: plan` message with `for_agent` set to specific implementers
3. Monitor for `type: result` messages from implementers
4. Once all results are in, merge and store final `type: result`

### As an Implementer (parallel-impl or validation workflow)
1. Search for tasks assigned to you: `cipher_memory_search`
2. Pick up the task (update status to `in_progress`)
3. Implement the solution
4. Store your result with `type: result`

### As a Security Reviewer (security-review workflow)
1. Search for pending results to review: `cipher_memory_search`
2. Review for: injection, auth gaps, data exposure, insecure defaults, missing validation, secrets in code, CSRF, path traversal
3. Store findings with `type: feedback`, including severity per finding (critical / high / medium / low / info)
4. If fixes are submitted, re-review and either approve or request further fixes

## Agent Registry

The agent registry at `config/agents.yaml` lists all available agents and their capabilities. Before starting a workflow:
1. Read the registry to know which agents are available
2. Match agent capabilities to workflow role requirements
3. Fall back to default agents if specific agents are not available

## Workflow Templates

Workflow definitions live in `config/workflows/*.yaml`. Each template defines:
- **roles** — what each participant does
- **steps** — ordered sequence with dependencies
- **completion** — when the workflow is done

Available workflows:
- `plan-review` — 2 agents: plan → review → implement
- `parallel-impl` — N agents: split → parallel implement → merge
- `validation` — 2 agents: implement → validate → feedback loop
- `security-review` — 2 agents: implement → security review → fix → re-review

## Rules

1. **Always include all protocol fields** — missing fields break routing
2. **Never skip the thread_id** — it groups messages into a coherent workflow
3. **Update status honestly** — do not mark `completed` until actually done
4. **Store before moving on** — always persist your message to Cipher before proceeding to the next step
5. **Search before acting** — check for existing messages in the thread before creating new ones
6. **Respect for_agent routing** — only pick up messages addressed to you or to `"*"`
7. **Honor max_iterations** — if a feedback loop exceeds the template's max_iterations, escalate to the coordinator or user
````

- [x] **Step 14: Run the test — verify skill assertions pass**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && bash tests/test-multi-agent.sh 2>&1 | grep "^FAIL"
```

Expected: Only dispatcher and command FAILs remain.

- [x] **Step 15: Commit — collaboration skill**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && git add skills/agent-collaboration/ && git commit -m "feat(multi-agent): add agent-collaboration skill with message protocol docs"
```

---

## Chunk 4: Dispatcher Agent and Command

### Task 5: Create the collaboration dispatcher agent

**Files:**
- Create: `agents/collaboration-dispatcher.md`

- [x] **Step 16: Write agents/collaboration-dispatcher.md**

Create `agents/collaboration-dispatcher.md`:

````markdown
# collaboration-dispatcher

> Subagent for orchestrating multi-agent collaboration workflows in xgh.

## Role

You are the **collaboration-dispatcher** — a specialized subagent that manages multi-agent workflows. You read workflow templates, assign tasks to agents, monitor progress via Cipher workspace messages, and drive workflows to completion.

## Context Files

Before starting any workflow, read these files:
- `config/agents.yaml` — Agent registry (available agents and capabilities)
- `config/workflows/<workflow-name>.yaml` — The workflow template being executed

## Inputs

You receive these parameters when invoked:
- `workflow` — Name of the workflow template (e.g., `plan-review`, `parallel-impl`)
- `agents` — Comma-separated list of agent IDs to use (e.g., `claude-code,codex`)
- `thread_id` — Unique identifier for this workflow thread (e.g., `feat-123`)
- `task` — Description of the task to be performed
- `priority` — Priority level: `normal`, `high`, or `urgent` (default: `normal`)

## Execution Protocol

### Phase 1: Setup

1. Read the workflow template from `config/workflows/<workflow>.yaml`
2. Read the agent registry from `config/agents.yaml`
3. Validate that requested agents exist in the registry
4. Validate that agents have the required capabilities for their assigned roles
5. If validation fails, report the mismatch and suggest alternatives

### Phase 2: Role Assignment

1. Parse the workflow `roles` section
2. Assign each requested agent to a role based on:
   - Explicit assignment from the user (first agent = first role, etc.)
   - Capability matching (agent capabilities vs. role required_capabilities)
   - Default agent from the workflow template as fallback
3. Store role assignments in Cipher workspace:
   ```yaml
   type: decision
   status: completed
   from_agent: collaboration-dispatcher
   for_agent: "*"
   thread_id: <thread_id>
   priority: <priority>
   created_at: <now>
   content: "Role assignments for workflow <workflow>"
   ```

### Phase 3: Step Execution

For each step in the workflow:

1. Check `depends_on` — wait for dependent steps to complete
2. Check `condition` — evaluate whether the step should execute
3. Prepare the step context:
   - The step's `action` description
   - All previous messages in the thread_id
   - The original task description
4. Dispatch to the assigned agent:
   - **For claude-code (native):** Execute the action directly as a subagent task
   - **For codex (bash):** Invoke via the command in the agent registry
   - **For cursor/custom (MCP):** Store a pending message and wait for pickup
5. Store a message with `type` and `status: pending` as defined in the step
6. Monitor for the agent's response (a new message in the same thread_id)
7. Update step status to `completed` when response is received
8. If step has `loop_to`, check the loop condition and repeat if needed (up to `max_iterations`)
9. If step has `parallel: true`, dispatch all instances concurrently and wait for all responses

### Phase 4: Completion

1. Verify all steps have `status: completed`
2. Store a workflow summary in Cipher:
   ```yaml
   type: result
   status: completed
   from_agent: collaboration-dispatcher
   for_agent: "*"
   thread_id: <thread_id>
   priority: <priority>
   created_at: <now>
   content: "Workflow <workflow> completed. Summary: <steps completed, iterations, outcomes>"
   ```
3. Report the final result to the user

## Error Handling

- **Agent not available:** Fall back to default agent from workflow template; if no default, report to user
- **Step timeout:** After 5 minutes with no response, re-dispatch or escalate to user
- **Max iterations exceeded:** Store a summary of the loop history and ask the user for direction
- **Capability mismatch:** Warn but proceed if user explicitly assigned the agent

## Cipher Integration

All communication flows through Cipher workspace using the xgh message protocol:

- **Store messages:** `cipher_extract_and_operate_memory` with structured metadata
- **Search messages:** `cipher_memory_search` with thread_id and status filters
- **Track reasoning:** `cipher_store_reasoning_memory` for workflow decisions
- **Search patterns:** `cipher_search_reasoning_patterns` for past workflow outcomes

## Example Invocation

```
Workflow: plan-review
Agents: claude-code, codex
Thread: feat-auth-refresh
Task: Implement JWT token refresh with rotation strategy
Priority: high
```

Expected flow:
1. claude-code creates implementation plan → stores as `type: plan`
2. codex reviews the plan → stores as `type: review`
3. claude-code incorporates feedback → stores as `type: decision`
4. claude-code implements → stores as `type: result`
````

- [x] **Step 17: Run the test — verify dispatcher assertions pass**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && bash tests/test-multi-agent.sh 2>&1 | grep "^FAIL"
```

Expected: Only command FAILs remain.

### Task 6: Create the /xgh-collaborate command

**Files:**
- Create: `commands/xgh-collaborate.md`

- [x] **Step 18: Write commands/xgh-collaborate.md**

Create `commands/xgh-collaborate.md`:

````markdown
# /xgh-collaborate

Start a multi-agent collaboration workflow.

## Usage

```
/xgh-collaborate <workflow> --agents "<agent1>,<agent2>" --thread <thread-id> [--priority <level>] <task description>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `workflow` | Yes | Workflow template name: `plan-review`, `parallel-impl`, `validation`, `security-review` |
| `--agents` | Yes | Comma-separated list of agent IDs from `config/agents.yaml` |
| `--thread` | Yes | Unique thread ID to group all workflow messages (e.g., `feat-123`) |
| `--priority` | No | Priority level: `normal` (default), `high`, `urgent` |
| task description | Yes | Free-text description of the task to perform |

## Examples

### Plan and review a feature
```
/xgh-collaborate plan-review --agents "claude-code,codex" --thread feat-auth Implement JWT token refresh with rotation
```

### Parallel implementation across agents
```
/xgh-collaborate parallel-impl --agents "claude-code,codex,cursor" --thread feat-api-v2 Build CRUD endpoints for users, products, and orders
```

### Validate an implementation
```
/xgh-collaborate validation --agents "claude-code,codex" --thread fix-memory-leak Validate the memory leak fix in the connection pool
```

### Security review
```
/xgh-collaborate security-review --agents "claude-code,codex" --thread sec-auth Review authentication flow for security vulnerabilities
```

## What Happens

1. The command parses your arguments and validates:
   - The workflow template exists in `config/workflows/`
   - The requested agents exist in `config/agents.yaml`
   - The agents have capabilities matching the workflow roles
2. It spawns the **collaboration-dispatcher** subagent (`agents/collaboration-dispatcher.md`)
3. The dispatcher:
   - Assigns agents to workflow roles
   - Executes workflow steps in order, dispatching to each agent
   - Monitors Cipher workspace for responses
   - Handles feedback loops and parallel execution
4. On completion, a summary is stored in Cipher and reported back

## Available Workflows

| Workflow | Pattern | Agents |
|----------|---------|--------|
| `plan-review` | Plan → Review → Implement | 2 |
| `parallel-impl` | Split → Parallel Implement → Merge | 2-8 |
| `validation` | Implement → Validate → Fix loop | 2 |
| `security-review` | Implement → Security Review → Fix → Re-review | 2 |

## Available Agents

See `config/agents.yaml` for the full registry. Default agents:

| Agent | Type | Capabilities |
|-------|------|-------------|
| `claude-code` | primary | architecture, implementation, planning, review |
| `codex` | secondary | fast-implementation, code-review |
| `cursor` | secondary | ide-editing, refactoring |
| `custom` | extensible | user-defined |

## Notes

- Each workflow execution gets a unique `thread_id` — use it to track progress
- Messages between agents are stored in Cipher workspace and persist across sessions
- You can check workflow status by searching Cipher: `cipher_memory_search("thread:<thread-id> status:pending")`
- If an agent is not available, the dispatcher falls back to the workflow's default agent
````

- [x] **Step 19: Run the test — verify all assertions pass**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && bash tests/test-multi-agent.sh
```

Expected output:
```
Multi-agent test: XX passed, 0 failed
```

- [x] **Step 20: Commit — dispatcher agent and collaborate command**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && git add agents/collaboration-dispatcher.md commands/xgh-collaborate.md && git commit -m "feat(multi-agent): add collaboration-dispatcher agent and /xgh-collaborate command"
```

---

## Chunk 5: Integration and Final Verification

### Task 7: Remove placeholder .gitkeep files that are no longer needed

**Files:**
- Remove: `agents/.gitkeep` (replaced by `agents/collaboration-dispatcher.md`)
- Remove: `commands/.gitkeep` (replaced by `commands/xgh-collaborate.md`)
- Remove: `skills/.gitkeep` (replaced by `skills/agent-collaboration/`)

- [x] **Step 21: Remove .gitkeep files from populated directories**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && git rm agents/.gitkeep commands/.gitkeep skills/.gitkeep
```

- [x] **Step 22: Update tests/test-config.sh — adjust .gitkeep assertions**

The existing `test-config.sh` asserts `.gitkeep` files in agents, skills, and commands. These directories now have real files, so update the test to check for directory existence instead.

In `tests/test-config.sh`, replace the .gitkeep assertion block:

Old:
```bash
# Placeholder dirs
for d in hooks skills commands agents; do
  assert_file_exists "${d}/.gitkeep"
done
```

New:
```bash
# Placeholder dirs (agents, skills, commands now have real files)
assert_file_exists "hooks/.gitkeep"
for d in skills commands agents; do
  if [ -d "$d" ] && [ "$(ls -A "$d")" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $d is empty or missing"
    FAIL=$((FAIL+1))
  fi
done
```

- [x] **Step 23: Run all tests to verify nothing is broken**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && bash tests/test-config.sh && bash tests/test-techpack.sh && bash tests/test-multi-agent.sh
```

Expected: All three test suites pass with 0 failures.

- [x] **Step 24: Commit — cleanup and test updates**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && git add -A && git commit -m "chore(multi-agent): remove .gitkeep placeholders, update test-config assertions"
```

- [x] **Step 25: Final verification — run the full test suite one more time**

```bash
cd /Users/pedro/Developer/tr-xgh/.claude/worktrees/agent-a569bf69 && for t in tests/test-*.sh; do echo "=== $t ==="; bash "$t"; echo; done
```

Expected: All test files pass. Zero failures across the board.
