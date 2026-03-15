# Memory Replay — Product Requirements Document

**Feature:** Memory Replay (decision timeline reconstruction for xgh)
**Author:** Pedro (via Claude Code)
**Date:** 2026-03-15
**Status:** PRD — ready for engineering review
**Proposal Source:** [`memory-and-learning.md`](./memory-and-learning.md)

---

## 1. Overview

### 1.1 Problem Statement: The Bag-of-Facts Gap

xgh's memory layer is a point-in-time retrieval system. When an agent searches for "how do we handle authentication?", it gets back 8 memory hits sorted by relevance score — not by time. A decision from month one and its reversal from month three appear side-by-side with no indication that one supersedes the other.

**Quantified impact:**

| Metric | Value | Source |
|--------|-------|--------|
| Average memory hits per topic query | 5-12 fragments | Cipher search behavior |
| Fragments with temporal ordering | 0% | Cipher returns by relevance, not time |
| Time spent re-deriving a past decision | 15-45 minutes | Developer self-report (enterprise teams) |
| Re-opened decisions per project per month | 2-5 | Team retrospective estimates |
| Onboarding time for domain context (new engineer) | 3-10 meetings + ad-hoc Slack | Enterprise self-report |
| Outdated memory application rate | ~20% of sessions | Agent confidently uses superseded patterns |

This creates three concrete pain points:

1. **Context collapse.** The agent treats all memories as equally current. It may apply a pattern that the team abandoned weeks ago because it cannot distinguish the original decision from its reversal.

2. **Onboarding friction.** A new team member (or a new agent session on an unfamiliar domain) cannot ask "how did we get here?" They can search for facts but cannot reconstruct the reasoning arc — the difference between reading a dictionary and reading a history.

3. **Decision amnesia.** Teams revisit the same decisions repeatedly because the reasoning is buried across 12 memories in 3 different collections. Without a replay, the team spends another hour re-deriving the same conclusion.

### 1.2 Vision

With Memory Replay, any topic in the project has a replayable narrative: a chronological story of decisions, pivots, and reversals with source citations. The agent stops giving you a bag of facts and starts telling you a story — "First you tried X, then Y broke, so you switched to Z."

**Before Memory Replay:**
```
Developer asks "why is auth like this?" → Agent returns 8 memory fragments sorted by
relevance → Developer reads them all → Developer mentally reconstructs timeline →
Developer guesses which pattern is current (25 min)
```

**After Memory Replay:**
```
Developer runs /xgh-replay authentication → Agent presents chronological narrative with
pivots, reversals, and confidence tags → Developer understands 3 months of history in
30 seconds
```

### 1.3 Success Metrics

| Metric | Current Baseline | Target | Measurement Method |
|--------|-----------------|--------|-------------------|
| Time to understand a topic's decision history | 15-45 min (manual reconstruction) | <60 seconds (read the replay) | Timestamp delta: query to developer's next action |
| Re-opened decision rate | 2-5/month/project | <1/month/project | Track decisions that match existing replays |
| Onboarding meetings for domain context | 3-10 per new engineer | 0-2 (replay playlist covers the rest) | New engineer self-report |
| Outdated memory application rate | ~20% of sessions | <5% of sessions | Agent applies superseded pattern then self-corrects |
| Replay generation time (cold) | N/A | <10s for <50 memories, <30s for 50-200 | Wall-clock time from `/xgh-replay` to rendered output |
| Replay cache hit rate | N/A | >60% after first month | Cached replay served vs. regenerated |
| Developer satisfaction (weekly pulse) | N/A | >4/5 | Optional one-question survey |

---

## 2. User Personas & Stories

### 2.1 Solo Dev — "The Side-Project Archaeologist"

**Persona:** Alex, a developer who works on personal projects in evenings and weekends. Sometimes weeks pass between sessions on the same module.

**Before:** Alex opens a file with a bizarre 40-line workaround that does what should be a 3-line stdlib call. `git blame` shows it was written by past-Alex, months ago. They spend 20 minutes reading git log, old TODOs, and Slack bookmarks trying to remember why. They almost "simplify" it, which would reintroduce the race condition that caused it.

**Story:** As a solo developer, I want to replay the decision history of any module in my project — including my own forgotten reasoning — so that I never accidentally revert a hard-won fix and I can resume from months-old context in seconds.

**After:** Alex runs `/xgh-replay token-refresh`. The replay shows: (1) originally used stdlib approach, (2) hit a race condition that corrupted sessions, (3) tried a lock-based fix that caused deadlocks under load, (4) settled on the manual approach as the only reliable solution, (5) filed upstream issue #847 (still open). Alex understands 3 months of debugging in 30 seconds and knows not to touch that function.

**Delight factor:** Seeing a replay that includes reasoning *you* wrote months ago and completely forgot. The system remembers your own thought process better than you do.

---

### 2.2 OSS Contributor — "The Context-Aware Contributor"

**Persona:** Jordan, an open-source contributor who contributes to 2 upstream projects. They want to submit a PR but need to understand why the current approach was chosen.

**Before:** Jordan wants to propose switching from REST to GraphQL. They open an issue, write a detailed proposal, and submit a PR. A maintainer responds: "We debated this 4 months ago — see Slack thread [dead link]. The latency overhead was unacceptable for our use case." Jordan's PR is closed. They wasted 3 hours.

