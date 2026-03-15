# Developer Experience & Workflows — Feature Proposals

**Domain:** How xgh feels to use day-to-day, the rituals it creates, the friction it removes.
**Date:** 2026-03-15
**Status:** Proposal

---

## Two Feature Ideas

### Idea 1: Session Replay

A `/xgh-replay` skill that reconstructs what happened in previous sessions — what decisions were made, what files were changed, what rationale was used — so you can pick up exactly where you left off or hand off to a teammate. Think `git log` but for your AI collaboration history, with semantic search over the *reasoning* not just the commits.

### Idea 2: Momentum

A background system that eliminates the "cold start" problem by preloading relevant context, surfacing unfinished work, and creating a persistent sense of forward motion across sessions. Instead of you telling the agent what you're working on, the agent already knows — and picks up mid-stride.

---

## Detailed Proposal: Momentum

### 1. Name

**Momentum** (`/xgh-momentum`)

### 2. One-liner

Momentum eliminates the cold-start tax by making every new session feel like a continuation of the last one — not a blank slate.

### 3. The Problem

Every time a developer opens a new AI coding session, there is an invisible tax: re-establishing context. Even with persistent memory (Cipher) and a committed knowledge base (context tree), the developer still has to:

1. **Remember** what they were doing — which task, which branch, which decision they were in the middle of.
2. **Re-explain** the current state — "I was refactoring the auth module, I got halfway through, the tests are broken because..."
3. **Re-orient** the agent — paste relevant files, point to the right docs, remind it of team conventions.
4. **Recall blockers** — "Oh right, I was stuck because the API endpoint changed and I was waiting on design review."

This adds 2-5 minutes of friction to every session. Across a team of engineers each starting 4-6 sessions/day, that is 40-150 minutes of wasted context reconstruction *per day*. Worse, it is cognitively draining — the developer has to context-switch from "doing the work" to "describing the work to the agent" before they can even start.

The irony: xgh already *has* all the information needed to eliminate this. Memory stores past decisions. The context tree holds conventions. Git holds the working state. The ingest pipeline captures external signals. But nothing ties them together into a *session-level continuity layer*.

### 4. Which Archetypes Benefit

| Archetype | How Momentum Helps | Intensity |
|---|---|---|
| **Solo Dev** | Picks up personal projects seamlessly between evenings/weekends. No more "where was I?" after a 3-day gap. The simplest form: last session summary + open branches + uncommitted work. | Medium |
| **OSS Contributor** | Juggles multiple repos. Momentum per-project means switching from `xgh` to `swift-mock-kit` to `tr-ios` doesn't require mental re-loading. Shows which PRs are open, which reviews need attention. | High |
| **Enterprise** | The biggest win. Engineers are pulled into meetings, context-switch between initiatives, and lose 30+ minutes/day to re-orientation. Momentum integrates with the ingest pipeline (Slack/Jira signals) to surface not just where *you* were, but what *changed* while you were away. | Very High |
| **OpenClaw** | Personal assistant continuity — remembers ongoing tasks, deadlines, life context. "You mentioned you'd follow up on the dentist appointment after your 2pm meeting." | Medium |

### 5. How It Works

**Architecture: Three Layers**

```
Layer 1: Session Snapshot (git-local, automatic)
Layer 2: Continuity Engine (Cipher memory, semantic)
Layer 3: Ambient Signals (ingest pipeline, external)
```

**Layer 1 — Session Snapshot** (all archetypes)

At session end (or when the agent detects a natural stopping point), Momentum automatically captures a structured snapshot:

```yaml
# .xgh/momentum/latest.yaml (git-ignored, local only)
session_id: "2026-03-15T14:32:00Z"
branch: "feat/archetype-modularization"
active_task: "Implementing skill bundling for Solo Dev archetype"
status: "in-progress"
next_steps:
  - "Wire up archetype selection in /xgh-init flow"
  - "Write tests for skill filtering by archetype"
blockers:
  - "Need to decide: should archetype be stored in .xgh/config.yaml or ingest.yaml?"
open_decisions:
  - question: "Should archetypes be mutable after init?"
    leaning: "Yes, via /xgh-setup"
    reason: "Users will want to upgrade from Solo to Enterprise"
modified_files:
  - "skills/xgh-init.md"
  - "config/archetypes.yaml"
  - "tests/test-archetype.sh"
uncommitted_changes: true
mood: "productive"  # optional, inferred from session tone
```

