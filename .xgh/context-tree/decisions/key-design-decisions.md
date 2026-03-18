---
title: Key Design Decisions
type: decision
status: validated
importance: 90
tags: [architecture, decision, design, byop, dual-engine, bash-first, git-committed]
keywords: [design-decisions, rationale, trade-offs, architecture-choices]
created: 2026-03-18
updated: 2026-03-18
---

# Key Design Decisions

## Raw Concept

Five foundational decisions made during xgh design (see `docs/plans/2026-03-13-xgh-design.md`):

1. **Dual-engine search** — Cipher vectors (semantic) + BM25 (keyword) in parallel; merged with weighted scoring `0.5 × cipher + 0.3 × bm25 + 0.1 × importance + 0.1 × recency`
2. **Git-committed context tree** — knowledge stored as markdown in `.xgh/context-tree/` — PR-reviewable, shareable without shared infra
3. **BYOP architecture** — presets in `config/presets/` abstract provider details; installer and Cipher MCP are provider-agnostic
4. **MCS tech pack format** — compatible with `mcs sync` (managed install) and `curl | bash` (standalone install)
5. **Bash-first implementation** — no custom runtime for Plans 1–3; Python only for BM25 (pre-installed on macOS/Linux)

## Narrative

These decisions were made to keep xgh lightweight, portable, and deployable without infrastructure. The key insight was that AI agents already have access to a runtime (the Claude Code process), so the tool only needs to inject context — not manage a server.

The dual-engine approach compensates for each engine's weakness: BM25 misses semantic similarity; vectors miss exact keyword matches. By running both and merging scores, recall and precision are both served.

Git-committed context tree was chosen over a pure vector store so that knowledge is auditable and does not require shared infrastructure. Teams can PR-review what the AI "knows."

BYOP was chosen to avoid vendor lock-in and allow the tool to run fully locally (privacy) or via cloud APIs (convenience).

## Facts

- **Decision:** Dual-engine search chosen over single-engine for higher recall + precision
- **Decision:** Git-committed markdown chosen over pure vector DB for auditability and zero-infra sharing
- **Decision:** BYOP presets chosen over hardcoded providers for local-first privacy and flexibility
- **Decision:** Bash-first chosen to minimize runtime dependencies on target machines
- **Decision:** MCS tech pack format chosen for compatibility with both managed and standalone installs
- **Constraint:** Python 3 is the only non-bash dependency, and it's pre-installed on macOS/Linux
- **Constraint:** Skills are markdown — no compilation, no runtime language required
