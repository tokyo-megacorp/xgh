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
