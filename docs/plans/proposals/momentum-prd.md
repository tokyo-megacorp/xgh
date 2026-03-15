# Momentum — Product Requirements Document

**Feature:** Momentum (session continuity layer for xgh)
**Author:** Pedro (via Claude Code)
**Date:** 2026-03-15
**Status:** PRD — ready for engineering review
**Proposal Source:** [`developer-experience.md`](./developer-experience.md)

---

## 1. Overview

### 1.1 Problem Statement: The Cold-Start Tax

Every AI coding session begins with an invisible tax: **context reconstruction**. The developer must remember what they were doing, re-explain the current state, re-orient the agent, and recall blockers. This happens despite xgh already possessing all the necessary information across Cipher memory, the context tree, and git.

**Quantified impact:**

| Metric | Value | Source |
|--------|-------|--------|
| Time lost per session to re-orientation | 2-5 minutes | Developer self-report |
| Sessions per developer per day | 4-6 | Typical usage pattern |
| Daily time wasted per developer | 8-30 minutes | Low/high estimates |
| Daily time wasted per 5-person team | 40-150 minutes | Team extrapolation |
| Cognitive cost | Unmeasured but high | Switching from "doing work" to "describing work to the agent" before starting |
| Annual cost per developer (at 15 min/day avg) | ~62 hours | 250 working days x 15 min |

The irony: xgh's memory layer, context tree, git state, and ingest pipeline already contain everything needed to eliminate this tax. Nothing ties them together into a **session-level continuity layer**.

### 1.2 Vision

With Momentum, every new session feels like a continuation of the last one — not a blank slate. The agent already knows what you were doing, what changed since, and what to do next. The gap between "I should work on this" and "I am working on this" collapses to near-zero.

**Before Momentum:**
```
Developer opens session → Reads git log → Remembers context → Explains to agent → Agent asks
clarifying questions → Developer re-explains → Work begins (5 min later)
```

**After Momentum:**
```
Developer opens session → Agent presents briefing → Developer says "continue" → Work begins (<15s)
```

### 1.3 Success Metrics