This is a structured YAML file, not a memory entry — it is deterministic, fast to read, and does not require a vector search to retrieve.

**Layer 2 — Continuity Engine** (Solo Dev+)

When a new session starts, the `SessionStart` hook triggers the Momentum skill, which:

1. Reads `.xgh/momentum/latest.yaml` (instant, local)
2. Queries Cipher for recent session memories (semantic: "what was I working on?")
3. Runs `git status`, `git log --since=last-session`, `git stash list`
4. Composes a **Momentum Briefing** — a concise, actionable summary injected into the agent's context

The briefing format:

```markdown
## Momentum Briefing

**Picking up from:** 2 hours ago (same branch: feat/archetype-modularization)

**You were:** Implementing skill bundling for the Solo Dev archetype.
Got about 60% through — the skill filtering logic works, but tests
are not yet written.

**Since then:**
- No new commits on main
- No open PR reviews
- Your uncommitted changes are still here (3 files modified)

**Suggested next steps:**
1. Write tests for skill filtering (you noted this as next)
2. Resolve open decision: where to store archetype selection
3. Run existing test suite to check for regressions

**Open decision:** Should archetypes be mutable after init?
You were leaning toward yes, via /xgh-setup.
```

**Layer 3 — Ambient Signals** (Enterprise archetype)

For teams using the ingest pipeline, Momentum also checks:

- New Slack messages in tracked channels since last session
- Jira ticket status changes (was your blocker resolved?)
- PR review comments that came in overnight
- Design updates in Figma (if configured)

These are appended to the briefing as a "While you were away" section:

```markdown
**While you were away:**
- @brenno replied on your PR #142: "LGTM, minor nit on line 47"
- PTECH-31204 moved from "In Review" to "Ready for QA"
- 3 new messages in #passcode-ios (summary: API contract finalized)
```

### 6. Use Cases

**Engineer Perspective: The Monday Morning**

It is Monday. You worked on a complex refactor Friday afternoon. You open Claude Code. Instead of spending 5 minutes reading git log and trying to remember what you were doing, you see:

> "You were refactoring the coordinator pattern in AuthFlow. You finished the protocol extraction but stopped before updating the 4 view controllers that conform to it. Tests are currently red (3 failures, all in AuthFlowTests — expected, since the protocol changed). You had a note that LoginViewController is the trickiest because it has a custom animation delegate."

You say "continue" and the agent starts on LoginViewController. Zero re-orientation.

**PM Perspective: The Standup Shortcut**

A PM asks: "What did you work on yesterday?" Instead of trying to remember or scrolling through commits, you run `/xgh-momentum --yesterday` and get a structured summary:

> "3 sessions. First: fixed the race condition in token refresh (PR #147, merged). Second: started archetype modularization (branch created, 40% done). Third: reviewed Brenno's PR on the design system, left 4 comments."

This takes 2 seconds and is more accurate than anything you would write from memory. The metric: time-to-standup-answer drops from 3 minutes of recall to instant. Session count, focus ratio (time on primary task vs context-switching), and completion velocity become measurable.

**Designer Perspective: The Context Bridge**

You are a frontend engineer who also does design implementation. You were matching a Figma comp to CSS on Thursday, then got pulled into backend work for two days. When you return on Monday, Momentum shows:

> "Last session on this branch was Thursday. You were matching the card component to Figma frame 'Card/Default'. You noted that the border-radius was 12px in Figma but the design system token is 8px — you flagged this in #design-review and were waiting for a response."

You check Slack — the designer responded Friday. The discrepancy is intentional. You update the token and move on. Without Momentum, you would have re-discovered the discrepancy, re-checked Figma, and maybe filed a duplicate question.

