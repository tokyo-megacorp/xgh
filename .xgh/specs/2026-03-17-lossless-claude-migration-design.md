# Design: Replace Cipher with lossless-claude

**Date:** 2026-03-17
**Status:** Draft
**Scope:** Memory persistence layer only — no changes to retrieval logic, Slack/Jira/GitHub integrations, or context tree structure.

---

## Problem

xgh's memory persistence layer uses Cipher MCP (`@byterover/cipher`), a stdio MCP server backed by Qdrant for vector storage. Cipher is being replaced by `@tokyo-megacorp/lossless-claude`, which provides:

- A two-layer memory model: episodic (SQLite DAG, per-session) + semantic (Qdrant, persistent cross-session)
- A full MCP server (same stdio pattern as Cipher)
- A local daemon at `http://127.0.0.1:3737`
- Better extraction quality: Claude extracts inline at the skill level (context-aware) rather than Cipher's fixed internal prompt

---

## Tool Mapping

Complete Cipher → lossless-claude substitution table:

| Cipher tool | lossless-claude equivalent |
|---|---|
| `cipher_extract_and_operate_memory` | Claude extracts inline (3-7 bullet summary) → `lcm_store(summary, [tag])` with context-appropriate tag |
| `cipher_store_reasoning_memory` | `lcm_store(text, ["reasoning"])` |
| `cipher_workspace_store` | `lcm_store(text, ["workspace"])` |
| `cipher_memory_search` | `lcm_search(query)` |
| `cipher_search_reasoning_patterns` | `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })` |
| `cipher_workspace_search` | `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })` |
| `cipher_evaluate_reasoning` | `lcm_search` to retrieve patterns → Claude evaluates inline |
| `cipher_extract_reasoning_steps` | Claude extracts inline → `lcm_store(steps, ["reasoning"])` |
| `cipher_bash` | Drop — use Bash directly |

### Retrieval-only tools: `lcm_grep`, `lcm_expand`, `lcm_describe`

These three tools have no direct Cipher equivalent — they are new capabilities:

| Tool | When to use |
|---|---|
| `lcm_grep` | Fast FTS5 full-text search within the episodic layer. Prefer over `lcm_search` when searching for exact strings (function names, error codes, commit hashes) in recent session history. |
| `lcm_expand` | Drill into a summary node to recover the original messages it was condensed from. Use when `lcm_search` returns a summary that needs more detail. |
| `lcm_describe` | Describe a conversation or summary node by ID. Use for inspection and debugging, or when `lcm_expand` needs a specific node ID. |

Skills that previously used `cipher_memory_search` for exact-string lookups should prefer `lcm_grep`. Skills doing broad semantic queries continue to use `lcm_search`.

### Tool signatures

```
lcm_store(text: string, tags?: string[], metadata?: object)
lcm_search(query: string, options?: { layers?: string[], tags?: string[], limit?: number, threshold?: number })
  -- threshold: similarity score cutoff 0–1; lower = more results, higher = stricter match
  -- omit options entirely for hybrid search (equivalent to layers: ["episodic", "semantic"])
lcm_grep(query: string)
lcm_expand(summaryId: string)
lcm_describe(id: string)
```

### Availability sentinel

All availability checks (`doctor`, `brief`, `status`, `help`) that currently detect Cipher by checking for `mcp__cipher__cipher_memory_search` in the tool list are updated to check for `mcp__lossless-claude__lcm_search`.

**Tool name format:** MCP tool identifiers are constructed as `mcp__<server-key>__<tool-name>` where `<server-key>` is the exact key from `mcpServers` in `.claude/mcp.json`. Claude Code preserves hyphens in server keys verbatim (consistent with how `cipher` produces `mcp__cipher__cipher_memory_search`). With the registration key `"lossless-claude"`, the sentinel tool name is `mcp__lossless-claude__lcm_search`.

**First-run verification step (Phase 1):** After updating `.claude/mcp.json`, start a Claude Code session and confirm that `mcp__lossless-claude__lcm_search` appears in the available tool list. If it appears as `mcp__lossless_claude__lcm_search` (underscore), update the sentinel string in all 43 files before proceeding to Phase 2. Success Criterion 5 uses the hyphen form as the canonical value.

---

## Two-Layer Memory Model

`templates/instructions.md` and all skill docs that reference memory tools must document the two layers:

**Episodic** (`layers: ["episodic"]`) — SQLite-backed, per-session history. Fast FTS5 full-text search. Use when you need recent in-session context, conversation history, or immediate task state. Access via `lcm_grep(query)` (preferred for exact-string search) or `lcm_search(query, { layers: ["episodic"] })` (vector search within episodic). Both `"episodic"` and `"semantic"` are valid `layers` values; `query` is always the first positional argument.

**Semantic** (`layers: ["semantic"]`) — Qdrant-backed, persistent cross-session memory. Vector similarity search. Use when you need past decisions, team conventions, reasoning patterns, or cross-session knowledge. Access via `lcm_search(query, { layers: ["semantic"] })`.

