# xgh Agent Collaboration

Use this skill for multi-agent orchestration with explicit handoffs.

## Message Protocol

Each handoff message protocol packet must contain:

1. `workflow`: template identifier
2. `step`: current stage
3. `owner`: responsible agent
4. `inputs`: required artifacts
5. `outputs`: produced artifacts
6. `status`: `pending|in-progress|done|blocked`

## Dispatch Rules

1. Select workflow template from `config/workflows/`.
2. Resolve role -> agent from `config/agents.yaml`.
3. Emit deterministic execution order.
4. Block completion until validation gate passes.
