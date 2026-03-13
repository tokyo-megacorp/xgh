# xgh — eXtreme Go Horse 🐴🤖

> **Context-aware AI coding conventions powered by [Cipher](https://github.com/campfirein/cipher) memory and a living context tree.**
> Persistent team knowledge that grows with every session — for productive engineering work, solo or within teams.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Plan 1](https://img.shields.io/badge/Plan%201%20Foundation-complete-brightgreen)](#implementation-roadmap)
[![Plans 2–6](https://img.shields.io/badge/Plans%202–6-in%20progress-yellow)](#implementation-roadmap)

---

## The Problem

AI coding agents (Claude Code, Cursor, Codex, etc.) start every session with **zero memory**. Conventions, past decisions, architectural patterns, and hard-won bug fixes — all lost when the session ends. Teams repeat the same mistakes, re-explain the same context, and diverge on patterns that should be shared.

xgh fixes this.

---

## What xgh Does

xgh installs a **persistent memory layer** into any project in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

After installation:

- Every AI session **starts** with your team's top conventions automatically injected
- Every prompt **surfaces** relevant past decisions before the agent writes code
- Every session **ends** with new learnings captured and stored for all future agents
- All knowledge is **git-committed** as human-readable markdown — reviewable in PRs, shareable without shared infrastructure

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      xgh MCS Tech Pack                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────────┐ │
│  │ Claude Code  │    │ Other Agents │    │  xgh CLI      │ │
│  │ (hooks +     │    │ (Cursor,     │    │  (skills +    │ │
│  │  skills)     │    │  Codex, etc) │    │  commands)    │ │
│  └──────┬───────┘    └──────┬───────┘    └──────┬────────┘ │
│         │                   │                   │          │
│         ▼                   ▼                   ▼          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Cipher MCP Server                      │   │
│  │  memory_search · extract_and_operate_memory         │   │
│  │  workspace_search · workspace_store                 │   │
│  │  knowledge_graph · reasoning_traces                 │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                  │
│         ┌───────────────┼───────────────┐                  │
│         ▼               ▼               ▼                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │  Vector DB │  │  SQLite    │  │  LLM + Emb │           │
│  │  (BYOP)   │  │ (sessions) │  │  (BYOP)    │           │
│  │ qdrant /  │  └────────────┘  │ ollama /   │           │
│  │ in-memory │                  │ openai /   │           │
│  └────────────┘                  │ anthropic  │           │
│                                  └────────────┘           │
│                         │                                  │
│                         ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         .xgh/context-tree/  (git-committed)         │   │
│  │  ├── domain/ → topic/ → subtopic/                   │   │
│  │  ├── YAML frontmatter (importance, maturity)        │   │
│  │  ├── _index.md (compressed summaries)               │   │
│  │  └── _manifest.json (registry)                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Dual-Engine Search

| Engine | Purpose | Storage | Search method |
|--------|---------|---------|---------------|
| **Cipher** | Semantic memory, reasoning traces | Qdrant vectors + SQLite | Vector similarity |
| **Context Tree** | Human-readable knowledge, git-shareable | `.xgh/context-tree/*.md` | BM25 keyword + frontmatter scoring |

Results are merged: `score = (0.5 × cipher_similarity + 0.3 × bm25 + 0.1 × importance + 0.1 × recency) × maturityBoost`

---

## Quick Start

### Prerequisites

- macOS or Linux
- Bash 5+
- Git

Everything else (Homebrew, Ollama, Qdrant, Node.js for Cipher) is installed automatically.

### Install with default preset (fully local, free)

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

### Install with a preset

```bash
# OpenAI (fastest, ~$0.01/session)
XGH_PRESET=openai XGH_TEAM=my-team \
  curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash

# Anthropic
XGH_PRESET=anthropic XGH_TEAM=my-team \
  curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash

# Local (no API keys, no cost)
XGH_PRESET=local XGH_TEAM=my-team \
  curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

### Custom team name and context tree path

```bash
XGH_TEAM=acme-frontend XGH_CONTEXT_PATH=.xgh/context-tree \
  curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/uninstall.sh | bash
```

---

## BYOP — Bring Your Own Provider

xgh is **provider-agnostic**. Choose the preset that matches your infrastructure:

| Preset | LLM | Embeddings | Vector Store | Cost |
|--------|-----|-----------|-------------|------|
| `local` *(default)* | Ollama llama3.2:3b | Ollama nomic-embed-text | Qdrant (local) | Free |
| `local-light` | Ollama llama3.2:3b | Ollama nomic-embed-text | In-memory | Free, no persistence |
| `openai` | GPT-4o-mini | text-embedding-3-small | Qdrant (local) | ~$0.01/session |
| `anthropic` | Claude Haiku | Ollama nomic-embed-text | Qdrant (local) | ~$0.01/session |
| `cloud` | OpenRouter (configurable) | OpenAI embeddings | Qdrant Cloud | ~$0.02/session |

Preset files are in `config/presets/`. You can add custom presets or override individual fields with environment variables.

---

## What Gets Installed

```
your-project/
├── .claude/
│   ├── .mcp.json               # Cipher MCP server configuration
│   ├── settings.local.json     # Claude Code permissions + hook registrations
│   ├── hooks/
│   │   ├── xgh-session-start.sh   # Context injection on session start
│   │   └── xgh-prompt-submit.sh   # Decision table on every prompt
│   ├── skills/
│   │   └── xgh-mcp-setup/         # Interactive MCP configuration skill
│   └── commands/
│       └── xgh-setup.md           # /xgh-setup slash command
├── CLAUDE.local.md             # Agent instructions with your team config
└── .xgh/
    └── context-tree/
        └── _manifest.json      # Knowledge registry (grows over time)
```

---

## Slash Commands

After installation, these commands are available in Claude Code:

| Command | Description |
|---------|-------------|
| `/xgh-setup` | Interactive MCP configuration wizard |
| `/xgh query <question>` | Search memory + context tree *(Plan 3)* |
| `/xgh curate <knowledge>` | Store knowledge in Cipher + sync to context tree *(Plan 3)* |
| `/xgh status` | Memory stats, context tree health, agent registry *(Plan 3)* |
| `/xgh collaborate <workflow>` | Start multi-agent workflow *(Plan 5)* |

---

## Context Tree

Knowledge is stored as structured markdown with YAML frontmatter:

```yaml
---
title: JWT Token Refresh Strategy
tags: [auth, jwt, security]
importance: 78          # 0-100, grows with usage
maturity: validated     # draft → validated (≥65) → core (≥85)
---

## Raw Concept
Refresh tokens rotate on every use with a 7-day absolute expiry.

## Narrative
We chose token rotation over sliding-window expiry to limit the
blast radius of a stolen token...
```

**Maturity levels:**

| Level | Importance threshold | Effect |
|-------|---------------------|--------|
| `draft` | < 65 | Normal weight in search results |
| `validated` | ≥ 65 | Included in session injection |
| `core` | ≥ 85 | ×1.15 score boost, always injected on session start |

---

## The Self-Learning Loop

xgh enforces one iron law:

> **Every coding session must query memory before writing code and curate learnings before ending.**

| Hook / Trigger | What happens |
|----------------|-------------|
| Session start | Top-5 core/validated knowledge files are injected as context |
| Every prompt | Decision table guides the agent to query first, curate after |
| Significant work completed | `cipher_extract_and_operate_memory` captures learnings |
| Architectural decision made | `cipher_store_reasoning_memory` records the reasoning chain |

---

## Multi-Agent Support

xgh's Cipher workspace acts as a **message bus** between agents. Any MCP-compatible agent can participate:

- **Claude Code** — primary agent (hooks + skills + MCP)
- **Cursor** — IDE editing, refactoring (MCP)
- **Codex** — fast implementation, code review (MCP + bash)
- **Custom agents** — user-defined capabilities (MCP)

Workflow templates for multi-agent patterns (`plan-review`, `parallel-impl`, `validation`, `security-review`) are implemented in Plan 5.

---

## Implementation Roadmap

The xgh development follows a 6-plan design-first roadmap. Each plan has a detailed implementation document in `docs/plans/` with task checklists.

### Progress Overview

```
Overall: ██░░░░░░░░░░  17% (1 of 6 plans complete)
```

---

### Plan 1 — Foundation ✅ Complete

> Scaffold, BYOP config system, one-liner installer

**Delivered:**
- [x] `techpack.yaml` — MCS tech pack manifest
- [x] `install.sh` — standalone one-liner installer (Brew, Ollama, Qdrant, Cipher MCP, hooks, skills, commands, context tree, gitignore, `CLAUDE.local.md`)
- [x] `uninstall.sh` — clean removal script
- [x] `config/presets/` — 5 BYOP provider presets (local, local-light, openai, anthropic, cloud)
- [x] `config/settings.json` — Claude Code tool permissions
- [x] `config/hooks-settings.json` — hook event registrations
- [x] `templates/instructions.md` — `CLAUDE.local.md` template with placeholder substitution
- [x] `scripts/configure.sh` — post-install context tree setup
- [x] `tests/test-install.sh`, `test-config.sh`, `test-techpack.sh`, `test-uninstall.sh`

📄 [Plan 1 document](docs/plans/2026-03-13-plan-1-foundation.md)

---

### Plan 2 — Context Tree Engine ⏳ Not started

> CRUD operations, BM25 search, scoring/maturity, archival, Cipher sync

**Will deliver:**
- [ ] `scripts/context-tree.sh` — main dispatcher (create/read/update/delete/list/search/score/archive/sync)
- [ ] `scripts/ct-frontmatter.sh` — YAML frontmatter parse/write helpers
- [ ] `scripts/ct-scoring.sh` — importance/recency/maturity calculations
- [ ] `scripts/ct-manifest.sh` — manifest + `_index.md` management
- [ ] `scripts/ct-archive.sh` — archival and restore logic
- [ ] `scripts/ct-search.sh` — BM25 + Cipher result merge
- [ ] `scripts/ct-sync.sh` — curate + query orchestration
- [ ] `scripts/bm25.py` — Python TF-IDF/BM25 search engine
- [ ] `tests/test-ct-*.sh` — full test suite for all context tree operations

📄 [Plan 2 document](docs/plans/2026-03-13-plan-2-context-tree.md)

---

### Plan 3 — Hooks & Core Skills ⏳ Not started

> Replace placeholder hooks, implement 5 core skills + 3 slash commands

**Will deliver:**
- [ ] `hooks/session-start.sh` — real implementation (load context tree, inject top-5 knowledge files)
- [ ] `hooks/prompt-submit.sh` — real implementation (inject decision table, auto-query/auto-curate)
- [ ] `skills/continuous-learning/` — iron law enforcement skill
- [ ] `skills/curate-knowledge/` — knowledge curation guidance
- [ ] `skills/query-strategies/` — tiered query routing
- [ ] `skills/context-tree-maintenance/` — scoring, maturity, archival
- [ ] `skills/memory-verification/` — verify store/retrieve correctness
- [ ] `commands/query.md` — `/xgh query` slash command
- [ ] `commands/curate.md` — `/xgh curate` slash command
- [ ] `commands/status.md` — `/xgh status` slash command
- [ ] `tests/test-hooks.sh`, `test-skills.sh`, `test-commands.sh`

📄 [Plan 3 document](docs/plans/2026-03-13-plan-3-hooks-and-skills.md)

---

### Plan 4 — Team Collaboration Skills ⏳ Not started

> 6 team collaboration skills, `/xgh-collaborate` command, collaboration dispatcher agent

**Will deliver:**
- [ ] `skills/pr-context-bridge/` — auto-curate PR reasoning
- [ ] `skills/knowledge-handoff/` — structured handoff on merge
- [ ] `skills/convention-guardian/` — enforce team conventions
- [ ] `skills/cross-team-pollinator/` — org-wide knowledge sharing
- [ ] `skills/subagent-pair-programming/` — TDD via spec writer + implementer
- [ ] `skills/onboarding-accelerator/` — new dev context bootstrapping
- [ ] `commands/collaborate.md` — `/xgh-collaborate` command
- [ ] `agents/collaboration-dispatcher.md` — multi-agent orchestration agent
- [ ] `tests/test-team-skills.sh`, `test-collaborate-command.sh`, `test-collaboration-agent.sh`

📄 [Plan 4 document](docs/plans/2026-03-13-plan-4-team-collaboration.md)

---

### Plan 5 — Multi-Agent Collaboration Bus ⏳ Not started

> Agent registry, workflow templates, message protocol, dispatcher

**Will deliver:**
- [ ] `config/agents.yaml` — agent registry (Claude Code, Codex, Cursor, custom)
- [ ] `config/workflows/plan-review.yaml` — 2-agent plan→review→implement
- [ ] `config/workflows/parallel-impl.yaml` — N-agent parallel implementation
- [ ] `config/workflows/validation.yaml` — implement→validate loop
- [ ] `config/workflows/security-review.yaml` — implement→review→fix→re-review
- [ ] `skills/agent-collaboration/` — message protocol + dispatch conventions skill
- [ ] `agents/collaboration-dispatcher.md` — orchestration agent
- [ ] `commands/xgh-collaborate.md` — `/xgh-collaborate` command
- [ ] `tests/test-multi-agent.sh`

📄 [Plan 5 document](docs/plans/2026-03-13-plan-5-multi-agent.md)

---

### Plan 6 — Workflow Skills ⏳ Not started

> `xgh:investigate`, `xgh:implement-design`, `xgh:implement-ticket` — MCP-powered workflow skills

**Will deliver:**
- [ ] `skills/investigate/investigate.md` — Superpowers-style investigation workflow with MCP auto-detection (Slack, Figma, Atlassian)
- [ ] `skills/implement-design/implement-design.md` — design-to-implementation workflow
- [ ] `skills/implement-ticket/implement-ticket.md` — ticket-to-implementation workflow
- [ ] `commands/investigate.md` — `/xgh investigate` command
- [ ] `commands/implement-design.md` — `/xgh implement-design` command
- [ ] `commands/implement.md` — `/xgh implement` command
- [ ] `tests/test-workflow-skills.sh`

📄 [Plan 6 document](docs/plans/2026-03-13-plan-6-workflow-skills.md)

---

## Agent Instructions

xgh includes ready-made agent instruction files for every major AI platform:

| Platform | File |
|----------|------|
| **Canonical (all agents)** | [`AGENTS.md`](AGENTS.md) |
| **Claude Code** | [`CLAUDE.md`](CLAUDE.md) |
| **GitHub Copilot** | [`.github/copilot-instructions.md`](.github/copilot-instructions.md) |
| **Copilot Chat (VS Code)** | [`.copilot/instructions.md`](.copilot/instructions.md) |
| **Cursor** | [`.cursor/rules/xgh.md`](.cursor/rules/xgh.md) |
| **Windsurf** | [`.windsurfrules`](.windsurfrules) |

---

## Contributing

1. Read [`AGENTS.md`](AGENTS.md) — development conventions, test commands, implementation status
2. Read the relevant plan in `docs/plans/` for the area you are working on
3. Write a failing test first (`tests/`)
4. Implement the feature
5. Run all tests: `bash tests/test-install.sh && bash tests/test-config.sh && bash tests/test-techpack.sh`
6. Open a PR — context tree diffs are normal and expected

### Development tips

```bash
# Dry-run installer without installing anything
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh

# Test with a specific preset
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. XGH_PRESET=openai bash install.sh

# Run individual tests
bash tests/test-config.sh
```

---

## Design Document

The full architecture is documented in [`docs/plans/2026-03-13-xgh-design.md`](docs/plans/2026-03-13-xgh-design.md), covering:

- Dual-engine design rationale (Cipher vs. context tree)
- Sync layer specification
- Context tree file format and scoring formula
- Hook-driven self-learning loop
- Multi-agent collaboration bus and message protocol
- Superpowers-inspired skill methodology
- CLI commands and skill reference
- Team collaboration patterns
- Workflow skills (investigate, implement-design, implement-ticket)

---

## License

MIT — see [LICENSE](LICENSE).

---

*Built around the [Cipher](https://github.com/campfirein/cipher) memory layer and inspired by the [Superpowers](https://github.com/obra/superpowers) methodology. Also check out [ByteRover](https://byterover.dev) — a very nice alternative product that does something similar.*
