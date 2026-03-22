---
name: xgh:collab
description: "This skill should be used when the user runs /xgh-collab or asks for multi-agent collaboration workflows. Teaches agents how to participate in structured collaboration via the xgh message protocol and lossless-claude workspace — handles message routing, coordination between agents, and workflow completion."
---

## Preamble — Execution mode

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('collab')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **collab** in background (returns summary when done) or interactive? [b/i, default: i]"
- If "b": "Check in with a quick question before starting, or fire-and-forget? [c/f, default: c]"

**Step P3 — Write preference:**
```bash
python3 -c "
import json, os, sys
mode, autonomy = sys.argv[1], sys.argv[2]
path = os.path.expanduser('~/.xgh/prefs.json')
os.makedirs(os.path.dirname(path), exist_ok=True)
try: p = json.load(open(path))
except: p = {}
p.setdefault('skill_mode', {})
entry = {'mode': mode} if mode == 'interactive' else {'mode': mode, 'autonomy': autonomy}
p['skill_mode']['collab'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` → use background mode
- contains `--interactive` or `--fg` → use interactive mode
- contains `--checkin` → use check-in autonomy
- contains `--auto` → use fire-and-forget autonomy
- contains `--reset` → run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('collab',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** → proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context: user's request verbatim, current branch (`git branch --show-current`), recent log (`git log --oneline -5`), any relevant file paths mentioned.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply: "Collab running in background — I'll post findings when done."
5. When agent completes: post a ≤5-bullet summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions).
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "Collab running in background — I'll post findings when done."
4. When agent completes: post a ≤5-bullet summary.

---


# xgh:collab

> Skill for multi-agent collaboration workflows. Teaches agents how to participate in structured collaboration via the xgh message protocol and lossless-claude workspace.

## When to Activate

This skill activates when:
- A user requests `/xgh-collab` or mentions multi-agent collaboration
- A collaboration workflow message is found in lossless-claude workspace addressed to this agent
- The dispatcher agent delegates a task as part of a workflow

## Message Protocol

All inter-agent messages use structured metadata stored in lossless-claude workspace. Every message MUST include these fields:

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

Use `lcm_store(text, ["workspace"])` to store a message in lossless-claude workspace:

```
Content: <your message content — plan, review, feedback, etc.>
Tags: ["workspace"]
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

Use `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })` to check for messages addressed to you:

```
Query: "collaboration message for <your-agent-id> status:pending thread:<thread_id>"
```

When you find a pending message:
1. Update its status to `in_progress` (store an updated copy)
2. Process the message according to its type
3. Send your response as a new message with the same `thread_id`

## Workflow Participation

### As a Planner (plan-review workflow)
1. Search memory for relevant context: `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })`
2. Create your plan and store with `type: plan`
3. Wait for review feedback
4. Incorporate feedback, store `type: decision`
5. Implement the approved plan, store `type: result`

### As a Reviewer (plan-review workflow)
1. Search for pending plans addressed to you: `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })`
2. Read the plan thoroughly
3. Search memory for related patterns: `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })`
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
1. Search for tasks assigned to you: `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })`
2. Pick up the task (update status to `in_progress`)
3. Implement the solution
4. Store your result with `type: result`

### As a Security Reviewer (security-review workflow)
1. Search for pending results to review: `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })`
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

## Workflow Completion

When a collaboration workflow reaches its completion state (all steps done, final result stored):

Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the
summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store.
Use tags: ["workspace"]

Content to capture: decisions made, patterns established, feedback incorporated, final outcome.

## Rules

1. **Always include all protocol fields** — missing fields break routing
2. **Never skip the thread_id** — it groups messages into a coherent workflow
3. **Update status honestly** — do not mark `completed` until actually done
4. **Store before moving on** — always persist your message to lossless-claude before proceeding to the next step
5. **Search before acting** — check for existing messages in the thread before creating new ones
6. **Respect for_agent routing** — only pick up messages addressed to you or to `"*"`
7. **Honor max_iterations** — if a feedback loop exceeds the template's max_iterations, escalate to the coordinator or user
