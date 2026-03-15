# Intelligence & Proactive Behavior — Feature Proposals

**Date:** 2026-03-15
**Domain:** Intelligence & Proactive Behavior
**Status:** Proposal

---

## Two Feature Ideas

### Idea 1: Déjà Vu — Pattern-Matched Preemptive Warnings

Every engineering team makes the same mistakes in cycles. Someone picks an approach that was tried and abandoned six months ago. Someone refactors a module without knowing that three past attempts caused regressions. The knowledge exists in memory — but nobody asks for it at the right time.

**Déjà Vu** intercepts agent actions in real-time (via hooks) and pattern-matches them against stored reasoning memories, past failures, and archived decisions. When it detects that the current trajectory resembles a known bad outcome, it surfaces a warning *before* the damage is done. Not a search you have to remember to run — a tripwire that fires automatically.

### Idea 2: Momentum — Session-Aware Adaptive Planning

Agents today start every session from zero. Even with briefings and memory, the agent doesn't know *how well* past sessions went, *which approaches worked*, or *where momentum stalled*. It can't distinguish "we're making great progress, keep pushing" from "we've been stuck on this for three sessions, try something different."

**Momentum** tracks execution velocity across sessions: what was attempted, what succeeded, what was reverted, where time was spent. It builds a per-task trajectory model and uses it to proactively adjust strategy — suggesting pivots when stuck, surfacing alternative approaches from memory when the current one plateaus, and highlighting when a task is going suspiciously smoothly (a sign that edge cases are being missed).

---

## Favorite: Déjà Vu — Pattern-Matched Preemptive Warnings

### 1. Name

**Déjà Vu**

### 2. One-liner

Automatically warns agents when their current approach matches a pattern that has failed before — before the failure happens again.

### 3. The Problem

Memory systems are *pull-based*. They store knowledge faithfully but require someone — human or agent — to ask the right question at the right moment. The problem is that you don't know what you don't know. The most dangerous knowledge gaps aren't the ones you're aware of; they're the ones where you don't even realize a question should be asked.

Consider:
- An engineer starts implementing caching with Redis. Three months ago, a different engineer tried Redis for this service and reverted it because of connection pool exhaustion under load. That reasoning chain sits in Cipher. But why would the current engineer search for "Redis connection pool failures" when they're confidently setting up caching?
- A new contributor refactors the authentication middleware. The context tree has a decision record explaining why the current (ugly) implementation handles a subtle race condition. But the contributor doesn't know the decision exists, so they never search for it.
- A team adopts a new API pattern. The pattern was tried in another project six months ago and abandoned after causing integration test flakiness. The cross-project memory exists, but nobody thinks to check.

The failure mode is always the same: the knowledge exists, but the trigger to retrieve it is missing. **Déjà Vu solves the trigger problem.**

### 4. Which Archetypes Benefit

| Archetype | How Déjà Vu Helps | Value Level |
|---|---|---|
| **Solo Dev** | Guards against your own forgotten mistakes. You tried something six months ago, abandoned it, forgot why. Déjà Vu remembers for you. Prevents the solo developer's worst enemy: repeating your own history because there was no one around to remind you. | High |
| **OSS Contributor** | Surfaces institutional knowledge to newcomers who can't possibly know the project's history. A contributor opens a PR that restructures something — Déjà Vu flags that this was tried in issue #247 and reverted. Dramatically reduces maintainer review burden. | Very High |
| **Enterprise** | Cross-team knowledge sharing without meetings. Team A's failure becomes Team B's warning. Compliance teams get audit evidence that known risks were surfaced. Reduces "why didn't anyone tell us?" moments that derail sprints. | Very High |
| **OpenClaw** | Personal assistant remembers your past learning experiences. "Last time you set up a Kubernetes cluster, you spent 4 hours on RBAC — here's the pattern you eventually used." Turns personal history into personal coaching. | Medium |

### 5. How It Works

#### Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     Déjà Vu Module                       │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────┐     ┌──────────────┐    ┌───────────┐  │
│  │ Signal       │     │ Pattern      │    │ Warning   │  │
│  │ Extractor    │────>│ Matcher      │───>│ Composer  │  │
│  └─────────────┘     └──────────────┘    └───────────┘  │
│        ▲                    ▲                   │        │
│        │                    │                   ▼        │
│  ┌─────────────┐     ┌──────────────┐    ┌───────────┐  │
│  │ Hook         │     │ Cipher +     │    │ Hook      │  │
│  │ Input        │     │ Context Tree │    │ Output    │  │
│  │ (prompt/     │     │ (known       │    │ (injected │  │
│  │  tool call)  │     │  patterns)   │    │  warning) │  │
│  └─────────────┘     └──────────────┘    └───────────┘  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

#### Three-stage pipeline

**Stage 1 — Signal Extraction (hook layer, fast)**

Runs inside the existing `PreToolUse` or `UserPromptSubmit` hook. Extracts lightweight signals from the agent's current intent:

