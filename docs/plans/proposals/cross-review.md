# Cross-Review: 5 xgh Feature PRDs

**Reviewer:** Product Architect (via Claude Code)
**Date:** 2026-03-15
**PRDs Reviewed:**

1. **Momentum** — session continuity (capture/restore)
2. **Memory Replay** — chronological decision narratives
3. **Repo Whisperer** — git history as living context
4. **Context Drops** — shareable knowledge snapshots
5. **Deja Vu** — push-based warnings from past failures

---

## 1. Synergies

These are concrete producer/consumer relationships where features amplify each other.

| # | Feature A (Producer) | Feature B (Consumer) | What | Impact |
|---|---------------------|---------------------|------|--------|
| S1 | **Momentum** (M-P0-01, M-P0-11) | **Memory Replay** (R-P0-02 GATHER) | Momentum captures `open_decisions` with leanings and reasons at session end. These become Cipher memories tagged `type: momentum-session`. Memory Replay's GATHER phase pulls these as source material for decision timelines. | High. Momentum is a continuous decision-capture pipeline that feeds Replay's reconstruction engine. Without Momentum, Replay relies on ad-hoc `/xgh-curate` for decision provenance. |
| S2 | **Repo Whisperer** (RW-P0-03, RW-P0-04) | **Memory Replay** (R-P0-02 GATHER) | Whisperer classifies git history chunks as `decision`, `tradeoff`, `constraint`, `revert-reason` and stores them in Cipher with `type: repo-whisperer`. Replay's GATHER can query these alongside manual memories for richer timelines. | High. Whisperer gives Replay access to decisions that were never explicitly stored by a human — only expressed in commit messages and PR threads. |
| S3 | **Repo Whisperer** (RW-P0-03) | **Deja Vu** (DV-P0-05) | Whisperer's `revert-reason` and `bug-fix-rationale` classifications are natural pattern candidates for Deja Vu. A reverted commit with a classified reason is exactly the "past failure" Deja Vu needs. | High. Whisperer automates Deja Vu pattern seeding from git history — every revert becomes a potential warning. |
| S4 | **Momentum** (M-P0-01) | **Deja Vu** (DV-P0-05) | Momentum's `blockers` and `open_decisions` capture the context of what went wrong or was uncertain. When a session's blocker is later resolved, the blocker-to-resolution arc is a Deja Vu pattern candidate. | Medium. Requires a P2 integration to automatically promote blocker resolutions to patterns, but the data format is already compatible. |
| S5 | **Memory Replay** (R-P0-05 CACHE) | **Context Drops** (CD-P0-04) | Cached replays live in `.xgh/context-tree/replays/` as markdown with standard frontmatter. The Drop Compiler already exports context tree subsets. Replays are naturally exportable as drop content. | High. A "project onboarding drop" can include pre-built replays, giving a new contributor decision history on day zero. |
| S6 | **Context Drops** (CD-P0-02) | **Deja Vu** (DV-P0-05) | When a drop is absorbed, its reasoning chains and vector memories enter Cipher. If those memories include failure patterns, Deja Vu can match against them — inheriting another project's hard-won warnings. | High. Cross-project failure transfer: "Project A learned this the hard way, now Project B's agent will warn before repeating it." |
| S7 | **Repo Whisperer** (RW-P0-06 context tree output) | **Momentum** (M-P0-04 SessionStart) | Whisperer writes decision/convention files to `.xgh/context-tree/repo-history/`. These are loaded by SessionStart's existing scoring. Momentum's briefing benefits from richer context tree entries without additional integration. | Medium. Indirect but valuable — Momentum briefings are more informed when the context tree has deeper historical context. |
| S8 | **Deja Vu** (DV-P0-03 warnings) | **Memory Replay** (R-P1-03 conflict detection) | When Deja Vu fires a warning, the developer's response (dismiss, accept, resolve) creates a new memory. If that response conflicts with an existing replay narrative, Replay's conflict detection (R-P1-03) can flag it. | Low (P1+). Both features need to mature before this synergy is useful. |
| S9 | **Momentum** (M-P1-04 multi-branch tracking) | **Repo Whisperer** (RW-P0-07 incremental ingestion) | Momentum knows which branches the developer is active on. Whisperer could prioritize incremental ingestion for active branches, avoiding wasted compute on branches the developer has not touched in weeks. | Low. Optimization opportunity, not a core synergy. |

