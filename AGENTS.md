# AGENTS.md — xgh (eXtreme Go Horse) 🐴

> Canonical agent instructions for AI systems working on the **xgh** repository.
> All platform-specific files (CLAUDE.md, .github/copilot-instructions.md, etc.) point here.

---

## What is xgh?

xgh is a **Model Context Server (MCS) tech pack** for Claude Code that gives AI agents persistent, team-shared memory across sessions. It combines:

- **Cipher MCP** — semantic vector memory (Qdrant-backed) for storing and querying past decisions, reasoning chains, and patterns
- **Context Tree** — a git-committed markdown knowledge base (`.xgh/context-tree/`) that is human-readable, PR-reviewable, and shareable without shared infrastructure
- **Dual-engine search** — Cipher vector similarity + BM25 keyword search merged with a scored ranking formula
- **Inference backends** — `vllm-mlx` (macOS Apple Silicon), `ollama` (Linux/Intel Mac), or `remote` (external server URL); auto-detected at install time, overridable via `XGH_BACKEND`
- **BYOP (Bring Your Own Provider)** — presets for OpenAI, Anthropic, OpenRouter, or cloud Qdrant (separate from the inference backend)

Install via Claude Code plugin:

```bash
claude plugin install xgh@ipedro
/xgh-init
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Install & hooks | Bash (`set -euo pipefail`) |
| Config | YAML (presets), JSON (settings) |
| Skills / commands / agents | Markdown (Claude Code format) |
| Context tree search | Python 3 (BM25/TF-IDF, Plan 2) |
| Vector memory | Cipher MCP + Qdrant |
| Model server | vllm-mlx (macOS arm64), Ollama (Linux/Intel), or remote URL |
| LLM / embeddings | vllm-mlx, Ollama, OpenAI, Anthropic, or OpenRouter (BYOP) |
| Tests | Bash with `assert_*` helpers (same pattern throughout) |

---

## Repository Structure

```
./
├── AGENTS.md                        # ← you are here — canonical agent instructions
├── CLAUDE.md                        # Claude Code pointer → AGENTS.md
├── README.md                        # Project README with roadmap + progress
├── config/
│   └── presets/                     # BYOP provider presets
│       ├── local.yaml               # vllm-mlx + local Qdrant (default)
│       ├── local-light.yaml         # vllm-mlx + in-memory vectors
│       ├── openai.yaml              # OpenAI GPT-4o-mini + Qdrant
│       ├── anthropic.yaml           # Claude Haiku + Qdrant
│       └── cloud.yaml               # OpenRouter + Qdrant Cloud
├── hooks/
│   ├── session-start.sh             # Injects context tree at session start
│   └── prompt-submit.sh             # Injects decision table on prompt submit
├── skills/                          # Claude Code skill definitions (markdown)
│   ├── mcp-setup/mcp-setup.md
│   ├── brief/brief.md
│   ├── ask/ask.md
│   ├── curate/curate.md
│   ├── collab/collab.md
│   ├── design/design.md
│   ├── implement/implement.md
│   ├── investigate/investigate.md
│   ├── profile/profile.md
│   ├── retrieve/retrieve.md
│   ├── analyze/analyze.md
│   ├── track/track.md
│   ├── doctor/doctor.md
│   ├── index/index.md
│   ├── calibrate/calibrate.md
│   └── init/init.md
├── commands/                        # Claude Code slash commands (markdown)
│   ├── setup.md
│   ├── brief.md
│   ├── ask.md
│   ├── curate.md
│   ├── collab.md
│   ├── design.md
│   ├── implement.md
│   ├── investigate.md
│   ├── profile.md
│   ├── retrieve.md
│   ├── analyze.md
│   ├── track.md
│   ├── doctor.md
│   ├── index.md
│   ├── calibrate.md
│   ├── init.md
│   └── help.md
├── agents/                          # Sub-agent definitions (Plan 5)
├── scripts/
├── tests/
│   └── test-config.sh
└── docs/
    └── plans/                       # Design doc + 6 implementation plans
