# /xgh-collaborate

Execute a configured multi-agent workflow.

## Usage

`/xgh-collaborate <workflow> [context]`

## Steps

1. Validate workflow from `config/workflows/`.
2. Resolve participating agents from `config/agents.yaml`.
3. Call collaboration dispatcher with role mapping.
4. Track progress and return artifacts.

## Example

`/xgh-collaborate plan-review "Design context tree archival strategy"`