**Story:** As an OSS contributor, I want to replay the decision history of a module before contributing, so that I understand not just the code but the decisions behind it — avoiding PRs that rehash settled debates.

**After:** Before writing the proposal, Jordan runs `/xgh-replay api-layer`. The replay shows the REST vs. GraphQL debate from 4 months ago, including benchmarks, the latency concern, and the final decision rationale. Jordan's PR instead proposes a hybrid approach that addresses the latency issue. The maintainer is impressed.

**Delight factor:** Understanding a project deeply enough to make contributions that *build on* past decisions rather than ignoring them.

---

### 2.3 Enterprise — "The Onboarding Accelerator"

**Persona:** Priya, a senior engineer joining a team mid-stream. The team has been working on a payments migration for 6 weeks. Priya needs to get up to speed without scheduling 5 catch-up meetings.

**Before:** Priya spends her first week in meetings: architecture overview, payments migration status, security decision rationale, vendor selection history, and deployment pipeline walkthrough. She takes 15 pages of notes. By Friday, she has a rough picture but still asks "why?" questions that the team considers obvious.

**Story:** As an enterprise engineer onboarding to a new domain, I want to replay the decision history of key topics — including who drove each decision, when, and why — so that I can onboard in hours instead of weeks, and walk into my first standup already knowing the history.

**After:** Priya's onboarding playlist: `/xgh-replay payments-migration`, `/xgh-replay auth-architecture`, `/xgh-replay deployment-pipeline`. Each replay includes team attribution (who drove each decision), compliance tags for security-sensitive choices, and links to corroborating memories. She walks into Monday's standup already knowing the history and asks targeted questions instead of "so, um, what's the status?"

**Delight factor:** "While you were away" becomes "before you even started." The institutional memory outlasts any single contributor.

---

### 2.4 OpenClaw — "The Learning Journey Mapper"

**Persona:** Sam, who uses xgh's OpenClaw archetype as a personal AI assistant. They have been learning Rust for 6 months across 3 different projects.

**Before:** Sam wants to review how their understanding of lifetimes evolved. They search memory and get back 20 fragments: confused questions from month one, breakthrough moments from month three, and pattern applications from month five — all mixed together by relevance score.

**Story:** As an OpenClaw user, I want to replay my learning journey on any topic across all my projects, so that I can see how my understanding evolved and identify patterns in how I learn.

**After:** Sam runs `/xgh-replay rust-lifetimes`. The replay reconstructs the journey: initial confusion about borrowing, the tutorial that clicked, the first project where they applied lifetimes correctly, the advanced pattern they discovered in project three. It is a map of their own learning, organized chronologically.

**Delight factor:** Personal knowledge archaeology — seeing your own intellectual growth as a narrative.

---

## 3. Requirements

### 3.1 Must Have (P0) — Core Replay Engine

