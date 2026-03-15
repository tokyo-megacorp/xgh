# Memory & Learning — Feature Proposals

> **Domain:** How xgh remembers, forgets, and gets smarter over time
> **Date:** 2026-03-15
> **Author:** Product brainstorm (Memory & Learning track)

---

## Two Feature Ideas

### Idea 1: Memory Drift Detection

Every project evolves. Conventions change, architectures shift, teams reorganize. But memory doesn't know that. Stored memories from 3 months ago may actively contradict today's reality — the agent confidently applies a pattern that the team abandoned weeks ago. Memory Drift Detection continuously compares stored knowledge against current signals (recent commits, new context tree entries, fresh ingest data) and flags memories that have gone stale. It quarantines contradictions, surfaces "did you know this changed?" prompts, and lets the agent self-correct before giving outdated advice.

### Idea 2: Memory Replay

When an agent starts a session, it gets a flat dump of relevant memories — a bag of facts with no narrative. It knows *what* was decided but not the *journey* of how the project got here. Memory Replay reconstructs the decision timeline for any topic: "First you tried X, then Y broke, so you switched to Z." It turns scattered vector hits into a coherent story, giving the agent (and the human) a replayable history of how the codebase arrived at its current state.

---

## Selected Proposal: Memory Replay

### Name

**Memory Replay**

### One-liner

Reconstructs the decision timeline for any topic, turning scattered memories into a replayable narrative of how your project got where it is.

### The Problem

xgh's memory is a point-in-time retrieval system. You ask "how do we handle authentication?" and get back 8 memory hits: a Slack discussion from January, an architectural decision from February, a bug fix reasoning chain from last week, and five other fragments. These are sorted by relevance score, not by time. There is no *story*.

This creates three concrete pain points:

1. **Context collapse.** The agent treats all memories as equally current. A decision from month one and a reversal from month three appear side-by-side with no indication that one supersedes the other. The agent may confidently apply the *original* pattern, not the *current* one.

2. **Onboarding friction.** A new team member (or a new agent session on an unfamiliar part of the codebase) cannot ask "how did we get here?" They can search for facts, but they cannot reconstruct the reasoning arc. The difference is like reading a dictionary versus reading a history book — both contain the same words, but only one tells you why things are the way they are.

3. **Decision amnesia.** Teams revisit the same decisions repeatedly because nobody remembers *why* the current approach was chosen. "Should we switch from REST to GraphQL?" was debated and resolved 4 months ago, but the reasoning is buried across 12 memories in 3 different collections. Without a replay, the team spends another hour re-deriving the same conclusion.

### Which Archetypes Benefit

| Archetype | How it helps | Intensity |
|-----------|-------------|-----------|
| **Solo Dev** | "Why did I do it this way?" — replay your own reasoning from months ago when you've forgotten. Essential for side projects with long gaps between sessions. | High |
| **OSS Contributor** | Understand a project's evolution before contributing. Replay the history of a module to grasp not just the code, but the decisions behind it. Reduces "why not just do X?" PRs that rehash settled debates. | Medium |
| **Enterprise** | Onboarding accelerator. New engineers replay the decision history of their assigned domain instead of asking 15 people. Compliance teams can audit *why* a security-sensitive choice was made, not just *what* it is. | Very high |
| **OpenClaw** | Personal knowledge archaeology. "How did my understanding of X evolve?" Replay your learning journey on any topic across all your projects. | Medium |

### How It Works

**Architecture sketch:**

