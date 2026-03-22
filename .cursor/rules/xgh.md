# Cursor Rules — xgh (eXtreme Go Horse)

Full agent instructions: see `AGENTS.md` at the repository root.

## Project type

Bash/YAML/Markdown MCS tech pack. No compiled artifacts. No npm/cargo/maven.

## Must-follow rules

- Start every task by reading `AGENTS.md`
- Write failing tests in `tests/` before implementing (bash `assert_*` pattern)
- All bash scripts: `#!/usr/bin/env bash` + `set -euo pipefail`
- Track progress with `- [x]` checkboxes in `docs/plans/`
- Never commit secrets — env vars only

## Install

```bash
claude plugin install xgh@extreme-go-horse
/xgh-init
```

## Test commands

```bash
bash tests/test-config.sh
```

## Implementation order

Plan 2 (Context Tree) → Plan 3 (Hooks & Skills) → Plan 4 (Team Collaboration) → Plan 5 (Multi-Agent) → Plan 6 (Workflow Skills)

Details and task checklists are in `docs/plans/`.