- **Action signals**: What tool is being called? What file is being modified? What pattern is being applied? (e.g., "adding Redis cache to user-service," "refactoring auth middleware," "switching from REST to gRPC")
- **Context signals**: What ticket is being worked on? What branch? What area of the codebase?
- **Approach signals**: Keywords and patterns that indicate a technical direction (framework names, architectural patterns, library choices)

This stage is deliberately shallow — it extracts 3-5 signal terms, not a full semantic analysis. Speed matters because it runs on every action.

**Stage 2 — Pattern Matching (Cipher query, sub-second)**

Takes the extracted signals and runs a targeted Cipher search against a dedicated `deja_vu` collection containing:

- **Failure memories**: Past sessions where an approach was tried and reverted/abandoned, tagged with `outcome: failed` and `reason: <why>`
- **Decision records**: Architectural decisions from the context tree, especially ones tagged with `alternatives_rejected` (the roads not taken and why)
- **Regression markers**: Past bugs or incidents linked to specific code areas or patterns
- **Cross-project patterns**: If linked workspaces are configured, patterns from sibling projects

The search uses a hybrid query: semantic similarity on the signal terms + BM25 keyword match on file paths, library names, and pattern identifiers. Results above a configurable confidence threshold (default: 0.75) proceed to Stage 3.

**Stage 3 — Warning Composition (LLM call, optional)**

For matches above threshold, compose a human-readable warning. Two modes:

- **Fast mode** (default): Template-based. No LLM call. Pulls the stored reasoning directly: "This approach was tried on [date] in [context] and [outcome]. Reason: [stored reason]. See: [link to decision record]."
- **Rich mode** (opt-in): Uses the local LLM (already running for Cipher) to synthesize a contextual warning that explains *why this specific situation matches* and *what to do instead*.

The warning is injected into the hook response, appearing in the agent's context as a system-level advisory — the same mechanism the existing decision table uses, but with dynamic content.

#### Memory Structure

Déjà Vu reads from existing memory but introduces one new memory type:

```yaml
type: deja_vu_pattern
id: "dv-2026-03-15-redis-cache-user-service"
signals:
  - "redis"
  - "cache"
  - "user-service"
  - "connection pool"
area: "src/services/user/"
outcome: "reverted"
severity: "high"
reason: "Connection pool exhaustion under >200 concurrent users. Redis Cluster mode required but not configured. Fallback to in-memory LRU cache with TTL was sufficient for this use case."
original_session: "2025-12-08"
ticket: "USR-1847"
related_decisions:
  - "context-tree://architecture/caching-strategy.md"
```

These patterns are created automatically during the existing post-session curation step (the `cipher_extract_and_operate_memory` call). When an agent reverts code, abandons an approach, or explicitly records a "this didn't work" moment, the post-session hook extracts it as a `deja_vu_pattern`. No extra manual work.

#### Confidence Calibration

False positives are the death of warning systems. Déjà Vu uses three calibration mechanisms:

1. **Decay**: Pattern match confidence decays over time. A failure from last week is highly relevant; one from two years ago is less so (technologies change). Configurable half-life (default: 6 months).
2. **Feedback loop**: If an agent acknowledges a warning and proceeds anyway (successfully), the pattern's confidence for that specific signal combination decreases. If the agent heeds the warning, confidence holds.
3. **Specificity threshold**: Generic matches ("you used Redis before") are suppressed. Only specific matches ("you used Redis for caching in a high-concurrency service and hit connection pool limits") fire.

### 6. Use Cases

#### Engineer: "I've been here before"

Yuki is implementing a WebSocket-based notification system for a microservice. She starts writing the connection manager. Déjà Vu fires:

> **Pattern match (0.82 confidence):** WebSocket connection management in this service was attempted in session 2025-11-20 (ticket NOTIF-334) and reverted. Reason: The service runs behind an AWS ALB which has a 60s idle timeout that silently drops WebSocket connections. The team switched to Server-Sent Events (SSE) instead. Decision record: `architecture/notifications/transport-choice.md`

Yuki reads the decision record, confirms the ALB constraint still exists, and starts with SSE instead. She just saved herself a day of debugging silent connection drops. She didn't know to search for "ALB WebSocket timeout" — but Déjà Vu connected her action (writing a WebSocket manager in the notification service) to the stored failure pattern.

#### PM: "Why does this keep happening?"

Marcus is reviewing sprint velocity and notices that his team keeps underestimating authentication-related tickets. He asks the agent to investigate. The agent runs `/xgh-ask "Why do auth tickets take longer than estimated?"` — but more importantly, Déjà Vu has been firing warnings on auth-related work for weeks. Marcus pulls the Déjà Vu log:

- 3 warnings fired on auth middleware changes (all related to the same race condition documented in a 2025 decision)
- 2 warnings fired on OAuth flow modifications (a known edge case with refresh token rotation)
- 1 warning fired on session management (a subtle bug with Redis session store TTL)

