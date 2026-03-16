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
| `feedback` | Structured feedback with action items | Validation loops |
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
3. Wait for review feedback (`type: review` addressed to you)
4. Incorporate feedback and implement

### As a Reviewer (plan-review workflow)
1. Search for pending plans: `cipher_memory_search "thread:<id> type:plan status:pending"`
2. Review the plan against requirements and conventions
3. Store your review with `type: review`

### As a Worker (parallel-impl workflow)
1. Search for your assigned work item
2. Implement your subtask
3. Store the result with `type: result`

### As a Validator (validation workflow)
1. Search for completed implementations
2. Run tests and check conventions
3. Store feedback with `type: feedback`
4. Loop until implementation passes

## Tool Reference

| Tool | Usage |
|------|-------|
| `cipher_memory_search` | Find messages by thread, type, status, or agent |
| `cipher_extract_and_operate_memory` | Store new messages or update existing ones |
| `cipher_store_reasoning_memory` | Record workflow decisions for future learning |
| `cipher_search_reasoning_patterns` | Find past workflow patterns for the current situation |