---

## 2. Duplications

These are areas where multiple PRDs solve the same problem independently or build overlapping infrastructure.

| # | What's Duplicated | PRDs Involved | Severity | Recommended Resolution |
|---|------------------|---------------|----------|----------------------|
| D1 | **`prompt-submit.sh` extensions — 4 features want to extend the same hook** | Momentum (capture trigger detection), Repo Whisperer (history hints), Memory Replay (staleness check + "why" suggestion), Deja Vu (signal extraction + pattern matching) | **Critical.** Four independent extensions to one hook file. Each adds latency. Combined worst-case: 50ms (existing) + 50ms (Momentum regex) + 200ms (Whisperer state.yaml lookup + Cipher metadata) + 200ms (Replay staleness check) + 350ms (Deja Vu extraction + Cipher query) = **~850ms per prompt**. This exceeds the 500ms perceptible-latency threshold. | **Extract a shared hook dispatch framework.** The `prompt-submit.sh` hook should become a dispatcher that runs registered modules in parallel (not serial). Each module returns its contribution to a merged JSON output. Modules that don't match exit immediately (<10ms). Budget: 500ms total wall-clock, not cumulative. See "Shared Infrastructure" section. |
| D2 | **`session-start.sh` extensions — 3 features extend this hook** | Momentum (snapshot restore, <500ms), Repo Whisperer (incremental ingestion, <500ms), Memory Replay (implicit — cached replays scored by context tree) | **High.** Three features add logic to session start. Momentum adds YAML read + git status. Whisperer adds git log comparison + background spawn. Both claim <500ms budgets independently, but combined they could push session start past 1s. | **Establish a session-start budget allocation.** Total session-start hook budget: 800ms. Allocate: existing context tree (200ms) + Momentum restore (300ms) + Whisperer incremental check (200ms) + headroom (100ms). Whisperer's heavy ingestion must remain background-only. Replay does not extend the hook (consumes via context tree scoring), so it stays at zero cost. |
| D3 | **Cipher memory tagging — overlapping `type` tags** | Momentum (`type: momentum-session`), Repo Whisperer (`type: repo-whisperer`), Memory Replay (queries all types), Deja Vu (`type: deja_vu_pattern`), Context Drops (imports with `source_drop` tag) | **Medium.** Each feature invents its own Cipher tagging convention. No shared schema for `type` values, metadata fields, or tag namespacing. Memory Replay's GATHER phase must know about all these types to build comprehensive timelines. | **Define a shared Cipher metadata schema.** All features should follow a common convention: `type` prefix (`momentum:session`, `whisperer:decision`, `whisperer:convention`, `deja-vu:pattern`), shared metadata fields (`created_at`, `source_module`, `project`, `confidence`), and a registry in `.xgh/config.yaml` that Memory Replay can enumerate. |
| D4 | **Decision extraction from git history — overlapping with different approaches** | Repo Whisperer (RW-P0-03 Chunker & Classifier: classifies commits as `decision`, `tradeoff`, etc.), Memory Replay (R-P0-02 GATHER: `git log --all --grep=<topic>` + commit/PR search) | **Medium.** Both features parse git history for decisions. Whisperer does it systematically (all commits, classified). Replay does it per-topic on demand. They could produce duplicate entries in Cipher — the same commit classified by Whisperer and also pulled by Replay's git gather. | **Make Replay consume Whisperer's output.** If Whisperer has already ingested git history, Replay's GATHER phase should query Cipher for `type: repo-whisperer` memories instead of running its own `git log` parsing. Replay's direct git search becomes a fallback for projects without Whisperer. Add to R-P0-02: "If `modules.whisperer.enabled`, prefer Cipher query over direct git log." |
| D5 | **Config namespace in `.xgh/config.yaml`** | All 5 PRDs (each creates `modules.<name>`) | **Low.** All features use `modules.*` in config, which is correct and consistent. But none define a shared schema for module config (e.g., required fields like `enabled`, `version`). | **Define a module config schema** with required fields: `enabled` (bool), `version` (string). Optional common fields: `archetype_default` (mapping), `performance_budget_ms` (int). Each module extends this base. |
| D6 | **Context tree output patterns — 3 features write to context tree** | Repo Whisperer (writes to `.xgh/context-tree/repo-history/`), Memory Replay (writes to `.xgh/context-tree/replays/`), Context Drops (imports to `.xgh/context-tree/` root) | **Low.** Different directories, no collision. But all three produce markdown files with frontmatter, and there is no shared template for frontmatter fields. The session-start scoring algorithm needs consistent frontmatter across all sources. | **Publish a context tree frontmatter schema** that all modules must follow: `title`, `importance` (1-10), `maturity` (draft/validated/canonical), `source_module`, `created_at`, `updated_at`. Each module can add custom fields. This ensures the session-start scoring works consistently. |
| D7 | **"Why is it like this?" answering — two features address this** | Repo Whisperer (proactive context injection via prompt-submit hook — surfaces git history when files are modified), Memory Replay (on-demand `/xgh-replay` — comprehensive decision narrative) | **Low.** Different trigger mechanisms (push vs. pull) and different depth (Whisperer: file-level hints; Replay: full topic narrative). They complement rather than compete. | **Clarify the handoff.** Whisperer's prompt-submit hint should suggest `/xgh-replay <topic>` when it detects deep history. Replay's "why" pattern detection (R-P0-06) should not duplicate Whisperer's hint. Add cross-reference: "If Whisperer already injected a history hint for this file, skip the Replay suggestion." |