Marcus now has evidence for the pattern: auth work is consistently underestimated because there are documented landmines that every engineer has to navigate. He proposes adding a "known complexity" tag to auth tickets and padding estimates by 40%. Déjà Vu turned invisible friction into visible, actionable data.

#### Designer: "The design system remembers"

Priya is working with an AI agent to implement a new modal component. The agent starts generating code using absolute positioning for the overlay. Déjà Vu fires:

> **Pattern match (0.78 confidence):** Absolute-positioned modal overlays were replaced with `<dialog>` element approach in session 2026-01-14 (ticket DES-892). Reason: Absolute positioning broke scroll lock on iOS Safari and conflicted with the app's existing portal system. The team standardized on native `<dialog>` with a custom backdrop. See: `patterns/components/modal-implementation.md`

The agent switches to the `<dialog>` approach immediately. Priya doesn't have to catch this in review. The design system's implementation decisions are enforced proactively, not just documented in a Storybook page nobody checks during coding.

### 7. The "Aha" Moment

The aha moment comes the first time Déjà Vu saves you from a mistake you *would not have caught yourself*. Not a mistake you forgot about — a mistake you didn't even know was possible because the knowledge came from a different person, a different project, or a different time.

It is the difference between a memory system that answers questions and one that knows which questions you *should* be asking.

The second-order aha moment: realizing that every failed attempt and abandoned approach is no longer wasted work. It becomes a tripwire protecting the next person. Failed experiments become organizational antibodies. The team gets smarter not just from what it builds, but from what it tried and discarded.

### 8. What It Enables

**Downstream features and workflows Déjà Vu unlocks:**

- **Pattern Analytics Dashboard**: Aggregate Déjà Vu firing data to identify systemic issues — which codebase areas generate the most warnings? Which patterns keep tripping people up? This turns reactive warnings into proactive architectural insights.
- **Onboarding Accelerator**: New team members get the benefit of the entire team's failure history from day one. Instead of "ask someone who's been here a while," the institutional knowledge intercepts bad patterns in real-time.
- **Decision Deprecation**: When an old decision record is no longer relevant (e.g., you migrated off the ALB), you mark it deprecated and Déjà Vu stops firing for it. This creates a natural lifecycle for architectural decisions.
- **Cross-Project Immune System**: With linked workspaces, a failure in Project A becomes a warning in Project B. Teams working on similar services benefit from each other's mistakes without any coordination overhead.
- **Compliance Evidence**: In regulated environments, Déjà Vu's warning log becomes evidence that known risks were surfaced to engineers. "The system warned about this pattern and the engineer made an informed decision to proceed" is a powerful audit artifact.
- **"Why Did We Do It This Way?" answers**: When someone asks why the code looks a certain way, Déjà Vu's pattern history shows what was tried before and why the current approach was chosen. The code stops being mysterious.

### 9. Pluggability

Déjà Vu ships as an optional module with zero dependencies beyond core xgh:

**Module manifest (`modules/deja-vu/module.yaml`):**
```yaml
name: deja-vu
description: Pattern-matched preemptive warnings from past failures
version: 1.0.0
requires:
  xgh: ">=1.0.0"
  cipher: true          # needs vector memory
  context-tree: true    # reads decision records
optional:
  linked-workspaces: true  # enables cross-project patterns
  local-llm: true          # enables rich mode warnings
archetypes:
  - solo-dev
  - oss-contributor
  - enterprise
  - openclaw
```

**What gets installed:**
- `hooks/deja-vu-pre-tool.sh` — PreToolUse hook that runs signal extraction + pattern matching
- `hooks/deja-vu-post-session.sh` — PostSession hook that extracts new patterns from reverted/abandoned work
- `skills/deja-vu/deja-vu.md` — Skill for manually querying pattern history and managing pattern lifecycle
- `commands/deja-vu.md` — `/xgh-deja-vu` command for viewing recent warnings and pattern stats

**Configuration:**
```yaml
# In .xgh/config.yaml
deja-vu:
  enabled: true
  confidence-threshold: 0.75   # minimum match confidence to fire
  mode: fast                    # fast (template) or rich (LLM-composed)
  decay-half-life: 180         # days
  cross-project: false          # requires linked-workspaces module
  suppress:
    - "test-*"                  # don't warn on test file changes
```

**Archetype defaults:**
- **Solo Dev**: Enabled, fast mode, 6-month decay, personal patterns only
- **OSS Contributor**: Enabled, fast mode, 12-month decay (project history is more stable), no cross-project
- **Enterprise**: Enabled, rich mode, 12-month decay, cross-project on, compliance log on
- **OpenClaw**: Enabled, fast mode, 3-month decay (personal projects change faster), no cross-project

**Disable with one line:** `deja-vu: { enabled: false }` — the hooks become no-ops, zero performance impact.

**No new infrastructure:** Déjà Vu reads and writes to the same Cipher instance and context tree xgh already uses. It adds a new collection/tag type (`deja_vu_pattern`) but requires no additional services, databases, or API keys. If you have xgh running, you can turn on Déjà Vu.
