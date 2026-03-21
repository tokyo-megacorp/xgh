---
name: codex
description: "Dispatch tasks to Codex CLI for parallel implementation or code review"
usage: "/xgh-codex [exec|review] <prompt>"
aliases: ["cdx"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh codex`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh codex

Dispatch implementation tasks or code reviews to OpenAI's Codex CLI. Supports worktree-isolated parallel dispatch (Codex works in a branch while Claude Code continues) and same-directory sequential dispatch.

## Usage

```
/xgh-codex exec "Add unit tests for the auth module"
/xgh-codex review --base main
/xgh-codex exec --model gpt-5.4 "Refactor connection pooling"
/xgh-codex review --uncommitted
/xgh-codex exec --same-dir "Fix lint warnings in src/utils/"
/xgh-codex review --commit abc1234 "Focus on security"
```

## Behavior

1. Load the `xgh:codex` skill from `skills/codex/codex.md`
2. Check prerequisites: verify Codex CLI is installed
3. Parse dispatch parameters: type (exec/review), isolation mode, model, prompt
4. Setup workspace:
   - **Worktree mode** (default for exec): create isolated git worktree
   - **Same-dir mode** (default for review): use current directory
5. Dispatch to Codex CLI and collect results
6. For worktree mode: present integration options (merge, cherry-pick, keep, discard)

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `type` | No | `exec` (default) or `review` |
| `prompt` | Yes (exec) | Task description for Codex |
| `--model`, `-m` | No | Override model (e.g., `gpt-5.4-mini`, `gpt-5.1-codex-mini`). Omit to use CLI default. |
| `--effort`, `--thinking` | No | Reasoning effort: `low`, `medium`, `high`, `max`/`xhigh`. Both flags are aliases. |
| `--search` | No | Enable live web search for Codex |
| `[any codex flag]` | No | All unrecognized flags are forwarded to Codex CLI as-is |
| `--worktree` | No | Force worktree isolation (default for exec) |
| `--same-dir` | No | Force same-directory mode (default for review) |
| `--base` | No | Base branch for review (default: `main`) |
| `--uncommitted` | No | Review uncommitted changes |
| `--commit` | No | Review a specific commit SHA |

## Examples

```
# Dispatch implementation task (worktree mode, o4-mini)
/xgh-codex exec "Add unit tests for the auth module"

# Code review against main branch
/xgh-codex review --base main

# Complex task with frontier model
/xgh-codex exec --model gpt-5.4 "Refactor database connection pooling for thread safety"

# Review uncommitted changes
/xgh-codex review --uncommitted

# Max reasoning effort for a complex task
/xgh-codex exec --effort max "Refactor the auth middleware for thread safety"

# Same-dir mode for a quick fix
/xgh-codex exec --same-dir "Fix all ESLint warnings in src/utils/"

# Review a specific commit with custom instructions
/xgh-codex review --commit abc1234 "Focus on error handling and edge cases"
```

## Related Skills

- `xgh:codex` -- the dispatch workflow skill this command triggers
- `xgh:implement` -- full ticket implementation (can delegate subtasks to Codex)
- `xgh:collab` -- multi-agent collaboration (dispatches to Codex via this skill)
