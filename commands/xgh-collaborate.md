# /xgh-collaborate

Start a multi-agent collaboration workflow using the xgh collaboration bus.

## Usage

```
/xgh-collaborate <workflow> --agents "<agent1>,<agent2>" --thread <thread-id> [--priority <level>] <task description>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `workflow` | Yes | Workflow template: `plan-review`, `parallel-impl`, `validation`, `security-review` |
| `--agents` | Yes | Comma-separated agent IDs from `config/agents.yaml` |
| `--thread` | Yes | Unique thread ID to group all workflow messages (e.g., `feat-123`) |
| `--priority` | No | Priority level: `normal` (default), `high`, `urgent` |
| task description | Yes | Free-text description of the task to perform |

## Examples

```bash
# Plan and review a feature
/xgh-collaborate plan-review --agents "claude-code" --thread feat-auth Implement JWT token refresh with rotation

# Parallel implementation across agents
/xgh-collaborate parallel-impl --agents "claude-code,cursor" --thread feat-api-v2 Build CRUD endpoints for users, products, and orders

# Validate an implementation
/xgh-collaborate validation --agents "claude-code" --thread fix-memory-leak Validate the memory leak fix in the connection pool

# Security review
/xgh-collaborate security-review --agents "claude-code" --thread sec-auth Review authentication flow for security vulnerabilities
```

## What Happens

1. The command parses arguments and validates:
   - The workflow template exists in `config/workflows/`
   - The requested agents exist in `config/agents.yaml`
   - The agents have capabilities matching the workflow roles

2. It spawns the **collaboration-dispatcher** subagent (`agents/collaboration-dispatcher.md`) with:
   - `workflow` — the template name
   - `agents` — the comma-separated agent list
   - `thread_id` — the unique thread identifier
   - `task` — the task description
   - `priority` — the priority level

3. The dispatcher orchestrates the workflow:
   - Assigns agents to roles defined in the workflow template
   - Drives each step in order, respecting `depends_on` and `condition` fields
   - Stores all inter-agent messages in MAGI workspace under the `thread_id`
   - Loops through feedback cycles until completion conditions are met

4. Reports workflow progress and final status to the user.

## Workflow Templates

| Template | Roles | Pattern |
|----------|-------|---------|
| `plan-review` | planner, reviewer | Plan → Review → Implement |
| `parallel-impl` | orchestrator, implementers | Split → Parallel Implement → Merge |
| `validation` | implementer, validator | Implement → Validate → Loop |
| `security-review` | implementer, security-reviewer | Implement → Review → Fix → Re-review |

## Message Protocol

All inter-agent messages use the xgh message protocol stored in MAGI workspace. See `skills/collab/collab.md` for full protocol details.

## Dispatcher Agent

The collaboration-dispatcher agent (`agents/collaboration-dispatcher.md`) manages the full workflow lifecycle — reading templates, assigning roles, dispatching tasks, and monitoring progress via MAGI workspace messages.
