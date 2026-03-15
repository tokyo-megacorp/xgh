# Context Sources & Adapters -- Feature Proposals

**Domain:** Where xgh pulls context from and how it ingests the world
**Date:** 2026-03-15
**Status:** Proposal

---

## Two Feature Ideas

### Idea 1: Repo Whisperer -- Git History as Living Context

Turn a repository's git history into a searchable context layer. Every commit message, PR description, code review comment, and merge conflict resolution becomes queryable memory. The agent stops treating the repo as a snapshot and starts understanding it as a narrative -- who changed what, why, and what was debated along the way.

**Why it's interesting:** Most AI agents treat code as static. But half of "why is the code like this?" lives in git blame, PR threads, and commit messages. This bridges the gap between code-as-artifact and code-as-conversation.

### Idea 2: Ambient Docs -- Live Document Sync from Notion, Google Docs, and Confluence

A background adapter that watches shared documents (Notion pages, Google Docs, Confluence spaces) and continuously syncs their content into xgh's memory layer. When a PM updates a PRD or a designer edits a spec, the agent's context updates automatically -- no manual ingestion step.

**Why it's interesting:** The biggest context gap in AI coding isn't the code -- it's the surrounding human documents that explain intent, constraints, and decisions. This makes the agent as informed as the best-read engineer on the team.

---

## Selected Proposal: Repo Whisperer

### Name

**Repo Whisperer** -- git history as living context

### One-liner

Turns your repository's git history, PR discussions, and code review threads into searchable, semantic memory that agents query as naturally as they search code.

### The Problem

AI coding agents are brilliant at reading the code that exists right now. They are terrible at understanding how it got there. When an agent encounters a function with a non-obvious implementation, it has no way to know:

- **The commit message** that explains the tradeoff ("chose O(n^2) because n is always < 10 and readability matters more")
- **The PR discussion** where three engineers debated the approach and the tech lead made the call
- **The reverted commit** that tried the "obvious" approach and broke production
- **The code review comment** that says "don't change this without updating the mobile client"

This matters because agents keep proposing changes that were already tried and rejected, refactoring code that has hidden constraints, and missing context that any teammate who's been on the project for a month would know. The codebase has a memory -- it's encoded in git -- but agents can't access it.

Today, the only option is for a human to manually write these things into CLAUDE.md or the context tree. That doesn't scale. The history is already there, sitting in git, unread.

### Which Archetypes Benefit

| Archetype | How they benefit |
|-----------|-----------------|
| **Solo Dev** | Even solo developers forget why they made decisions 3 months ago. Repo Whisperer gives them a "past self" to consult. "Why did I add this workaround?" becomes a searchable question. Lightweight mode: git log + commit messages only. |
| **OSS Contributor** | The killer use case. Contributors joining a project have zero historical context. Repo Whisperer lets their agent answer "what's the project's stance on X?" by searching past PR discussions. Reduces maintainer burden for onboarding. |
| **Enterprise** | Teams with high turnover or cross-team dependencies. When the person who wrote the authentication layer leaves, their reasoning survives in git. Repo Whisperer makes institutional knowledge durable. Full mode: git + GitHub/GitLab PR threads + code review comments. |
| **OpenClaw** | Personal assistant use case: "What was I working on in this repo last month?" or "Show me every decision I made about the database schema." Repo Whisperer becomes a personal engineering journal you never had to write. |

### How It Works

**Architecture: Three-layer pipeline**

```
Layer 1: Extractors        Layer 2: Processors       Layer 3: Memory

git log ─────────┐
                 │         ┌─────────────┐
git blame ───────┼────────>│  Chunker &  │   ┌─────────────────┐
                 │         │  Classifier │──>│ Cipher (Qdrant)  │
PR threads ──────┤         └─────────────┘   │ + Context Tree   │
(GitHub/GitLab)  │                │          └─────────────────┘
                 │         ┌──────┴──────┐
review comments ─┤         │  Decision   │   Queryable via
                 │         │  Extractor  │   cipher_memory_search
diff hunks ──────┘         └─────────────┘   and /xgh-ask
```

