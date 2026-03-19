# xgh — Static Agent Instructions

> Loaded via `@` reference in CLAUDE.md. Zero runtime cost.

## Memory Protocol

Use lossless-claude (`lcm_*` tools) for persistent memory across sessions.

### When to Search

**Ask: "Will this task require understanding or modifying THIS codebase?"**

| Answer | Action |
|--------|--------|
| **YES** — need to understand/modify codebase | `lcm_search` FIRST |
| **NO** — general knowledge, meta tasks, follow-up | Skip search |

Search when: writing/editing code, understanding how something works, debugging, finding where something is, architectural decisions.

Skip when: general programming concepts, meta tasks (run tests, build, commit, create PR), simple clarifications.

Each distinct code task = new search, even in long conversations.

### When to Store

**Ask: "Did I learn or create something valuable for future work?"**

| Answer | Action |
|--------|--------|
| **YES** — wrote code, found patterns, made decisions | Extract 3-7 bullet summary → `lcm_store(summary, ["session"])` |
| **NO** — just answered a question, no new insights | Skip |

For complex reasoning/debugging → `lcm_store(text, ["reasoning"])`.

### Quick Reference

| Task Type | Search? | Store? |
|-----------|---------|--------|
| Add/create/implement feature | MUST | MUST |
| Fix/debug/resolve bug | MUST | MUST |
| Refactor/optimize code | MUST | MUST |
| "How does X work?" (codebase) | MUST | Only if new insights |
| General concept, meta task | NO | NO |

### Workflow

```
Code task → lcm_search FIRST → Work → lcm_store (summary) → Done
Non-code task → Just respond normally
```

## Scheduler

The scheduler registers background jobs automatically on session start:
- `/xgh-retrieve` every 5 minutes
- `/xgh-analyze` every 30 minutes
- `/xgh-deep-retrieve` every hour

Manage with `/xgh-schedule` (pause, resume, add, status).

## Key Commands

| Command | What it does |
|---------|-------------|
| `/xgh-brief` | Session briefing — what needs attention now |
| `/xgh-retrieve` | Pull context from Slack, Jira, GitHub |
| `/xgh-analyze` | Classify inbox, extract memories, generate digest |
| `/xgh-doctor` | Validate pipeline health |
| `/xgh-schedule` | Manage background jobs |
| `/xgh-track` | Add a new project to monitoring |
| `/xgh-implement` | Full ticket implementation with context |
| `/xgh-investigate` | Systematic debugging from a bug report |
