
<!-- mcs:begin xgh.instructions -->
# xgh - eXtreme Go Horse for AI Teams

You are an AI agent operating within the **my-team** team, enhanced by the xgh memory and reasoning system. xgh gives you persistent memory across sessions via the lossless-claude MCP server, enabling you to learn from past decisions, recall team context, and improve over time.

## Context Tree

Your team's context tree is located at: `.xgh/context-tree`

The context tree is a structured knowledge base that captures your team's architecture, decisions, patterns, and conventions. Always consult it before making significant decisions.

## lossless-claude Memory Tools

You have access to lossless-claude MCP tools for memory storage and retrieval. lossless-claude uses a two-layer model:

**Episodic** (`layers: ["episodic"]`) — SQLite-backed per-session history. Fast full-text search. Use for recent in-session context. Access via `lcm_grep(query)` or `lcm_search(query, { layers: ["episodic"] })`.

**Semantic** (`layers: ["semantic"]`) — Qdrant-backed persistent cross-session memory. Vector similarity search. Use for past decisions, team conventions, reasoning patterns. Access via `lcm_search(query, { layers: ["semantic"] })`.

**Hybrid (default)** — `lcm_search(query)` with no `layers` arg searches both layers.

### Tools

- **lcm_store** — Persist a memory. Signature: `lcm_store(text, tags?, metadata?)`

  - Before storing: extract key learnings as a 3-7 bullet summary. Do not pass raw conversation content to lcm_store.

- **lcm_search** — Hybrid or layer-targeted search. `lcm_search(query, { layers?, tags?, limit?, threshold? })`

- **lcm_grep** — Fast FTS5 full-text search within the episodic layer. Prefer over `lcm_search` for exact strings (function names, error codes, commit hashes).

- **lcm_expand** — Drill into a summary node to recover original messages.

- **lcm_describe** — Describe a conversation or summary node by ID.

## Decision Protocol

When facing a decision, follow this table:

| Situation | Action |
|---|---|
| Starting a new task | `lcm_search(query)` for related past work |
| Making an architectural decision | `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })` for similar past decisions |
| Choosing between approaches | `lcm_search` to retrieve patterns → evaluate inline |
| Completing significant work | Extract 3-7 bullet summary → `lcm_store(summary, ["session"])` |
| Solving a non-trivial problem | `lcm_store(text, ["reasoning"])` to record the reasoning chain |
| Encountering an error/bug | `lcm_search(query)` to check if this was seen before |
| Before writing new code | `lcm_search(query)` for team conventions and patterns |

## Document Locations

Save all generated artifacts to the `.xgh/` folder so they are indexed by the context tree and available across sessions:

| Artifact | Path |
|----------|------|
| Implementation plans | `.xgh/plans/YYYY-MM-DD-<feature>.md` |
| Design specs / brainstorms | `.xgh/specs/YYYY-MM-DD-<topic>.md` |
| Architecture decisions | `.xgh/context-tree/architecture/<slug>.md` |
| Team conventions | `.xgh/context-tree/conventions/<slug>.md` |

> These paths override superpowers skill defaults (`docs/superpowers/`).

## Guidelines

1. **Memory-first**: Always search memory before starting work. Past sessions may have solved similar problems or established relevant patterns.
2. **Capture everything significant**: After completing tasks, store memories so future sessions benefit from your work.
3. **Follow team conventions**: The context tree and stored memories contain your team's established patterns. Follow them unless there is a clear reason to deviate.
4. **Explain deviations**: If you deviate from an established pattern, store a reasoning memory explaining why.
5. **Be specific in searches**: Use detailed, specific queries when searching memory for better results.
<!-- mcs:end xgh.instructions -->
