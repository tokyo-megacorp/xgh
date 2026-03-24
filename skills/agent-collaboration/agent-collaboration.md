---
name: agent-collaboration
description: Multi-agent collaboration protocol for coordinating work across Planner, Reviewer, Coordinator, Implementer, and Security Reviewer roles using lossless-claude message threads
---

# xgh:agent-collaboration

> Skill for multi-agent collaboration workflows. Teaches agents how to participate in structured collaboration via the xgh message protocol and lossless-claude memory.

## When to Activate

This skill activates when:
- A user requests `/xgh-collaborate` or mentions multi-agent collaboration
- A collaboration workflow message is found in lossless-claude memory addressed to this agent
- The dispatcher agent delegates a task as part of a workflow

## Message Protocol

All inter-agent messages use structured metadata stored in lossless-claude memory. Every message MUST include these fields:

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

Use `lcm_store` to persist a message in lossless-claude memory:

```
lcm_store(
  "type: plan | status: pending | from: claude-code | for: codex | thread: feat-123 | priority: normal | created: 2026-03-13T10:00:00Z\n\n<your message content — plan, review, feedback, etc.>",
  ["workspace", "collaboration"]
)
```

## How to Receive Messages

Use `lcm_search` to check for messages addressed to you:

```
lcm_search("collaboration message for <your-agent-id> status:pending thread:<thread_id>")
```

When you find a pending message:
1. Update its status to `in_progress` (store an updated copy via `lcm_store`)
2. Process the message according to its type
3. Send your response as a new message with the same `thread_id`

## Workflow Participation

### As a Planner (plan-review workflow)
1. Search memory for relevant context: `lcm_search`
2. Create your plan and store with `type: plan`
3. Wait for review feedback
4. Incorporate feedback, store `type: decision`
5. Implement the approved plan, store `type: result`

### As a Reviewer (plan-review workflow)
1. Search for pending plans addressed to you: `lcm_search`
2. Read the plan thoroughly
3. Search memory for related patterns: `lcm_search` with tags `["reasoning"]`
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
1. Search for tasks assigned to you: `lcm_search`
2. Pick up the task (update status to `in_progress`)
3. Implement the solution
4. Store your result with `type: result`

### As a Security Reviewer (security-review workflow)
1. Search for pending results to review: `lcm_search`
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
4. **Store before moving on** — always persist your message to lossless-claude memory before proceeding to the next step
5. **Search before acting** — check for existing messages in the thread before creating new ones
6. **Respect for_agent routing** — only pick up messages addressed to you or to `"*"`
7. **Honor max_iterations** — if a feedback loop exceeds the template's max_iterations, escalate to the coordinator or user
