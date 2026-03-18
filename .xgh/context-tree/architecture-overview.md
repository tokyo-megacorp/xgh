---
title: xgh Architecture Overview
type: architecture
status: validated
importance: 95
tags: [architecture, overview, core]
keywords: [xgh, tech-pack, MCS, memory, context-tree, cipher, dual-engine]
created: 2026-03-16
updated: 2026-03-18
---

# xgh Architecture Overview

xgh (eXtreme Go Horse) is a **Model Context Server (MCS) tech pack** for Claude Code that gives AI agents persistent, team-shared memory across sessions.

## Three-Layer Stack

1. **Memory Layer (Dual-Engine)**
   - **Cipher MCP**: Semantic vector search via Qdrant + embeddings (workspace memory, reasoning traces)
   - **Context Tree**: Git-committed markdown knowledge base (`.xgh/context-tree/*.md`)
   - **Sync Layer**: Keeps both engines consistent

2. **Hook Layer (Self-Learning)**
   - **SessionStart** (`hooks/session-start.sh`): Loads context tree, injects top knowledge into session
   - **UserPromptSubmit** (`hooks/prompt-submit.sh`): Detects intent, injects cipher memory as additionalContext

3. **Skill/Command Layer**
   - 25 skills (auto-triggered or explicit invocation)
   - 18 slash commands (`/xgh-*`)
   - Agents for multi-agent collaboration

## Dual-Engine Search

| Engine | Strength | Storage |
|--------|----------|---------|
| BM25 (Context Tree) | Keyword precision, auditable | Git-committed markdown |
| Cipher (Vector) | Semantic recall | Qdrant collections |

Merged scoring: `0.5 × cipher + 0.3 × bm25 + 0.1 × importance + 0.1 × recency`

## BYOP (Bring Your Own Provider)

Provider-agnostic model backends:

| Backend | Platform | Set via |
|---------|----------|---------|
| vllm-mlx | macOS arm64 (default) | `XGH_BACKEND=local` |
| Ollama | Linux / Intel Mac | `XGH_BACKEND=ollama` |
| Remote URL | Any (cloud, corporate) | `XGH_BACKEND=remote` + `XGH_REMOTE_URL` |
| OpenAI / Anthropic / OpenRouter | Any | BYOP presets in `config/presets/` |

`XGH_SERVE_NETWORK=1` exposes the local model server on the LAN (Plan 9).

## Implementation Status (as of 2026-03-18)

All plans complete — project is feature-stable:
- Plans 1–7, Ingest, Refresh: ✅ Complete (indexed 2026-03-16)
- Plan 8 (Ollama/Linux Support): ✅ Complete
- Plan 9 (Remote Backend): ✅ Complete