```
┌─────────────────────────────────────────────────────────┐
│                    Memory Replay Engine                  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. GATHER                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐  │
│  │ Cipher   │  │ Context  │  │ Git log / Ingest    │  │
│  │ vectors  │  │ Tree     │  │ history             │  │
│  └────┬─────┘  └────┬─────┘  └──────────┬──────────┘  │
│       │              │                   │              │
│       ▼              ▼                   ▼              │
│  2. CORRELATE                                           │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Timeline Builder                               │    │
│  │  - Cluster memories by topic (semantic groups)  │    │
│  │  - Order by timestamp (memory creation date)    │    │
│  │  - Detect supersession (A was replaced by B)    │    │
│  │  - Mark pivots (points where direction changed) │    │
│  └────────────────────┬────────────────────────────┘    │
│                       │                                  │
│       ▼                                                  │
│  3. NARRATE                                              │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Story Synthesizer (LLM pass)                   │    │
│  │  - Converts timeline into readable narrative    │    │
│  │  - Highlights pivots, reversals, open questions │    │
│  │  - Cites source memories (linked, not inlined)  │    │
│  │  - Tags confidence level per segment            │    │
│  └────────────────────┬────────────────────────────┘    │
│                       │                                  │
│       ▼                                                  │
│  4. CACHE                                                │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Replay stored as context tree document         │    │
│  │  (.xgh/context-tree/replays/{topic-slug}.md)    │    │
│  │  - Invalidated when new memories touch topic    │    │
│  │  - Versioned (replay v1, v2... as story grows)  │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Key technical decisions:**

- **Gather** casts a wide net: semantic search for the topic across all Cipher collections, BM25 keyword search across the context tree, and git log filtering for related commits and PR descriptions. The goal is to find *every* memory fragment related to the topic, not just the top-5 nearest neighbors.

- **Correlate** is the novel piece. It clusters gathered memories by sub-topic (e.g., under "authentication" you might have clusters for "token format," "session management," "provider selection"), then orders each cluster chronologically. Supersession detection identifies when a later memory contradicts or replaces an earlier one — using both explicit markers (if present) and semantic opposition scoring. Pivot detection flags moments where the project changed direction.

- **Narrate** uses a single LLM pass (the project's configured BYOP model) to synthesize the timeline into a human-readable story. The prompt template emphasizes: chronological flow, explicit "this replaced that" callouts, confidence tagging ("high confidence: 4 corroborating memories" vs. "low confidence: single Slack message"), and source citations.

- **Cache** stores the replay as a markdown document in the context tree under a `/replays` directory. This means replays are git-committed, PR-reviewable, and searchable by future sessions. Cache invalidation is timestamp-based: if any new memory is stored that semantically matches the replay topic, the replay is marked stale and regenerated on next access.

### Use Cases

**Engineer scenario — "Why is this code so weird?"**

You open a file with a bizarre workaround: a 40-line function that does what should be a 3-line stdlib call. `git blame` shows it was written by someone who left the team. You ask xgh: `/xgh-replay authentication token refresh`. The replay shows: (1) originally used the stdlib approach, (2) hit a race condition in production that corrupted sessions, (3) tried a lock-based fix that caused deadlocks under load, (4) settled on the current manual approach as the only reliable solution, (5) filed an upstream issue that's still open. In 30 seconds, you understand 3 months of debugging history and know not to "simplify" that function.

**PM scenario — "Catch me up on this initiative"**

You're a PM joining a project mid-stream. The team has been working on a payments migration for 6 weeks. Instead of scheduling 3 catch-up meetings, you run `/xgh-replay payments migration`. The replay shows the full arc: initial proposal, the three approaches considered, why approach B was selected, the mid-course pivot when the vendor API changed, current blockers, and open decisions. You walk into your first standup already knowing the history, and can ask targeted questions instead of "so, um, what's the status?"

**Designer scenario — "Why does the flow work this way?"**

You're reviewing a user flow that feels unnecessarily complex — 4 screens where 2 should suffice. Before proposing a simplification, you run `/xgh-replay onboarding flow`. The replay reveals: the original design *was* 2 screens, but user testing showed a 40% drop-off at the second screen because it asked for too much information at once. The team split it into 4 screens and drop-off fell to 12%. The "complexity" is intentional and evidence-backed. Your proposal shifts from "simplify this" to "can we make screen 3 feel lighter while keeping the 4-step structure?"

### The "Aha" Moment

The first time you ask "why is it like this?" and get back not a list of facts but a *story* — with a beginning, turning points, and a conclusion — something clicks. It feels like the codebase has a memory. Not your memory, not any individual's memory, but an institutional memory that outlasts any single contributor.

The specific "oh wow" trigger: seeing a replay that includes a decision *you* made months ago, with reasoning *you* forgot. The system remembers your own thought process better than you do. That's when it stops being a tool and starts feeling like an extension of your brain.

### What It Enables

Memory Replay is a foundation layer that unlocks several downstream features:

1. **Decision audit trail.** Enterprise teams get a compliance-friendly record of why security, architecture, and data handling decisions were made. Not retroactive documentation — organic, continuous, generated from actual memories.

2. **Conflict detection.** If a new memory contradicts the latest replay for a topic, xgh can proactively warn: "This decision conflicts with the approach established in March — see replay." This turns Memory Replay into an active consistency guardian, not just a passive history viewer.

3. **Onboarding playlists.** A curated list of replays that new team members should watch/read: "Start with the architecture replay, then authentication, then deployment pipeline." An automated onboarding curriculum generated from actual project history.

4. **Memory compaction.** Once a replay exists, the individual memories that were superseded can be archived or downweighted. The replay becomes the canonical record, and the raw memories become supporting evidence. This keeps the active memory pool lean and reduces retrieval noise over time.

5. **Cross-project pattern detection.** When replays exist across multiple projects, a meta-analysis can spot recurring patterns: "You've hit this same authentication problem in 3 projects — here's what worked each time." This is the path to xgh learning not just project history, but engineering *wisdom*.

6. **Linked workspace narratives.** Combined with the planned linked workspaces feature, replays can span projects: "The swift-mock-kit mocking approach evolved because of changes in tr-ios's coordinator architecture — here's the full cross-project story."

### Pluggability

Memory Replay ships as an optional module with clear boundaries:

**What ships:**
- A new skill: `/xgh-replay` (skill markdown + command markdown)
- A Python module: `replay_engine.py` (timeline builder + supersession detection)
- A prompt template: `replay-narrate.md` (for the LLM synthesis pass)
- A context tree directory convention: `.xgh/context-tree/replays/`
- A cache invalidation hook: extends `prompt-submit.sh` to check replay staleness

**Dependencies:**
- **Required:** Cipher MCP (for memory search) + Context Tree (for storage and BM25 search)
- **Optional:** xgh-ingest (enriches replays with Slack/Jira context if available)
- **Optional:** Git history (enriches replays with commit/PR context)

**Archetype installation:**
- **Solo Dev:** Included. Core value prop — personal decision archaeology.
- **OSS Contributor:** Included. Understanding project history is essential for meaningful contributions.
- **Enterprise:** Included + enhanced. Adds team attribution (who drove each decision), compliance tags, and export-to-Confluence capability.
- **OpenClaw:** Included. Personal learning journey replays across all projects.

**Integration points:**
- `/xgh-brief` can reference recent replays: "The authentication replay was updated yesterday after new memories were stored."
- `/xgh-curate` can trigger replay regeneration: "This memory touches the 'authentication' replay — marking it for refresh."
- `/xgh-ask` can route to replays: "For the full history, see the authentication replay" instead of dumping raw memories.

**Module manifest (extends techpack.yaml):**
```yaml
modules:
  memory-replay:
    version: 1.0.0
    skills: [replay]
    commands: [replay]
    hooks:
      prompt-submit: replay-staleness-check
    context-tree-dirs: [replays]
    dependencies:
      required: [cipher-mcp, context-tree]
      optional: [xgh-ingest, git]
    archetypes: [solo-dev, oss-contributor, enterprise, openclaw]
```

---

## Appendix: Why Memory Replay Over Memory Drift Detection

Both features address the "stale memory" problem, but from different angles. Drift Detection is reactive — it catches contradictions after they occur. Memory Replay is generative — it *creates* a new artifact (the narrative) that naturally surfaces contradictions as part of telling the story. A good replay inherently performs drift detection ("in March we decided X, but in April we reversed to Y") while also providing the richer context of *why* things changed.

Additionally, Memory Replay has a clearer "aha" moment and broader archetype appeal. Drift Detection is a maintenance tool (important but invisible when working well). Memory Replay is a discovery tool — users actively seek it out, share replays with teammates, and build workflows around it. The engagement model is fundamentally different: drift detection is a warning you dismiss, while a replay is a story you read.

That said, Drift Detection is a natural follow-on. Once replays exist, drift detection becomes: "does this new memory contradict the latest replay?" — a much simpler problem than detecting drift across an unstructured memory pool.
