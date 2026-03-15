# Collaboration & Sharing -- Feature Proposals

**Date:** 2026-03-15
**Domain:** How xgh enables knowledge to flow between people, agents, projects, and teams
**Status:** Draft / Brainstorm

---

## Two Feature Ideas

### Idea 1: Memory Mesh -- Federated Cross-Project Knowledge

A mesh network of xgh-powered projects that can read from each other's memory with scoped permissions. When you work on `swift-mock-kit`, your agent already knows how `tr-ios` uses coordinators, what mock patterns the team prefers, and which tests flake. No re-explaining. No copy-pasting context. The mesh just knows.

This builds directly on the linked workspaces concept (already in memory) but generalizes it: instead of pairwise links, projects join a mesh where knowledge flows based on declared dependency graphs and access scopes.

### Idea 2: Context Drops -- Shareable Knowledge Snapshots

A developer or agent can "drop" a self-contained bundle of curated knowledge -- reasoning chains, decisions, patterns, context tree fragments -- that another person or project can pick up and absorb. Think AirDrop for AI memory. An engineer onboarding to a repo runs `/xgh-absorb payments-context.drop` and instantly their agent has 6 months of team decisions, architecture rationale, and gotcha patterns without wading through Confluence or Slack history.

---

## Favorite: Context Drops

### 1. Name

**Context Drops**

### 2. One-liner

Shareable, portable bundles of curated AI knowledge that any xgh-powered project can absorb in one command.

### 3. The Problem

Knowledge transfer between people and projects is brutally expensive. Today:

- **Onboarding:** A new engineer joins the team. Their AI agent starts with zero memory. Every session, they re-explain the architecture, naming conventions, API patterns, and "don't touch that, it's load-bearing" warnings. It takes weeks before the agent is as useful as a tenured teammate's.
- **Cross-team handoffs:** Team A builds a payment SDK. Team B integrates it. Team B's agent has no idea why the SDK works the way it does -- the retry logic, the idempotency keys, the specific error codes. That knowledge lives in Team A's Cipher memory and context tree, inaccessible.
- **Open source:** A maintainer has deep context about why the library's API looks the way it does, which patterns are intentional vs. accidental, and what the migration path looks like. Contributors start from scratch every time. Issues get filed for "bugs" that are deliberate design decisions.
- **Personal knowledge:** You built something clever 8 months ago in a different project. You remember the shape of the solution but not the details. That reasoning chain exists in an old project's Cipher memory, but you can't get it into your current session.

The core tension: xgh makes individual projects incredibly context-rich, but that context is trapped. Knowledge accumulates vertically (deeper in one project) but never flows horizontally (across projects, teams, people).

### 4. Which Archetypes Benefit

| Archetype | How they use it | Impact |
|-----------|----------------|--------|
| **Solo Dev** | Export drops from mature personal projects and absorb them into new ones. "Start every project with everything I learned from the last 5." Self-to-self knowledge transfer across time. | High -- solo devs have the most fragmented knowledge across projects |
| **OSS Contributor** | Maintainers publish official drops alongside releases. `v3.0-migration.drop` contains every decision, pattern, and gotcha for the major version bump. Contributors absorb it before submitting PRs. | Transformative -- solves the "maintainer context is inaccessible" problem that plagues every OSS project |
| **Enterprise** | Teams publish curated drops for shared services. The Platform team drops `auth-sdk-patterns.drop` and every team that integrates the SDK gets the institutional knowledge instantly. Onboarding drops for new hires. | High -- directly reduces onboarding time (measurable, PM-friendly metric) |
| **OpenClaw** | Personal AI assistant absorbs drops from the user's professional projects. "Teach my personal agent everything my work agent knows about iOS architecture." | Medium -- interesting for power users who blur personal/professional contexts |

### 5. How It Works

#### Architecture overview

```
                     EXPORT                              ABSORB
                +--------------+                   +--------------+
                |  /xgh-drop   |                   | /xgh-absorb  |
                |   (export)   |                   |   (import)   |
                +------+-------+                   +------+-------+
                       |                                  |
                       v                                  v
              +--------+--------+               +---------+---------+
              | Drop Compiler   |               | Drop Hydrator     |
              | - Select scope  |               | - Verify manifest |
              | - Filter PII    |               | - Resolve conflicts|
              | - Snapshot CT   |               | - Merge into CT   |
              | - Export vectors|               | - Inject vectors  |
              | - Bundle        |               | - Score & tag     |
              +--------+--------+               +---------+---------+
                       |                                  |
                       v                                  v
              +--------+--------+               +---------+---------+
              |  .drop bundle   |               | Local Cipher +    |
              |  (portable)     |-----git------>| Context Tree      |
              +-----------------+  or URL       +-------------------+
```