```

---

## Development Guidelines

### General principles

1. **Test-first**: Write a failing test before implementing any feature. Tests live in `tests/` and use the `assert_*` bash helper pattern (see existing tests).
2. **Shell conventions**: All bash scripts must start with `#!/usr/bin/env bash` and `set -euo pipefail`.
3. **Plan discipline**: Each change should map to a plan step. Check off `- [x]` items in the relevant plan doc as you complete them.
4. **Minimal diffs**: Make the smallest correct change. Do not refactor unrelated code.
5. **No secrets**: Never commit API keys, tokens, or credentials. Secrets belong in environment variables only.

### Coding conventions

- Bash functions: `lower_snake_case`
- Constants / env vars: `UPPER_SNAKE_CASE`
- YAML keys: `camelCase` (following MCS tech pack schema)
- Markdown skills: one directory per skill, markdown file matches directory name
- Slash commands: markdown files in `commands/`, filename is the command name

### Adding a new BYOP preset

1. Copy an existing preset from `config/presets/` as a starting point
2. Update `vector_store.type`, `vector_store.url`, `llm.*`, and `embeddings.*` fields
3. Add a test in `tests/test-config.sh`

### Running tests

```bash
bash tests/test-config.sh       # Config files and presets
```

No build step — this is a shell-based project with no compiled artifacts.

---

## Implementation Status

| Plan | Title | Status |
|------|-------|--------|
| Plan 1 | Foundation — scaffold, BYOP config, installer | ✅ Complete |
| Plan 2 | Context Tree Engine — CRUD, BM25 search, sync | ✅ Complete |
| Plan 3 | Hooks & Core Skills — real hook implementations | ✅ Complete |
| Plan 4 | Team Collaboration Skills | ✅ Complete |
| Plan 5 | Multi-Agent Collaboration Bus | ✅ Complete |
| Plan 6 | Workflow Skills (investigate, design, implement) | ✅ Complete |
| Plan 7 | Briefing | ✅ Complete |
| Ingest | Context ingestion pipeline (25 files, 68 tests) | ✅ Complete |
| Refresh | Command rename, output style, /xgh-help | ✅ Complete |
| Plan 8 | Ollama / Linux Support — Ollama backend, backend-aware cipher.yml + MCP env vars | ✅ Complete |
| Plan 9 | Remote Backend — `XGH_BACKEND=remote`, `XGH_REMOTE_URL`, `XGH_SERVE_NETWORK` | ✅ Complete |

See `docs/plans/` for detailed implementation plans with task checklists.

For the full env var reference, backend/MCP matrix, and cipher post-hook behavior see [`docs/configuration-reference.md`](docs/configuration-reference.md).

> **Note on plans directories:** `docs/plans/` tracks xgh's own development work (these checklists). `.xgh/plans/` is a template directory that xgh creates in user projects for their own work tracking.

---

## Superpowers Methodology

xgh uses the **Superpowers** disciplined decision protocol. When working on this repo, follow it:

| Situation | Action |
|-----------|--------|
| Starting a task | Search for related past work in context tree + memories |
| Making an architectural decision | Check `docs/plans/2026-03-13-xgh-design.md` first |
| Choosing between approaches | Use the rationalization table pattern from design doc |
| Completing significant work | Capture learnings in context tree |
| Deviating from a plan | Document the reason explicitly |
| Writing new code | Check existing patterns in the codebase first |

### Iron Laws

1. **Never skip the test** — every implementation task starts with a failing test
2. **Never leave a placeholder** — replace stubs before marking a task complete
3. **Never break existing tests** — run the full test suite before marking a plan step done
4. **Never commit secrets** — use env vars; add patterns to `.gitignore`

---

## Key Design Decisions

1. **Dual-engine search** — Cipher vectors (semantic) + BM25 (keyword) in parallel; results merged with weighted scoring
2. **Git-committed context tree** — knowledge stored as markdown so it's PR-reviewable and shareable without shared infra
3. **BYOP architecture** — presets abstract provider details; the installer and Cipher MCP are provider-agnostic
4. **MCS tech pack format** — compatible with `mcs sync` (managed install) and `curl | bash` (standalone install)
5. **Bash-first implementation** — no custom runtime language needed for Plans 1–3; Python only for BM25 (available on macOS/Linux without install)

See `docs/plans/2026-03-13-xgh-design.md` for the full architecture document.
