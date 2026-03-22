# lossless-claude Migration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all Cipher MCP tool references across xgh with `@extreme-go-horse/lossless-claude` MCP tools, preserving memory semantics via a complete Cipher → lossless-claude mapping.

**Architecture:** Three-phase migration — Phase 1 updates config and the CLAUDE.local.md template (root of truth), Phase 2 updates all 21 command files, Phase 3 updates all 22 skill files. Each phase ends with a grep-based verification. Phase 1 includes a sentinel tool-name check before Phase 2 begins.

**Tech Stack:** `@extreme-go-horse/lossless-claude` MCP server (stdio), lossless-claude daemon (HTTP :3737), SQLite episodic layer + Qdrant semantic layer. No new code — all changes are prose substitutions in Markdown instruction files.

**Spec:** `.xgh/specs/2026-03-17-lossless-claude-migration-design.md`

---

## Substitution Reference

Keep this open throughout. Every occurrence of each old pattern must be replaced with its new form.

| Old | New |
|---|---|
| `cipher_memory_search` | `lcm_search` |
| `mcp__cipher__cipher_memory_search` | `mcp__lossless-claude__lcm_search` |
| `mcp__cipher__cipher_extract_and_operate_memory` | `mcp__lossless-claude__lcm_store` |
| `mcp__cipher__cipher_store_reasoning_memory` | `mcp__lossless-claude__lcm_store` |
| `mcp__cipher__cipher_*` (wildcard in allowedTools) | `mcp__lossless-claude__lcm_*` |
| `cipher_store_reasoning_memory` | `lcm_store(text, ["reasoning"])` |
| `cipher_workspace_store` | `lcm_store(text, ["workspace"])` |
| `cipher_search_reasoning_patterns` | `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })` |
| `cipher_workspace_search` | `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })` |
| `cipher_evaluate_reasoning` | retrieve patterns with `lcm_search` → Claude evaluates inline |
| `cipher_extract_reasoning_steps` | Claude extracts inline → `lcm_store(steps, ["reasoning"])` |
| `cipher_extract_and_operate_memory` | inline extraction → `lcm_store(summary, [tag])` (see Extraction Pattern below) |
| `cipher_bash` | remove; use Bash directly |
| `Cipher MCP` / `Cipher` (as memory system name) | `lossless-claude` |

### Extraction Pattern

For every file that previously called `cipher_extract_and_operate_memory`, replace the call instruction with:

```
Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the
summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store.
```

Tags by context:
- `["workspace"]` — `collab`, `knowledge-handoff` (cross-agent state)
- `["workspace", "index"]` — `index.md` per-module loop
- `["session"]` — everything else (`analyze`, `implement`, `investigate`, `briefing`, `curate`, `design`, `todo-killer`, `track`)

### Availability Sentinel Pattern

Replace all checks for `mcp__cipher__cipher_memory_search` in availability/health-check prose with `mcp__lossless-claude__lcm_search`.

For `doctor.md` (both command and skill), replace the single-mode check with:
```
Check if mcp__lossless-claude__lcm_search is present in the available tool list:
- Tool absent → lossless-claude MCP not registered. Fix: add lossless-claude entry to .claude/mcp.json
- Tool present but call returns error → lossless-claude daemon not running. Fix: lossless-claude daemon start
```

---

## Chunk 1: Phase 1 — Config & Authority Files

### Task 1: Update `.claude/mcp.json`

**Files:**
- Modify: `.claude/mcp.json`

- [ ] **Step 1: Verify current state**

```bash
grep -c "cipher" .claude/mcp.json
```
Expected: non-zero (confirms Cipher entry exists)

- [ ] **Step 2: Replace the cipher MCP entry**

Open `.claude/mcp.json`. The full file should become:

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

Note: Remove any other keys that were Cipher-specific (env vars for Qdrant, embedding provider, etc.). The lossless-claude daemon manages its own config independently.

- [ ] **Step 3: Verify**

```bash
grep "cipher" .claude/mcp.json
```
Expected: no output

- [ ] **Step 4: Sentinel verification (REQUIRED before Phase 2)**

Start a Claude Code session in this project. In the session, type:

```
What MCP tools do you have available? List all mcp__ prefixed tools.
```

Confirm: the tool list includes `mcp__lossless-claude__lcm_search` (hyphen preserved).

If it shows `mcp__lossless_claude__lcm_search` (underscore) instead, update the substitution reference table above — replace `mcp__lossless-claude__` with `mcp__lossless_claude__` — before proceeding.

- [ ] **Step 5: Commit**

```bash
git add .claude/mcp.json
git commit -m "feat: replace Cipher MCP registration with lossless-claude"
```

---

### Task 2: Update `techpack.yaml`

**Files:**
- Modify: `techpack.yaml`

- [ ] **Step 1: Verify current state**

```bash
grep -n "cipher\|qdrant" techpack.yaml
```
Expected: shows `cipher` mcpServer entry and `qdrant` brew entry

- [ ] **Step 2: Remove cipher and qdrant entries**