#### What is a `.drop` bundle?

A `.drop` is a directory (or tarball) containing:

```
payments-patterns.drop/
  manifest.json          # Metadata: author, date, version, scope, tags, hash
  context-tree/          # Subset of .xgh/context-tree/ markdown files
  vectors.jsonl          # Exported Cipher vectors (embeddings + metadata)
  reasoning-chains/      # Serialized reasoning memories
  README.md              # Human-readable summary of what this drop contains
```

**Key design decisions:**

- **Vectors are portable** because xgh controls the embedding model. All xgh instances using the same embed model (default: ModernBERT) produce compatible vectors. For mismatched models, the hydrator re-embeds from the source text stored alongside each vector.
- **Context tree fragments are markdown** -- they merge into the receiving project's `.xgh/context-tree/` using the existing manifest system. Conflicts are resolved by the hydrator (keep both, prefer newer, or ask).
- **PII filtering** happens at export time. The drop compiler runs the same content-type filters the analyzer already uses, plus configurable redaction rules (strip email addresses, Slack handles, internal URLs). Enterprise teams can add custom scrubbers.
- **Provenance tracking** -- every piece of knowledge in a drop carries a `source_drop` tag so the receiving project knows where it came from and can update or purge it later.

#### Commands

| Command | What it does |
|---------|-------------|
| `/xgh-drop` | Export a context drop. Prompts for scope (whole project, specific topics, date range). Runs PII filter. Produces a `.drop` bundle. |
| `/xgh-absorb` | Import a context drop. Reads the manifest, shows a summary of what will be absorbed, merges into local Cipher + context tree. |
| `/xgh-drops` | List available drops (local, git-hosted, or from a registry URL). Shows what each contains and when it was created. |

#### Distribution channels

Drops are just directories. They can travel via:

1. **Git** -- commit a `.drop` directory to a repo. OSS maintainers ship drops in their release artifacts.
2. **URL** -- host a tarball anywhere. `/xgh-absorb https://example.com/payments-v3.drop.tar.gz`
3. **Registry** (future) -- a central or self-hosted registry where teams publish and discover drops. Think npm but for AI context.
4. **Local file system** -- copy a `.drop` directory between machines. The simplest path.

### 6. Use Cases

#### Engineer: "I keep re-explaining the same architecture"

Sofia maintains three Swift packages that all follow the same architecture: protocol-oriented, async/await, dependency injection via factory closures. Every time she starts a new package, her agent needs 2-3 sessions before it stops suggesting delegate patterns and starts using the factory closures correctly.

With Context Drops: Sofia runs `/xgh-drop` in her most mature package, scoped to "architecture patterns + naming conventions." She gets `swift-architecture.drop`. In her new package, `/xgh-absorb swift-architecture.drop`. First session, first prompt -- the agent already uses factory closures, names protocols correctly, and structures tests the way Sofia expects. Two days of context-building compressed to 10 seconds.

#### PM: "Onboarding is our biggest cost center"

Marcus manages a platform team with 40% annual turnover. Every new hire spends 3-4 weeks before their AI agent is productive -- they lack the institutional context about why the payment service retries exactly 3 times, why the auth flow uses a specific token rotation pattern, and which Confluence pages are outdated vs. authoritative.

With Context Drops: Marcus asks senior engineers to run `/xgh-drop` scoped to their domain expertise. These become onboarding drops: `payments-domain.drop`, `auth-patterns.drop`, `testing-conventions.drop`. New hire runs `/xgh-absorb *.drop` on day one. Their agent immediately knows the team's conventions, can explain past decisions, and flags when the new hire is about to violate an established pattern. Marcus measures onboarding time dropping from 3 weeks to 3 days. He puts this in his quarterly review.

#### Designer: "Engineers keep breaking my design rationale"

Priya is a design system maintainer. She has carefully documented why each component works the way it does -- the accessibility requirements, the regulatory constraints, the user research that drove specific interaction patterns. But engineers on consuming teams never read the Confluence page, and their agents have no idea these constraints exist.

