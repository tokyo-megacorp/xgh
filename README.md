# xgh — eXtreme Go Horse 🐴

> **Context-aware AI coding conventions powered by Cipher memory and a living context tree.**
> An open, self-hosted alternative to ByteRover — team knowledge that grows with every session.
> Auto-detects the right inference backend for your platform.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-initial%20release-brightgreen)](#implementation-status)

---

## The Problem

AI coding agents (Claude Code, Cursor, Codex, etc.) start every session with **zero memory**. Conventions, past decisions, architectural patterns, and hard-won bug fixes — all lost when the session ends. Teams repeat the same mistakes, re-explain the same context, and diverge on patterns that should be shared.

xgh fixes this.

---

## Quick Start

### Prerequisites

- macOS or Linux
- Bash 5+
- Git

Everything else (Homebrew/curl, model server, Qdrant, Node.js for Cipher) is installed automatically.

### Platform matrix

| Platform | Auto-detected backend | What installs locally |
|---|---|---|
| macOS Apple Silicon | `vllm-mlx` | vllm-mlx + Qdrant (Homebrew) |
| Linux / Intel Mac | `ollama` | Ollama + Qdrant (binary) |
| Any — remote server | `remote` | Qdrant only |

### Install (fully local, free)

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

The installer auto-detects your platform and picks the right backend.

### Override the backend

```bash
# Force Ollama on any platform
XGH_BACKEND=ollama bash install.sh

# Point at another machine's inference server (e.g. Mac Mini → Raspberry Pi)
XGH_BACKEND=remote XGH_REMOTE_URL=http://192.168.1.x:11434 bash install.sh
```

### Serve to other devices (server-side flag)

```bash
# On the machine running the model server — bind to network instead of localhost
XGH_SERVE_NETWORK=1 bash install.sh
# Prints: ✓ vllm-mlx bound to 0.0.0.0:11434
#         On other machines: XGH_BACKEND=remote XGH_REMOTE_URL=http://<your-ip>:11434 bash install.sh
```

### Install with a cloud preset

```bash
# OpenAI (fastest, ~$0.01/session)
XGH_PRESET=openai XGH_TEAM=my-team \
  curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash

# Anthropic
XGH_PRESET=anthropic XGH_TEAM=my-team \
  curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

The installer will ask if you'd like to add optional plugins ([context-mode](#optional-plugins) and [superpowers](#optional-plugins)). You can also control this with `XGH_INSTALL_PLUGINS=all|skip`.

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/uninstall.sh | bash
```

---

## What You Get

After installation, every AI session automatically:

- **Starts** with your team's top conventions injected as context
- **Surfaces** relevant past decisions before the agent writes code
- **Ends** with new learnings captured and stored for all future agents
- **Commits** all knowledge as human-readable markdown — reviewable in PRs, shareable without infrastructure

### Installed files

```
your-project/
├── .claude/
│   ├── .mcp.json                  # lossless-claude MCP server config
│   ├── settings.local.json        # Permissions + hook registrations
│   ├── hooks/
│   │   ├── xgh-session-start.sh   # Injects top-5 context files as JSON
│   │   └── xgh-prompt-submit.sh   # Intent detection + decision table
│   ├── skills/                    # 18 workflow + collaboration skills
│   ├── commands/                  # 10 slash commands
│   └── agents/
│       └── xgh-collaboration-dispatcher.md
├── CLAUDE.local.md                # Agent instructions with your team config
└── .xgh/
    └── context-tree/
        └── _manifest.json         # Knowledge registry (grows over time)
```

---

## Slash Commands

| Command | Description |
|---------|-------------|
| `/xgh-briefing` | Session briefing — checks Slack, Jira, GitHub for actionable updates |
| `/xgh-query <question>` | Search memory + context tree |
| `/xgh-curate <knowledge>` | Store knowledge in Cipher + sync to context tree |
| `/xgh-status` | Memory stats, context tree health, agent registry |
| `/xgh-investigate` | MCP-powered investigation workflow (auto-detects Slack, Figma, Atlassian) |
| `/xgh-implement <ticket>` | Ticket-to-implementation workflow |
| `/xgh-implement-design` | Design-to-implementation workflow |
| `/xgh-collaborate <workflow>` | Start multi-agent workflow |
| `/xgh-setup` | Interactive MCP configuration wizard |

---

## Context Tree

Knowledge is stored as structured markdown with YAML frontmatter:

```yaml
---
title: JWT Token Refresh Strategy
tags: [auth, jwt, security]
keywords: [token, refresh]
importance: 78          # 0-100, grows with usage
recency: 0.8521         # exponential decay (half-life: 21 days)
maturity: validated     # draft → validated → core
accessCount: 12
updateCount: 3
createdAt: 2026-03-01T00:00:00Z
updatedAt: 2026-03-10T14:30:00Z
---

Refresh tokens rotate on every use with a 7-day absolute expiry.
We chose token rotation over sliding-window expiry to limit the
blast radius of a stolen token...
```

### Maturity levels (with hysteresis)

| Level | Promotion threshold | Demotion threshold | Effect |
|-------|--------------------|--------------------|--------|
| `draft` | — | — | Normal weight in search results |
| `validated` | importance ≥ 65 | importance < 30 | Included in session injection |
| `core` | importance ≥ 85 | importance < 50 | 1.15× score boost, always injected |

Separate promotion/demotion thresholds prevent maturity flapping.

### Context tree CLI

```bash
context-tree.sh init                          # Initialize context tree + manifest
context-tree.sh create <path> <title> [body]  # Create entry with frontmatter
context-tree.sh read <path>                   # Read entry (bumps importance)
context-tree.sh update <path> <content>       # Append update section
context-tree.sh delete <path>                 # Remove entry + archived counterparts
context-tree.sh list                          # List entries with maturity/importance
context-tree.sh search <query> [top]          # BM25 search with scoring
context-tree.sh score <path> [event]          # Bump importance by event type
context-tree.sh archive                       # Archive low-importance drafts
context-tree.sh restore <archived-file>       # Restore from archive
context-tree.sh sync curate <args...>         # Create entry via sync layer
context-tree.sh sync query <query>            # Search via sync layer
context-tree.sh sync refresh                  # Rebuild manifest + indexes
```

---

## The Self-Learning Loop

xgh enforces one iron law:

> **Every coding session must query memory before writing code and curate learnings before ending.**

| Hook / Trigger | What happens |
|----------------|-------------|
| Session start | Top-5 core/validated files injected as structured JSON (`contextFiles[]`) |
| Every prompt | Intent detection classifies prompt as `code-change` or `general`, injects relevant actions |
| Significant work completed | `lcm_store` captures learnings |
| Architectural decision made | `lcm_store` records the reasoning chain |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      xgh Tech Pack                           │
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
│  │              lossless-claude MCP Server             │   │
│  │  lcm_search · lcm_store · lcm_grep                  │   │
│  │  lcm_expand · lcm_describe                          │   │
│  │  episodic (SQLite) · semantic (Qdrant)               │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                  │
│         ┌───────────────┼───────────────┐                  │
│         ▼               ▼               ▼                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │  Vector DB │  │  SQLite    │  │  LLM + Emb │           │
│  │  (BYOP)   │  │ (sessions) │  │  (BYOP)    │           │
│  │ qdrant /  │  └────────────┘  │ vllm-mlx / │           │
│  │ in-memory │                  │ ollama /   │           │
│  └────────────┘                  │ remote /   │           │
│                                  │ openai /   │           │
│                                  │ anthropic  │           │
│                                  └────────────┘           │
│                         │                                  │
│                         ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         .xgh/context-tree/  (git-committed)         │   │
│  │  ├── domain/ → topic/ → entry.md                    │   │
│  │  ├── YAML frontmatter (importance, recency, maturity│   │
│  │  ├── _index.md (per-domain summary)                 │   │
│  │  └── _manifest.json (flat entries[] registry)       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Backend Selection

xgh auto-detects the inference backend at install time: `vllm-mlx` on macOS Apple Silicon, `ollama` on Linux/Intel Mac, or `remote` when you provide `XGH_REMOTE_URL`. Override with `XGH_BACKEND=<backend>`. On the server side, `XGH_SERVE_NETWORK=1` binds the model server to `0.0.0.0` so remote clients can reach it.

### Dual-engine search

| Engine | Purpose | Storage | Search method |
|--------|---------|---------|---------------|
| **Cipher** | Semantic memory, reasoning traces | Qdrant vectors + SQLite | Vector similarity |
| **Context Tree** | Human-readable knowledge, git-shareable | `.xgh/context-tree/*.md` | Field-weighted BM25 (title×3, tags×2, keywords×2, body×1) |

**BM25-only:** `score = (0.6 × bm25 + 0.2 × importance/100 + 0.2 × recency) × maturityBoost`

**Cipher-merged:** `score = (0.5 × cipher + 0.3 × bm25 + 0.1 × importance/100 + 0.1 × recency) × maturityBoost`

---

## BYOP — Bring Your Own Provider

xgh is **provider-agnostic**. **Backend** (local inference server: `vllm-mlx`, `ollama`, or `remote`) is separate from **provider** (cloud API: OpenAI, Anthropic, OpenRouter). The presets below override the provider; the backend is set independently via `XGH_BACKEND`.

Choose the preset that matches your infrastructure:

| Preset | LLM | Embeddings | Vector Store | Cost |
|--------|-----|-----------|-------------|------|
| `local` *(default)* | vllm-mlx Llama-3.2-3B | vllm-mlx modernbert-embed | Qdrant (local) | Free |
| `local-light` | vllm-mlx Llama-3.2-3B | vllm-mlx modernbert-embed | In-memory | Free, no persistence |
| `openai` | GPT-4o-mini | text-embedding-3-small | Qdrant (local) | ~$0.01/session |
| `anthropic` | Claude Haiku | vllm-mlx modernbert-embed | Qdrant (local) | ~$0.01/session |
| `cloud` | OpenRouter (configurable) | OpenAI embeddings | Qdrant Cloud | ~$0.02/session |

Preset files are in `config/presets/`. Add custom presets or override individual fields with environment variables.

---

## Multi-Agent Support

xgh's Cipher workspace acts as a **message bus** between agents. Any MCP-compatible agent can participate:

- **Claude Code** — primary agent (hooks + skills + MCP)
- **Cursor** — IDE editing, refactoring (MCP)
- **Codex** — fast implementation, code review (MCP + bash)
- **Custom agents** — user-defined capabilities (MCP)

### Workflow templates

| Workflow | Pattern | Agents |
|----------|---------|--------|
| `plan-review` | Plan → review → implement | 2 agents |
| `parallel-impl` | Parallel implementation | N agents |
| `validation` | Implement → validate loop | 2 agents |
| `security-review` | Implement → review → fix → re-review | 2-3 agents |

Workflow templates are in `config/workflows/`. The collaboration dispatcher agent (`agents/collaboration-dispatcher.md`) orchestrates multi-agent workflows.

---

## Optional Plugins

The installer offers two optional Claude Code plugins that complement xgh:

| Plugin | What it does | Author |
|--------|-------------|--------|
| [**context-mode**](https://github.com/mksglu/context-mode) | Session runtime optimizer — 98% context savings, sandboxed execution, FTS5 search, compaction recovery | mksglu |
| [**superpowers**](https://github.com/obra/superpowers) | Development methodology — TDD, brainstorming, plan writing/execution, subagent-driven development, code review | obra |

Install manually if you skipped during setup:

```bash
claude plugin marketplace add mksglu/context-mode && claude plugin install context-mode@context-mode
claude plugin marketplace add claude-plugins-official/superpowers && claude plugin install superpowers@superpowers
```

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

## Implementation Status

Plans 1–7 are complete. 18 skills, 10 commands, 4 workflow templates, 22 test suites.

| Plan | Scope | Status |
|------|-------|--------|
| 1 — Foundation | Scaffold, BYOP config, one-liner installer | ✅ |
| 2 — Context Tree Engine | CRUD, BM25 search, scoring/maturity, archival, sync | ✅ |
| 3 — Hooks & Core Skills | Session-start/prompt-submit hooks, 5 core skills, 3 commands | ✅ |
| 4 — Team Collaboration | 6 team skills, collaborate command, dispatcher agent | ✅ |
| 5 — Multi-Agent Bus | Agent registry, 4 workflow templates, message protocol | ✅ |
| 6 — Workflow Skills | investigate, implement-design, implement-ticket workflows | ✅ |
| 7 — Best-of-Both Merge | Sourceable library architecture, flat manifest, structured JSON hooks | ✅ |
| 8 — Ollama / Linux Support | Ollama backend for Linux/Intel Mac, backend-aware cipher.yml + MCP env vars | 🔄 |
| 9 — Remote Backend | `XGH_BACKEND=remote` — point at another machine's inference server | 🔄 |

Plan documents are in `docs/plans/`. Design specs are in `docs/superpowers/specs/`.

---

## Contributing

1. Read [`AGENTS.md`](AGENTS.md) — development conventions and implementation status
2. Read the relevant plan in `docs/plans/` for the area you are working on
3. Write a failing test first (`tests/`)
4. Implement the feature
5. Run tests: `for t in tests/test-*.sh; do bash "$t"; done`
6. Open a PR — context tree diffs are normal and expected

### Development tips

```bash
# Dry-run installer without installing anything
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh

# Test with a specific preset
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. XGH_PRESET=openai bash install.sh

# Test with a specific backend
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. XGH_BACKEND=ollama bash install.sh
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. XGH_BACKEND=remote XGH_REMOTE_URL=http://192.168.1.x:11434 bash install.sh

# Test network-serve mode (server side)
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. XGH_SERVE_NETWORK=1 bash install.sh

# Run individual test suites
bash tests/test-ct-integration.sh    # Full context tree lifecycle
bash tests/test-hooks.sh             # Hook JSON output
bash tests/test-install.sh           # Installer

# Run all tests
for t in tests/test-*.sh; do echo -n "$(basename $t): "; bash "$t" 2>&1 | tail -1; done
```

---

## Configuration Reference

All environment variables, the backend/MCP env key matrix, cipher post-hook behavior, and the backend extension pattern are documented in [`docs/configuration-reference.md`](docs/configuration-reference.md).

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

---

## License

MIT — see [LICENSE](LICENSE).

---

*xgh is inspired by [ByteRover](https://byterover.dev) and the [Superpowers methodology](https://www.claudesuperpowers.com). It is an open, self-hosted, provider-agnostic alternative.*