### 7. The "Aha" Moment

The aha moment happens on the **second session**, not the first.

The first session, you use xgh normally. The agent stores a snapshot. You do not notice anything.

The second session, you open Claude Code and *before you type anything*, the agent says: "Last time you were working on X. You got to Y. Want to continue?"

That is the moment. The realization that the agent has *continuity*. It is not a blank slate. It is not a chatbot you have to re-brief. It is a collaborator that remembers. The feeling is not "oh, a cool feature" — it is "oh, this is how it should have always worked." Like the first time you used `git stash` and realized you did not have to lose your work to switch branches.

The second aha comes when you return to a project after a week. You expect to spend 10 minutes re-orienting. The agent gives you a 15-second briefing and you are immediately productive. The gap between "I should work on this" and "I am working on this" collapses to near-zero.

### 8. What It Enables

Momentum is a foundation layer that unlocks several downstream features:

- **Session Analytics** — Track focus time, context-switching frequency, task completion patterns. A `/xgh-review` skill could aggregate Momentum data for performance reviews or personal productivity insights.

- **Predictive Tasking** — With enough session history, Momentum can predict what you will work on next ("You usually work on the iOS project Monday mornings") and pre-load that context before you even ask.

- **Team Handoffs** — Momentum snapshots could be shared (opt-in) between team members. "Sarah was working on this and got stuck here — here is her exact context." Pair programming without the pairing.

- **Linked Workspace Momentum** — Combined with the linked workspaces feature, Momentum could track cross-project continuity. "You were updating swift-mock-kit to support the new auth flow in tr-ios. tr-ios merged the auth changes yesterday — you can now proceed."

- **Flow State Detection** — By tracking session patterns (long uninterrupted sessions vs frequent short ones), Momentum can learn your flow-state triggers and optimize briefing length. Deep-focus session? Minimal briefing. Scattered day? Detailed briefing with prioritized next steps.

- **Standup/Status Automation** — Momentum data feeds directly into automated status updates. A `/xgh-standup` skill could generate a standup message from yesterday's sessions, formatted for your team's Slack channel.

### 9. Pluggability

Momentum ships as an optional module with three tiers that map to archetypes:

**Core Module** (installed for all archetypes)
- `hooks/xgh-session-end-momentum.sh` — SessionEnd hook that captures the snapshot
- `skills/xgh-momentum.md` — Skill definition for the `/xgh-momentum` command
- `.xgh/momentum/` directory (git-ignored) for local snapshot storage
- Dependencies: git (already required), Cipher MCP (already required)

**Enhanced Module** (Solo Dev, OSS Contributor, Enterprise)
- Adds Layer 2 (Continuity Engine) — semantic session memory via Cipher
- Adds `--yesterday` and `--week` flags for historical views
- Adds multi-branch tracking (for OSS contributors juggling repos)
- Dependencies: none beyond core xgh

**Enterprise Module** (Enterprise archetype only)
- Adds Layer 3 (Ambient Signals) — integration with the ingest pipeline
- Adds "While you were away" section to briefings
- Adds team handoff snapshots (opt-in sharing)
- Dependencies: xgh-ingest pipeline (Slack, Jira, etc.)

**Installation:**

Momentum is selected by default when choosing any archetype during `/xgh-init`. It can be disabled via `/xgh-setup` or by removing the hook from `hooks-settings.json`. The module tiers auto-select based on archetype — no additional configuration needed.

```yaml
# .xgh/config.yaml
modules:
  momentum:
    enabled: true
    tier: "enhanced"  # auto-set by archetype
    snapshot_retention: 30  # days to keep local snapshots
    briefing_verbosity: "auto"  # auto | minimal | detailed
```

The snapshot format (YAML) is intentionally simple and human-readable so that other tools, scripts, or even non-xgh agents can consume it. This makes Momentum a protocol, not just a feature — other MCS tech packs could adopt the same `.xgh/momentum/latest.yaml` format for interoperability.