With Context Drops: Priya publishes `design-system-rationale.drop` alongside each design system release. It contains the "why" behind every component: "The fee breakdown uses a bottom sheet instead of a modal because BaFin requires fee visibility before the confirmation action." When an engineer's agent suggests swapping the bottom sheet for a modal, the absorbed drop triggers a reasoning match: "This contradicts a regulatory design rationale from design-system-rationale.drop." The engineer learns about the constraint before writing the wrong code, not after a QA rejection.

### 7. The "Aha" Moment

You have been working on a project for 6 months. Your agent knows everything -- the architecture, the gotchas, the team conventions, the reasoning behind every non-obvious decision.

You start a brand new project. You type:

```
/xgh-absorb ~/projects/my-mature-project/.drops/everything.drop
```

Your very first prompt to the agent in the new project: "Set up the networking layer."

The agent responds: "Based on your established patterns, I'll use the async/await protocol-oriented approach with factory-closure DI, the same retry policy (3 attempts, exponential backoff, jittered) you settled on in the payments service, and the error type hierarchy you evolved over the last 4 months. I'll also apply your naming conventions and test structure. Should I proceed?"

You did not explain any of this. The agent just *knows*. Six months of accumulated wisdom, transferred in one command.

That is the moment.

### 8. What It Enables

Context Drops is a primitive that unlocks a cascade of downstream features:

- **Drop Marketplace** -- a community registry where OSS maintainers and teams publish curated knowledge drops. "The 20 most popular Swift architecture drops." This becomes a distribution channel for best practices that is consumed by machines, not just humans.
- **Versioned Knowledge** -- drops can be versioned alongside code releases. When a library ships v4.0, it ships `v4-migration.drop` too. Dependabot for context.
- **Knowledge Diffing** -- compare two drops to see how a team's understanding evolved. "What did we learn between Q1 and Q3?" Useful for retrospectives and knowledge audits.
- **Composite Drops** -- a drop that references other drops. The "senior engineer onboarding" drop includes payments, auth, and testing drops. Compose knowledge bundles from atomic pieces.
- **CI-Generated Drops** -- a GitHub Action that runs `/xgh-drop` after each release, automatically publishing the project's current knowledge state. Knowledge stays in sync with code.
- **Memory Mesh via Drops** -- the "Memory Mesh" idea from above can be implemented as automatic drop exchange between linked workspaces. The mesh becomes a protocol on top of drops rather than a separate system.

### 9. Pluggability

Context Drops ships as an optional module with clear boundaries:

#### What it adds

| Component | File | Purpose |
|-----------|------|---------|
| Export command | `commands/xgh-drop.md` | The `/xgh-drop` slash command |
| Import command | `commands/xgh-absorb.md` | The `/xgh-absorb` slash command |
| List command | `commands/xgh-drops.md` | The `/xgh-drops` slash command |
| Compiler skill | `skills/drop-compiler/drop-compiler.md` | Export logic: scope selection, PII filtering, bundling |
| Hydrator skill | `skills/drop-hydrator/drop-hydrator.md` | Import logic: conflict resolution, vector injection, tagging |
| Manifest schema | `config/drop-manifest.schema.json` | JSON schema for `.drop/manifest.json` |

#### What it depends on

- Core xgh (context tree + Cipher memory) -- reads from context tree and Cipher vectors during export, writes to them during import.
- Embedding model compatibility -- either same model (zero-cost import) or text fallback for re-embedding.

#### What it does NOT depend on

- No team tools (Slack, Jira, Confluence) -- works for Solo Dev and OSS archetypes.
- No ingest pipeline -- drops are manually curated, not automatically generated.
- No shared infrastructure -- drops are files. No server, no registry (registry is a future add-on).

#### Archetype installation

| Archetype | Installed by default? | Why |
|-----------|----------------------|-----|
| Solo Dev | Yes | Core value prop: transfer knowledge across personal projects |
| OSS Contributor | Yes | Publishing and absorbing drops is the primary collaboration channel for OSS |
| Enterprise | Yes | Onboarding drops and cross-team knowledge sharing |
| OpenClaw | Optional | Useful for power users, but not core to the personal assistant use case |

#### Progressive enhancement

The module works at three levels of sophistication:

1. **Basic (no infra):** Export to local directory, absorb from local directory or URL. Works on day one.
2. **Git-integrated:** Drops committed to repos. GitHub Actions auto-generate drops on release. Discoverable via `/xgh-drops --repo`.
3. **Registry (future):** Central/self-hosted drop registry with search, versioning, and access control. The npm-for-context vision.

Each level works independently. You never need level 3 to use level 1.
