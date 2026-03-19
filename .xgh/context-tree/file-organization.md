---
title: File Organization & Naming Conventions
type: architecture
status: validated
importance: 85
tags: [architecture, conventions, file-structure]
keywords: [directories, naming, skills, commands, hooks, scripts, lib]
created: 2026-03-16
updated: 2026-03-16
---

# File Organization

## Directory Structure

| Directory | Purpose | Count |
|-----------|---------|-------|
| `skills/` | Skill definitions (one dir per skill) | 25 |
| `commands/` | Slash command definitions (`/xgh-*`) | 18 |
| `hooks/` | Claude Code hooks (session-start, prompt-submit) | 2 |
| `lib/` | Runtime utilities (config reader, usage tracker) | 2 |
| `scripts/` | Context tree CLI, search, scheduling, model management | ~12 |
| `config/` | Templates for YAML/JSON config | 4 |
| `agents/` | Multi-agent collaboration definitions | 1 |
| `templates/` | Output style guides | 1 |
| `tests/` | Bash test suites with assert helpers | ~20 |
| `docs/` | Plans, proposals, research | varies |

## File Types

- 91 `.md` files (skills, commands, docs)
- 43 `.sh` files (scripts, hooks, tests, lib)
- 12 `.yaml` files (config)
- 2 `.json` files (settings)
- 2 `.plist` files (launchd schedulers)
- 1 `.py` (BM25 search)

## Naming Conventions

- **Bash functions**: `lower_snake_case` with prefix matching file (e.g., `ct-search.sh` → `ct_search_run()`)
- **Constants/env vars**: `UPPER_SNAKE_CASE`
- **YAML keys**: `snake_case`
- **Skills**: directory name = skill name (e.g., `skills/retrieve/retrieve.md`)
- **Commands**: filename = command name (e.g., `commands/retrieve.md` → `/xgh-retrieve`)