**Hybrid (default)** — omit the `options` argument entirely (e.g., `lcm_search(query)`) to search both layers. Use for general-purpose queries when you're unsure which layer holds the answer.

### Tag conventions

| Tag | Meaning | Call sites |
|---|---|---|
| `["reasoning"]` | Architectural decisions, tradeoffs, why something was chosen | `cipher_store_reasoning_memory`, `cipher_extract_reasoning_steps`, `cipher_evaluate_reasoning` replacements |
| `["workspace"]` | Cross-agent state, handoffs, collaboration context | `cipher_workspace_store` replacement; `collab`, `knowledge-handoff` end-of-task stores |
| `["workspace", "index"]` | Codebase module knowledge indexed for retrieval | `index.md` per-module loop stores |
| `["session"]` | General work captures, findings, task outcomes | `cipher_extract_and_operate_memory` replacements in skills without a more specific domain tag (e.g. `briefing`, `todo-killer`, `track`) |

When a skill replaces `cipher_extract_and_operate_memory` and the stored content is clearly domain-specific (reasoning, workspace collab, indexed code), use the matching tag. Fall back to `["session"]` when the content is general task output.

---

## Extraction-Before-Store Pattern

Any skill or command that previously called `cipher_extract_and_operate_memory` must include this explicit instruction at the store call site:

> "Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store."

**Mid-flow callers** (`analyze`, `implement`, `investigate`, `index`) — grep the file for `cipher_extract_and_operate_memory` to find all call sites (there may be more than one). Insert at each exact point in the flow where the old call appeared. For `index.md` this is the per-module loop body.

**End-of-task callers** (`briefing`, `collab`, `curate`, `design`, `knowledge-handoff`, `todo-killer`, `track`) — insert in the completion/wrap-up step.

Note: `subagent-pair-programming`, `cross-team-pollinator`, and `onboarding-accelerator` reference `cipher_extract_and_operate_memory` only in their tool-reference summary tables, not as active procedure call sites. Their actual store calls use `cipher_store_reasoning_memory` → apply mechanical substitution only.

Tag guidance for end-of-task callers: `collab` and `knowledge-handoff` store cross-agent state → use `["workspace"]`. All others store general task outcomes → use `["session"]`.

---

## Daemon Availability

If `lcm_search` is present in the tool list but the call returns an error (any non-empty `error` field, connection refused, or timeout — as opposed to an empty results array), Claude should surface:

> "`lossless-claude` daemon not running — start with: `lossless-claude daemon start`"

This check is added to `doctor.md` and `mcp-setup.md`. For `mcp-setup.md`: add a "Verify lossless-claude" step that runs `lcm_search("xgh health check")` and reports the result using the same two-failure-mode logic as `doctor.md`.

---

## Migration Phases

### Phase 1 — Config & authority files (3 files)

**`.claude/mcp.json`**
Replace the `cipher` MCP server entry:
```json
{
  "mcpServers": {
    "lossless-claude": {
      "command": "lossless-claude",
      "args": ["mcp"]
    }
  }
}
```

**`techpack.yaml`**
Remove the `cipher` and `qdrant` MCP entries. Add lossless-claude:
```yaml
  - id: lossless-claude
    type: mcpServer
    command: "lossless-claude"
    args: ["mcp"]
    description: "Two-layer memory MCP server (episodic + semantic)"
```

**`templates/instructions.md`**
- Rewrite the "Cipher MCP Tools" section → "lossless-claude Memory Tools"
- Document `lcm_store`, `lcm_search`, `lcm_grep`, `lcm_expand`, `lcm_describe` with their signatures
- Add one-paragraph two-layer model explanation with `layers` and `tags` params
- Update the decision protocol table (all Cipher tool references → lossless-claude equivalents)
- Remove `cipher_bash` row entirely

### Phase 2 — Commands (21 files in `plugin/commands/`)

All 21 command files, all located in `plugin/commands/`:
`analyze.md`, `ask.md`, `brief.md`, `briefing.md`, `calibrate.md`, `collab.md`, `curate.md`, `design.md`, `doctor.md`, `help.md`, `implement.md`, `index.md`, `init.md`, `investigate.md`, `profile.md`, `retrieve.md`, `setup.md`, `status.md`, `todo-killer.md`, `track.md`, `xgh-collaborate.md`

Notes:
- `collab.md` and `xgh-collaborate.md` are separate files in `plugin/commands/` — both must be updated
- `calibrate.md` and `doctor.md` exist as both command files and skill files; both locations must be updated independently
- `brief.md`, `help.md`, `setup.md`, and `status.md` exist only as command files — there are no corresponding skill directories
- `knowledge-handoff` exists only as a skill (`plugin/skills/knowledge-handoff/`) — it is covered in Phase 3, not Phase 2

Apply to all 21 files:
- Mechanical substitution using the mapping table
- Extraction-before-store pattern at every former `cipher_extract_and_operate_memory` call site
- Swap availability sentinel from `cipher_memory_search` → `lcm_search`
- Remove all `cipher_bash` references; replace associated instructions with Bash tool usage