| Metric | Current Baseline | Target | Measurement Method |
|--------|-----------------|--------|-------------------|
| Time-to-productive (session start to first meaningful action) | 2-5 minutes | <15 seconds | Timestamp delta: session start to first code edit or command |
| Context accuracy (briefing matches developer's intent) | N/A | >90% of sessions | User does not correct or override the briefing |
| Session pickup rate (developer continues suggested work) | N/A | >70% | Developer responds "continue" or equivalent vs. starting fresh |
| Briefing generation time | N/A | <500ms (P0), <2s (P1 with Cipher) | Wall-clock time from session start to briefing render |
| Capture overhead per session | N/A | <100ms | Time added to session-end flow |
| Developer satisfaction (weekly pulse) | N/A | >4/5 | Optional one-question survey |
| Cross-session continuity (same task resumed across sessions) | Unknown | Measurable | Track task IDs across session snapshots |

---

## 2. User Personas & Stories

### 2.1 Solo Dev — "The Weekend Warrior"

**Persona:** Alex, a developer who works on personal projects in evenings and weekends. Sometimes days pass between sessions.

**Before:** Alex opens their side project on Saturday morning. They stare at `git log` for 2 minutes trying to remember what branch they were on, what the failing test was about, and why they left a TODO in the auth module. By the time they recall everything, their coffee is cold and their motivation is lower.

**Story:** As a solo developer, I want my AI agent to remember exactly where I left off — including what branch I was on, what tests were failing, and what my next step was — so that I can resume productive work instantly after days away from a project.

**After:** Alex opens Claude Code. Before they type anything, the agent says: "You were on `feat/oauth-refactor`, 3 tests failing in `auth_test.go` (expected — you changed the token struct), and your next step was updating the refresh handler. Want to continue?" Alex says "yes" and is coding in 10 seconds.

**Delight factor:** The "aha" moment on the second session. The realization that the agent has continuity — it is not a blank slate.

---

### 2.2 OSS Contributor — "The Multi-Repo Juggler"

**Persona:** Jordan, an open-source contributor who maintains 3 libraries and contributes to 2 upstream projects. Context-switching between repos is constant.

**Before:** Jordan finishes a PR review on `swift-mock-kit`, then switches to `xgh` to implement a feature. They spend 4 minutes reading their own PR description to remember the approach they were taking, then check Slack for feedback from a maintainer. When they switch back to `swift-mock-kit` later, they have to re-load that context too.

**Story:** As an OSS contributor juggling multiple repositories, I want per-project session state that restores instantly when I switch between repos, so that context-switching between projects costs seconds instead of minutes.

**After:** Jordan switches to the `xgh` project. Momentum loads: "Last session 3 hours ago. You were implementing skill bundling for the Solo Dev archetype. Branch `feat/archetype-modularization`, 60% through. 2 open PRs need your review (#142 and #145)." When Jordan switches back to `swift-mock-kit`, that project's Momentum loads independently.

**Delight factor:** Cross-project continuity without cross-project contamination. Each repo has its own memory lane.

---

### 2.3 Enterprise — "The Meeting-Interrupted Engineer"

**Persona:** Priya, a senior engineer at a company using Slack, Jira, and Figma. She gets pulled into meetings, reviews, and cross-team conversations throughout the day. Her average uninterrupted coding session is 47 minutes.

**Before:** Priya returns from a 1-hour architecture meeting. She had 3 active branches across 2 projects. She spends 6 minutes re-orienting: reading Slack for updates, checking if her PR was reviewed, remembering which Jira ticket she was working on. Meanwhile, the designer responded to her Figma comment while she was in the meeting — she won't discover this until tomorrow.

**Story:** As an enterprise engineer with frequent context switches, I want my AI agent to not only restore my session state but also surface what changed while I was away — Slack messages, PR reviews, Jira status changes — so that I never miss a signal and never waste time re-discovering known information.

**After:** Priya opens Claude Code after her meeting. Momentum shows her session state plus: "@brenno approved your PR #142 (minor nit on line 47). PTECH-31204 moved to 'Ready for QA'. Designer responded to your Figma comment: border-radius discrepancy is intentional." Priya merges the PR, addresses the nit, and continues coding — all within 30 seconds of sitting down.

**Delight factor:** "While you were away" feels like having a chief of staff. The agent is not just remembering — it is watching.

---

### 2.4 OpenClaw — "The Life Context Keeper"

**Persona:** Sam, who uses xgh's OpenClaw archetype as a personal AI assistant across life tasks — not just code. Tracks appointments, errands, ongoing projects, and personal goals.

**Before:** Sam opens a session to plan their week. They have to manually remind the agent about the dentist appointment they rescheduled, the home renovation quote they were comparing, and the running training plan they are 3 weeks into.

**Story:** As an OpenClaw user, I want my AI assistant to maintain continuity across all my ongoing life tasks — not just code — so that every session feels like talking to someone who genuinely knows what is going on in my life.

**After:** Momentum: "You mentioned you'd follow up on the dentist appointment after your 2pm meeting yesterday. Your renovation quotes from 3 contractors are in — the cheapest is $4200. Week 3 of your half-marathon plan starts tomorrow (long run: 8 miles)." Sam says "Let me compare those quotes" and is immediately productive.

**Delight factor:** The feeling that the AI is a collaborator, not a tool. It remembers your life, not just your code.

---

## 3. Requirements

### 3.1 Must Have (P0) — Core Session Capture & Restore

These requirements form the minimum viable Momentum. Without all of them, the feature does not deliver its core promise.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **M-P0-01** | **Agent-side semantic state capture:** At natural stopping points (before commits, PR creation, sign-off), the agent writes semantic session state (task, next_steps, blockers, decisions, open_files) to `.xgh/momentum/agent-state.yaml`. | Agent instruction includes explicit snapshot-write triggers. `agent-state.yaml` includes: `session_id`, `active_task`, `status`, `next_steps[]`, `blockers[]`, `open_decisions[]`, `open_files[]`. File is written even if SessionEnd hook never fires. |
| **M-P0-02** | **Session snapshot restore:** At session start, read `.xgh/momentum/latest.yaml` and compose a Momentum Briefing injected into the agent's initial context. | Briefing renders in <500ms (local YAML + git only). Briefing includes: time since last session, branch name, task summary, next steps, uncommitted changes status. P1 with Cipher semantic enrichment: <2s. |
| **M-P0-03** | **SessionEnd hook (backup capture):** New hook `hooks/xgh-session-end-momentum.sh` that fires on session end as a **safety net**. The hook reads `agent-state.yaml` (written by the agent), enriches it with git state (branch, dirty files, recent commits, stash count), and writes the final `.xgh/momentum/latest.yaml`. If `agent-state.yaml` is missing (agent did not write it), the hook captures git-only state. | Hook registered in `hooks-settings.json` under `SessionEnd` event. Hook exits 0 even on capture failure (non-blocking). `latest.yaml` is always the merged result of agent semantic state + hook git state. |
| **M-P0-04** | **SessionStart integration:** Extend the existing `session-start.sh` hook to invoke Momentum restore after context tree loading. | Momentum briefing appended to session-start output. If no snapshot exists, no briefing is shown (graceful no-op). |
| **M-P0-05** | **Local snapshot storage:** Snapshots stored in `.xgh/momentum/` directory, git-ignored. | Directory created on first capture. `.gitignore` pattern `.xgh/momentum/` added by installer. `latest.yaml` is always the most recent. |
| **M-P0-06** | **Snapshot retention:** Configurable retention period (default: 30 days). Old snapshots archived as `{session_id}.yaml`. | Config key: `modules.momentum.snapshot_retention`. Cleanup runs on each capture. |
| **M-P0-07** | **Graceful first session:** On the very first session (no snapshot exists), Momentum produces no briefing — no error, no empty output, no confusion. | First session is indistinguishable from a non-Momentum session. On the second session, the magic begins. |
| **M-P0-08** | **`/xgh-momentum` skill:** Skill file `skills/momentum/momentum.md` and command `commands/momentum.md` for on-demand briefing invocation. | Skill shows current Momentum state. Supports `--status` flag to show last snapshot without composing a full briefing. |
| **M-P0-09** | **Git state enrichment:** Snapshot capture includes git branch, uncommitted file count, stash count, and most recent commit hash. | `git status --porcelain`, `git stash list`, `git log -1 --format=%H` are captured. Adds <50ms to capture time. |
| **M-P0-10** | **Config integration:** Momentum configuration lives in `.xgh/config.yaml` under `modules.momentum`. | Keys: `enabled` (bool), `snapshot_retention` (int, days), `briefing_verbosity` (auto/minimal/detailed). |
| **M-P0-11** | **Agent-initiated snapshot writes:** Agent writes snapshot at natural stopping points (before commits, PR creation, sign-off). The SessionEnd hook is a safety net, not the primary capture mechanism. | Agent instruction includes explicit snapshot-write triggers. Snapshot is written even if hook never fires. |
| **M-P0-12** | **techpack.yaml registration:** Momentum components (hook, skill, command, config) registered as components in `techpack.yaml`. | New component IDs: `momentum-session-end-hook`, `momentum-skill`, `momentum-command`. Components follow existing schema patterns. |

### 3.2 Should Have (P1) — Enhanced Features

These features differentiate Momentum from a simple "last session" log. They require Cipher integration.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **M-P1-01** | **Semantic session memory (Layer 2):** At session end, store a semantic summary of the session in Cipher. At session start, query Cipher for recent session summaries to enrich the briefing beyond the local snapshot. | Cipher memory tagged with `type: momentum-session`. Query retrieves last 5 sessions by recency. Briefing shows multi-session narrative, not just the last one. Restore budget with Cipher enrichment: <2s. |
| **M-P1-02** | **Open decisions tracking:** Snapshot captures explicit open decisions with the developer's "leaning" and reasoning. Briefing surfaces these prominently. | YAML schema: `open_decisions[].question`, `.leaning`, `.reason`. Briefing renders as "Open decision: [question]. You were leaning toward [leaning] because [reason]." |
| **M-P1-03** | **Historical views:** `/xgh-momentum --yesterday` and `/xgh-momentum --week` flags that aggregate multiple session snapshots into a summary. | `--yesterday` shows all sessions from the previous calendar day. `--week` shows the last 7 calendar days. Output is structured with per-session entries and a roll-up summary. |
| **M-P1-04** | **Multi-branch tracking:** When the developer switches branches during a session, Momentum captures per-branch state. Briefing shows all active branches, not just the current one. | Snapshot includes `branches[]` array. Each entry: `name`, `last_active`, `task`, `status`. Briefing highlights: "You also have work in progress on `fix/token-refresh` (last touched 2 days ago)." |
| **M-P1-05** | **Briefing verbosity auto-tuning:** `briefing_verbosity: auto` adjusts briefing length based on time gap. Short gap (<1 hour): minimal (2-3 lines). Long gap (>24 hours): detailed (full briefing with all context). | Verbosity thresholds: <1h = minimal, 1-8h = standard, 8-24h = detailed, >24h = full. Developer can override with explicit `minimal` or `detailed` in config. |

### 3.3 Nice to Have (P2) — Future Possibilities

These are features Momentum enables but does not implement in v1. They are documented here to shape architectural decisions.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **M-P2-01** | **Ambient signals (Layer 3):** Enterprise-only. On session start, query the ingest pipeline for changes since last session: Slack messages, Jira status changes, PR reviews, Figma updates. Append as "While you were away" section. | Requires xgh-ingest pipeline. Queries ingest data store with `since: last_session_end`. Renders per-source summaries. |
| **M-P2-02** | **Predictive tasking:** With enough session history (>20 sessions), predict what the developer will work on next based on day-of-week and time-of-day patterns. | Prediction model: simple frequency analysis. "You usually work on [project] on Monday mornings." Pre-loads that project's context. |
| **M-P2-03** | **Team handoff snapshots:** Opt-in sharing of Momentum snapshots between team members via shared Cipher workspace. | Snapshot includes `shareable: true` flag when the developer explicitly opts in. Shared snapshots are read-only for other team members. |
| **M-P2-04** | **Flow state detection:** Track session patterns (duration, interruption frequency, task focus ratio). Adapt briefing style: long uninterrupted session = minimal briefing, scattered day = detailed briefing with prioritized next steps. | Requires >10 sessions of history. Metric: session duration variance, task switch count. Output: `flow_profile: focused | scattered | exploring`. |
| **M-P2-05** | **Linked workspace momentum:** Cross-project continuity via the linked workspaces feature. "You were updating swift-mock-kit to support the new auth flow in tr-ios. tr-ios merged the auth changes yesterday." | Requires linked workspaces feature. Momentum queries linked projects' snapshots for cross-references. |
| **M-P2-06** | **Session analytics dashboard:** `/xgh-momentum --analytics` showing focus time, context-switching frequency, task completion patterns over 30 days. | Output: table with per-day summary (sessions, focus time, tasks completed, context switches). Trend indicators (arrows). |
| **M-P2-07** | **Standup generation:** `/xgh-momentum --standup` generates a standup-formatted summary from yesterday's sessions. | Output format: "Yesterday: [bullet list of completed/in-progress work]. Today: [planned next steps from latest snapshot]. Blockers: [list or 'none']." Suitable for pasting into Slack. |

---

## 4. User Experience

### 4.1 During a Session: Invisible Capture

Momentum's capture layer is completely invisible to the developer. There is no UI, no prompt, no confirmation.

**What happens under the hood:**

1. **Continuous observation:** The agent passively tracks which files are modified, which branch is active, what task is being worked on, and what decisions are made. This uses information already available in the session context — no additional tool calls.

2. **Agent writes semantic state (primary mechanism):** When the agent detects a logical pause (commit, PR creation, explicit "I'm done for now"), it writes `.xgh/momentum/agent-state.yaml` with the semantic session state: active task, next steps, blockers, open decisions, and open files. This happens at every natural stopping point, ensuring state is captured even if the session ends abruptly.

3. **SessionEnd hook fires (safety net):** `hooks/xgh-session-end-momentum.sh` executes. It:
   - Reads `.xgh/momentum/agent-state.yaml` (if present — the agent wrote it)
   - Runs `git status --porcelain` and `git log -1 --format=%H` (shell, <50ms)
   - Merges agent semantic state with git state
   - Writes `.xgh/momentum/latest.yaml` (YAML, <10ms)
   - Stores a semantic summary in Cipher (`cipher_store_reasoning_memory`)
   - Archives the previous `latest.yaml` as `{session_id}.yaml`
   - Cleans up snapshots older than `snapshot_retention` days
   - If `agent-state.yaml` is missing, captures git-only state as a fallback

4. **Total overhead:** <100ms for P0, <500ms for P1 (Cipher write is async-tolerant).

**What the developer sees:** Nothing. The session ends normally.

### 4.2 At Session Start: The Restore Moment

This is the "magic moment." The developer opens a new session and the agent already knows the context.

**Flow:**

```
1. Developer opens Claude Code
2. SessionStart hook fires
3. Hook loads context tree (existing behavior)
4. Hook checks for .xgh/momentum/latest.yaml
5. If found → compose Momentum Briefing
6. If not found → skip (first session behavior)
7. Briefing injected into agent's initial context
8. Agent presents briefing before developer types anything
```

**What the developer sees:**

```markdown
## 🐴 Momentum Briefing

**Picking up from:** 2 hours ago | Branch: `feat/archetype-modularization`

| | |
|---|---|
| **You were** | Implementing skill bundling for the Solo Dev archetype. Got about 60% through — skill filtering logic works, tests not yet written. |
| **Since then** | No new commits on main. No open PR reviews. 3 files still modified (uncommitted). |
| **Git state** | 🟡 Uncommitted changes in `skills/init/init.md`, `config/archetypes.yaml`, `tests/test-archetype.sh` |

### Next Steps
1. Write tests for skill filtering (you noted this as next)
2. Resolve open decision: where to store archetype selection
3. Run full test suite for regressions

### Open Decision
> **Should archetypes be mutable after init?**
> You were leaning: **Yes, via `/xgh-setup`**
> Reason: Users will want to upgrade from Solo to Enterprise
```

### 4.3 Output Style Guide

Momentum briefings follow the xgh output convention: scannable, emoji-accented, table-structured.

**Principles:**
- **Scannable over readable:** Use tables and bullet lists, not paragraphs. A developer should get the gist in 3 seconds.
- **Actionable over informative:** Every briefing ends with numbered next steps. The developer should be able to say "do step 1" immediately.
- **Honest over optimistic:** If the session state is ambiguous, say so. "I think you were working on X, but I'm not sure about the exact state."
- **Concise by default, detailed on request:** `auto` verbosity adapts to the gap length. Developer can always run `/xgh-momentum --detailed` for the full picture.

**Visual elements:**

| Element | Purpose |
|---------|---------|
| `## 🐴 Momentum Briefing` | Consistent header, immediately recognizable |
| Time + branch badges | Instant orientation: how long ago, which branch |
| "You were" / "Since then" table | Two-row summary: past state + delta |
| Git state with status emoji | 🟢 clean, 🟡 uncommitted changes, 🔴 conflicts |
| Numbered next steps | Actionable, ordered by priority |
| Blockquoted open decisions | Visually distinct, captures the nuance (leaning + reason) |
| "While you were away" section | Enterprise only — external signals |

### 4.4 Edge Cases

#### First Session Ever (No Snapshot)

**Behavior:** No briefing is shown. The session starts exactly as it does today. After this session ends, the first snapshot is captured. The developer will see their first Momentum Briefing on the second session.

**Why not show a "welcome" message?** Because it adds noise. Momentum's value proposition is *continuity* — and you cannot have continuity without a prior session. The "aha" moment comes when the developer is surprised by the briefing on session two, not when they see a placeholder on session one.

#### Session With No Meaningful Work

**Behavior:** If the session involved no file modifications, no commits, no meaningful decisions (e.g., the developer opened a session, asked a question, and closed it), the snapshot is still captured but marked with `status: idle`.

**Briefing impact:** The next session's briefing skips this idle session and restores from the last `in-progress` or `completed` snapshot instead.

```yaml
# Idle session snapshot
session_id: "2026-03-15T16:00:00Z"
branch: "main"
active_task: null
status: "idle"
next_steps: []
modified_files: []
uncommitted_changes: false
```

#### Conflicting State From Parallel Sessions

**Scenario:** Developer has two terminal tabs open, both running Claude Code on the same project. Tab A is working on feature X, Tab B is working on feature Y. Both sessions end within minutes of each other.

**Behavior:**
- Each session writes its snapshot. The last one to write wins `latest.yaml`.
- However, previous snapshots are archived as `{session_id}.yaml`, so no data is lost.
- On the next session start, Momentum reads `latest.yaml` (the winning snapshot) but also checks for archived snapshots within the last hour.
- If multiple recent snapshots exist, the briefing notes: "Multiple parallel sessions detected. Most recent: [branch X]. Also active: [branch Y]."

**Why not merge?** Because merging session states is a hard problem with subtle correctness issues. Showing both and letting the developer choose is simpler and more trustworthy.

#### Returning After a Long Absence (>7 days)

**Behavior:** The briefing includes a longer-form summary and explicitly notes the gap: "It's been 12 days since your last session. Here's a full summary of where things were." The verbosity auto-escalates to `detailed` regardless of the config setting.

Additionally, the briefing suggests running `/xgh-momentum --week` to see a summary of all sessions in the last month (if they exist), and checks for major changes on the main branch since the last session (`git log --oneline main..HEAD` equivalent).

#### Snapshot Corruption or Missing File

**Behavior:** If `.xgh/momentum/latest.yaml` is corrupted (invalid YAML) or missing (deleted manually), Momentum:
1. Logs a warning to `.xgh/momentum/momentum.log`
2. Falls back to Cipher query for recent session memories
3. If Cipher also has nothing, produces no briefing (same as first session)
4. Does not crash, does not show an error to the developer

---

## 5. Technical Boundaries

### 5.1 Data Captured and Storage

**What is captured:**

| Data Point | Storage Location | Retention |
|------------|-----------------|-----------|
| Session snapshot (YAML) | `.xgh/momentum/latest.yaml` (local, git-ignored) | Configurable, default 30 days |
| Archived snapshots | `.xgh/momentum/{session_id}.yaml` (local, git-ignored) | Same as above |
| Semantic session summary | Cipher vector memory (Qdrant) | Follows Cipher retention policy |
| Momentum log | `.xgh/momentum/momentum.log` | 7 days, max 5MB |
| Momentum config | `.xgh/config.yaml` → `modules.momentum` | Permanent (config file) |

**Snapshot schema (P0) — two-file split:**

The agent writes semantic state; the hook enriches with git state.

```yaml
# .xgh/momentum/agent-state.yaml  (written by the agent at natural stopping points)
schema_version: 1
session_id: "2026-03-15T14:32:00Z"       # ISO 8601 timestamp
active_task: "Implementing skill bundling"  # Human-readable task description
status: "in-progress"                       # in-progress | completed | blocked | idle
next_steps:                                 # Ordered list of intended next actions
  - "Wire up archetype selection in /xgh-init flow"
  - "Write tests for skill filtering"
blockers:                                   # Current blockers (empty if none)
  - "Need to decide: archetype storage location"
open_decisions:                             # Pending decisions with leaning
  - question: "Should archetypes be mutable after init?"
    leaning: "Yes, via /xgh-setup"
    reason: "Users will want to upgrade from Solo to Enterprise"
open_files:                                 # Files the agent was actively working with
  - "skills/xgh-init.md"
  - "config/archetypes.yaml"
session_duration_minutes: 47                # Approximate session length
```

```yaml
# .xgh/momentum/latest.yaml  (written by the SessionEnd hook, merging agent-state + git)
schema_version: 1
session_id: "2026-03-15T14:32:00Z"       # Copied from agent-state.yaml
branch: "feat/archetype-modularization"    # From git (hook-enriched)
commit_hash: "a1b2c3d"                     # HEAD at session end (hook-enriched)
active_task: "Implementing skill bundling"  # From agent-state.yaml
status: "in-progress"                       # From agent-state.yaml
next_steps:                                 # From agent-state.yaml
  - "Wire up archetype selection in /xgh-init flow"
  - "Write tests for skill filtering"
blockers:                                   # From agent-state.yaml
  - "Need to decide: archetype storage location"
open_decisions:                             # From agent-state.yaml
  - question: "Should archetypes be mutable after init?"
    leaning: "Yes, via /xgh-setup"
    reason: "Users will want to upgrade from Solo to Enterprise"
open_files:                                 # From agent-state.yaml
  - "skills/xgh-init.md"
  - "config/archetypes.yaml"
modified_files:                             # From git (hook-enriched)
  - "skills/xgh-init.md"
  - "config/archetypes.yaml"
uncommitted_changes: true                   # From git (hook-enriched)
stash_count: 0                              # From git (hook-enriched)
session_duration_minutes: 47                # From agent-state.yaml
```

### 5.2 Privacy: What NEVER Gets Stored

| Excluded Data | Reason |
|---------------|--------|
| File contents | Snapshots reference file paths only, never content. Content stays in git. |
| API keys, tokens, credentials | Explicitly excluded from all capture paths. Snapshot YAML only captures structured metadata. |
| Full conversation history | Only the distilled task summary, not the raw conversation. |
| Personal identifying information beyond git username | No email, no IP, no device info. |
| Contents of `.env` files | Never referenced, never captured. |
| Diff contents | Modified file list only, not the actual diffs. Too large, too sensitive. |
| Clipboard contents | Never accessed. |

**Privacy contract:** Momentum's snapshot is a *summary of work state*, not a *recording of work content*. A snapshot should be safe to accidentally commit — it would reveal what you were working on (branch name, task description) but not the code itself.

### 5.3 Performance Budget

| Operation | Budget | Method |
|-----------|--------|--------|
| **Snapshot capture (P0)** | <100ms total | `git status` (~30ms) + `git log -1` (~10ms) + YAML write (~5ms) + cleanup (~20ms) |
| **Snapshot capture (P1 addon)** | <500ms total | P0 + Cipher write (async-tolerant, can complete after session ends) |
| **Briefing restore (P0, local YAML + git only)** | <500ms | YAML read (~5ms) + `git status` (~30ms) + `git log --since` (~50ms) + markdown compose (~10ms) |
| **Briefing restore (P1, with Cipher semantic enrichment)** | <2000ms total | P0 + Cipher query (~1000ms) + semantic merge (~200ms) |
| **Briefing restore (P2 Enterprise)** | <3000ms total | P1 + ingest pipeline query (~1000ms) |
| **Snapshot disk usage** | <1KB per snapshot | YAML is tiny. 30 days x 6 sessions/day = 180 files x 1KB = <200KB. |
| **Snapshot cleanup** | <50ms | Glob + delete of expired files. |

**Non-negotiable:** Capture must NEVER block session end. If any operation takes longer than budget, it must be fire-and-forget (log the failure, move on).

### 5.4 Interaction With Existing xgh Components

#### Existing Hooks Inventory

xgh currently ships 4 hooks. Here is every hook, what it does today, and how Momentum leverages it:

| Hook | Event | What it does today | Momentum integration |
|------|-------|-------------------|---------------------|
| **`xgh-session-start.sh`** | `SessionStart` | Loads top 5 context tree files by score, injects decision table, optionally triggers `/xgh-brief` | **Extended.** After loading context tree, reads `.xgh/momentum/latest.yaml` and appends `"momentumBriefing"` key to JSON output. This is the **restore** moment. |
| **`xgh-prompt-submit.sh`** | `UserPromptSubmit` | Detects code-change intent via regex, injects Cipher tool hints | **Extended.** Detect natural stopping-point signals (commit messages, PR creation, "done"/"ship it" patterns) and inject a reminder for the agent to write `agent-state.yaml`. This is the **capture trigger**. |
| **`cipher-pre-hook.sh`** | `PreToolUse` (Cipher extract/workspace tools) | Warns when sending complex content to Cipher's 3B extraction model | **No change.** Operates independently. |
| **`cipher-post-hook.sh`** | `PostToolUse` (Cipher extract/workspace tools) | Detects `extracted:0` failures, instructs agent to retry via direct Qdrant storage | **Indirect benefit.** Ensures Momentum's Cipher writes (session summaries) succeed even with complex content. |

#### New Hook

| Hook | Event | Purpose |
|------|-------|---------|
| **`xgh-session-end-momentum.sh`** | `SessionEnd` | **Safety net.** Reads `agent-state.yaml` (if written by agent), enriches with git state, writes `latest.yaml`. Falls back to git-only snapshot if agent didn't write state. Must be registered in `hooks-settings.json`. |

**Hook registration change:**

```json
{
  "hooks": {
    "SessionStart": [ /* existing, extended */ ],
    "UserPromptSubmit": [ /* existing, unchanged */ ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-session-end-momentum.sh"
          }
        ]
      }
    ]
  }
}
```

#### Existing Skills Integration

Skills that naturally interact with Momentum — either as capture triggers or restore consumers:

| Skill | Momentum role | How |
|-------|--------------|-----|
| **`/xgh-brief`** | **Restore consumer.** | Momentum adds a "Where you left off" section *before* the Slack/Jira/GitHub data. The briefing becomes: last session state → what changed since → what needs attention. |
| **`/xgh-curate`** | **Capture trigger.** | When the user curates knowledge, that's a natural stopping point. The curate skill should trigger an `agent-state.yaml` write — the decision being curated likely belongs in `open_decisions`. |
| **`/xgh-status`** | **Health display.** | Status adds a Momentum section: last snapshot age, restore count, session streak, snapshot disk usage. |
| **`/xgh-implement`** | **Capture trigger.** | Implementation tasks have clear milestones (test passing, commit, PR). Each milestone triggers a snapshot write with updated `next_steps`. |
| **`/xgh-investigate`** | **Capture trigger.** | Investigation sessions produce findings and hypotheses. The investigate skill should write these into `open_decisions` so the next session picks up where debugging left off. |
| **`/xgh-help`** | **Contextual hint.** | If Momentum detects a stale snapshot (>24h), help suggests running `/xgh-brief` to re-orient. |

#### Cipher MCP

- **Capture (P0):** Uses `cipher_store_reasoning_memory` to store session summaries. Tagged with `type: momentum-session` for filtered retrieval.
- **Restore (P1 enrichment):** Uses `cipher_memory_search` with query "recent session context" filtered by `type: momentum-session`, limited to last 5 results. Adds multi-session narrative to briefing (P1 restore budget: <2s).
- **No new Cipher capabilities required.** Momentum uses existing Cipher tools. Cipher is a P0 dependency for all archetypes.

#### Context Tree

- **No direct interaction.** Momentum operates alongside the context tree, not inside it. Momentum is ephemeral session state; the context tree is durable team knowledge. They complement each other.
- **Possible future integration (P2):** If a decision captured in a Momentum snapshot is later confirmed/validated, it could be promoted to the context tree via `/xgh-curate`.

#### Ingest Pipeline

- **P0/P1:** No interaction with ingest.
- **P2 (Enterprise Layer 3):** Queries ingest data store for changes since `last_session_end`. Uses the same data that `/xgh-brief` already accesses, filtered by time window.

### 5.5 Archetype Tiering

Cipher is a P0 dependency for all archetypes. There is no "Core" tier without Cipher -- the Cipher integration (Layer 2) is what makes Momentum meaningfully better than `git log`.

| Capability | Standard (all archetypes) | Enterprise |
|------------|:-----------------------:|:---------:|
| Session snapshot capture (Layer 1) | **Yes** | **Yes** |
| Session snapshot restore + briefing | **Yes** | **Yes** |
| `/xgh-momentum` command | **Yes** | **Yes** |
| Git state enrichment | **Yes** | **Yes** |
| Semantic session memory (Layer 2, Cipher) | **Yes** | **Yes** |
| Open decisions tracking | **Yes** | **Yes** |
| Multi-branch tracking | **Yes** | **Yes** |
| Historical views (--yesterday, --week) | **Yes** | **Yes** |
| Briefing verbosity auto-tuning | **Yes** | **Yes** |
| Ambient signals / "While you were away" (Layer 3) | | **Yes** |
| Team handoff snapshots | | **Yes** |
| Predictive tasking | | **Yes** |

**Auto-selection:** The tier auto-selects based on the archetype chosen during `/xgh-init`:
- Solo Dev → Standard
- OSS Contributor → Standard
- Enterprise → Enterprise
- OpenClaw → Standard

---

## 6. Non-Goals

Momentum is a session continuity layer. These are things it explicitly does NOT do:

| Non-Goal | Why Not | Related Feature |
|----------|---------|-----------------|
| **Code review or diff analysis** | Momentum captures *what* files changed, not *how*. Code analysis is a different skill. | `/xgh-investigate`, `git diff` |
| **Task management or ticket creation** | Momentum surfaces tasks, it does not manage them. No Jira integration for task creation. | Jira MCP, `/xgh-implement` |
| **Automated commits or PRs** | Momentum observes git state, it never modifies it. No auto-commit, no auto-push. | Developer's own workflow |
| **Real-time collaboration** | Momentum is async and per-session. It does not support live co-editing or real-time sync between agents. | `/xgh-collab` |
| **Full conversation replay** | Momentum captures a distilled summary, not the full conversation transcript. Session Replay (the other proposal in `developer-experience.md`) covers this. | Session Replay (separate feature) |
| **Performance monitoring** | Momentum is not an APM tool. It does not track build times, test durations, or system metrics. | External monitoring tools |
| **Notifications or alerts** | Momentum surfaces information at session start. It does not push notifications between sessions. | Ingest pipeline notifications |
| **Cross-machine sync** | Snapshots are local-only (git-ignored). Cipher provides cross-machine memory, but the local snapshot is device-specific. | Cipher MCP (already cross-machine) |

**What Momentum enables but does not implement:**

- **Session Analytics** — Momentum's archived snapshots are the data source for a future analytics feature. But Momentum itself does not compute or display analytics in P0/P1 (standup generation is P2).
- **Predictive Tasking** — Momentum captures the patterns. A future feature could analyze them for predictions. Momentum itself does not predict.
- **Team Handoffs** — Momentum's snapshot format is designed to be shareable. But v1 does not implement the sharing mechanism.

---

## 7. Open Questions

These are design decisions that need user input, prototyping, or further technical investigation before implementation.

### 7.1 Design Decisions Needing Input

| # | Question | Options | Recommendation | Needs |
|---|----------|---------|---------------|-------|
| Q1 | **How does the agent compose the snapshot?** The SessionEnd hook is a shell script, but the session context (active task, next steps, open decisions) lives in the agent's conversation, not in shell-accessible state. | (a) Agent writes the YAML before the hook fires, hook just validates. (b) Hook passes a template, agent fills it. (c) The skill instruction tells the agent to always write the snapshot as the last action before session end. | **RESOLVED:** Split responsibility. Agent writes semantic state (task, next_steps, blockers, decisions, open_files) to `agent-state.yaml`. Hook reads `agent-state.yaml`, enriches with git state (branch, dirty files, recent commits), and writes final `latest.yaml`. See M-P0-01 and M-P0-03. | Resolved. |
| Q2 | **Should Momentum have an explicit "session end" trigger?** Claude Code sessions can end abruptly (terminal close, timeout, crash). | (a) Rely on `SessionEnd` hook only. (b) Periodic snapshot writes every N minutes as a safety net. (c) Agent writes snapshot at natural stopping points + hook as backup. | **RESOLVED:** Option (c). Agent-side writes at natural stopping points (before commits, PR creation, sign-off) are the primary capture mechanism. The SessionEnd hook is a safety net, not the primary mechanism. See M-P0-11. | Resolved. |
| Q3 | **Where does the Momentum config live?** | (a) `.xgh/config.yaml` (new file). (b) Inside `ingest.yaml` under a `momentum` key. (c) Standalone `.xgh/momentum/config.yaml`. | **(a)** — `.xgh/config.yaml` is the natural home for module-level configuration. `ingest.yaml` is ingest-specific. Standalone config is unnecessary fragmentation. | Confirm `.xgh/config.yaml` does not already exist with conflicting schema. |
| Q4 | **Should the briefing be injected automatically or require developer opt-in?** | (a) Always inject on session start. (b) Inject only if `XGH_MOMENTUM=1` env var is set. (c) Inject by default, suppress with `XGH_MOMENTUM=0`. | **(c)** — Default-on with opt-out. The value of Momentum is in the zero-friction experience. Requiring opt-in defeats the purpose. | User testing: does the briefing ever feel intrusive for short sessions? |
| Q5 | **What happens when the developer changes projects (different repo)?** | (a) Momentum is per-project (each repo has its own `.xgh/momentum/`). (b) Global Momentum that spans projects. | **(a)** — Per-project. Each repo has its own `.xgh/momentum/` directory with its own snapshots. Cross-project continuity is a P2 feature (linked workspaces). | Confirm that Claude Code sessions are scoped to a project directory. |

### 7.2 Technical Unknowns

| # | Unknown | Risk Level | Investigation Plan |
|---|---------|-----------|-------------------|
| T1 | **SessionEnd hook reliability.** Does the `SessionEnd` hook fire reliably on all termination paths (graceful exit, terminal close, SSH disconnect, crash)? | High | Test all termination paths in Claude Code. If unreliable, implement periodic snapshot writes as a P0 fallback. |
| T2 | **Agent-authored YAML quality.** Can the agent reliably produce well-formed YAML for the snapshot, including correct quoting and escaping? | Medium | Prototype with 10 diverse sessions. Validate output with a YAML parser in the hook. If unreliable, use JSON instead of YAML. |
| T3 | **Cipher query latency under load.** With hundreds of session memories, does `cipher_memory_search` stay under 1000ms for the P1 restore flow? | Medium | Benchmark Cipher with 500 `momentum-session` type entries. If slow, implement a local index of recent session IDs to avoid broad semantic search. |
| T4 | **Hook output size limits.** The SessionStart hook returns JSON. Is there a size limit on hook output that could truncate a long Momentum Briefing? | Low | Test with a briefing exceeding 2KB. If limited, move the briefing to a file reference instead of inline JSON. |
| T5 | **Parallel session conflict frequency.** How often do developers actually run parallel Claude Code sessions on the same project? | Low | Add a counter to the snapshot: `parallel_session_count`. Analyze after 30 days of usage. If <5% of sessions are parallel, defer the conflict resolution UX. |

### 7.3 Scope Boundary Questions

| # | Question | Current Answer | May Change If |
|---|----------|---------------|---------------|
| S1 | Is Session Replay (the other proposal) a prerequisite for Momentum? | **No.** They are independent. Momentum captures *distilled state*, Replay captures *full history*. | User testing reveals that developers want to see the full conversation, not just the summary. |
| S2 | Does Momentum replace `/xgh-brief`? | **No.** `/xgh-brief` is an on-demand briefing from ingest sources (Slack, Jira). Momentum is automatic session state restoration. They can coexist — Momentum runs first, `/xgh-brief` adds external context. | Enterprise Layer 3 absorbs `/xgh-brief` functionality, making them redundant. |
| S3 | Should Momentum snapshots be stored in the context tree? | **No.** Snapshots are ephemeral personal state, not durable team knowledge. The context tree is for validated, shared knowledge. | A "promoted decisions" flow moves confirmed decisions from Momentum to the context tree. |
| S4 | Should Momentum work without Cipher? | **No.** Cipher is a P0 dependency for all archetypes. The Core tier has been removed — Cipher integration is what makes Momentum meaningfully better than `git log`. | N/A — resolved. |

---

## Appendix A: Implementation Sequence

Suggested implementation order, mapping to existing xgh development patterns:

| Phase | Scope | Components | Est. Effort |
|-------|-------|-----------|-------------|
| **Phase 1** | P0 Core (agent-state + hook capture + restore) | `agent-state.yaml` schema, agent snapshot-write instructions, `session-end-momentum.sh` (hook reads agent-state, enriches with git, writes `latest.yaml`), `session-start.sh` extension, `.xgh/momentum/` directory, `skills/momentum/momentum.md`, `commands/momentum.md`, config schema, `techpack.yaml` registration | 2-3 days |
| **Phase 2** | P0 Polish (edge cases, first session, config) | Graceful first session, idle session detection, snapshot retention cleanup, Cipher P0 integration, tests | 1-2 days |
| **Phase 3** | P1 Enhanced (historical views, multi-branch) | `--yesterday`/`--week` flags, open decisions tracking, multi-branch tracking, verbosity auto-tuning | 3-4 days |
| **Phase 4** | P2 Extended (ambient signals, standup, analytics) | Layer 3 ingest integration, "While you were away" section, team handoff snapshots, `--standup` generation, session analytics | 2-3 days (after archetype modularization) |

**Total estimated effort:** 8-12 days for P0+P1. P2 is deferred until the archetype system ships.

---

## Appendix B: Snapshot Format Evolution

The snapshot uses `schema_version` to support forward-compatible evolution:

| Version | Additions | Breaking Changes |
|---------|-----------|-----------------|
| **v1** (P0 launch) | Two-file split: `agent-state.yaml` (semantic: `session_id`, `active_task`, `status`, `next_steps`, `blockers`, `open_decisions`, `open_files`, `session_duration_minutes`) + `latest.yaml` (merged: agent-state + git-enriched `branch`, `commit_hash`, `modified_files`, `uncommitted_changes`, `stash_count`) | N/A (initial version) |
| **v2** (P1) | `open_decisions[]`, `branches[]`, `semantic_summary`, `mood` (optional) | None — additive only |
| **v3** (P2) | `parallel_session_count`, `ambient_signals{}`, `shareable` flag | None — additive only |

**Compatibility rule:** Momentum must always be able to read snapshots from older schema versions. Unknown fields are ignored. Missing fields use sensible defaults (empty arrays, `false`, `null`).

---

*This PRD is a living document. Update it as design decisions from Section 7 are resolved.*