In `techpack.yaml`, find and delete the entire `qdrant` brew entry block:
```yaml
  - id: qdrant
    type: brew
    package: qdrant
    description: "Vector database for Cipher semantic memory"
```

Find and delete the entire `cipher` mcpServer entry block:
```yaml
  - id: cipher
    type: mcpServer
    command: "npx -y @byterover/cipher"
    env:
      QDRANT_URL: "http://localhost:6333"
      CIPHER_COLLECTION: "__TEAM_NAME__-memory"
```

- [ ] **Step 3: Add lossless-claude entry**

In the same `mcpServers` section (or equivalent), add:
```yaml
  - id: lossless-claude
    type: mcpServer
    command: "lossless-claude"
    args: ["mcp"]
    description: "Two-layer memory MCP server (episodic SQLite + semantic Qdrant)"
```

- [ ] **Step 4: Verify**

```bash
grep "cipher\|qdrant" techpack.yaml
```
Expected: no output (or only in comments/docs sections, not in the MCP entries)

- [ ] **Step 5: Commit**

```bash
git add techpack.yaml
git commit -m "feat: replace Cipher/Qdrant techpack deps with lossless-claude"
```

---

### Task 3: Rewrite `templates/instructions.md`

**Files:**
- Modify: `templates/instructions.md`

This file is the CLAUDE.local.md template installed for each team. It currently describes all Cipher tools and the decision protocol. The "Cipher MCP Tools" section needs a full rewrite.

- [ ] **Step 1: Verify current state**

```bash
grep -c "cipher" templates/instructions.md
```
Expected: non-zero

- [ ] **Step 2: Replace the memory system description**

Find the section heading `## Cipher MCP Tools` and rename it to `## lossless-claude Memory Tools`.

Replace the intro sentence (currently "You have access to the following Cipher MCP tools...") with:

```markdown
You have access to lossless-claude MCP tools for memory storage and retrieval. lossless-claude
uses a two-layer model:

**Episodic** (`layers: ["episodic"]`) — SQLite-backed per-session history. Fast full-text search.
Use for recent in-session context. Access via `lcm_grep(query)` or
`lcm_search(query, { layers: ["episodic"] })`.

**Semantic** (`layers: ["semantic"]`) — Qdrant-backed persistent cross-session memory. Vector
similarity search. Use for past decisions, team conventions, reasoning patterns.
Access via `lcm_search(query, { layers: ["semantic"] })`.

**Hybrid (default)** — `lcm_search(query)` with no `layers` arg searches both layers.
```

- [ ] **Step 3: Replace the tool list**

Replace the old tool bullet list (cipher_memory_search, cipher_extract_and_operate_memory, etc.) with:

```markdown
### Memory Tools

- **lcm_store** — Persist a memory. Signature: `lcm_store(text, tags?, metadata?)`
  - Use tags to categorize: `["reasoning"]` for decisions/tradeoffs, `["workspace"]` for
    cross-agent state, `["session"]` for general task outcomes.
  - Before storing: extract key learnings as a 3-7 bullet summary. Do not pass raw
    conversation content to lcm_store.

- **lcm_search** — Hybrid or layer-targeted search. `lcm_search(query, { layers?, tags?, limit?, threshold? })`
  - Use `layers: ["semantic"]` for cross-session knowledge.
  - Use `layers: ["episodic"]` for in-session context.
  - Omit `layers` for general-purpose hybrid search.

- **lcm_grep** — Fast FTS5 full-text search within the episodic layer. Prefer over `lcm_search`
  for exact strings (function names, error codes, commit hashes).

- **lcm_expand** — Drill into a summary node to recover original messages.

- **lcm_describe** — Describe a conversation or summary node by ID.
```

- [ ] **Step 4: Replace the decision protocol table**

Find the decision table (the `| Situation | Action |` table). Replace all Cipher tool references:

| Old cell | New cell |
|---|---|
| `cipher_memory_search` for related past work | `lcm_search(query)` for related past work |
| `cipher_search_reasoning_patterns` for similar past decisions | `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })` |
| `cipher_evaluate_reasoning` to check against known patterns | `lcm_search` to retrieve patterns → evaluate inline |
| `cipher_extract_and_operate_memory` to capture learnings | Extract 3-7 bullet summary → `lcm_store(summary, ["session"])` |
| `cipher_store_reasoning_memory` to record the reasoning chain | `lcm_store(text, ["reasoning"])` |
| `cipher_memory_search` to check if this was seen before | `lcm_search(query)` |
| `cipher_memory_search` for team conventions and patterns | `lcm_search(query)` |

Remove the `cipher_bash` row entirely.

- [ ] **Step 5: Verify**

```bash
grep -i "cipher" templates/instructions.md
```
Expected: no output

- [ ] **Step 6: Commit**

```bash
git add templates/instructions.md
git commit -m "docs: replace Cipher tool docs with lossless-claude in CLAUDE.local.md template"
```

---

## Chunk 2: Phase 2 — Commands (21 files)

