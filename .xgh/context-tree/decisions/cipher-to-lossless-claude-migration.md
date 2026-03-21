---
title: "Memory Backend: Cipher → lossless-claude Migration"
type: decision
status: validated
importance: 92
tags: [decision, memory, lossless-claude, cipher, migration, architecture]
keywords: [lossless-claude, cipher, memory-backend, lcm_store, lcm_search]
created: 2026-03-20
updated: 2026-03-20
---

## Raw Concept

xgh originally used **Cipher MCP** (Qdrant-backed semantic vector memory) as its memory backend. This has been replaced by **lossless-claude** across all skills and documentation.

- Old: `mcp__cipher__store`, `mcp__cipher__search` via Cipher MCP server
- New: `lcm_store`, `lcm_search`, `lcm_grep`, `lcm_expand` via `lossless-claude mcp`
- MCP registration: `claude mcp add lossless-claude -- lossless-claude mcp`
- Binary: `lossless-claude` (installed via curl installer or Homebrew)
- Skills reference `mcp__lossless-claude__lcm_store` in their `mcp_dependencies`
- AGENTS.md still mentions "Cipher MCP" in the "What is xgh?" section — this is stale and refers to the old architecture

All `[REPO] [AREA]` memories stored via `lcm_store(text, ["workspace", "index"])`.

## Narrative

When xgh was first designed, Cipher was the planned vector memory backend (Qdrant-backed, with vllm-mlx/Ollama for embeddings). As the project evolved to become a pure Claude Code plugin, Cipher was replaced by lossless-claude — a lighter-weight, session-aware memory MCP that doesn't require running a local vector database or embedding server.

The migration simplified the dependency stack considerably: users no longer need Qdrant or a local embedding model. lossless-claude uses a hybrid SQLite (episodic) + Qdrant-optional (semantic) architecture with managed compaction.

**Why the switch?**
- Cipher required local Qdrant + embedding server (heavy install)
- lossless-claude works out of the box with just `brew install lossless-claude` or curl installer
- Better fit for a Claude Code plugin that should "just work" after `claude plugin install xgh@ipedro`

Any documentation or skill files that still reference "Cipher" are stale and should be updated to lossless-claude.

## Facts

- **Stale references**: AGENTS.md "What is xgh?" section still mentions Cipher MCP — treat as stale
- **Current tool names**: `lcm_store`, `lcm_search`, `lcm_grep`, `lcm_expand`, `lcm_describe`
- **Install**: `lossless-claude` binary + `claude mcp add lossless-claude -- lossless-claude mcp`
- **Tags convention**: `["workspace", "index"]` for codebase memories, `["session"]` for session context, `["reasoning"]` for decisions
- **No Qdrant required**: lossless-claude's episodic layer is SQLite-only; semantic layer is optional
- **xgh-lcm-integration.md** in ecosystem/ describes the integration roadmap (status: draft)
