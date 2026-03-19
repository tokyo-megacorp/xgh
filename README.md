# xgh — The developer's cockpit

**One install wires memory, compression, context efficiency, and dev methodology into your AI agent.** No glue code. No config drift. No re-setup per project.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-initial%20release-brightgreen)](#implementation-status)

## What xgh wires together

| What you need | What does it | Installed by xgh |
|---------------|-------------|------------------|
| Persistent memory | [lossless-claude](https://github.com/ipedro/lossless-claude) | Automatic |
| Token compression | [RTK](https://github.com/rtk-ai/rtk) | Automatic |
| Context efficiency | [context-mode](https://github.com/mksglu/context-mode) | Optional plugin |
| Dev methodology | [superpowers](https://github.com/obra/superpowers) | Optional plugin |

## Your controls

| Command | What it does |
|---------|-------------|
| `/xgh-init` | First-run onboarding — verify connections, set up profile |
| `/xgh-brief` | Morning briefing — Slack, Jira, GitHub, what needs attention now |
| `/xgh-command-center` | Cross-project triage and dispatch |
| `/xgh-ask` | Search memory and context tree |
| `/xgh-implement` | Ticket to working code — full context gathering first |
| `/xgh-investigate` | Systematic debugging from a bug report |
| `/xgh-design` | Figma to implementation |
| `/xgh-doctor` | Validate pipeline health — config, connectivity, scheduler |
| `/xgh-track` | Add a project to monitoring (Slack, Jira, GitHub, Figma) |
| `/xgh-index` | Index a codebase into memory |

<details>
<summary><b>All commands</b></summary>

| Command | What it does |
|---------|-------------|
| `/xgh-setup` | Audit and configure MCP integrations |
| `/xgh-help` | Contextual guide and command reference |
| `/xgh-curate` | Store knowledge in memory and context tree |
| `/xgh-collab` | Multi-agent collaboration |
| `/xgh-profile` | Engineer throughput analysis from Jira history |
| `/xgh-retrieve` | Run context retrieval loop |
| `/xgh-analyze` | Run context analysis loop |
| `/xgh-schedule` | Manage background scheduler jobs |
| `/xgh-calibrate` | Calibrate dedup threshold with F1 scoring |
| `/xgh-status` | Memory stats and system health |
| `/xgh-todo-killer` | Resolve TODO comments across the codebase |

</details>

## Install

<details open>
<summary><b>Claude Code</b> (recommended)</summary>

```bash
claude plugin install xgh@ipedro
```

That installs:
1. [lossless-claude](https://github.com/ipedro/lossless-claude) — persistent memory (hooks, MCP server, daemon)
2. xgh — team context, skills, and dev methodology

Then configure the summarizer:

```bash
lossless-claude install
```

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

## What changes after install

| Before | After |
|--------|-------|
| Agent forgets everything between sessions | Conventions, decisions, and fixes recalled automatically |
| CLI output dumps 200 lines into context | RTK compresses to ~20 |
| You explain project context every session | Top-5 knowledge files injected at session start |
| Four tools configured separately, if at all | One install, zero drift |

All knowledge is stored as human-readable markdown in `.xgh/context-tree/` — reviewable in PRs, greppable in CI, readable without xgh.

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

<details>
<summary><b>BYOP — Bring Your Own Provider</b></summary>

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

</details>

<details>
<summary><b>Architecture</b></summary>

```
┌─────────────────────────────────────────────────────────────┐
│                    xgh — developer's cockpit                 │
│               25 commands · 5 hooks · context tree           │
├──────────┬──────────────┬───────────────┬───────────────────┤
│          │              │               │                   │
│  lossless-claude   context-mode      RTK          superpowers
│  (memory)          (efficiency)   (compression)  (methodology)
│  lcm_search        ctx_execute    rtk rewrite    brainstorming
│  lcm_store         ctx_search    rtk git/gh/..   writing-plans
│  lcm_grep          ctx_batch      rtk read        TDD, review
│          │              │               │                   │
├──────────┴──────────────┴───────────────┴───────────────────┤
│                                                             │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Vector DB │  │  SQLite    │  │  LLM + Emb │            │
│  │  (Qdrant)  │  │ (sessions) │  │  (BYOP)    │            │
│  └────────────┘  └────────────┘  └────────────┘            │
│                         │                                   │
│  ┌──────────────────────┴────────────────────────────────┐  │
│  │         .xgh/context-tree/  (git-committed)            │  │
│  │  ├── domain/ → topic/ → entry.md                       │  │
│  │  └── _manifest.json (flat entries[] registry)          │  │
│  └────────────────────────────────────────────────────────┘  │
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
| Tests | Bash with `assert_*` helpers (33 test suites) |

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

xgh's workspace acts as a message bus between agents. Any MCP-compatible agent can participate.

| Workflow | Pattern | Agents |
|----------|---------|--------|
| `plan-review` | Plan -> review -> implement | 2 |
| `parallel-impl` | Parallel implementation | N |
| `validation` | Implement -> validate loop | 2 |
| `security-review` | Implement -> review -> fix -> re-review | 2-3 |

</details>

<details>
<summary><b>Implementation Status</b></summary>

22 skills, 25 commands, 4 workflow templates, 33 test suites.

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

*xgh is inspired by [Fastlane](https://fastlane.tools), [ByteRover](https://byterover.dev), and the [Superpowers methodology](https://www.claudesuperpowers.com). It is an open, self-hosted, provider-agnostic alternative.*