> All files are in `plugin/commands/`. All 21 must be checked — even "mechanical substitution" files may have sentinel strings or tool name references embedded in prose.

### Task 4: Availability-check commands

**Files:** `doctor.md`, `status.md`, `setup.md`, `init.md` (not `help.md` — handled in Task 8)

These files contain availability sentinel checks and/or MCP health descriptions.

- [ ] **Step 1: Verify cipher references exist**

```bash
grep -l "cipher" plugin/commands/doctor.md plugin/commands/status.md plugin/commands/setup.md plugin/commands/init.md
```
Expected: all 4 files listed

- [ ] **Step 2: Update `plugin/commands/doctor.md`**

Find the Cipher availability check section. Replace the single-mode check with the two-failure-mode diagnostic:

```
Check if mcp__lossless-claude__lcm_search is present in the available tool list:
- Tool absent → lossless-claude MCP not registered. Fix: update .claude/mcp.json with the
  lossless-claude entry (command: lossless-claude, args: [mcp])
- Tool present but call returns error → daemon not running. Fix: lossless-claude daemon start
```

Apply all other substitutions from the Substitution Reference.

- [ ] **Step 3: Update `plugin/commands/status.md`**

Line 49: `cipher_memory_search` with query `"xgh health check"` → `lcm_search("xgh health check")`
Line 77: `Cipher MCP | Connected/Disconnected` row → `lossless-claude MCP | Connected/Disconnected`

Apply all other substitutions.

- [ ] **Step 4: Update `plugin/commands/setup.md`**

Update the supported MCP servers list (Cipher → lossless-claude). Apply all substitutions.

- [ ] **Step 5: Update `plugin/commands/init.md`**

Update MCP connection verification to check for lossless-claude instead of Cipher. Apply all substitutions.

- [ ] **Step 6: Verify**

```bash
grep -l "cipher" plugin/commands/doctor.md plugin/commands/status.md plugin/commands/setup.md plugin/commands/init.md
```
Expected: no files listed

- [ ] **Step 7: Commit**

```bash
git add plugin/commands/doctor.md plugin/commands/status.md plugin/commands/setup.md plugin/commands/init.md
git commit -m "feat: migrate availability-check commands from Cipher to lossless-claude"
```

---

### Task 5: Mid-flow extraction commands

**Files:** `analyze.md`, `implement.md`, `investigate.md`

These files call `cipher_extract_and_operate_memory` mid-flow (during task execution, not only at wrap-up). The extraction pattern must be inserted at the exact point where the old call appeared, with a `["session"]` tag.

- [ ] **Step 1: Verify cipher references exist**

```bash
grep -c "cipher" plugin/commands/analyze.md plugin/commands/implement.md plugin/commands/investigate.md
```
Expected: non-zero counts for each file

- [ ] **Step 2: Update `plugin/commands/analyze.md`**

Find every `cipher_extract_and_operate_memory` call instruction. Replace each with:
```
Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the
summary text and tags ["session"]. Do not pass raw conversation content to lcm_store.
```

Replace the Cipher availability check (Step 1 of the analyze flow):
- Old: Check if `mcp__cipher__cipher_memory_search` is available → Cipher ✓/✗
- New: Check if `mcp__lossless-claude__lcm_search` is available → lossless-claude ✓/✗
- Update the print statement: `lossless-claude MCP ✓ available` or `lossless-claude MCP ⚠ not available — skipping vector ops`

Update `--allowedTools "mcp__cipher__*,Bash,..."` → `--allowedTools "mcp__lossless-claude__lcm_*,Bash,..."`

Update the `requires:` list at the top of the file:
- `mcp__cipher__cipher_memory_search` → `mcp__lossless-claude__lcm_search`
- `mcp__cipher__cipher_extract_and_operate_memory` → `mcp__lossless-claude__lcm_store`

Apply all remaining substitutions.

- [ ] **Step 3: Update `plugin/commands/implement.md`**

Find `cipher_extract_and_operate_memory` call sites (there may be multiple — grep first):
```bash
grep -n "cipher_extract_and_operate_memory" plugin/commands/implement.md
```
Replace each with the extraction pattern using `["session"]` tag.

Apply all remaining substitutions.

- [ ] **Step 4: Update `plugin/commands/investigate.md`**

```bash
grep -n "cipher_extract_and_operate_memory" plugin/commands/investigate.md
```
Replace each with the extraction pattern using `["session"]` tag.

Apply all remaining substitutions.

- [ ] **Step 5: Verify**

```bash
grep "cipher" plugin/commands/analyze.md plugin/commands/implement.md plugin/commands/investigate.md
```
Expected: no output

- [ ] **Step 6: Commit**

```bash
git add plugin/commands/analyze.md plugin/commands/implement.md plugin/commands/investigate.md
git commit -m "feat: migrate mid-flow extraction commands from Cipher to lossless-claude"
```

---

### Task 6: End-of-task extraction commands (workspace callers)

**Files:** `collab.md`, `xgh-collaborate.md`