---

## 3. Contradictions

These are conflicts where features make incompatible assumptions or compete for shared resources.

| # | What Conflicts | PRDs Involved | Severity | Recommended Resolution |
|---|---------------|---------------|----------|----------------------|
| C1 | **`UserPromptSubmit` hook architecture: extend-in-place vs. separate handler** | Repo Whisperer (extends `prompt-submit.sh` inline), Momentum (extends `prompt-submit.sh` inline), Memory Replay (extends `prompt-submit.sh` inline), Deja Vu (recommends separate `deja-vu-prompt-submit.sh` as a second handler — Q1 in open questions) | **Critical.** Three PRDs assume they will extend the existing hook script inline. Deja Vu recommends a separate handler. If all four extend inline, `prompt-submit.sh` becomes a 500-line monolith. If Deja Vu runs as a separate handler, Claude Code must merge JSON outputs from multiple handlers on the same event — **this capability is unverified** (Deja Vu Q1 flags this as an open question). | **Resolve the multi-handler question first.** Test whether Claude Code merges output from multiple `UserPromptSubmit` handlers. If yes: all features should register separate handlers (maximum modularity). If no: build the shared dispatcher (D1 resolution) as a single handler that loads module-specific logic. Either way, no feature should extend `prompt-submit.sh` inline — the file must remain a thin dispatcher. |
| C2 | **Cumulative `UserPromptSubmit` latency exceeds any individual budget** | Momentum (<50ms assumed), Repo Whisperer (<200ms for state lookup + Cipher query), Memory Replay (<200ms for staleness check), Deja Vu (<350ms for extraction + pattern match, P0 fast mode) | **Critical.** Each PRD specifies its own hook latency budget in isolation. None accounts for other features running on the same event. Deja Vu's non-negotiable: "<100ms when no match." Repo Whisperer's non-negotiable: "zero overhead when no data." But Replay's staleness check (read `_index.yaml` + semantic similarity) runs unconditionally at 200ms. Combined serial execution: 800ms+. | **Establish a global `UserPromptSubmit` budget of 500ms wall-clock** with per-module allocations. Modules run in parallel where possible. Staleness-check operations (Replay, Whisperer) that read local files can run concurrently with Deja Vu's Cipher query. Each module must have a fast-exit path (<10ms) when it has nothing to contribute. Specific fixes: Memory Replay (R-P0-06) must cache `_index.yaml` in memory after first read, not re-read per prompt. |
| C3 | **`SessionEnd` hook — contested ownership** | Momentum (M-P0-03: new `xgh-session-end-momentum.sh` for snapshot capture, <100ms), Deja Vu (DV-P0-05 mentions pattern extraction at session end during "existing post-session curation") | **Medium.** Momentum creates a new SessionEnd hook. Deja Vu's pattern extraction piggybacks on "existing post-session curation" — but there is no existing SessionEnd hook today. The "existing curation" is an agent-side behavior, not a hook. If both create SessionEnd handlers, the combined budget must be defined. | **Clarify Deja Vu's session-end mechanism.** Deja Vu should explicitly state whether it: (a) extends Momentum's SessionEnd hook, (b) registers its own separate SessionEnd handler, or (c) relies on agent-side instructions (not a hook). Recommendation: agent-side instruction is more reliable for pattern extraction (it needs access to session context that hooks cannot access). Momentum's hook handles git-state capture; Deja Vu's pattern extraction stays agent-side. |
| C4 | **Archetype tiering inconsistency — Repo Whisperer treats Solo Dev differently** | Repo Whisperer (Solo Dev: "Optional add-on, not installed by default"), Momentum (Solo Dev: Standard tier, installed), Memory Replay (Solo Dev: Standard, installed), Context Drops (Solo Dev: installed by default), Deja Vu (Solo Dev: enabled by default) | **Medium.** Four features consider Solo Dev a primary persona and install by default. Repo Whisperer excludes Solo Dev, calling it "Optional." But the Solo Dev persona ("The Past-Self Archaeologist") in the Whisperer PRD is one of its strongest use cases — a solo developer who forgets their own past decisions. | **Repo Whisperer should install for Solo Dev by default.** The "Past-Self Archaeologist" persona is compelling. A solo developer benefits enormously from automated git history extraction. The bootstrap operation (one-time, 5 minutes) is the only barrier, and it's a one-time cost. Change RW archetype tiering: Solo Dev from "Optional add-on" to "Default." |
| C5 | **Cipher collection strategy — shared vs. dedicated** | Deja Vu (Q2 recommends same collection with `type` tag filtering), Repo Whisperer (stores in main Cipher collection with `type: repo-whisperer`), Memory Replay (queries all types in main collection), Context Drops (imports into main collection with `source_drop` tag) | **Low.** All PRDs assume a single Cipher collection with tag filtering, which is consistent. But Deja Vu's Q2 explicitly debates a dedicated collection. If any feature switches to a dedicated collection, Memory Replay's GATHER phase breaks (it queries one collection). | **Standardize: single collection, tag-filtered.** All features MUST use the same Cipher collection. No dedicated collections. This is the only way Memory Replay can build comprehensive timelines. Add this as a platform constraint in the shared infrastructure spec. |
| C6 | **Hook output JSON schema — no merge specification** | All PRDs that extend hooks | **Medium.** Each feature adds its own key to the hook JSON output: Momentum (`momentumBriefing`), Whisperer (`whispererStatus`, `whisperHint`, `whisperWarning`), Replay (none — consumes only), Deja Vu (`dejaVuWarning`). But no PRD defines how Claude Code merges these keys if multiple handlers return separate JSON objects. | **Define a hook output envelope schema.** All hook handlers contribute to a shared output envelope: `{ "result": "...", "modules": { "momentum": {...}, "whisperer": {...}, "deja-vu": {...} } }`. The dispatcher (D1 resolution) is responsible for assembling this envelope. Each module returns its contribution under its own namespace key. |

