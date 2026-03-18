---
title: Tech Stack
type: architecture
status: validated
importance: 75
tags: [architecture, tech-stack]
keywords: [bash, python, javascript, qdrant, cipher, yaml, launchd, vllm-mlx]
created: 2026-03-16
updated: 2026-03-18
---

# Tech Stack

| Layer | Technology |
|-------|-----------|
| Installation & Hooks | Bash (`set -euo pipefail`) |
| Config | YAML (ingest), JSON (settings, hooks) |
| Skills/Commands | Markdown (Claude Code skill format) |
| Context Tree Search | Python 3 (BM25/TF-IDF via `bm25.py`) |
| Vector Memory | Cipher MCP + Qdrant |
| Direct Qdrant Writes | Node.js (`lib/workspace-write.js`) |
| Embeddings | vllm-mlx (macOS), Ollama (Linux/Intel), or OpenAI-compatible API |
| LLM | Provider-agnostic: vllm-mlx, Ollama, OpenAI, Anthropic, OpenRouter |
| Model Backend | `XGH_BACKEND=local|ollama|remote` (Plan 8/9) |
| Scheduling | launchd (macOS) |
| Tests | Bash with `assert_*` helpers |
| GitHub CLI | `gh` for repo, issues, PRs, actions |

## Key Design Choices
- **No runtime dependencies beyond bash** — installer and hooks are pure shell
- **BYOP** — Bring Your Own Provider for embeddings and LLM
- **Dual-engine search** — BM25 (auditable) + vector (semantic recall)
- **Git-committed knowledge** — context tree is reviewable in PRs
- **launchd for scheduling** — native macOS, no cron dependency
- **Multi-platform model backends** — vllm-mlx (macOS arm64), Ollama (Linux/Intel), or remote URL via `XGH_BACKEND`