These requirements form the minimum viable Memory Replay. Without all of them, the feature does not deliver its core promise.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **R-P0-01** | **`/xgh-replay` skill and command:** Skill file `skills/replay/replay.md` and command `commands/replay.md` for on-demand replay invocation. Takes a topic as argument. | `/xgh-replay <topic>` generates a chronological narrative. Topic can be free-text (e.g., "authentication token refresh") or a slug (e.g., "auth-tokens"). |
| **R-P0-02** | **Memory gathering (GATHER phase):** Cast a wide net across all memory sources: Cipher vector search (semantic), context tree BM25 search (keyword), and git log filtering (commits/PRs). | Gather retrieves from all 3 sources. Minimum: Cipher vectors + context tree. Git log is additive. No source hard-coded to a limit below 20 results per source. |
| **R-P0-03** | **Timeline building (CORRELATE phase):** Cluster gathered memories by sub-topic, order chronologically by memory creation timestamp, detect supersession (A replaced by B), and mark pivots (direction changes). | Output is a structured timeline object with: `clusters[]`, each containing `events[]` ordered by timestamp. Each event has: `timestamp`, `summary`, `source`, `supersedes` (optional), `is_pivot` (boolean). |
| **R-P0-04** | **Narrative synthesis (NARRATE phase):** Single LLM pass (project's configured BYOP model) to convert the timeline into a human-readable story. | Narrative includes: chronological flow, explicit "this replaced that" callouts, confidence tagging per segment ("high: 4 corroborating memories" vs. "low: single Slack message"), and source citations (linked, not inlined). |
| **R-P0-05** | **Replay caching (CACHE phase):** Store generated replays as markdown in `.xgh/context-tree/replays/{topic-slug}.md`. Cached replays are git-committed, PR-reviewable, and searchable by future sessions. | Replay file includes: frontmatter (topic, generated_at, version, memory_count, confidence), narrative body, and source citations section. File is valid markdown parseable by context tree search. |
| **R-P0-06** | **Cache invalidation:** When new memories are stored that semantically match an existing replay topic, mark the replay as stale. Stale replays are regenerated on next access. | Staleness check runs during `UserPromptSubmit` hook when Cipher store tools are invoked. Stale replays show a "This replay may be outdated" banner until regenerated. Staleness detection budget: <200ms. |
| **R-P0-07** | **Supersession detection:** Identify when a later memory contradicts or replaces an earlier one, using semantic opposition scoring and explicit markers (if present). | Superseded memories are rendered as struck-through or annotated in the narrative: "Originally decided X (Jan) — reversed to Y (Mar) because [reason]." |
| **R-P0-08** | **Confidence tagging:** Each segment of the narrative is tagged with a confidence level based on corroboration count. | Confidence levels: `high` (3+ corroborating memories), `medium` (2 memories), `low` (single source). Tags rendered inline in the narrative. |
| **R-P0-09** | **Graceful no-history:** When no memories exist for a topic, the replay produces a clear "No history found" message — no error, no empty output, no confusion. | Message: "No decision history found for '{topic}'. As memories are stored, replays will become available." |
| **R-P0-10** | **techpack.yaml registration:** Memory Replay components registered in `techpack.yaml`. | New component IDs: `replay-skill`, `replay-command`. Components follow existing schema patterns. Module manifest extends `techpack.yaml` with `modules.memory-replay`. |
| **R-P0-11** | **Config integration:** Memory Replay configuration lives in `.xgh/config.yaml` under `modules.memory-replay`. | Keys: `enabled` (bool), `max_memories_per_source` (int, default 20), `cache_enabled` (bool, default true), `narrate_model` (string, default "byop" — uses project's configured model). |

### 3.2 Should Have (P1) — Enhanced Replay Features

These features differentiate Memory Replay from a basic timeline dump. They require deeper integration.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **R-P1-01** | **Replay versioning:** As new memories are added and replays regenerated, previous versions are preserved. Users can view replay history: `/xgh-replay <topic> --version 2`. | Replay files use versioned filenames: `{topic-slug}-v{N}.md`. Latest version is also symlinked/copied to `{topic-slug}.md`. `--version` flag shows a specific historical version. |
| **R-P1-02** | **Replay diff:** Show what changed between replay versions: `/xgh-replay <topic> --diff`. | Output highlights: new events added, superseded events, confidence changes, and pivot points discovered since the previous version. |
| **R-P1-03** | **Conflict detection:** When a new memory contradicts the latest replay for a topic, proactively warn the agent. | Warning injected via `UserPromptSubmit` hook: "This decision conflicts with the approach established in the '{topic}' replay — see replay for history." |
| **R-P1-04** | **Onboarding playlists:** Curated list of replays for onboarding. `/xgh-replay --playlist` generates a recommended reading order based on topic importance and dependency. | Playlist output: ordered list of replay topics with one-line summaries. Order determined by: replay confidence (high first), topic freshness (recent pivots first), cross-references between replays. |
| **R-P1-05** | **Team attribution (Enterprise):** Replay narrative includes who drove each decision, sourced from memory metadata and git author information. | Each event in the timeline includes an optional `author` field. Narrative renders as: "The team (led by @brenno) decided to switch from..." Attribution requires Enterprise archetype. |
| **R-P1-06** | **Compliance tags (Enterprise):** Security-sensitive and compliance-relevant decisions are tagged in the replay. | Tags: `security`, `data-handling`, `privacy`, `regulatory`. Tags sourced from memory metadata or keyword detection. Enterprise archetype only. |
| **R-P1-07** | **Cross-topic linking:** When a replay references a topic that has its own replay, link them. | Narrative includes inline links: "...which was driven by the [deployment pipeline changes](replays/deployment-pipeline.md)." Links are relative paths within the context tree. |

### 3.3 Nice to Have (P2) — Future Possibilities

These are features Memory Replay enables but does not implement in v1. Documented here to shape architectural decisions.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **R-P2-01** | **Memory compaction:** Once a replay exists, individual memories that were superseded can be archived or downweighted. The replay becomes the canonical record. | Compacted memories tagged with `superseded_by: replay/{topic-slug}`. Retrieval deprioritizes them. |
| **R-P2-02** | **Cross-project pattern detection:** When replays exist across multiple projects (via linked workspaces), identify recurring patterns. | Output: "You've hit this same authentication problem in 3 projects — here's what worked each time." Requires linked workspaces feature. |
| **R-P2-03** | **Export to Confluence (Enterprise):** `/xgh-replay <topic> --export confluence` publishes the replay as a Confluence page. | Requires Atlassian MCP. Page created under a configurable space. Replay markdown converted to Confluence wiki format. |
| **R-P2-04** | **Linked workspace narratives:** Replays that span projects via linked workspaces. | "The swift-mock-kit mocking approach evolved because of changes in tr-ios's coordinator architecture." Requires linked workspaces feature. |
| **R-P2-05** | **Visual timeline:** `/xgh-replay <topic> --visual` generates a Mermaid diagram of the decision timeline. | Output: Mermaid gantt or timeline diagram embedded in the replay markdown. Renderable in GitHub PRs and Confluence. |

---

## 4. User Experience

### 4.1 Invoking a Replay

Memory Replay is invoked on-demand via the `/xgh-replay` command. It is not automatic (unlike Momentum, which runs at session start).

**Flow:**

```
1. Developer runs /xgh-replay <topic>
2. Engine checks cache: .xgh/context-tree/replays/{topic-slug}.md
3. If cached and fresh → render cached replay (<500ms)
4. If cached but stale → show stale banner, offer regeneration
5. If not cached → run GATHER → CORRELATE → NARRATE pipeline
6. Rendered narrative presented to developer
7. Cached to context tree for future sessions
```

### 4.2 What the Developer Sees

**Cached replay (fast path):**

```markdown
## 🐴 Memory Replay: Authentication Token Refresh

**Generated:** 2026-03-10 (v3) | **Sources:** 14 memories, 6 commits, 3 context tree docs | **Confidence:** High

---

### Timeline

**January 2026 — Initial Implementation**
Used the stdlib `http.TokenSource` for automatic refresh. Straightforward, 3 lines of code.
📎 *Sources: architectural-decisions/auth.md, commit a1b2c3d*

**February 2 — Production Race Condition** 🔄 *pivot*
Under concurrent load, multiple goroutines called `Token()` simultaneously. The stdlib implementation is not goroutine-safe for refresh — two goroutines could both detect an expired token and both attempt refresh, corrupting the session store.
📎 *Sources: cipher memory #412 (reasoning chain), commit d4e5f6g, Slack #backend 2026-02-02*

**February 5 — Lock-Based Fix Attempt**
Added a `sync.Mutex` around the token refresh. Fixed the race condition but introduced deadlocks under high load — the lock was held during the HTTP call to the auth provider, blocking all other requests.
📎 *Sources: cipher memory #418, commit h7i8j9k*
🤖 **Confidence: High** (3 corroborating sources)

**February 12 — Manual Refresh Handler** ✅ *current approach*
~~Replaced stdlib TokenSource~~ with a manual refresh handler: dedicated goroutine that refreshes tokens 60s before expiry, never during a request. The 40-line function is intentional — it handles retry, backoff, and graceful degradation.
📎 *Sources: cipher memory #425 (reasoning chain), commit l0m1n2o, context-tree/architecture/auth.md*
🤖 **Confidence: High** (4 corroborating sources)

**February 14 — Upstream Issue Filed**
Filed issue #847 on the stdlib repo requesting goroutine-safe token refresh. Status: **open**, no maintainer response yet.
📎 *Sources: cipher memory #430, GitHub issue #847*
🤖 **Confidence: Medium** (2 sources)

---

### Open Questions
- Upstream issue #847 may resolve this — revisit if accepted
- Consider adding metrics to the manual handler (refresh latency, failure rate)

### Superseded Decisions
- ~~stdlib TokenSource~~ → replaced by manual handler (Feb 12)
- ~~Mutex-based fix~~ → abandoned due to deadlocks (Feb 12)
```

**No history found:**

```markdown
## 🐴 Memory Replay: Payment Gateway

No decision history found for 'payment gateway'. As memories are stored about this
topic, replays will become available.

💡 Try `/xgh-ask payment gateway` to search individual memories, or `/xgh-curate` to
store what you know.
```

**Stale replay:**

```markdown
## 🐴 Memory Replay: Authentication Token Refresh

⚠️ **This replay may be outdated.** New memories were stored since it was generated
(2026-03-10). Run `/xgh-replay authentication --refresh` to regenerate.

[cached replay content follows]
```

### 4.3 Output Style Guide

Memory Replay output follows the xgh output convention: scannable, emoji-accented, structured.

**Principles:**
- **Chronological over ranked:** Events are always presented in time order. Never by relevance score.
- **Narrative over list:** The output reads as a story, not a bullet list. Each section has connective tissue: "this led to," "because of," "which prompted."
- **Honest over complete:** Confidence tags tell the developer how much to trust each segment. Low-confidence segments are explicitly marked.
- **Cited over asserted:** Every claim links to its source memories. Nothing is stated without provenance.

**Visual elements:**

| Element | Purpose |
|---------|---------|
| `## 🐴 Memory Replay: {Topic}` | Consistent header, immediately recognizable |
| Generation date + version badge | Shows freshness and how many times this replay has evolved |
| Source count summary | "14 memories, 6 commits, 3 docs" — shows breadth of evidence |
| 🔄 pivot markers | Highlights moments where direction changed |
| ✅ current approach markers | Identifies which decision is active today |
| ~~Strikethrough~~ for superseded | Visually clear what was abandoned |
| 📎 source citations | Per-section provenance — linked, not inlined |
| 🤖 confidence tags | Per-section reliability rating |
| Open Questions section | Surfaces unresolved threads from the replay |
| Superseded Decisions summary | Quick reference of what was replaced by what |

---

## 5. Technical Boundaries

### 5.1 Data and Storage

**What the Replay Engine reads:**

| Data Source | What It Reads | Access Method |
|-------------|--------------|---------------|
| Cipher vector memory | All memories semantically matching the topic | `cipher_memory_search` (broad query, limit 20-50) |
| Context tree | Markdown docs matching topic keywords | BM25 keyword search via `ctx_search` or Python TF-IDF |
| Git log | Commits and PR descriptions mentioning the topic | `git log --all --grep=<topic>` + `gh pr list --search` |
| Existing replays | Previously generated replays for cross-referencing | Direct file read from `.xgh/context-tree/replays/` |

**What the Replay Engine writes:**

| Data Point | Storage Location | Retention |
|------------|-----------------|-----------|
| Replay markdown | `.xgh/context-tree/replays/{topic-slug}.md` (git-committed) | Permanent (versioned in git) |
| Replay versions | `.xgh/context-tree/replays/{topic-slug}-v{N}.md` | Permanent (P1 versioning) |
| Staleness index | `.xgh/context-tree/replays/_index.yaml` | Updated on each Cipher store event |
| Replay generation log | `.xgh/local/replay.log` (git-ignored) | 7 days, max 2MB |

### 5.2 Privacy: What NEVER Gets Stored in Replays

| Excluded Data | Reason |
|---------------|--------|
| Raw file contents or diffs | Replays reference file paths only. Code stays in git. |
| API keys, tokens, credentials | Explicitly excluded from narrative synthesis. |
| Full conversation transcripts | Only distilled decisions and reasoning, not raw chat. |
| Personal info beyond git author name | No email, no IP, no device info. |
| Contents of `.env` files | Never accessed, never referenced. |
| Clipboard contents | Never accessed. |

**Privacy contract:** A replay is a *decision narrative*, not a code dump. A replay committed to git reveals *what was decided and why* but not the code itself. This is by design — replays are meant to be PR-reviewable and shareable.

### 5.3 Performance Budget

| Operation | Budget | Method |
|-----------|--------|--------|
| **Replay generation (cold, <50 memories)** | <10s total | Cipher search (~2s) + BM25 search (~500ms) + git log (~500ms) + timeline build (~1s) + LLM narrate (~5s) + cache write (~100ms) |
| **Replay generation (cold, 50-200 memories)** | <30s total | Wider search (~4s) + clustering (~3s) + LLM narrate (~15s for longer narrative) + cache write (~100ms) |
| **Replay serve (cached, fresh)** | <500ms | File read (~10ms) + markdown render (~50ms) |
| **Replay serve (cached, stale)** | <500ms + banner | Same as cached-fresh, plus staleness banner prepend |
| **Staleness check** | <200ms | Read `_index.yaml` (~10ms) + semantic similarity check (~150ms) |
| **Replay disk usage** | <50KB per replay | Markdown narrative + citations. 20 replays = ~1MB. |
| **Cache invalidation per Cipher store** | <200ms | Topic extraction from stored memory (~100ms) + index lookup (~50ms) + stale flag write (~10ms) |

**Non-negotiable:** Replay generation may take 10-30 seconds (LLM synthesis is the bottleneck). This is acceptable because it is on-demand, not blocking session start. The cached path (<500ms) is the common case after first generation.

### 5.4 Replay Document Schema

```yaml
# .xgh/context-tree/replays/{topic-slug}.md frontmatter
---
title: "Authentication Token Refresh"
topic_slug: "authentication-token-refresh"
generated_at: "2026-03-10T14:32:00Z"
version: 3
memory_count: 14
commit_count: 6
context_tree_count: 3
confidence: "high"              # high | medium | low (overall)
stale: false                    # set to true when new memories invalidate
superseded_topics: []           # topics this replay has absorbed
related_topics:                 # cross-references to other replays
  - "deployment-pipeline"
  - "session-management"
maturity: "validated"           # context tree maturity for search ranking
importance: 8                   # 1-10 importance for context tree scoring
---
```

### 5.5 Staleness Index Schema

```yaml
# .xgh/context-tree/replays/_index.yaml
replays:
  authentication-token-refresh:
    generated_at: "2026-03-10T14:32:00Z"
    version: 3
    stale: false
    topic_embedding_hash: "a1b2c3d4"   # for fast semantic comparison
  deployment-pipeline:
    generated_at: "2026-03-08T09:15:00Z"
    version: 1
    stale: true
    stale_since: "2026-03-12T16:00:00Z"
    topic_embedding_hash: "e5f6g7h8"
```

---

## 6. Hooks & Skills Integration

### 6.1 Existing Hooks — Integration Map

Memory Replay interacts with all 4 existing xgh hooks. For each: the relationship type (extends, consumes, triggers from, no change) and the specific integration.

#### `xgh-session-start.sh` (SessionStart) — CONSUMES

**What it does today:** Loads the top 5 context tree files by score, injects the decision table, optionally triggers `/xgh-brief`.

**Memory Replay integration:** Memory Replay **consumes** this hook's context tree loading. Since cached replays live in `.xgh/context-tree/replays/`, the existing session-start hook already picks up high-importance replays via its context tree scoring mechanism. A replay with `importance: 8` and `maturity: validated` will naturally rank in the top 5 context files when relevant.

**Changes required:** None to the hook itself. Replays must have valid frontmatter (`importance`, `maturity`) so the existing scoring algorithm includes them. If a Momentum snapshot references a topic with a stale replay, the session-start output could note "The '{topic}' replay has new information — run `/xgh-replay {topic} --refresh`."

**Relationship:** Consumes (no hook modification needed).

---

#### `xgh-prompt-submit.sh` (UserPromptSubmit) — EXTENDS

**What it does today:** Detects code-change intent via regex, injects Cipher tool hints and decision table.

**Memory Replay integration:** Memory Replay **extends** this hook with two new capabilities:

1. **Staleness detection on Cipher store:** When the prompt triggers Cipher store tools (`cipher_store_reasoning_memory`, `cipher_extract_and_operate_memory`), the hook checks whether the content being stored semantically matches any existing replay topic. If it does, the hook marks the replay as stale in `_index.yaml` and injects a hint: "Note: this memory may update the '{topic}' replay. Run `/xgh-replay {topic} --refresh` when ready."

2. **Replay suggestion on "why" questions:** When the prompt matches a "why" or "how did we" pattern (e.g., "why is auth like this?", "how did we decide on X?"), the hook injects a suggestion: "Try `/xgh-replay {topic}` for the full decision history."

**Changes required:** Add staleness-check logic and "why" pattern detection to `prompt-submit.sh`. Both are lightweight (<200ms): staleness check reads `_index.yaml` and compares topic embeddings; "why" detection is regex.

**Relationship:** Extends (adds staleness checks and replay suggestions).

---

#### `cipher-pre-hook.sh` (PreToolUse) — NO CHANGE

**What it does today:** Warns when sending complex/structured content to Cipher's 3B extraction model, suggesting direct Qdrant storage.

**Memory Replay integration:** Memory Replay does not modify this hook. However, this hook **indirectly protects** replay quality: if a developer tries to store a large reasoning chain that would enrich a future replay, the pre-hook ensures the storage succeeds (via direct Qdrant fallback), which means more memories for the replay engine to draw from.

**Changes required:** None.

**Relationship:** No change (operates independently; indirect quality benefit).

---

#### `cipher-post-hook.sh` (PostToolUse) — TRIGGERS FROM

**What it does today:** Detects `extracted:0` failures from Cipher's extraction model, instructs the agent to retry via direct Qdrant storage.

**Memory Replay integration:** Memory Replay **triggers from** this hook's successful storage events. When the post-hook detects a successful Cipher write (i.e., *not* an `extracted:0` failure), it provides a signal that new memory was stored. The replay staleness checker piggybacks on this: after a successful Cipher store, the staleness check runs against the `_index.yaml` to determine if any existing replay is now stale.

**Changes required:** Add a post-store staleness check invocation to `cipher-post-hook.sh`. When the hook detects a successful store (not a failure path), it calls the replay staleness checker: `python3 .xgh/scripts/replay-staleness.py --check-new-memory`. Budget: <200ms.

**Relationship:** Triggers from (piggybacks on successful store events for staleness detection).

---

### 6.2 Skills — Integration Map

| Skill | Relationship | How |
|-------|-------------|-----|
| **`/xgh-brief`** | **Consumes replay data.** | Briefing references recent replays: "The authentication replay was updated yesterday after new memories were stored. Run `/xgh-replay authentication` for the full history." If Momentum is also installed, the brief shows replay staleness alongside session state. |
| **`/xgh-ask`** | **Routes to replays.** | When `/xgh-ask` retrieves multiple memories on the same topic, it suggests: "For the full decision history, see `/xgh-replay {topic}`." This prevents the user from manually piecing together a timeline that already exists as a replay. |
| **`/xgh-curate`** | **Triggers replay regeneration.** | When `/xgh-curate` stores a new memory, it checks replay staleness. If the curated memory touches an existing replay topic, the skill suggests regeneration: "This memory touches the 'authentication' replay — run `/xgh-replay authentication --refresh` to update it." |
| **`/xgh-status`** | **Displays replay health.** | Status adds a Memory Replay section: total replays, stale replay count, last generation timestamp, total disk usage, and largest replay. |
| **`/xgh-implement`** | **Pre-loads relevant replays.** | Before implementing a task, the implement skill checks if any replays are relevant to the task domain. If found, the replay narrative is loaded as implementation context — the agent understands the decision history before writing code. |
| **`/xgh-investigate`** | **Pre-loads relevant replays.** | Before investigating a bug, the investigate skill checks for replays in the bug's domain. Historical context prevents re-investigating solved problems: "This area was previously affected by a race condition — see the authentication replay." |
| **`/xgh-help`** | **Documents the replay command.** | Help includes `/xgh-replay` in the command reference with usage examples. If the user asks about decision history or "why" questions, help suggests `/xgh-replay`. |

### 6.3 Module Manifest

```yaml
# Extends techpack.yaml
modules:
  memory-replay:
    version: 1.0.0
    skills: [replay]
    commands: [replay]
    hooks:
      prompt-submit: replay-staleness-check   # extends existing hook
      cipher-post-hook: replay-staleness-trigger  # triggers from existing hook
    context-tree-dirs: [replays]
    scripts: [replay-staleness.py, replay-engine.py]
    templates: [replay-narrate.md]
    dependencies:
      required: [cipher-mcp, context-tree]
      optional: [xgh-ingest, git]
    archetypes: [solo-dev, oss-contributor, enterprise, openclaw]
```

### 6.4 Archetype Tiering

| Capability | Standard (Solo, OSS, OpenClaw) | Enterprise |
|------------|:-----------------------------:|:---------:|
| `/xgh-replay <topic>` command | **Yes** | **Yes** |
| GATHER from Cipher + context tree + git | **Yes** | **Yes** |
| CORRELATE (timeline, supersession, pivots) | **Yes** | **Yes** |
| NARRATE (LLM synthesis) | **Yes** | **Yes** |
| Replay caching in context tree | **Yes** | **Yes** |
| Cache staleness detection | **Yes** | **Yes** |
| Confidence tagging | **Yes** | **Yes** |
| Replay versioning (P1) | **Yes** | **Yes** |
| Cross-topic linking (P1) | **Yes** | **Yes** |
| Team attribution (P1) | | **Yes** |
| Compliance tags (P1) | | **Yes** |
| Export to Confluence (P2) | | **Yes** |

---

## 7. Non-Goals

Memory Replay is a decision history tool. These are things it explicitly does NOT do:

| Non-Goal | Why Not | Related Feature |
|----------|---------|-----------------|
| **Real-time memory monitoring** | Replay is on-demand, not continuous. It generates a narrative when asked, not when memories change. | Memory Drift Detection (separate proposal) |
| **Automatic session-start injection** | Unlike Momentum, replays are not injected at session start. They are pulled by the user or by skills that detect relevance. | Momentum (session continuity) |
| **Code diff analysis** | Replays reference commits and file paths but never include raw diffs. Code analysis is a different tool. | `git diff`, `/xgh-investigate` |
| **Memory editing or deletion** | Replays present memories as read-only narrative. They do not provide a UI to edit or delete individual memories. | Cipher MCP admin tools |
| **Task management** | Replays show decision history, not task tracking. They do not create tickets or manage backlogs. | Jira MCP, `/xgh-implement` |
| **Full conversation replay** | Memory Replay reconstructs *decisions*, not *conversations*. It synthesizes, not transcribes. | Session Replay (separate feature concept) |
| **Cross-machine memory sync** | Replays are cached in the context tree (git-committed). The underlying memories live in Cipher. Memory Replay does not implement sync. | Cipher MCP (already cross-machine) |
| **Automated memory cleanup** | Memory compaction (P2) is documented but not implemented in v1. Replays do not auto-archive old memories. | Memory Compaction (P2 future) |

---

## 8. Open Questions

### 8.1 Design Decisions Needing Input

| # | Question | Options | Recommendation | Needs |
|---|----------|---------|---------------|-------|
| Q1 | **How should the NARRATE phase handle conflicting memories?** Two memories may directly contradict each other with no clear supersession signal. | (a) Present both with a "conflicting accounts" label. (b) Prefer the more recent memory. (c) Prefer the higher-confidence memory. (d) Ask the developer to resolve. | **(a)** — Present both. The replay should be honest about contradictions, not silently resolve them. The developer resolves, and the resolution becomes a new memory that clarifies the next replay. | Prototype with 5 topics that have known contradictions. |
| Q2 | **Should replays be auto-generated or always on-demand?** | (a) Always on-demand via `/xgh-replay`. (b) Auto-generate for topics with >10 memories. (c) Auto-generate when a topic's memory count crosses a threshold. | **(a)** — Always on-demand. Auto-generation adds complexity (which topics? when?) and compute cost. The user knows when they need a replay. Auto-generation is a P2 consideration once usage patterns are clear. | Monitor: how often do users run `/xgh-replay`? If >3x/day, consider auto-generation. |
| Q3 | **What model should NARRATE use?** The LLM pass is the most expensive operation. | (a) Always use the project's BYOP model. (b) Use a cheaper model (e.g., Haiku) for narration, reserve the main model for code. (c) Make it configurable. | **(c)** — Configurable via `modules.memory-replay.narrate_model`, defaulting to `byop`. Some users will prefer a cheaper model for narration; others will want the best model for accuracy. | Benchmark narration quality across model tiers. |
| Q4 | **Should cached replays be committed to git?** | (a) Yes — context tree is git-committed, replays are context tree docs. (b) No — replays are generated artifacts, git-ignore them. (c) Configurable. | **(a)** — Yes. Committed replays are PR-reviewable, searchable by future sessions, and shareable without extra infrastructure. The context tree's value proposition is git-committed knowledge. Replays are knowledge. | Confirm replay sizes stay under 50KB. Monitor git repo size impact after 20+ replays. |
| Q5 | **How granular should topic slugs be?** | (a) User specifies the exact topic. (b) Engine auto-detects sub-topics and creates separate replays. (c) User specifies topic, engine suggests sub-topics. | **(c)** — User specifies, engine suggests. After generating a broad replay (e.g., "authentication"), the engine notes: "This topic has 3 sub-clusters: token refresh, provider selection, session management. Run `/xgh-replay authentication/token-refresh` for a focused replay." | Prototype clustering on a project with >50 memories. |

### 8.2 Technical Unknowns

| # | Unknown | Risk Level | Investigation Plan |
|---|---------|-----------|-------------------|
| T1 | **Supersession detection accuracy.** Semantic opposition scoring may produce false positives — two memories that are different but not contradictory may be flagged as superseding. | High | Build a test set of 30 memory pairs: 10 true supersessions, 10 related-but-not-contradictory, 10 unrelated. Measure precision/recall. If <80%, add explicit supersession markers to Cipher memory schema. |
| T2 | **LLM narration hallucination.** The NARRATE pass may invent connections between memories that do not exist in the timeline. | Medium | Require the narration prompt to include a "cite-or-omit" instruction: every claim must reference a source memory ID. Post-narration validation: check that all cited IDs exist in the GATHER output. |
| T3 | **Cipher query breadth.** To build a comprehensive timeline, GATHER needs to retrieve *all* memories on a topic, not just the top-5 nearest neighbors. Cipher's default limit may be too low. | Medium | Test with `cipher_memory_search` limit set to 50. If recall is too low, use multiple overlapping queries (topic + sub-topic variations) and deduplicate results. |
| T4 | **Context tree search quality.** BM25 keyword search may miss relevant context tree documents with different terminology (e.g., "auth" vs. "authentication"). | Low | Use query expansion: generate 3-5 keyword variations from the topic before searching. Alternatively, use Cipher's semantic search against the context tree if indexed. |
| T5 | **Git log parsing reliability.** `git log --grep` is substring matching, which may produce false positives on common terms. | Low | Filter git results by combining `--grep` with file path heuristics. If a commit mentions "auth" but only touches `README.md`, deprioritize it. |

### 8.3 Scope Boundary Questions

| # | Question | Current Answer | May Change If |
|---|----------|---------------|---------------|
| S1 | Does Memory Replay replace `/xgh-ask`? | **No.** `/xgh-ask` is for individual memory lookup. Replay is for decision history reconstruction. They complement each other — ask finds facts, replay tells stories. | Usage data shows >80% of `/xgh-ask` queries are "why" questions better served by replays. |
| S2 | Is Momentum a prerequisite for Memory Replay? | **No.** They are independent features. Momentum provides session continuity; Replay provides decision history. They can coexist — Momentum's captured decisions become source material for replays. | Momentum's open_decisions format is adopted as the standard for replay pivot detection. |
| S3 | Should Memory Replay handle real-time streaming (progressive narrative)? | **No.** v1 generates the full replay and presents it. Streaming adds UX complexity for marginal benefit on a 10-30s operation. | Generation times exceed 60s for large topics, making a progress indicator necessary. |
| S4 | Does Memory Replay work without Cipher? | **No.** Cipher is the primary memory source. Without it, the engine has only git log and context tree — insufficient for meaningful replays. | A "git-only replay" mode could work for projects with rich commit messages but no Cipher. |

---

## Appendix A: Implementation Sequence

| Phase | Scope | Components | Est. Effort |
|-------|-------|-----------|-------------|
| **Phase 1** | P0 Core (GATHER + CORRELATE + NARRATE + CACHE) | `replay-engine.py` (timeline builder + supersession detection), `replay-narrate.md` (prompt template), `skills/replay/replay.md`, `commands/replay.md`, `.xgh/context-tree/replays/` convention, `techpack.yaml` registration | 3-4 days |
| **Phase 2** | P0 Integration (hooks + staleness + config) | `replay-staleness.py` (staleness checker), `prompt-submit.sh` extension, `cipher-post-hook.sh` extension, `_index.yaml` schema, config integration in `.xgh/config.yaml`, graceful no-history UX | 2-3 days |
| **Phase 3** | P0 Polish (edge cases + testing) | Confidence tagging calibration, supersession detection tuning, narration hallucination guardrails, tests | 1-2 days |
| **Phase 4** | P1 Enhanced (versioning + playlists + enterprise) | Replay versioning, replay diff, onboarding playlists, conflict detection, team attribution, compliance tags, cross-topic linking | 3-4 days |
| **Phase 5** | P2 Extended (compaction + cross-project + export) | Memory compaction, cross-project patterns, Confluence export, visual timelines | 2-3 days (after linked workspaces) |

**Total estimated effort:** 6-9 days for P0. 9-13 days for P0+P1. P2 is deferred.

---

## Appendix B: Interaction With Momentum

Memory Replay and Momentum are complementary but independent features:

| Dimension | Momentum | Memory Replay |
|-----------|----------|---------------|
| **Trigger** | Automatic (session start/end) | On-demand (`/xgh-replay`) |
| **Scope** | Single session state | Full topic history (months/years) |
| **Output** | Briefing (what to do next) | Narrative (how we got here) |
| **Storage** | `.xgh/momentum/` (git-ignored, ephemeral) | `.xgh/context-tree/replays/` (git-committed, permanent) |
| **Data source** | Session snapshot + recent Cipher | All Cipher + context tree + git log |
| **Latency** | <500ms (P0), <2s (P1) | <500ms (cached), 10-30s (cold) |

**When both are installed:** Momentum's captured decisions (via `agent-state.yaml` → Cipher) become source material for future replays. A decision recorded in Momentum today appears in tomorrow's replay narrative. Momentum is the capture layer; Replay is the synthesis layer.

---

## Appendix C: Self-Review Notes

The following issues were identified and fixed during self-review:

1. **Contradicting performance budgets (fixed).** Initial draft had "replay generation <5s" which was unrealistic given LLM synthesis latency. Revised to <10s for <50 memories, <30s for 50-200 memories, with explicit acknowledgment that LLM narration is the bottleneck.

2. **Missing acceptance criteria for R-P0-06 (fixed).** Cache invalidation requirement originally lacked a performance budget for the staleness check. Added "<200ms" budget and specified it runs during `UserPromptSubmit` hook.

3. **Scope creep in P0 — playlist feature (fixed).** Onboarding playlists were initially P0. Moved to P1 (R-P1-04) because they require multiple replays to exist first and add UX complexity beyond core replay generation.

4. **Unrealistic disk budget (fixed).** Initial draft said "<10KB per replay." A narrative covering 3+ months of decisions with citations will be 20-50KB. Revised to "<50KB per replay" with a note that 20 replays is approximately 1MB.

5. **Missing Enterprise-only markers (fixed).** Team attribution and compliance tags were listed as general features. Added explicit "Enterprise archetype only" markers per the archetype modularization plan.

6. **Ambiguous hook relationship for cipher-post-hook (clarified).** Original draft said "extends" but the integration is better described as "triggers from" — Memory Replay does not modify the hook's failure-detection logic; it piggybacks on successful store events.

7. **Missing skill integration for /xgh-implement and /xgh-investigate (fixed).** These workflow skills benefit from pre-loading relevant replays as implementation/investigation context. Added to the skills integration table.

*This PRD is a living document. Update it as design decisions from Section 8 are resolved.*