These files store cross-agent state at end-of-task — use `["workspace"]` tag.

- [ ] **Step 1: Find all cipher_extract_and_operate_memory call sites**

```bash
grep -n "cipher_extract_and_operate_memory\|cipher_store_reasoning_memory\|cipher_memory_search\|cipher_workspace" plugin/commands/collab.md plugin/commands/xgh-collaborate.md
```

- [ ] **Step 2: Update `plugin/commands/collab.md`**

Replace `cipher_extract_and_operate_memory` call instruction (end-of-task):
```
Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the
summary text and tags ["workspace"]. Do not pass raw conversation content to lcm_store.
```

`cipher_store_reasoning_memory` → `lcm_store(text, ["reasoning"])`
`cipher_memory_search` → `lcm_search(query)` (or `lcm_search` with appropriate options per context)
Update the tool reference table at the bottom.

Apply all remaining substitutions.

- [ ] **Step 3: Update `plugin/commands/xgh-collaborate.md`**

Apply the same pattern. Check if this file has Cipher workspace messaging protocol — update all references to Cipher workspace → lossless-claude memory.

- [ ] **Step 4: Verify**

```bash
grep "cipher" plugin/commands/collab.md plugin/commands/xgh-collaborate.md
```
Expected: no output

- [ ] **Step 5: Commit**

```bash
git add plugin/commands/collab.md plugin/commands/xgh-collaborate.md
git commit -m "feat: migrate collab commands from Cipher to lossless-claude"
```

---

### Task 7: End-of-task extraction commands (session callers)

**Files:** `brief.md`, `briefing.md`, `curate.md`, `design.md`, `todo-killer.md`, `track.md`

These store general task outcomes at wrap-up — use `["session"]` tag for `cipher_extract_and_operate_memory` replacements.

Note: `brief.md` and `briefing.md` are two separate files. `brief.md` is the `/xgh-brief` command; `briefing.md` is the `/xgh-briefing` command.

- [ ] **Step 1: Verify cipher references**

```bash
grep -l "cipher" plugin/commands/brief.md plugin/commands/briefing.md plugin/commands/curate.md plugin/commands/design.md plugin/commands/todo-killer.md plugin/commands/track.md
```

- [ ] **Step 2: For each file, apply substitutions**

For any `cipher_extract_and_operate_memory` call found (grep first with `-n` to locate):
```
Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the
summary text and tags ["session"]. Do not pass raw conversation content to lcm_store.
```

For `curate.md` specifically (heavily Cipher-focused):
- All `cipher_extract_and_operate_memory` → extraction pattern + `lcm_store(summary, ["session"])`
- All `cipher_store_reasoning_memory` → `lcm_store(text, ["reasoning"])`
- All `cipher_memory_search` → `lcm_search(query)` or layer-targeted form per context
- Update the verification steps (the "Cipher search (title)" / "Cipher search (question)" checklist rows) → "lossless-claude search (title)" / "lossless-claude search (question)"
- Update section heading "Store in Cipher" → "Store in lossless-claude"

Apply all substitutions from the reference table to all 6 files.

- [ ] **Step 3: Verify**

```bash
grep "cipher" plugin/commands/brief.md plugin/commands/briefing.md plugin/commands/curate.md plugin/commands/design.md plugin/commands/todo-killer.md plugin/commands/track.md
```
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add plugin/commands/brief.md plugin/commands/briefing.md plugin/commands/curate.md plugin/commands/design.md plugin/commands/todo-killer.md plugin/commands/track.md
git commit -m "feat: migrate end-of-task extraction commands from Cipher to lossless-claude"
```

---

### Task 8: Mechanical-substitution commands

**Files:** `ask.md`, `calibrate.md`, `help.md`, `index.md`, `profile.md`, `retrieve.md`

These files only use `cipher_memory_search` and similar read-path tools — no `cipher_extract_and_operate_memory` active call sites.

- [ ] **Step 1: Verify cipher references**

```bash
grep -l "cipher" plugin/commands/ask.md plugin/commands/calibrate.md plugin/commands/help.md plugin/commands/index.md plugin/commands/profile.md plugin/commands/retrieve.md
```

- [ ] **Step 2: Apply substitutions to each file**

For `plugin/commands/ask.md`:
- 3× `cipher_memory_search` → `lcm_search`
- `cipher_search_reasoning_patterns` → `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })`
- `cipher_evaluate_reasoning` → retrieve with `lcm_search` → Claude evaluates inline
- Update the scoring formula: `cipher_similarity` → `lcm_similarity`
- Update the output template: `Sources: Cipher (**N**)` → `Sources: lossless-claude (**N**)`

For `plugin/commands/calibrate.md`:
- `cipher_memory_search` → `lcm_search` for memory sampling

For `plugin/commands/help.md`:
- Lines 18-19: Update "Codebase indexed" check → `lcm_search` instead of `cipher_memory_search`
- Update "MCP connections" check to reference lossless-claude instead of Cipher
- Apply all other substitutions

For `plugin/commands/index.md`:
- Apply mechanical substitutions; if `cipher_extract_and_operate_memory` appears as an active call, apply extraction pattern with `["workspace", "index"]` tag

For `plugin/commands/profile.md`:
- `cipher_memory_search` → `lcm_search`
- `mcp__cipher__cipher_store_reasoning_memory` → `mcp__lossless-claude__lcm_store`

For `plugin/commands/retrieve.md`:
- Apply all substitutions from the reference table

- [ ] **Step 3: Verify**

```bash
grep "cipher" plugin/commands/ask.md plugin/commands/calibrate.md plugin/commands/help.md plugin/commands/index.md plugin/commands/profile.md plugin/commands/retrieve.md
```
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add plugin/commands/ask.md plugin/commands/calibrate.md plugin/commands/help.md plugin/commands/index.md plugin/commands/profile.md plugin/commands/retrieve.md
git commit -m "feat: migrate mechanical-substitution commands from Cipher to lossless-claude"
```