**`plugin/commands/index.md`** — command description file (distinct from `plugin/skills/index/index.md`). Apply mechanical substitution only unless it contains `cipher_extract_and_operate_memory` calls with loop semantics — if so, treat as mid-flow caller.

**`plugin/commands/doctor.md`** — apply the two-failure-mode daemon diagnostic:
- Tool absent from tool list → MCP not registered; fix: update `.claude/mcp.json`
- Tool present but errors → daemon not running; fix: `lossless-claude daemon start`

### Phase 3 — Skills (22 skill files across `plugin/skills/`)

All paths relative to `plugin/skills/` — top-level skills:
`analyze/analyze.md`, `ask/ask.md`, `briefing/briefing.md`, `calibrate/calibrate.md`, `collab/collab.md`, `curate/curate.md`, `design/design.md`, `doctor/doctor.md`, `implement/implement.md`, `index/index.md`, `init/init.md`, `investigate/investigate.md`, `knowledge-handoff/knowledge-handoff.md`, `mcp-setup/mcp-setup.md`, `pr-context-bridge/pr-context-bridge.md`, `profile/profile.md`, `retrieve/retrieve.md`, `todo-killer/todo-killer.md`, `track/track.md`

Nested team skills (must not be skipped):
`team/cross-team-pollinator/cross-team-pollinator.md`, `team/onboarding-accelerator/onboarding-accelerator.md`, `team/subagent-pair-programming/subagent-pair-programming.md`

Same substitution table and extraction-before-store requirement as Phase 2.

**Skill-specific notes:**
- `doctor/doctor.md` — update sentinel check + apply two-failure-mode daemon diagnostic (same as Phase 2 note for `plugin/commands/doctor.md`)
- `index/index.md` — **mid-flow caller**: `cipher_extract_and_operate_memory` is called in a loop once per module/package. Apply extraction-before-store at the loop call site. Tags must be `["workspace", "index"]`.
- `collab/collab.md` — end-of-task extraction caller; use `["workspace"]` tag (cross-agent state). The same applies to `plugin/commands/collab.md`.
- `calibrate/calibrate.md` — `cipher_memory_search` → `lcm_search` for memory sampling; no structural change.
- `mcp-setup/mcp-setup.md` — update Cipher install instructions → lossless-claude registration block; does not contain `cipher_extract_and_operate_memory` as active call site, so no extraction-before-store requirement.
- `init/init.md` — update first-run Cipher verification → lossless-claude verification.
- `pr-context-bridge/pr-context-bridge.md` — mechanical substitution; `cipher_store_reasoning_memory` calls → `lcm_store(text, ["reasoning"])`.
- `team/cross-team-pollinator/cross-team-pollinator.md` — mechanical substitution only; `cipher_extract_and_operate_memory` appears only in the tool-reference table, not as an active procedure call.
- `team/onboarding-accelerator/onboarding-accelerator.md` — mechanical substitution only; same table-only reference.
- `team/subagent-pair-programming/subagent-pair-programming.md` — mechanical substitution only; same table-only reference.
- All others (mechanical substitutions only): `ask/ask.md`, `profile/profile.md`, `retrieve/retrieve.md`.

Note: `briefing/briefing.md`, `curate/curate.md`, `design/design.md`, `investigate/investigate.md`, `knowledge-handoff/knowledge-handoff.md`, `todo-killer/todo-killer.md`, `track/track.md` have specific notes above (extraction callers or workspace callers) — they are NOT mechanical-only despite appearing in this list in an earlier draft.

---

## Out of Scope

- xgh retrieval logic (Slack, Jira, GitHub ingestion)
- Context tree structure or sync scripts
- `lib/workspace-write.js` (does not call Cipher MCP tools)
- Any files that mention "cipher" only in documentation/research context (e.g. `docs/research/cipher-mcp-deep-dive.md`)
- **Historical data migration** — existing memories in Qdrant and `data/cipher-sessions.db` are abandoned; no migration of historical Cipher memories into lossless-claude's semantic layer is performed as part of this change

---

## Success Criteria

1. `.claude/mcp.json` contains no `cipher` entry; `lossless-claude` entry with key `"lossless-claude"` is present
2. `techpack.yaml` contains no `cipher` or `qdrant` MCP entries
3. No file matching `plugin/skills/**/*.md` or `plugin/commands/*.md` contains `cipher_` tool references (recursive glob — catches nested team skills)
4. `templates/instructions.md` documents the two-layer model and all five lossless-claude tools (`lcm_store`, `lcm_search`, `lcm_grep`, `lcm_expand`, `lcm_describe`)
5. All availability sentinels in `plugin/skills/**/*.md` and `plugin/commands/*.md` check for `mcp__lossless-claude__lcm_search`; `.claude/mcp.json` server key is `"lossless-claude"` (matching the sentinel prefix)
6. Every active `cipher_extract_and_operate_memory` call site (mid-flow and end-of-task callers listed above) contains both anchor phrases: "3-7 bullets" and "Do not pass raw conversation content to lcm_store" (grep-verifiable, ASCII hyphens, no backticks in the anchor strings). For loop call sites (e.g. `index/index.md`), anchors appearing once within the loop body is sufficient.