---

## 4. Recommended Build Order

Based on dependency analysis, shared infrastructure needs, and data-flow direction (producers before consumers):

### Phase 0: Shared Infrastructure (1-2 days)

Build the platform components that multiple features depend on. Without these, every feature builds its own version.

1. **Hook dispatch framework** for `UserPromptSubmit` — resolves D1, C1, C2
2. **Session-start budget allocator** — resolves D2
3. **Cipher metadata schema** (`type` naming, required fields) — resolves D3, C5
4. **Context tree frontmatter schema** — resolves D6
5. **Module config base schema** for `.xgh/config.yaml` — resolves D5
6. **Hook output envelope schema** — resolves C6

### Phase 1: Momentum (8-12 days per PRD estimate)

**Rationale:** Momentum is the foundation layer. It captures session state (decisions, blockers, next steps) that feeds Memory Replay, Deja Vu, and indirectly enriches everything. It also introduces the `SessionEnd` hook, which Deja Vu and potentially other features will extend. Building it first means every subsequent feature has richer data to work with from day one.

- Produces: session snapshots, Cipher memories (`type: momentum:session`), `SessionEnd` hook infrastructure
- Consumes: nothing (standalone)

### Phase 2: Repo Whisperer (11-15 days)

**Rationale:** Whisperer is the second producer — it fills Cipher with classified git history that both Memory Replay and Deja Vu consume. Building it before Replay means Replay's GATHER phase has rich, pre-classified data instead of raw `git log` output. Building it before Deja Vu means the pattern library can be auto-seeded from reverts and bug fixes.