---

### Task 8b: Phase 2 gate — verify all 21 command files clean

This must run after Task 8 and before Phase 3 begins.

- [ ] **Step 1: Phase 2 final verification**

```bash
grep -rl "cipher" plugin/commands/
```
Expected: **no output** — if any files are listed, go back and apply the substitution table to them before continuing.

---

## Chunk 3: Phase 3 — Skills (22 files)

> All paths are relative to `plugin/skills/`. Remember: `calibrate.md` and `doctor.md` exist in both `plugin/commands/` (done in Phase 2) and `plugin/skills/` (done here). Both locations are updated independently.

### Task 9: Availability/setup skills

**Files:** `doctor/doctor.md`, `mcp-setup/mcp-setup.md`, `init/init.md`, `calibrate/calibrate.md`

- [ ] **Step 1: Verify cipher references**

```bash
grep -l "cipher" plugin/skills/doctor/doctor.md plugin/skills/mcp-setup/mcp-setup.md plugin/skills/init/init.md plugin/skills/calibrate/calibrate.md
```

- [ ] **Step 2: Update `plugin/skills/doctor/doctor.md`**

Find the Cipher availability check instruction. Replace with two-failure-mode diagnostic (same pattern as Task 4, Step 2).

Update the sentinel: `mcp__cipher__cipher_memory_search` → `mcp__lossless-claude__lcm_search`

Apply all remaining substitutions.

- [ ] **Step 3: Update `plugin/skills/mcp-setup/mcp-setup.md`**

Find the Cipher row in the integration table:
```
| **Cipher** | `cipher_memory_search` | All xgh skills (core) | Installed by xgh |
```
Replace with:
```
| **lossless-claude** | `lcm_search` | All xgh skills (core) | Installed by xgh |
```

Update the sentinel detection list: `Cipher → cipher_memory_search` → `lossless-claude → lcm_search`

Update Cipher install instructions → lossless-claude registration block:
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

Add a "Verify lossless-claude" step:
```
Run lcm_search("xgh health check").
- Returns results or empty array → lossless-claude MCP ✓
- Tool absent → MCP not registered (update .claude/mcp.json)
- Returns error → daemon not running (run: lossless-claude daemon start)
```

Apply all remaining substitutions.

- [ ] **Step 4: Update `plugin/skills/init/init.md`**

Update the MCP verification step to check `mcp__lossless-claude__lcm_search` instead of Cipher.
Update the `cipher:` entry in the MCP check list:
```
- lossless-claude: "lossless-claude MCP — core memory (lcm_search)"
```

Apply all remaining substitutions.

- [ ] **Step 5: Update `plugin/skills/calibrate/calibrate.md`**

`cipher_memory_search` → `lcm_search` (for memory sampling). No structural change needed.
Apply all remaining substitutions.

- [ ] **Step 6: Verify**

```bash
grep "cipher" plugin/skills/doctor/doctor.md plugin/skills/mcp-setup/mcp-setup.md plugin/skills/init/init.md plugin/skills/calibrate/calibrate.md
```
Expected: no output

- [ ] **Step 7: Commit**

```bash
git add plugin/skills/doctor/doctor.md plugin/skills/mcp-setup/mcp-setup.md plugin/skills/init/init.md plugin/skills/calibrate/calibrate.md
git commit -m "feat: migrate availability/setup skills from Cipher to lossless-claude"
```

---

### Task 10: Mid-flow extraction skills

**Files:** `analyze/analyze.md`, `implement/implement.md`, `investigate/investigate.md`, `index/index.md`

- [ ] **Step 1: Find all active cipher_extract_and_operate_memory call sites**

```bash
grep -n "cipher_extract_and_operate_memory" plugin/skills/analyze/analyze.md plugin/skills/implement/implement.md plugin/skills/investigate/investigate.md plugin/skills/index/index.md
```

- [ ] **Step 2: Update `plugin/skills/analyze/analyze.md`**

Apply the same changes as Task 5 Step 2 (this file is the skill version of the analyze command).

