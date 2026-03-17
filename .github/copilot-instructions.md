# GitHub Copilot Instructions — xgh (eXtreme Go Horse)

> Full agent instructions are in [`AGENTS.md`](../AGENTS.md) at the repository root.
> Read it before making any changes to this repository.

## Summary

xgh is a **Model Context Server (MCS) tech pack** for Claude Code that provides persistent, team-shared memory via lossless-claude MCP + a git-committed context tree. The tech stack is Bash + YAML + Markdown (no compiled runtime).

## Key conventions

- All bash scripts: `#!/usr/bin/env bash` + `set -euo pipefail`
- Tests live in `tests/` and use the `assert_*` bash helper pattern
- Write a failing test before implementing any feature
- Implementation is tracked in `docs/plans/` with `- [ ]` / `- [x]` checkboxes
- Never commit API keys or secrets — use environment variables

## Run tests

```bash
bash tests/test-install.sh
bash tests/test-config.sh
bash tests/test-techpack.sh
bash tests/test-uninstall.sh
```

## Current status

Plan 1 (Foundation) is complete. Plans 2–6 are pending — see [`AGENTS.md`](../AGENTS.md#implementation-status) for the full roadmap.