- Produces: classified git memories (`type: whisperer:*`), context tree entries (`repo-history/`), revert/bug-fix data
- Consumes: nothing (standalone)

### Phase 3: Memory Replay (6-9 days)

**Rationale:** Replay is a consumer — it synthesizes data from Cipher (including Momentum sessions and Whisperer chunks), context tree, and git. Building it after Momentum and Whisperer means it has rich source material from the first replay generation. The cached replays it produces are then available for Context Drops export and for enriching Deja Vu's context.

- Produces: cached replay documents in context tree, stale/fresh signals
- Consumes: Momentum session memories, Whisperer classified chunks, context tree, git log

### Phase 4: Deja Vu (7-10 days)

**Rationale:** Deja Vu is primarily a consumer at P0 — it needs an existing pattern library. Building it after Whisperer means auto-seeded patterns from reverts. Building it after Momentum means session-end infrastructure exists. Deja Vu's P0 can be seeded from Whisperer's `revert-reason` and `bug-fix-rationale` classifications.

- Produces: warnings, pattern library, feedback signals
- Consumes: Whisperer revert data (for seeding), Cipher memories, prompt intent signals

### Phase 5: Context Drops (5-8 days)

**Rationale:** Context Drops is the distribution layer — it packages everything the other four features produce. Building it last means drops can include Momentum snapshots, Whisperer classifications, Replay narratives, and Deja Vu patterns. The full value proposition ("share everything your project learned") requires all producers to exist.

- Produces: portable knowledge bundles
- Consumes: Cipher vectors from all modules, context tree entries from all modules, reasoning chains

### Total estimated effort: 33-44 days + 1-2 days shared infrastructure

---

## 5. Shared Infrastructure to Extract

These components should be built once and shared across all 5 features.

### 5.1 Hook Dispatch Framework

**Problem:** Four features extend `UserPromptSubmit`. Three extend `SessionStart`. Two use `SessionEnd`.

**Solution:** A thin dispatcher script per hook event that:
- Loads module-specific handler scripts from a `hooks/modules/` directory
- Runs handlers in parallel (fork + wait) within a global timeout
- Merges JSON outputs into the envelope schema
- Provides a fast-exit contract: handlers return empty JSON in <10ms if they have nothing to contribute
- Handles module enable/disable via `.xgh/config.yaml` — disabled modules' handlers are not loaded

**Files:**
- `hooks/dispatch.sh` — shared dispatcher logic
- `hooks/modules/momentum-prompt-submit.sh`
- `hooks/modules/whisperer-prompt-submit.sh`
- `hooks/modules/replay-prompt-submit.sh`
- `hooks/modules/deja-vu-prompt-submit.sh`
- `hooks/modules/momentum-session-end.sh`
- etc.

### 5.2 Cipher Metadata Schema

**Problem:** Five features store data in Cipher with ad-hoc tagging.

**Solution:** A shared metadata schema registered in `.xgh/config.yaml`:

```yaml
# .xgh/config.yaml (shared section)
cipher:
  metadata_schema:
    required_fields:
      - type          # namespaced: "momentum:session", "whisperer:decision", "deja-vu:pattern"
      - source_module # "momentum", "whisperer", "replay", "deja-vu", "drops"
      - created_at    # ISO 8601
      - project       # project identifier
    optional_fields:
      - confidence    # 0.0-1.0
      - file_paths    # array of strings
      - authors       # array of strings
      - source_drop   # drop name + version (for imported content)
      - superseded_by # reference to newer memory
  type_registry:
    - "momentum:session"
    - "whisperer:decision"
    - "whisperer:convention"
    - "whisperer:constraint"
    - "whisperer:revert"
    - "whisperer:bug-fix"
    - "replay:narrative"      # cached replay reference
    - "deja-vu:pattern"
    - "drops:imported"
```

### 5.3 Context Tree Frontmatter Schema

**Problem:** Three features write context tree files with inconsistent frontmatter.

**Solution:** A base frontmatter template:

```yaml
---
title: "Required: human-readable title"
source_module: "whisperer|replay|drops"  # Required
importance: 7                             # Required: 1-10
maturity: "validated"                     # Required: draft|validated|canonical
created_at: "2026-03-15T14:32:00Z"       # Required: ISO 8601
updated_at: "2026-03-15T14:32:00Z"       # Required: ISO 8601
# Module-specific fields below this line
---
```