Key points:
- `requires:` list at top: `mcp__cipher__cipher_memory_search` → `mcp__lossless-claude__lcm_search`, `mcp__cipher__cipher_extract_and_operate_memory` → `mcp__lossless-claude__lcm_store`
- Availability check step: update sentinel and print messages
- `cipher_extract_and_operate_memory` mid-flow → extraction pattern + `lcm_store(summary, ["session"])`
- All other substitutions

- [ ] **Step 3: Update `plugin/skills/implement/implement.md`**

```bash
grep -n "mcp__cipher__\|cipher_" plugin/skills/implement/implement.md | head -20
```

Replace `cipher_extract_and_operate_memory` at each active call site with extraction pattern + `lcm_store(summary, ["session"])`.
Apply all remaining substitutions including `mcp__cipher__cipher_memory_search` → `mcp__lossless-claude__lcm_search`.

- [ ] **Step 4: Update `plugin/skills/investigate/investigate.md`**

Same pattern as implement. `cipher_extract_and_operate_memory` → extraction + `lcm_store(summary, ["session"])`.
Apply all remaining substitutions.

- [ ] **Step 5: Update `plugin/skills/index/index.md`** (mid-flow loop caller)

This file calls `cipher_extract_and_operate_memory` in a loop over modules/packages. The loop body instruction must include the extraction pattern.

```bash
grep -n "cipher_extract_and_operate_memory\|per area\|per.area\|For each" plugin/skills/index/index.md
```

Replace the loop-body call with:
```
For each module, extract key learnings as a concise summary (3-7 bullets), then call
lcm_store with the summary text and tags ["workspace", "index"].
Do not pass raw conversation content to lcm_store.
```

Update the `requires:` list and any memory-stored-via descriptions.
Apply all remaining substitutions.

- [ ] **Step 6: Verify**

```bash
grep "cipher" plugin/skills/analyze/analyze.md plugin/skills/implement/implement.md plugin/skills/investigate/investigate.md plugin/skills/index/index.md
```
Expected: no output

- [ ] **Step 7: Commit**

```bash
git add plugin/skills/analyze/analyze.md plugin/skills/implement/implement.md plugin/skills/investigate/investigate.md plugin/skills/index/index.md
git commit -m "feat: migrate mid-flow extraction skills from Cipher to lossless-claude"
```

---

### Task 11: End-of-task extraction skills (workspace callers)

**Files:** `collab/collab.md`, `knowledge-handoff/knowledge-handoff.md`

These store cross-agent state — use `["workspace"]` tag.

- [ ] **Step 1: Verify**

```bash
grep -c "cipher" plugin/skills/collab/collab.md plugin/skills/knowledge-handoff/knowledge-handoff.md
```

- [ ] **Step 2: Update `plugin/skills/collab/collab.md`**

`cipher_extract_and_operate_memory` (end-of-task wrap-up) → extraction pattern + `lcm_store(summary, ["workspace"])`
`cipher_store_reasoning_memory` → `lcm_store(text, ["reasoning"])`
`cipher_memory_search` → `lcm_search(query)` (or workspace-scoped form per context)
Update the tool reference table at the bottom of the file.

Apply all remaining substitutions.

- [ ] **Step 3: Update `plugin/skills/knowledge-handoff/knowledge-handoff.md`**

```bash
grep -n "cipher_" plugin/skills/knowledge-handoff/knowledge-handoff.md
```

`cipher_extract_and_operate_memory` → extraction pattern + `lcm_store(summary, ["workspace"])`
`cipher_store_reasoning_memory` → `lcm_store(text, ["reasoning"])`
`cipher_memory_search` → `lcm_search(query)`
Update tool reference table.

- [ ] **Step 4: Verify**

```bash
grep "cipher" plugin/skills/collab/collab.md plugin/skills/knowledge-handoff/knowledge-handoff.md
```
Expected: no output

- [ ] **Step 5: Commit**

```bash
git add plugin/skills/collab/collab.md plugin/skills/knowledge-handoff/knowledge-handoff.md
git commit -m "feat: migrate workspace-state skills from Cipher to lossless-claude"
```

---

### Task 12: End-of-task extraction skills (session callers)

**Files:** `briefing/briefing.md`, `curate/curate.md`, `design/design.md`, `todo-killer/todo-killer.md`, `track/track.md`

Use `["session"]` tag for all `cipher_extract_and_operate_memory` replacements.

**Note:** `briefing/briefing.md` is an **extraction caller** — it has an active `cipher_extract_and_operate_memory` call in its wrap-up step. The spec's Phase 3 "all others" list mistakenly included it; the extraction-before-store pattern applies here. This plan takes precedence.

- [ ] **Step 1: Verify**

```bash
grep -l "cipher" plugin/skills/briefing/briefing.md plugin/skills/curate/curate.md plugin/skills/design/design.md plugin/skills/todo-killer/todo-killer.md plugin/skills/track/track.md
```

- [ ] **Step 2: Apply substitutions to each file**

