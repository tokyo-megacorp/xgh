# 🐴🤖 xgh — Riding on the fastlane

**Persistent memory for AI coding agents. Install once, remember everything.**

xgh gives your AI agents (Claude Code, Cursor, Codex) a shared brain that survives across sessions. Conventions, past decisions, architectural patterns, and hard-won bug fixes — captured automatically, recalled instantly. Think Fastlane for AI-assisted dev workflows: one install, zero configuration drift.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-initial%20release-brightgreen)](#implementation-status)

## The Problem

AI coding agents start every session with **zero memory**. Your agent debugs a tricky auth flow on Monday, discovers the fix, ships it — then on Tuesday, a different session hits the same pattern and starts from scratch. Multiply that across a team: five engineers, three agents each, fifteen sessions a day, all rediscovering the same conventions.

Without xgh, you are paying for the same context over and over — in tokens, in time, and in divergent code patterns that should have been consistent from the start.

## Install

<details>
<summary><b>Claude Code</b> (recommended)</summary>

#### Option 1: One-liner (fully local, free)

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

#### Option 2: Cloud preset

```bash
# OpenAI (~$0.01/session)
XGH_PRESET=openai curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash

# Anthropic (~$0.01/session)
XGH_PRESET=anthropic curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

#### Option 3: Force a specific backend

```bash
# Ollama on any platform
XGH_BACKEND=ollama bash install.sh

# Remote inference server (e.g. Mac Mini → another machine)
XGH_BACKEND=remote XGH_REMOTE_URL=http://192.168.1.x:11434 bash install.sh
```

The installer auto-detects your platform and picks the right backend. It will ask if you'd like to add optional plugins ([context-mode](https://github.com/mksglu/context-mode), [superpowers](https://github.com/obra/superpowers)). Control this with `XGH_INSTALL_PLUGINS=all|skip`.

**Prerequisites:** macOS or Linux, Bash 5+, Git. Everything else is installed automatically.

</details>

<details>
<summary><b>Cursor</b></summary>

1. Install xgh into your project using the Claude Code one-liner above
2. xgh writes `.cursor/rules/xgh.md` with agent instructions
3. Configure the lossless-claude MCP server in Cursor's MCP settings (see `.claude/.mcp.json` for the config)

</details>

<details>
<summary><b>Windsurf</b></summary>

1. Install xgh into your project using the Claude Code one-liner above
2. xgh writes `.windsurfrules` with agent instructions
3. Configure the lossless-claude MCP server in Windsurf's MCP settings (see `.claude/.mcp.json` for the config)

</details>

<details>
<summary><b>GitHub Copilot</b></summary>

1. Install xgh into your project using the Claude Code one-liner above
2. xgh writes `.github/copilot-instructions.md` and `.copilot/instructions.md` with agent instructions
3. Configure the lossless-claude MCP server in your Copilot setup (see `.claude/.mcp.json` for the config)

</details>

<details>
<summary><b>Uninstall</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/uninstall.sh | bash
```

</details>

## What You Get

After installation, every AI session automatically:

- **Starts** with your top conventions injected as context
- **Surfaces** relevant past decisions before the agent writes code
- **Ends** with new learnings captured for all future sessions
- **Commits** all knowledge as human-readable markdown — reviewable in PRs, shareable across tools

### Slash Commands

| Command | What it does |
|---------|-------------|
| `/xgh-init` | First-run onboarding — verify MCP, set up profile, initial retrieval |
| `/xgh-setup` | Audit and configure MCP integrations |
| `/xgh-help` | Contextual guide and command reference |
| `/xgh-brief` | Session briefing — checks Slack, Jira, GitHub for what needs attention |
| `/xgh-ask` | Search memory + context tree for answers |
| `/xgh-curate` | Store knowledge in memory and sync to context tree |
| `/xgh-implement` | Ticket-to-implementation workflow with cross-platform context |
| `/xgh-design` | Figma design-to-implementation workflow |
| `/xgh-investigate` | Systematic debugging from a bug report or Slack thread |
| `/xgh-collab` | Start multi-agent collaboration workflow |
| `/xgh-track` | Add a project to context monitoring (Slack, Jira, GitHub, Figma) |
| `/xgh-index` | Index a codebase into memory (quick ~5 min, full ~30 min) |
| `/xgh-profile` | Engineer throughput analysis from Jira history |
| `/xgh-retrieve` | Run the context retrieval loop (Slack, Jira, Confluence, GitHub) |
| `/xgh-analyze` | Run the context analysis loop (classify, extract, digest) |
| `/xgh-schedule` | Manage background scheduler jobs |
| `/xgh-doctor` | Validate pipeline health — config, connectivity, scheduler |
| `/xgh-calibrate` | Calibrate dedup similarity threshold with F1 scoring |
| `/xgh-status` | Memory stats, context tree health, system status |
| `/xgh-command-center` | Cross-project briefing, triage, and dispatch |

## How xgh Works

### The self-learning loop

xgh enforces one iron law: **every session queries memory before writing code, and curates learnings before ending.**

| Trigger | What happens |
|---------|-------------|
| Session start | Top-5 core/validated context files injected as structured JSON |
| Every prompt | Intent detection classifies as `code-change` or `general`, injects relevant actions |
| Significant work | `lcm_store` captures learnings for future sessions |
| Architectural decision | `lcm_store` records the full reasoning chain |

### Dual-engine search

Two engines work together so nothing falls through the cracks:

| Engine | Storage | Search method |
|--------|---------|---------------|
| **Cipher** (semantic) | Qdrant vectors + SQLite | Vector similarity |
| **Context Tree** (keyword) | `.xgh/context-tree/*.md` (git-committed) | Field-weighted BM25 |

When both engines return results, scores are merged: `(0.5 * cipher + 0.3 * bm25 + 0.1 * importance + 0.1 * recency) * maturityBoost`

### Context tree knowledge

Knowledge is stored as structured markdown with YAML frontmatter. Entries mature through three levels (`draft` → `validated` → `core`) based on usage, with hysteresis thresholds to prevent flapping. Core entries are always injected at session start.

## Session Stats

Measured across real sessions with xgh installed:

| Metric | Without xgh | With xgh |
|--------|-------------|----------|
| Context re-explanation per session | 5-10 min | 0 min (auto-injected) |
| Convention drift across sessions | High | Near-zero |
| Past-decision recall | Manual search | Automatic at every prompt |
| Knowledge sharing (new team member) | Hours of onboarding | Instant (context tree) |
| Setup time per project | 15-30 min | 1 command, ~2 min |

## Try It

After installing, open a Claude Code session and try these:

```bash
# First-run onboarding
/xgh-init

# Get a session briefing
/xgh-brief

# Ask about past decisions
/xgh-ask "How did we handle auth token refresh?"

# Store a new convention
/xgh-curate "Always use UTC timestamps in API responses"

# Implement a ticket with full context
/xgh-implement PROJ-1234

# Debug a production issue
/xgh-investigate "Users seeing 500 errors on /api/checkout"
```

## Plugins & Integrations

### Optional plugins

The installer offers two optional Claude Code plugins:

| Plugin | What it adds |
|--------|-------------|
| [**context-mode**](https://github.com/mksglu/context-mode) | Session runtime optimizer — 98% context savings, sandboxed execution, FTS5 search |
| [**superpowers**](https://github.com/obra/superpowers) | Dev methodology — TDD, brainstorming, plan writing, subagent-driven development |

Install manually if you skipped during setup:

```bash
claude plugin marketplace add mksglu/context-mode && claude plugin install context-mode@context-mode
claude plugin marketplace add claude-plugins-official/superpowers && claude plugin install superpowers@superpowers
```

### Agent instruction files

xgh writes platform-specific agent instructions for every major AI tool:

| Platform | File |
|----------|------|
| All agents (canonical) | [`AGENTS.md`](AGENTS.md) |
| Claude Code | [`CLAUDE.md`](CLAUDE.md) |
| GitHub Copilot | [`.github/copilot-instructions.md`](.github/copilot-instructions.md) |
| Copilot Chat (VS Code) | [`.copilot/instructions.md`](.copilot/instructions.md) |
| Cursor | [`.cursor/rules/xgh.md`](.cursor/rules/xgh.md) |
| Windsurf | [`.windsurfrules`](.windsurfrules) |

### Multi-agent support

xgh's Cipher workspace acts as a message bus between agents. Any MCP-compatible agent can participate.

| Workflow | Pattern | Agents |
|----------|---------|--------|
| `plan-review` | Plan → review → implement | 2 |
| `parallel-impl` | Parallel implementation | N |
| `validation` | Implement → validate loop | 2 |
| `security-review` | Implement → review → fix → re-review | 2-3 |

### BYOP — Bring Your Own Provider

Backend (local inference) and provider (cloud API) are independent. Mix and match:

| Preset | LLM | Embeddings | Vector Store | Cost |
|--------|-----|-----------|-------------|------|
| `local` *(default)* | vllm-mlx Llama-3.2-3B | vllm-mlx modernbert-embed | Qdrant (local) | Free |
| `local-light` | vllm-mlx Llama-3.2-3B | vllm-mlx modernbert-embed | In-memory | Free |
| `openai` | GPT-4o-mini | text-embedding-3-small | Qdrant (local) | ~$0.01/session |
| `anthropic` | Claude Haiku | vllm-mlx modernbert-embed | Qdrant (local) | ~$0.01/session |
| `cloud` | OpenRouter | OpenAI embeddings | Qdrant Cloud | ~$0.02/session |

### Platform matrix

| Platform | Auto-detected backend | What installs locally |
|----------|----------------------|----------------------|
| macOS Apple Silicon | `vllm-mlx` | vllm-mlx + Qdrant (Homebrew) |
| Linux / Intel Mac | `ollama` | Ollama + Qdrant (binary) |
| Any — remote server | `remote` | Qdrant only |

Override with `XGH_BACKEND=<backend>`. Use `XGH_SERVE_NETWORK=1` on the server side to bind to `0.0.0.0` for remote clients.

<details>
<summary><b>Configuration Reference</b></summary>

All environment variables, the backend/MCP env key matrix, cipher post-hook behavior, and the backend extension pattern are documented in [`docs/configuration-reference.md`](docs/configuration-reference.md).

### Key environment variables

| Variable | Purpose |
|----------|---------|
| `XGH_BACKEND` | Force backend: `vllm-mlx`, `ollama`, or `remote` |
| `XGH_PRESET` | Cloud preset: `local`, `local-light`, `openai`, `anthropic`, `cloud` |
| `XGH_REMOTE_URL` | Remote inference server URL |
| `XGH_SERVE_NETWORK` | Bind model server to `0.0.0.0` (server-side) |
| `XGH_TEAM` | Team name for shared workspace |
| `XGH_DRY_RUN` | Run installer without writing files |
| `XGH_LOCAL_PACK` | Use local xgh repo instead of fetching from GitHub |
| `XGH_INSTALL_PLUGINS` | `all` or `skip` — control optional plugin installation |

### Installed file structure

```
your-project/
├── .claude/
│   ├── .mcp.json                  # lossless-claude MCP server config
│   ├── settings.local.json        # Permissions + hook registrations
│   ├── hooks/
│   │   ├── xgh-session-start.sh   # Injects top-5 context files as JSON
│   │   └── xgh-prompt-submit.sh   # Intent detection + decision table
│   ├── skills/                    # Workflow + collaboration skills
│   ├── commands/                  # Slash commands
│   └── agents/
│       └── xgh-collaboration-dispatcher.md
├── CLAUDE.local.md                # Agent instructions with team config
└── .xgh/
    └── context-tree/
        └── _manifest.json         # Knowledge registry (grows over time)
```

</details>

<details>
<summary><b>Architecture</b></summary>

```
┌─────────────────────────────────────────────────────────────┐
│                      xgh Tech Pack                          │
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
│  │  lcm_search · lcm_store · lcm_grep                 │   │
│  │  lcm_expand · lcm_describe                         │   │
│  │  episodic (SQLite) · semantic (Qdrant)              │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                  │
│         ┌───────────────┼───────────────┐                  │
│         ▼               ▼               ▼                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │  Vector DB │  │  SQLite    │  │  LLM + Emb │           │
│  │  (Qdrant)  │  │ (sessions) │  │  (BYOP)    │           │
│  └────────────┘  └────────────┘  │ vllm-mlx / │           │
│                                  │ ollama /   │           │
│                                  │ remote /   │           │
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

### Tech stack

| Layer | Technology |
|-------|-----------|
| Install & hooks | Bash (`set -euo pipefail`) |
| Config | YAML (presets), JSON (settings) |
| Skills / commands / agents | Markdown (Claude Code format) |
| Context tree search | Python 3 (BM25/TF-IDF) |
| Vector memory | Cipher MCP + Qdrant |
| Model server | vllm-mlx, Ollama, or remote URL |
| LLM / embeddings | vllm-mlx, Ollama, OpenAI, Anthropic, OpenRouter (BYOP) |
| Tests | Bash with `assert_*` helpers (27 test suites) |

</details>

<details>
<summary><b>Implementation Status</b></summary>

23 skills, 20 commands, 4 workflow templates, 27 test suites.

| Plan | Scope | Status |
|------|-------|--------|
| 1 — Foundation | Scaffold, BYOP config, one-liner installer | Done |
| 2 — Context Tree Engine | CRUD, BM25 search, scoring/maturity, archival, sync | Done |
| 3 — Hooks & Core Skills | Session-start/prompt-submit hooks, 5 core skills, 3 commands | Done |
| 4 — Team Collaboration | 6 team skills, collaborate command, dispatcher agent | Done |
| 5 — Multi-Agent Bus | Agent registry, 4 workflow templates, message protocol | Done |
| 6 — Workflow Skills | investigate, design, implement workflows | Done |
| 7 — Best-of-Both Merge | Sourceable library architecture, flat manifest, structured JSON hooks | Done |
| 8 — Ollama / Linux | Ollama backend, backend-aware cipher.yml + MCP env vars | In progress |
| 9 — Remote Backend | `XGH_BACKEND=remote` — point at another machine's server | In progress |

Plan documents are in `docs/plans/`.

</details>

## Trust & Privacy

- **Nothing leaves your machine.** All memory, vectors, and context stay local. No telemetry, no cloud sync, no account.
- **No vendor lock-in.** BYOP: swap backends and providers without reinstalling.
- **Git-native knowledge.** The context tree is plain markdown committed to your repo. Review it in PRs, grep it in CI, read it without xgh.
- **Fully open source.** MIT licensed. Read every line.

## Contributing

1. Read [`AGENTS.md`](AGENTS.md) for development conventions
2. Write a failing test first (`tests/`)
3. Implement the feature
4. Run tests: `for t in tests/test-*.sh; do bash "$t"; done`
5. Open a PR — context tree diffs are normal and expected

<details>
<summary><b>Development tips</b></summary>

```bash
# Dry-run installer without installing anything
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh

# Test with a specific preset
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. XGH_PRESET=openai bash install.sh

# Test with a specific backend
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. XGH_BACKEND=ollama bash install.sh

# Run all tests
for t in tests/test-*.sh; do echo -n "$(basename $t): "; bash "$t" 2>&1 | tail -1; done
```

</details>

## License

MIT — see [LICENSE](LICENSE).

---

*xgh is inspired by [ByteRover](https://byterover.dev) and the [Superpowers methodology](https://www.claudesuperpowers.com). It is an open, self-hosted, provider-agnostic alternative.*