### 5.4 Module Config Base Schema

**Problem:** Five features each define config under `modules.*` with no consistency.

**Solution:**

```yaml
# Every module config must include:
modules:
  <module-name>:
    enabled: true          # Required: bool
    version: "1.0.0"       # Required: semver
    # Module-specific keys below
```

### 5.5 Hook Output Envelope

**Problem:** Multiple handlers on the same event produce separate JSON objects with no merge strategy.

**Solution:**

```json
{
  "result": "xgh: hook executed",
  "modules": {
    "momentum": { "briefing": "..." },
    "whisperer": { "status": "up-to-date", "hints": [] },
    "replay": { "staleReplays": [] },
    "deja-vu": { "warning": null }
  }
}
```

The dispatcher assembles this. Each module handler returns only its namespace object. Missing modules default to `null`.

### 5.6 Shared Performance Budget Framework

**Problem:** Each PRD defines budgets in isolation. Combined budgets exceed thresholds.

**Solution:** A global budget table in `.xgh/config.yaml`:

```yaml
performance:
  hooks:
    session_start_total_ms: 800
    prompt_submit_total_ms: 500
    session_end_total_ms: 300
  per_module:
    momentum:
      session_start_ms: 300
      prompt_submit_ms: 50
      session_end_ms: 100
    whisperer:
      session_start_ms: 200
      prompt_submit_ms: 200
    replay:
      prompt_submit_ms: 100
    deja-vu:
      prompt_submit_ms: 350
```

---

## 6. Per-PRD Fixes Needed

### 6.1 Momentum

| Issue | Ref | Fix Required |
|-------|-----|-------------|
| Assumes inline extension of `prompt-submit.sh` | Section 5.4, Hook 2 | Refactor to use the shared hook dispatch framework. Momentum's capture-trigger detection becomes a separate module handler. |
| SessionEnd hook is the only SessionEnd handler today, but Deja Vu also wants session-end access | M-P0-03 | Clarify that the SessionEnd hook dispatcher should support multiple handlers, not just Momentum. Design the hook file as a dispatcher from day one. |
| Performance budgets are stated in isolation | Section 5.3 | Add a "Combined Hook Budget" section acknowledging other features. State Momentum's allocation within the shared budget, not in isolation. |
| No mention of Cipher metadata schema compliance | M-P0-01 | Agent-state snapshots stored in Cipher (M-P1-01) must use `type: momentum:session` (namespaced) and include all required metadata fields. |

### 6.2 Memory Replay

| Issue | Ref | Fix Required |
|-------|-----|-------------|
| GATHER phase re-parses git log even if Whisperer has already ingested it | R-P0-02 | Add: "If `modules.whisperer.enabled`, GATHER queries Cipher with `type: whisperer:*` filter instead of running `git log --grep`. Direct git search is a fallback." This avoids D4 (duplicate git parsing). |
| Staleness check runs unconditionally on every prompt via `prompt-submit.sh` | R-P0-06 | Move to a lazy check: only run staleness detection after a successful Cipher store (piggyback on `cipher-post-hook.sh` as already described). Remove the `prompt-submit.sh` "why" pattern detection or make it a <10ms regex-only fast path. This reduces C2 budget pressure. |
| Assumes inline extension of `prompt-submit.sh` | Section 6.1, hook 2 | Refactor to use the shared hook dispatch framework. |
| No mention of combined hook latency | Section 5.3 | Add a "Combined Hook Budget" section. Replay's staleness check at 200ms per prompt is too expensive when 3 other modules share the hook. Reduce to <100ms (cached `_index.yaml` read + in-memory hash comparison). |

### 6.3 Repo Whisperer