For each file, grep first to locate all active call sites:
```bash
grep -n "cipher_" plugin/skills/briefing/briefing.md
```

For `brief.md`:
- Grep first: `grep -n "cipher_" plugin/commands/brief.md`
- Apply full substitution table; `cipher_extract_and_operate_memory` if present → extraction + `lcm_store(summary, ["session"])`
- Update availability detection to reference lossless-claude instead of Cipher

For `briefing/briefing.md`:
- `cipher_extract_and_operate_memory` (store session start state) → extraction + `lcm_store(summary, ["session"])`
- All `cipher_memory_search` → `lcm_search(query)` (with appropriate options per context)
- Update `requires:` list

For `curate/curate.md`:
- `cipher_extract_and_operate_memory` → extraction + `lcm_store(summary, ["session"])`
- `cipher_store_reasoning_memory` → `lcm_store(text, ["reasoning"])`
- `cipher_memory_search` → `lcm_search(query)` (verification calls → use hybrid default)
- Update verification checklist rows: "Cipher search (title/question)" → "lossless-claude search (title/question)"
- Update heading "Store in Cipher" → "Store in lossless-claude"
- Update `requires:` list

For `design/design.md`, `todo-killer/todo-killer.md`, `track/track.md`:
- Apply full substitution table; use `["session"]` for any `cipher_extract_and_operate_memory` replacements
- Update `requires:` lists

- [ ] **Step 3: Verify**

```bash
grep "cipher" plugin/skills/briefing/briefing.md plugin/skills/curate/curate.md plugin/skills/design/design.md plugin/skills/todo-killer/todo-killer.md plugin/skills/track/track.md
```
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add plugin/skills/briefing/briefing.md plugin/skills/curate/curate.md plugin/skills/design/design.md plugin/skills/todo-killer/todo-killer.md plugin/skills/track/track.md
git commit -m "feat: migrate session-capture skills from Cipher to lossless-claude"
```

---

### Task 13: Mechanical-substitution skills

**Files:** `ask/ask.md`, `pr-context-bridge/pr-context-bridge.md`, `profile/profile.md`, `retrieve/retrieve.md`

- [ ] **Step 1: Verify**

```bash
grep -l "cipher" plugin/skills/ask/ask.md plugin/skills/pr-context-bridge/pr-context-bridge.md plugin/skills/profile/profile.md plugin/skills/retrieve/retrieve.md
```

- [ ] **Step 2: Apply substitutions**

For `ask/ask.md`:
- `cipher_memory_search` (3 occurrences) → `lcm_search(query)` or with options per context
- `cipher_search_reasoning_patterns` → `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })`
- `cipher_evaluate_reasoning` → retrieve with `lcm_search` → Claude evaluates inline
- `cipher_similarity` scoring formula → `lcm_similarity`

For `pr-context-bridge/pr-context-bridge.md`:
- All `cipher_store_reasoning_memory` → `lcm_store(text, ["reasoning"])`
- All `cipher_memory_search` → `lcm_search(query)` or layer-targeted per context
- Update tool reference table

For `profile/profile.md`:
- `cipher_memory_search` → `lcm_search(query)`
- `mcp__cipher__cipher_store_reasoning_memory` → `mcp__lossless-claude__lcm_store`

For `retrieve/retrieve.md`:
- Apply full substitution table

- [ ] **Step 3: Verify**

```bash
grep "cipher" plugin/skills/ask/ask.md plugin/skills/pr-context-bridge/pr-context-bridge.md plugin/skills/profile/profile.md plugin/skills/retrieve/retrieve.md
```
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add plugin/skills/ask/ask.md plugin/skills/pr-context-bridge/pr-context-bridge.md plugin/skills/profile/profile.md plugin/skills/retrieve/retrieve.md
git commit -m "feat: migrate mechanical-substitution skills from Cipher to lossless-claude"
```

---

### Task 14: Team skills (nested)

**Files:** `team/cross-team-pollinator/cross-team-pollinator.md`, `team/onboarding-accelerator/onboarding-accelerator.md`, `team/subagent-pair-programming/subagent-pair-programming.md`

Note: `cipher_extract_and_operate_memory` appears only in the tool-reference summary tables in these files (not as active procedure call sites). Apply mechanical substitutions only — no extraction-before-store pattern needed.

- [ ] **Step 1: Confirm extraction calls are table-only**

```bash
grep -n "cipher_extract_and_operate_memory" plugin/skills/team/cross-team-pollinator/cross-team-pollinator.md plugin/skills/team/onboarding-accelerator/onboarding-accelerator.md plugin/skills/team/subagent-pair-programming/subagent-pair-programming.md
```

Expected: references appear only in `| tool | description |` table rows, not in procedural steps.

If any appear in numbered/bulleted procedural steps, apply the extraction pattern with `["session"]` tag at those locations before proceeding.

- [ ] **Step 2: Apply substitutions to `cross-team-pollinator.md`**

