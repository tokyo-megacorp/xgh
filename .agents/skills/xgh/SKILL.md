---
name: xgh
description: xgh project context — conventions, active branch, key decisions, and dispatch commands
---

<!-- Managed by xgh — do not edit. Run /xgh-seed to refresh. -->

# xgh Context

Project context auto-injected by xgh. Read `context.md` in this directory for current project state.

## Agent conventions

- Read `AGENTS.md` at repo root for full project conventions, iron laws, and test commands.
- Before modifying any file, check if it is auto-generated (AGENTS.md is — run `bash scripts/gen-agents-md.sh` to regenerate).
- Default test command: `bash tests/test-config.sh`
- Commit format: `<type>: <description>` — e.g., `fix:`, `feat:`, `docs:`

## Dispatch commands available in Claude Code

- `/xgh-brief` — fresh session briefing
- `/xgh-seed` — refresh this context
- `/xgh-codex`, `/xgh-gemini`, `/xgh-opencode` — dispatch tasks to other AI agents