| Issue | Ref | Fix Required |
|-------|-----|-------------|
| Solo Dev archetype excluded by default | Section 5.6 | Change to "Default" for Solo Dev. The "Past-Self Archaeologist" persona is one of the strongest in the PRD. C4 explains the inconsistency. |
| Assumes inline extension of `prompt-submit.sh` | Section 6.1, Hook 2 | Refactor to use the shared hook dispatch framework. Whisperer's history-hint injection becomes a separate module handler. |
| No mention of Deja Vu as a consumer of `revert-reason` classifications | Section 6.2 (Skills Integration) | Add Deja Vu to the skills integration table: "Whisperer's `revert-reason` and `bug-fix-rationale` chunks are natural pattern candidates for Deja Vu auto-seeding." |
| Incremental ingestion budget (<500ms) conflicts with Momentum's session-start budget | Section 5.4 | Reduce incremental check to <200ms (git hash comparison only). The actual ingestion must be background-only. State this as non-negotiable within the shared session-start budget. |
| Cipher metadata uses `type: repo-whisperer` (non-namespaced) | RW-P0-04 | Change to namespaced types: `type: whisperer:decision`, `type: whisperer:convention`, etc. Align with the shared Cipher metadata schema. |

### 6.4 Context Drops

| Issue | Ref | Fix Required |
|-------|-----|-------------|
| No mention of Memory Replay cached replays as exportable content | CD-P0-04 | Add: "Context tree fragments exported include `.xgh/context-tree/replays/` when scope matches. Cached replays are first-class drop content." |
| No mention of Deja Vu patterns as exportable content | CD-P0-01 scope | Add: "Drop export can include Deja Vu patterns (Cipher vectors with `type: deja-vu:pattern`) when the scope includes failure patterns. This enables cross-project failure knowledge transfer." |
| Imported vectors may collide with existing module-typed memories | CD-P0-02 | Add: "Imported Cipher vectors retain their original `type` tag (e.g., `whisperer:decision`) and gain an additional `source_drop` tag. Dedup logic must consider `source_drop` to avoid treating imported and native memories as duplicates." |
| No explicit frontmatter schema for imported context tree files | CD-P0-04 | Add: "Imported context tree files must conform to the shared frontmatter schema. The hydrator adds `source_module: drops` and `source_drop: <name>` to frontmatter." |

### 6.5 Deja Vu

| Issue | Ref | Fix Required |
|-------|-----|-------------|
| Q1 (separate hook handler vs. inline extension) is still open | Section 8.1, Q1 | **Resolve as (b): separate handler.** This is validated by the cross-review finding that 3 other features also extend `prompt-submit.sh`. The shared dispatch framework makes separate handlers the standard pattern. |
| Session-end pattern extraction mechanism is vague ("existing post-session curation") | DV-P0-05, Section 6 | Clarify: pattern extraction is an **agent-side instruction**, not a hook. The agent writes pattern candidates to a staging file (`.xgh/deja-vu/candidates.yaml`) at natural stopping points (similar to Momentum's agent-state.yaml). A SessionEnd hook handler (optional) validates and promotes candidates. |
| No mention of Repo Whisperer as a pattern source | DV-P0-05 | Add: "Auto-seeding from Repo Whisperer. When Whisperer classifies a commit as `revert-reason` or `bug-fix-rationale`, the pattern creation pipeline (DV-P0-07) should consider it a high-confidence pattern candidate. Requires `modules.whisperer.enabled`." |
| Performance budget assumes Deja Vu is the only `prompt-submit` extension | Section 5.2 | Add: "Combined prompt-submit budget is 500ms. Deja Vu's allocation is 350ms (fast mode) or must negotiate a larger allocation with the performance framework. When running alongside Whisperer and Replay, all three run in parallel within the 500ms envelope." |
| `type: deja_vu_pattern` uses underscore, inconsistent with other modules | DV-P0-05 | Change to `type: deja-vu:pattern` (namespaced with colon, hyphenated module name). Align with the shared Cipher metadata schema. |

---

## Appendix: Dependency Graph

```
                    ┌──────────────┐
                    │   Shared     │
                    │Infrastructure│
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              v            v            v
        ┌──────────┐ ┌──────────┐     (all features)
        │ Momentum │ │  Repo    │
        │          │ │ Whisperer│
        └────┬─────┘ └────┬─────┘
             │             │
             │    ┌────────┴──────┐
             │    v               v
             │ ┌──────────┐ ┌──────────┐
             └>│  Memory  │ │ Deja Vu  │
               │  Replay  │ │          │
               └────┬─────┘ └──────────┘
                    │
                    v
              ┌──────────┐
              │ Context  │
              │  Drops   │
              └──────────┘

Arrows = "produces data consumed by"
```

---

*This cross-review is a living document. Update it as PRDs are revised to address the findings above.*