**Layer 1 -- Extractors** (pluggable, one per source)

- `git-log-extractor`: Parses commit messages, author, date, files changed. Runs locally, no API needed.
- `git-blame-extractor`: For a given file, builds an authorship + change-frequency map. Identifies "hot zones" (frequently changed code).
- `pr-thread-extractor`: Calls GitHub/GitLab API to pull PR descriptions, review comments, and inline code comments. Requires a PAT or MCP integration (GitHub MCP already exists in Claude Code's ecosystem).
- `diff-hunk-extractor`: Pairs significant code changes with their commit messages to create "change narratives" -- what changed and why, together.

**Layer 2 -- Processors**

- **Chunker & Classifier**: Splits raw extractions into semantic chunks. Classifies each as one of: `decision`, `tradeoff`, `constraint`, `convention`, `bug-fix-rationale`, `revert-reason`, `refactor-motivation`, or `context-note`. This classification drives how chunks are stored and surfaced.
- **Decision Extractor**: Specifically identifies moments where alternatives were weighed. Looks for patterns in PR discussions: disagreement followed by resolution, "I tried X but Y because Z", explicit approval/rejection language. These become first-class `decision` objects in memory.

**Layer 3 -- Memory**

- Processed chunks are stored in Cipher (Qdrant vectors) with rich metadata: source type, file paths affected, authors, date, classification.
- High-confidence decisions also get written to the context tree as knowledge files under `.xgh/context-tree/repo-history/`, making them git-committed, human-reviewable, and available even without Cipher running.
- A deduplication layer prevents re-ingesting commits that are already in memory (tracks HEAD position per branch).

**Ingestion modes:**

| Mode | Trigger | Scope | Use case |
|------|---------|-------|----------|
| **Bootstrap** | `/xgh-whisper --bootstrap` | Full history (configurable depth, default 500 commits) | First-time setup, new team member onboarding |
| **Incremental** | `session-start` hook | New commits since last ingestion | Every session, automatic |
| **Targeted** | `/xgh-whisper <file-or-path>` | History of specific files/directories | Deep-diving into a module's evolution |
| **PR mode** | `/xgh-whisper --pr 123` | Single PR thread + all its commits | Understanding a specific change |

### Use Cases

**Engineer scenario -- "Why is this code like this?"**

Sarah is refactoring the payment service. She finds a function that manually retries HTTP calls with hardcoded delays instead of using the team's retry library. Her agent, powered by Repo Whisperer, surfaces this before she changes it:

> "This function was modified in PR #847 (2025-11-02). The PR discussion shows that the retry library had a bug with non-idempotent POST requests that caused duplicate charges. @mike-t added this manual retry as a hotfix. The library bug was filed as PAYMENTS-2341 but is still open. Recommendation: check if PAYMENTS-2341 is resolved before switching back to the library."

Without Repo Whisperer, Sarah would have "fixed" the code, reintroduced the duplicate charge bug, and spent two days debugging it.

**PM scenario -- "What's the velocity story on this module?"**

Jordan is preparing a planning session and needs to understand which parts of the codebase are actively evolving vs. stable. They ask:

> "Which modules have had the most architectural decisions in the last quarter?"

Repo Whisperer returns a ranked list of modules by decision density, with summaries: "The auth module had 12 decisions in Q4, mostly around migrating from session tokens to JWTs. The payments module had 3, all related to PCI compliance. The notification service has been stable -- last decision was in September."

Jordan now has data-backed input for sprint planning without reading hundreds of PRs.

**Designer scenario -- "Did they implement what we agreed on?"**

Alex is a design engineer who proposed a specific error-handling UX pattern in a PR comment three months ago. The implementation went through multiple revisions. Alex asks:

> "What happened to the inline error pattern I proposed for the transfer confirmation screen?"

Repo Whisperer traces the thread: "Your proposal in PR #612 was approved. The initial implementation in commit a3f2c matched the spec. However, commit d91b (PR #701) modified it to use a toast instead of inline, with the note 'inline caused layout shift on smaller viewports.' The current implementation is a toast with a retry CTA."

Alex now knows the deviation was intentional and has the technical reason, without digging through months of git history.

### The "Aha" Moment

You install Repo Whisperer on a project you've worked on for a year. You ask your agent: "Why do we have two different date formatting functions?"

Instead of guessing or reading code comments, the agent responds with the actual historical narrative -- who introduced each one, the PR where someone proposed unifying them, why that PR was abandoned (it broke the legacy API consumers), and the follow-up ticket that's still in the backlog.

The aha is: **the agent knows the project's story, not just its current state.** It feels like pair-programming with someone who has perfect recall of every conversation the team ever had about the code.

### What It Enables

Repo Whisperer is a foundation layer. Once git history is in memory, it unlocks:

- **Change Impact Prediction**: "If I modify this function, what historically broke when it was changed?" -- cross-reference past commits that touched the same code and their associated bug reports.
- **Onboarding Autopilot**: New team members get a `/xgh-onboard` skill that walks them through the project's evolution, major decisions, and current architectural direction -- all sourced from real history, not stale wiki pages.
- **Convention Detection**: Instead of manually documenting coding conventions, Repo Whisperer can infer them from patterns in code review comments: "In 15 PRs, reviewers asked for exhaustive switch statements. This appears to be a team convention."
- **Revert Intelligence**: When a deploy goes bad, the agent can instantly surface "this file was last reverted in PR #445 for a similar reason" and suggest the known-good state.
- **Cross-repo Learning** (with linked workspaces): If the iOS repo's Repo Whisperer knows about an API contract decision, the backend repo's agent can find it when modifying the endpoint.
- **Review Assist**: When reviewing a PR, the agent can flag "this changes code that has a documented constraint from PR #312 -- verify with the original author."

### Pluggability

**Ships as:** `xgh-whisperer` module (directory under `modules/` or installable via `xgh plugin add whisperer`)

**Dependencies:**
- Core xgh memory layer (Cipher + context tree) -- required
- GitHub/GitLab PAT or MCP integration -- optional, enables PR thread extraction. Without it, Repo Whisperer still works with local git history only.
- No additional infrastructure. Git is already there.

**Installation surface:**
- Archetype mapping: included by default in OSS Contributor and Enterprise. Optional add-on for Solo Dev and OpenClaw.
- Config lives in `.xgh/config.json` under a `whisperer` key: ingestion depth, branch filters, file path exclusions, classification thresholds.

**Hook integration:**
- Adds a lightweight check to `session-start.sh`: if new commits exist since last ingestion, runs incremental mode in the background.
- Adds a `PreToolUse` hook hint: when the agent is about to modify a file, injects a "check history first" nudge if the file has high change frequency or known constraints.

**Skill surface:**
- `/xgh-whisper` -- main entry point. Supports `--bootstrap`, `--pr <number>`, `--file <path>`, and bare invocation for incremental sync.
- `/xgh-ask` gains a `--history` flag that biases search toward Repo Whisperer memories.

**Context tree output:**
- Writes high-confidence decisions to `.xgh/context-tree/repo-history/decisions/` as markdown files.
- Writes detected conventions to `.xgh/context-tree/repo-history/conventions/`.
- These are git-committed and travel with the repo -- even if someone uninstalls xgh, the extracted knowledge survives.

**Opt-out is clean:**
- Removing the module deletes the hook additions, the skill file, and the config key.
- Context tree files remain (they're committed knowledge, not runtime state).
- Cipher memories persist but are inert without the module's query patterns.
