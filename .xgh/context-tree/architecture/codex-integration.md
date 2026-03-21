---
title: Codex CLI Integration Architecture
date: 2026-03-21
status: current
tags: [codex, multi-agent, context-injection, dispatch]
---

# Codex CLI Integration Architecture

Findings from live pairing session on 2026-03-21. Validated empirically via probe dispatches.

---

## How Codex Reads Context (the chain)

On every `codex exec -C <repo>` dispatch, Codex automatically loads context in this order:

```
~/.codex/superpowers/        ← global skill framework (using-superpowers)
~/.codex/skills/xgh/         ← global xgh skill (if installed)
<repo>/AGENTS.md             ← primary project instructions (auto-read from -C dir)
<repo>/.agents/skills/xgh/SKILL.md  ← repo-local skill (requires valid YAML frontmatter)
<repo>/.agents/skills/xgh/context.md ← live project state (via pointer in SKILL.md)
```

**AGENTS.md is the most important layer.** Codex reads it on every dispatch, quotes it verbatim, and follows its instructions. It is the Codex equivalent of a system prompt.

**Skills require YAML frontmatter.** Without `---` delimiters, Codex silently fails to load the skill. Error: `"failed to load skill: missing YAML frontmatter delimited by ---"`. Fix: always add frontmatter to `.agents/skills/*/SKILL.md`.

---

## What We Tested and Confirmed

| Mechanism | Works? | Notes |
|-----------|--------|-------|
| `AGENTS.md` auto-read via `-C <dir>` | ✅ Yes | Codex reads all sections, quotes instructions verbatim |
| `.agents/skills/xgh/SKILL.md` | ✅ Yes (after frontmatter fix) | Must have valid YAML frontmatter |
| `.agents/skills/xgh/context.md` | ✅ Yes | Read via pointer in SKILL.md |
| `~/.codex/instructions.md` | ❌ No | File exists but is NOT injected as system context |
| `~/.codex/AGENTS.md` | ❌ Not tested | Exists empty — unknown if auto-read globally |
| `codex exec -` (stdin) | ✅ Confirmed | Reads full prompt from stdin; enables dynamic context injection |
| `codex exec "<arg>"` (positional) | ✅ Yes | Standard path; escaping risk for large/complex prompts |

**Key discovery:** `~/.codex/instructions.md` is NOT a dynamic injection point — writing to it before dispatch does nothing. The real dynamic injection mechanism is `codex exec -` (stdin).

---

## Three-Layer Prompt Architecture (current design)

Every exec dispatch builds a prompt file with three layers and pipes it via stdin:

```bash
cat "$PROMPT_FILE" | codex exec - --full-auto --ephemeral -C "$WORK_DIR"
```

| Layer | Source | Content |
|-------|--------|---------|
| 1 | `.agents/skills/xgh/context.md` | Live project state: branch, key decisions, recent commits. Injected if file is < 1 day old. |
| 2 | Task description | The actual work to do, validated by Step 0 clarity gate. |
| 3 | Verification footer | Test command, scope constraints (`git diff --name-only`), commit message. |

Layer 1 is optional — if `context.md` is stale or missing, it's skipped silently. Run `/xgh-seed` to refresh.

---

## Session Mode Architecture

### Default: stateless (`--ephemeral`)

```bash
cat prompt.md | codex exec - --full-auto --ephemeral -C "$WORK_DIR"
```

- Fresh context every dispatch
- Parallel-safe: multiple worktrees, multiple simultaneous Codex processes
- No history contamination from prior failed attempts
- Deterministic: same input → same behavior

### Opt-in: stateful (`--session`)

```bash
# First dispatch — capture UUID from output header "session id: <UUID>"
cat prompt.md | codex exec - --full-auto -C "$WORK_DIR" 2>&1 | tee output.md
SESSION_ID=$(grep "^session id:" output.md | awk '{print $3}')

# Follow-up dispatches
codex resume "$SESSION_ID" "<follow-up prompt>" --full-auto -C "$WORK_DIR"
```

Use only for exploratory, inherently iterative work where accumulated context is the feature not a liability (e.g., multi-step debugging investigation).

**Session mode risks:**
- Context contamination from prior failed attempts
- Serializes execution (no parallelism)
- Non-deterministic results
- Stale state if session is hours/days old
- Opaque history — Claude cannot see what Codex "remembers"

---

## When to Dispatch vs Stay in Claude

| Dispatch to Codex | Stay in Claude |
|-------------------|---------------|
| Isolated implementation with a complete spec | Ambiguous task needing clarification |
| Parallel execution while Claude works on something else | Quick edit faster than ~30s startup |
| Code review of a known diff | Task requires mid-execution judgment calls |
| Numbered task list from a written plan | Multi-turn back-and-forth needed |
| Large diffs that would flood Claude's context | Tightly coupled to Claude's live session context |

**Rule of thumb:** If you'd need to interrupt Codex mid-run to ask a question, don't dispatch — clarify first, then dispatch.

---

## What Codex Knows By Default (no extra injection)

From the live probe (2026-03-21):

- Project name, tagline, tech stack (from AGENTS.md)
- All iron laws and development guidelines (from AGENTS.md)
- Default test command: `bash tests/test-config.sh` (from AGENTS.md + SKILL.md)
- Full test suite: `test-config.sh`, `test-skills.sh`, `test-commands.sh`
- Active branch and focus area (from context.md via SKILL.md)
- Key architectural decisions (from context.md)
- Global superpowers skill framework (from `~/.codex/superpowers/`)

---

## Pre-Dispatch Clarity Gate (codex-driver Step 0)

Before touching the CLI, five checks must pass — one clarifying question at a time:

| Check | Fail condition |
|-------|---------------|
| Specificity | No file/function/line references |
| Scope | No "modify only X" boundary stated |
| Success criteria | No test command or observable outcome |
| No mid-run decision | "Pick the better approach" in the task |
| Self-contained context | References Slack thread, Claude session, image |

**Do not soften or skip checks.** One clarifying question costs seconds. A Codex run on a bad prompt costs minutes and produces wrong output.

---

## Maintenance Notes

- `context.md` goes stale — run `/xgh-seed` before important dispatches
- `SKILL.md` must have YAML frontmatter or Codex silently skips it
- `AGENTS.md` is auto-generated — run `bash scripts/gen-agents-md.sh` after changing config YAML
- `~/.codex/config.toml` sets global defaults (model, effort, trust levels per project)
- Codex runs the global superpowers skill framework on every dispatch — this is expected behavior, not a bug
