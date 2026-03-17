# /xgh-collab

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh collab`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

Start a multi-agent collaboration workflow using lossless-claude workspace as the async communication bus.

## Usage

```
/xgh-collab <workflow> [options]
```

### Arguments

| Argument | Required | Description |
|---|---|---|
| `workflow` | Yes | One of: `plan-review`, `parallel-impl`, `validation`, `security-review`, or a custom workflow name |
| `--thread <id>` | No | Thread ID for grouping messages (default: auto-generated) |
| `--agents <list>` | No | Comma-separated agent names (default: workflow-specific) |
| `--task <description>` | Yes | Description of the work to be done |

### Examples

```bash
# Plan-review: one agent plans, another reviews
/xgh-collab plan-review --task "Add rate limiting to API endpoints"

# Parallel implementation: split work across agents
/xgh-collab parallel-impl --task "Implement user preferences CRUD" --agents "claude,codex"

# Validation: implement then validate
/xgh-collab validation --task "Refactor auth middleware"

# Security review chain
/xgh-collab security-review --task "Add file upload endpoint"
```

---

## Workflow Templates

### plan-review (2 agents)

```
Agent A → PLAN (store to thread) → Agent B → REVIEW (store feedback) → Agent A → IMPLEMENT
```

**Flow:**

1. **Agent A (Planner)** receives the task, queries memory for context, and writes a detailed plan:

```
Tool: lcm_store(text, ["workspace"])
Content:
  ## Plan: [task description]

  ### Context gathered:
  [relevant memory, conventions, past work]

  ### Approach:
  [detailed implementation plan]

  ### Files to change:
  [list with rationale]

  ### Risks:
  [identified risks]
Metadata: thread: [thread-id], type: plan, status: pending, from_agent: claude-code, for_agent: reviewer
```

2. **Agent B (Reviewer)** queries the thread for the plan and stores review feedback:

```
Tool: lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })
Query: "thread:[thread-id] type:plan status:pending"
```

```
Tool: lcm_store(text, ["workspace"])
Content:
  ## Review: [task description]

  ### Feedback:
  [specific feedback on the plan]

  ### Concerns:
  [risks identified, gaps found]

  ### Approved: [yes/no/with-changes]

  ### Required changes:
  [if applicable]
Metadata: thread: [thread-id], type: review, status: completed, from_agent: reviewer, for_agent: claude-code
```

3. **Agent A** reads feedback, adjusts plan, and implements.

### parallel-impl (N agents)

```
Agent A → SPLIT tasks → Agents B,C,D → IMPLEMENT (parallel) → Agent A → MERGE + REVIEW
```

**Flow:**

1. **Orchestrator** splits the task into independent units and stores each as a work item:

```
Tool: lcm_store(text, ["workspace"])
Content:
  Work item [N]: [description]
  Files: [file list]
  Dependencies: [none / depends on item M]
  Acceptance criteria: [criteria]
Metadata: thread: [thread-id], type: plan, subtype: work-item, item_number: [N], status: pending, from_agent: orchestrator, for_agent: [assigned agent]
```

2. **Worker agents** pick up their assigned items, implement, and store results.

3. **Orchestrator** reviews all results and merges.

### validation (2 agents)

```
Agent A → IMPLEMENT (store) → Agent B → VALIDATE (store) → feedback loop until pass
```

**Flow:**

1. **Agent A (Implementer)** writes the implementation and stores it.
2. **Agent B (Validator)** reviews the implementation against requirements, runs tests, checks conventions.
3. If validation fails, feedback loop continues until pass.

### security-review (chain)

```
Agent A → IMPLEMENT → Agent B → SECURITY_REVIEW → Agent A → FIX → Agent B → RE-REVIEW
```

**Flow:**

1. **Agent A** implements the feature.
2. **Agent B** performs security-focused review (input validation, auth, injection, data exposure).
3. **Agent A** fixes identified issues.
4. **Agent B** re-reviews fixes.

---

## Message Protocol

All inter-agent messages in the lossless-claude workspace follow this structure:

```yaml
type: plan | review | feedback | result | decision | question
status: pending | in_progress | completed
from_agent: [who wrote it]
for_agent: [who should read it, or "*" for broadcast]
thread: [groups related messages]
priority: normal | high | urgent
created_at: [ISO timestamp]
```

### Message Types

| Type | Description | Expected Response |
|---|---|---|
| `plan` | Detailed implementation plan | `review` or `feedback` |
| `review` | Review of a plan or implementation | `result` or `feedback` |
| `feedback` | Specific feedback on work | `result` (addressing feedback) |
| `result` | Completed work output | `review` or completion |
| `decision` | A decision that needs acknowledgment | `feedback` (agree/disagree) |
| `question` | A question needing an answer | `result` (the answer) |

---

## Dispatch Mechanism

The collaborate command dispatches the collaboration-dispatcher agent, which:

1. Creates the thread in lossless-claude workspace
2. Stores the initial task with workflow metadata
3. Dispatches subagents according to the workflow template
4. Monitors the thread for message progression
5. Reports completion back to the user

```
Tool: lcm_store(text, ["workspace"])
Content:
  Collaboration workflow started.
  Workflow: [template name]
  Task: [description]
  Agents: [list]
  Thread: [thread-id]
Metadata: thread: [thread-id], type: orchestration, status: in_progress, from_agent: orchestrator, for_agent: "*"
```

---

## Tool Reference

| Tool | Usage |
|---|---|
| `lcm_store(text, ["workspace"])` | Store plans, reviews, feedback, results, decisions, and questions to thread |
| `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })` | Query thread for messages, check for new responses |
| Extract 3-7 bullet summary → `lcm_store(summary, ["workspace"])` | Extract learnings from completed collaboration. Do not pass raw conversation content to lcm_store. |

## Composability

- Dispatches **subagent-pair-programming** (`skills/team/subagent-pair-programming/`) for TDD workflows within collaboration
- Feeds into **pr-context-bridge** when collaboration produces a PR
- Feeds into **knowledge-handoff** when collaboration completes