`cipher_store_reasoning_memory` → `lcm_store(text, ["reasoning"])`
`cipher_memory_search` → `lcm_search(query)` (update both same-scope and cross-scope calls)
`cipher_extract_and_operate_memory` in table → `lcm_store`
Update the tool reference table at the bottom.

- [ ] **Step 3: Apply substitutions to `onboarding-accelerator.md`**

All `cipher_memory_search` (5 occurrences) → `lcm_search(query)` (with appropriate layer/tag options per context)
`cipher_store_reasoning_memory` → `lcm_store(text, ["reasoning"])`
`cipher_extract_and_operate_memory` in table → `lcm_store`
Update tool reference table.

- [ ] **Step 4: Apply substitutions to `subagent-pair-programming.md`**

All `cipher_store_reasoning_memory` (8 occurrences) → `lcm_store(text, ["reasoning"])`
All `cipher_memory_search` (3 occurrences) → `lcm_search(query)` or layer-targeted per context
`cipher_extract_and_operate_memory` in table → `lcm_store`
Update tool reference table.

- [ ] **Step 5: Verify**

```bash
grep "cipher" plugin/skills/team/cross-team-pollinator/cross-team-pollinator.md plugin/skills/team/onboarding-accelerator/onboarding-accelerator.md plugin/skills/team/subagent-pair-programming/subagent-pair-programming.md
```
Expected: no output

- [ ] **Step 6: Commit**

```bash
git add plugin/skills/team/cross-team-pollinator/cross-team-pollinator.md plugin/skills/team/onboarding-accelerator/onboarding-accelerator.md plugin/skills/team/subagent-pair-programming/subagent-pair-programming.md
git commit -m "feat: migrate team skills from Cipher to lossless-claude"
```

---

### Task 15: Final verification

- [ ] **Step 1: Verify zero cipher_ references remain in plugin/**

```bash
grep -rl "cipher" plugin/skills/ plugin/commands/
```
Expected: **no output** — zero files

- [ ] **Step 2: Verify success criteria from spec**

```bash
# Criterion 1: mcp.json has lossless-claude, no cipher
grep "cipher" .claude/mcp.json && echo "FAIL" || echo "PASS: no cipher in mcp.json"
grep "lossless-claude" .claude/mcp.json && echo "PASS: lossless-claude present" || echo "FAIL"

# Criterion 2: techpack.yaml has no cipher/qdrant MCP entries
grep -E "id: cipher|id: qdrant" techpack.yaml && echo "FAIL" || echo "PASS"

# Criterion 3: no cipher_ in skills/commands (recursive)
grep -rl "cipher_" plugin/skills/ plugin/commands/ && echo "FAIL" || echo "PASS: clean"

# Criterion 4: templates/instructions.md has all five lossless-claude tools documented
for tool in lcm_store lcm_search lcm_grep lcm_expand lcm_describe; do
  grep -q "$tool" templates/instructions.md && echo "PASS: $tool present" || echo "FAIL: $tool missing"
done

# Criterion 5: all sentinels updated
grep -rl "mcp__cipher__cipher_memory_search" plugin/skills/ plugin/commands/ && echo "FAIL" || echo "PASS: sentinels updated"

# Criterion 6: extraction pattern anchors present at active call sites
# Active callers: analyze (×2 cmd+skill), implement (×2), investigate (×2), index (×2),
#   briefing, collab, curate, design, knowledge-handoff, todo-killer, track = 13 files
grep -rl "cipher_extract_and_operate_memory" plugin/skills/ plugin/commands/ && echo "WARNING: unreplaced extract calls remain" || echo "PASS"
echo "--- '3-7 bullets' anchor count (expected 15) ---"
grep -rl "3-7 bullets" plugin/skills/ plugin/commands/ | wc -l
echo "--- 'Do not pass raw conversation content to lcm_store' anchor count (expected 15) ---"
grep -rl "Do not pass raw conversation content to lcm_store" plugin/skills/ plugin/commands/ | wc -l
```

Both `wc -l` counts should be **15**:
- `analyze`, `implement`, `investigate`, `index` each have a command file AND a skill file = 8 files
- `briefing`, `collab`, `curate`, `design`, `todo-killer`, `track` have command files only = 6 files
- `knowledge-handoff` exists as a skill file only = 1 file
- Total = 8 + 6 + 1 = **15 files**

If either count differs from 15, audit the outlier files before declaring success.

- [ ] **Step 3: Also check CLAUDE.local.md template**

```bash
grep -i "cipher" templates/instructions.md && echo "FAIL" || echo "PASS"
```

- [ ] **Step 4: Final commit**

```bash
git add -A
git status  # confirm nothing unexpected is staged
git commit -m "feat: complete lossless-claude migration — all Cipher references replaced

Replaces @byterover/cipher with @extreme-go-horse/lossless-claude across:
- .claude/mcp.json, techpack.yaml, templates/instructions.md
- 21 plugin/commands/ files
- 22 plugin/skills/ files (including 3 nested team skills)

Full tool mapping in .xgh/specs/2026-03-17-lossless-claude-migration-design.md"
```
