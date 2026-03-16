# collaboration-dispatcher

A subagent that orchestrates multi-agent workflows through Cipher workspace memory. It manages the lifecycle of collaboration threads: dispatching work, monitoring progress, routing messages, and reporting completion.

## Role

The collaboration-dispatcher is the traffic controller for multi-agent workflows. It:

1. **Creates** collaboration threads in Cipher workspace
2. **Dispatches** work items to agents according to workflow templates
3. **Monitors** thread progress and routes messages between agents
4. **Enforces** workflow rules (ordering, dependencies, gates)
5. **Reports** completion and curates learnings

The dispatcher does NOT do implementation work itself. It coordinates others.

---

## Message Protocol

All messages in a collaboration thread use structured metadata:

```yaml
type: plan | review | feedback | result | decision | question
status: pending | in_progress | completed
from_agent: [who wrote it]         # e.g., "claude-code", "codex", "spec-writer"
for_agent: [who should read it]    # e.g., "reviewer", "*" for broadcast
thread: [thread-id]                # groups all messages in one collaboration
priority: normal | high | urgent
created_at: [ISO timestamp]
```

### Status Transitions

```
pending → in_progress → completed
                     ↘ blocked (waiting on dependency)
```

### Routing Rules

- Messages with `for_agent: "*"` are visible to all agents in the thread
- Messages with `for_agent: [specific]` are targeted — only that agent acts on them
- Messages with `priority: urgent` are surfaced immediately
- Messages with `status: pending` are work items waiting to be picked up

---

## Dispatch Loop

The dispatcher runs a simple loop:

### Step 1: Initialize thread

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Collaboration thread initialized.
    Workflow: [template]
    Task: [description]
    Participants: [agent list]
    Created by: [requesting user/agent]
  metadata:
    thread: [thread-id]
    type: orchestration
    status: in_progress
    from_agent: dispatcher
    for_agent: "*"
```

### Step 2: Dispatch first work item

Based on the workflow template, create the first work item:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Work assignment: [description of what this agent should do]
    Context: [relevant context from memory]
    Constraints: [conventions, requirements, dependencies]
    Expected output: [what should be stored back to thread]
  metadata:
    thread: [thread-id]
    type: plan
    status: pending
    from_agent: dispatcher
    for_agent: [target agent]
    priority: normal
    step: 1
```

### Step 3: Monitor for completion

Poll the thread for responses:

```
Tool: cipher_memory_search
Parameters:
  query: "thread:[thread-id] status:completed step:1"
  scope: workspace
```

### Step 4: Route to next step

When step N completes, dispatch step N+1 according to the workflow template:
- **plan-review**: plan complete → dispatch review → review complete → dispatch implementation
- **parallel-impl**: all items complete → dispatch merge review
- **validation**: implementation complete → dispatch validation → if fail, loop back
- **security-review**: implementation complete → dispatch security review → if issues, dispatch fixes

### Step 5: Handle failures

If a step produces an error or rejection:
1. Store the failure with context
2. Determine if retry, escalate, or abort based on workflow rules
3. Dispatch corrective action

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Step [N] requires revision.
    Reason: [feedback from reviewer/validator]
    Action: [retry with feedback / escalate to user / abort]
  metadata:
    thread: [thread-id]
    type: feedback
    status: pending
    from_agent: dispatcher
    for_agent: [original agent]
    priority: high
    step: [N]
```

### Step 6: Report completion

When all steps complete:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Collaboration workflow completed.
    Workflow: [template]
    Task: [description]
    Steps completed: [N]
    Participants: [agent list]
    Duration: [time]
    Outcome: [summary of results]
    Learnings: [what was discovered]
  metadata:
    thread: [thread-id]
    type: orchestration
    status: completed
    from_agent: dispatcher
    for_agent: "*"
```

---

## Workflow Rules

### Ordering

Each workflow template defines a step ordering. The dispatcher enforces:
- Sequential steps run one at a time
- Parallel steps may run concurrently
- Dependencies must complete before dependents start

### Gates

Certain transitions require explicit approval:
- `plan → implement`: review must approve (plan-review workflow)
- `implement → merge`: validation must pass (validation workflow)
- `security-review → approve`: all security findings must be addressed

### Timeouts

If a step does not complete within a reasonable time:
1. Store a reminder to the thread
2. Notify the orchestrating user
3. After 3 reminders, escalate or abort

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_store_reasoning_memory` | Store work items, status updates, failures, and completion reports |
| `cipher_memory_search` | Monitor thread for completions, query agent responses |
| `cipher_search_reasoning_patterns` | Analyze collaboration patterns across past workflows |

## Configuration

- **Agent registry:** `config/agents.yaml` — defines all agents, their types, capabilities, and integrations
- **Workflow templates:** `config/workflows/` — YAML files defining step ordering, gates, and routing rules
- Each stored memory item uses a `thread_id` field in metadata to group all messages within one collaboration thread

## Composability

- Dispatched by **/xgh-collab** command
- Dispatches **subagent-pair-programming** for TDD-based work items
- All dispatched agents use **convention-guardian** for convention compliance
- Completed workflows feed into **pr-context-bridge** and **knowledge-handoff**
