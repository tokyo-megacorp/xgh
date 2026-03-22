# xgh (extreme-go-horsebot) — Design Document

> MCS tech pack for team-shared self-learning memory, inspired by ByteRover, powered by Cipher, disciplined by Superpowers methodology.

**Date:** 2026-03-13
**Status:** Approved
**Architecture:** Approach B — Dual-Engine (Cipher vectors + custom context tree)

---

## 1. Problem Statement

Engineering teams use AI coding agents (primarily Claude Code) daily. Each session starts from zero — agents have no memory of past decisions, conventions, or learnings. Knowledge is trapped in individual sessions and lost when they end.

ByteRover solves this commercially, but teams need:
- An open, self-hosted solution with no external SaaS dependency
- Team-wide knowledge sharing across repos
- Plug-and-play setup (zero manual configuration)
- **Bring Your Own Providers** — use any LLM, any embedding model, any vector store
- Multi-agent support (Claude Code preferred, but any MCP-compatible agent works)
- Works for any team, any stack, any org size

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      xgh MCS Tech Pack                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────────┐ │
│  │ Claude Code   │    │ Other Agents │    │ xgh CLI       │ │
│  │ (hooks +      │    │ (Cursor,     │    │ (skills +     │ │
│  │  skills)      │    │  Codex, etc) │    │  commands)    │ │
│  └──────┬───────┘    └──────┬───────┘    └──────┬────────┘ │
│         │                   │                   │          │
│         ▼                   ▼                   ▼          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Cipher MCP Server                      │   │
│  │  memory_search · extract_and_operate_memory         │   │
│  │  workspace_search · workspace_store                 │   │
│  │  knowledge_graph · reasoning_traces                 │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                  │
│         ┌───────────────┼───────────────┐                  │
│         ▼               ▼               ▼                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │  Vector DB  │  │  SQLite    │  │  LLM+Emb   │           │
│  │  (BYOP)    │  │  (sessions)│  │  (BYOP)    │           │
│  │ qdrant/    │  └────────────┘  │ vllm-mlx/ │           │
│  │ milvus/    │                  │ openai/    │           │
│  │ in-memory  │                  │ anthropic/ │           │
│  └────────────┘                  │ openrouter │           │
│                                  └────────────┘           │
│                         │                                  │
│                         ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │            Context Tree Sync Layer                  │   │
│  │   Cipher vectors ←→ .xgh/context-tree/ markdown     │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                  │
│                         ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         .xgh/context-tree/  (git-committed)         │   │
│  │  ├── domain/ → topic/ → subtopic/                   │   │
│  │  ├── YAML frontmatter (importance, maturity)        │   │
│  │  ├── _index.md (compressed summaries)               │   │
│  │  └── _manifest.json (registry)                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Multi-Agent Collaboration Bus               │   │
│  │  Message protocol · Workflow templates ·             │   │
│  │  Agent registry · Dispatch layer                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Dual-Engine Design

| Engine | Purpose | Storage | Search |
|--------|---------|---------|--------|
| **Cipher** | Semantic memory, reasoning traces, workspace | Qdrant vectors + SQLite | Vector similarity (embeddings) |
| **Context Tree** | Human-readable knowledge, git-shareable | `.xgh/context-tree/*.md` | BM25 keyword + frontmatter scoring |

**Why both?** Cipher's vector search has superior semantic recall. But git-committed markdown is auditable, reviewable in PRs, and shareable without shared infrastructure. The sync layer keeps them consistent.

### Sync Layer

On **curate** (new knowledge enters the system):
1. Cipher stores the vector embedding + metadata
2. Sync layer classifies into domain/topic/subtopic
3. Writes/updates the corresponding `.md` file in the context tree
4. Updates `_manifest.json` and parent `_index.md` files

On **query**:
1. Cipher semantic search runs in parallel with context tree BM25
2. Results are merged and ranked: `score = (0.5 × cipher_similarity + 0.3 × bm25_score + 0.1 × importance + 0.1 × recency) × maturityBoost`
3. Core maturity files get ×1.15 boost (adopted from ByteRover)

### Bring Your Own Providers (BYOP)

xgh is provider-agnostic. Cipher supports 18+ LLM providers and multiple vector stores. Users configure what they have:

```yaml
# .xgh/config.yaml (or env vars)
providers:
  llm:
    provider: openai              # openai | anthropic | openrouter | bedrock | azure | qwen
    model: llama3.2:3b            # any model the provider supports
    baseUrl: http://localhost:11434/v1  # vllm-mlx for local, omit for cloud
    api_key: ${OPENAI_API_KEY}    # "placeholder" for vllm-mlx, real key for cloud
  embeddings:
    provider: openai              # openai | openrouter
    model: nomic-embed-text       # any embedding model
  vector_store:
    type: qdrant                  # qdrant | milvus | in-memory
    url: http://localhost:6333    # only for qdrant/milvus
```

**Preset configurations for quick start:**

| Preset | LLM | Embeddings | Vector Store | Cost |
|--------|-----|------------|-------------|------|
| `local` (default) | vllm-mlx llama3.2:3b | vllm-mlx nomic-embed-text | Qdrant (local) | Free |
| `local-light` | vllm-mlx llama3.2:3b | vllm-mlx nomic-embed-text | In-memory | Free, no persistence |
| `openai` | GPT-4o-mini | text-embedding-3-small | Qdrant (local) | ~$0.01/session |
| `anthropic` | Claude Haiku | vllm-mlx nomic-embed-text | Qdrant (local) | ~$0.01/session |
| `cloud` | OpenRouter (auto) | OpenAI embeddings | Qdrant Cloud | ~$0.02/session |

```bash
# Install with a preset
XGH_PRESET=local curl -fsSL https://raw.githubusercontent.com/xgh-dev/xgh/main/install.sh | bash

# Or configure individually
XGH_LLM_PROVIDER=openai XGH_LLM_MODEL=gpt-4o-mini XGH_OPENAI_API_KEY=sk-... curl -fsSL .../install.sh | bash
```

## 3. Context Tree Structure

Adopted from ByteRover's proven hierarchy:

```
.xgh/context-tree/
├── _manifest.json              # Registry of all entries
├── authentication/             # Domain
│   ├── context.md              # Auto-generated domain overview
│   ├── _index.md               # Compressed summary (YAML frontmatter + condensed content)
│   ├── jwt-implementation/     # Topic
│   │   ├── context.md
│   │   ├── token-refresh.md    # Knowledge file
│   │   └── refresh-tokens/     # Subtopic
│   │       └── rotation.md
│   └── oauth-flow/
│       └── github-sso.md
├── api-design/
│   └── rest-conventions.md
└── _archived/                  # Low-importance drafts
    └── authentication/
        └── old-session-mgmt.stub.md
```

### Knowledge File Format

```yaml
---
title: JWT Token Refresh Strategy
tags: [auth, jwt, security]
keywords: [refresh-token, rotation, expiry]
importance: 78            # 0-100, increases with usage
recency: 0.85             # 0-1, decays with ~21-day half-life
maturity: validated        # draft → validated (≥65) → core (≥85)
related:
  - authentication/oauth-flow/github-sso
accessCount: 12
updateCount: 3
createdAt: 2026-03-13T10:00:00Z
updatedAt: 2026-03-13T14:30:00Z
source: auto-curate       # auto-curate | manual | agent-collaboration
fromAgent: claude-code
---

## Raw Concept
[Technical details, file paths, execution flow]

## Narrative
[Structured explanation, rules, examples]

## Facts
- category: convention
  fact: Refresh tokens rotate on every use with a 7-day absolute expiry
- category: decision
  fact: Chose rotation over sliding window to limit blast radius of token theft
```

### Scoring & Maturity

| Metric | Behavior |
|--------|----------|
| **Importance** | +3 per search hit, +5 per update, +10 per manual curate |
| **Recency** | Exponential decay, ~21-day half-life |
| **Maturity** | draft → validated (≥65 importance) → core (≥85). Hysteresis: −35/−60 to demote |
| **Archive** | Draft files with importance <35 → `.stub.md` (searchable ghost) + `.full.md` (lossless backup) |

## 4. Hook-Driven Self-Learning

The core learning loop, inspired by ByteRover's decision table pattern:

### UserPromptSubmit Hook

Fires on every user prompt. Injects a decision table:

```
┌─ xgh Decision Table ─────────────────────────────────┐
│                                                       │
│  About to write code?                                 │
│  → cipher_memory_search FIRST (check prior knowledge) │
│  → query context tree for conventions                 │
│                                                       │
│  Just wrote/modified code?                            │
│  → cipher_extract_and_operate_memory                  │
│  → sync new learnings to context tree                 │
│                                                       │
│  Made an architectural decision?                      │
│  → curate decision + rationale + alternatives         │
│                                                       │
│  Hit a bug and fixed it?                              │
│  → curate root cause + fix + trigger conditions       │
│                                                       │
│  Reviewing a PR?                                      │
│  → query context tree for related decisions           │
│  → curate any new patterns discovered                 │
│                                                       │
└───────────────────────────────────────────────────────┘
```

### SessionStart Hook

On session start:
1. Load context tree `_manifest.json` for the current repo
2. Inject top-5 most relevant core-maturity knowledge files as context
3. Inject team workspace highlights (cross-repo conventions)

### SessionEnd Hook (Post-Session Curation)

On session end:
1. Extract session learnings via `cipher_extract_and_operate_memory`
2. Sync new/updated entries to context tree
3. Update importance scores for accessed entries

## 5. Multi-Agent Collaboration Bus

Abstracted from the [ByteRover-Claude-Codex-Collaboration](https://github.com/trietdeptrai/Byterover-Claude-Codex-Collaboration-) pattern. Instead of hardcoding Claude→Codex, xgh provides a **generic dispatch layer**.

### Message Protocol

Every inter-agent message in Cipher workspace uses structured metadata:

```yaml
type: plan | review | feedback | result | decision | question
status: pending | in_progress | completed
from_agent: claude-code     # who wrote it
for_agent: "*"              # who should read it (* = broadcast)
thread_id: feat-123         # groups related messages
priority: normal | high | urgent
created_at: 2026-03-13T10:00:00Z
```

### Agent Registry

xgh maintains a registry of available agents and their capabilities:

```yaml
agents:
  claude-code:
    type: primary
    capabilities: [architecture, implementation, planning, review]
    integration: hooks + skills + MCP
  codex:
    type: secondary
    capabilities: [fast-implementation, code-review]
    integration: MCP + bash-invocation
  cursor:
    type: secondary
    capabilities: [ide-editing, refactoring]
    integration: MCP
  custom:
    type: extensible
    capabilities: [user-defined]
    integration: MCP
```

### Workflow Templates

Reusable multi-agent patterns:

**plan-review** (2 agents):
```
Agent A → PLAN (store) → Agent B → REVIEW (store) → Agent A → IMPLEMENT
```

**parallel-impl** (N agents):
```
Agent A → SPLIT tasks → Agents B,C,D → IMPLEMENT (parallel) → Agent A → MERGE + REVIEW
```

**validation** (2 agents):
```
Agent A → IMPLEMENT (store) → Agent B → VALIDATE (store) → feedback loop
```

**security-review** (chain):
```
Agent A → IMPLEMENT → Agent B → SECURITY_REVIEW → Agent A → FIX → Agent B → RE-REVIEW
```

### Dispatch Layer

```
┌─────────────┐     ┌──────────────────────┐     ┌─────────────┐
│  Agent A     │     │   Cipher Workspace   │     │  Agent B     │
│  (any agent) │────▶│                      │◀────│  (any agent) │
│              │     │  Structured messages: │     │              │
│  STORE:      │     │  ┌─ PLAN:  ...      │     │  SEARCH:     │
│  type: plan  │     │  ├─ REVIEW: ...     │     │  type: plan  │
│  for: review │     │  ├─ FEEDBACK: ...   │     │  status: new │
│              │     │  └─ RESULT: ...     │     │              │
└─────────────┘     └──────────────────────┘     └─────────────┘
```

The dispatch layer:
1. Watches for new messages in Cipher workspace
2. Routes to the appropriate agent based on `for_agent` field
3. Invokes the agent with the message context
4. Monitors for response and updates thread status

## 6. Superpowers-Inspired Skill Methodology

xgh skills follow the Superpowers framework's proven patterns for maximum quality.

### Skill Design Principles (from Superpowers)

| Principle | Application in xgh |
|-----------|-------------------|
| **TDD for documentation** | Every skill is pressure-tested against agent failure modes before shipping |
| **Iron Laws** | Each discipline skill has one non-negotiable rule (e.g., "NO CODE WITHOUT QUERYING MEMORY FIRST") |
| **Rationalization Tables** | Document actual agent excuses for skipping memory queries, then close loopholes |
| **Hard Gates** | Binary pass/fail checkpoints that block progression |
| **Fresh context per subagent** | Multi-agent tasks dispatch clean subagents to prevent context drift |
| **Evidence before claims** | Verification-before-completion applies to memory operations too |
| **2-5 minute task chunks** | Context tree curation broken into atomic operations |

### Skill Types

**Rigid skills** (mandatory process, no deviation):
- `xgh:continuous-learning` — the auto-query/auto-curate loop
- `xgh:memory-verification` — verify memory was actually stored/retrieved correctly
- `xgh:context-tree-maintenance` — scoring, maturity promotion, archival

**Flexible skills** (guidance, adaptable):
- `xgh:curate-knowledge` — how to structure knowledge for maximum retrieval
- `xgh:query-strategies` — tiered query routing patterns
- `xgh:agent-collaboration` — multi-agent workflow templates

### Enforcement Mechanisms

**The xgh Iron Law:**
> `EVERY CODING SESSION MUST QUERY MEMORY BEFORE WRITING CODE AND CURATE LEARNINGS BEFORE ENDING.`

**Rationalization Table** (anticipated agent excuses):

| Agent Thought | Reality |
|---------------|---------|
| "This is a simple change, no need to check memory" | Simple changes cause the most repeated mistakes |
| "I already know the conventions" | Your training data ≠ this team's conventions |
| "Curating this would slow me down" | 30 seconds now saves 30 minutes next session |
| "This learning is too specific to store" | Specific learnings are the most valuable |
| "Memory search returned nothing relevant" | Refine query, check context tree, then proceed |

## 7. CLI Commands & Skills

### Slash Commands (Claude Code)

| Command | Description |
|---------|-------------|
| `/xgh query <question>` | Search memory + context tree, return ranked results |
| `/xgh curate <knowledge>` | Store knowledge in Cipher + sync to context tree |
| `/xgh curate -f <file>` | Curate from file contents (up to 5 files) |
| `/xgh curate -d <dir>` | Curate from directory |
| `/xgh push` | Push context tree to git remote |
| `/xgh pull` | Pull context tree from git remote |
| `/xgh status` | Show memory stats, context tree health, agent registry |
| `/xgh collaborate <workflow> <agents>` | Start multi-agent workflow |

### Skills (auto-triggered)

| Skill | Trigger |
|-------|---------|
| `xgh:continuous-learning` | Every session (via hooks) |
| `xgh:curate-knowledge` | When agent detects new patterns/decisions |
| `xgh:query-strategies` | When agent needs to search prior knowledge |
| `xgh:agent-collaboration` | When multi-agent workflow is requested |
| `xgh:context-tree-maintenance` | Periodic (scoring updates, archival) |
| `xgh:investigate` | `/xgh investigate` or Slack thread URL detected |
| `xgh:implement-design` | `/xgh implement-design` or Figma URL detected |
| `xgh:implement-ticket` | `/xgh implement <ticket-id>` |
| `xgh:subagent-pair-programming` | `/xgh pair-program` or large implementation tasks |

## 8. Hub / Skill Marketplace

Inspired by ByteRover's BRV Hub and the MCS tech pack ecosystem.

### Hub Structure

xgh bundles are shareable packages of:
- **Context bundles** — pre-curated knowledge for specific domains (e.g., "React conventions", "Go backend patterns", "iOS architecture")
- **Workflow templates** — multi-agent collaboration patterns
- **Custom skills** — domain-specific xgh skills

### Distribution

Since xgh is an MCS tech pack, hub items can be:
1. **Git repos** — installable via `mcs pack add <repo>`
2. **Bundled in the tech pack** — shipped as part of xgh itself
3. **Team-shared** — via Cipher workspace memory (no git required)

## 9. MCS Tech Pack Structure

```yaml
schemaVersion: 1
identifier: xgh
displayName: "xgh (extreme-go-horsebot)"
description: "Self-learning memory layer with team sharing, inspired by ByteRover"
author: "xgh-dev"

components:
  # Infrastructure (plug-and-play)
  - id: vllm-mlx
    description: "Local OpenAI-compatible proxy for MLX models"
    brew: vllm-mlx

  - id: qdrant
    description: "Vector store"
    brew: qdrant

  - id: cipher
    description: "Cipher MCP memory server"
    mcp:
      command: npx
      args: ["-y", "@byterover/cipher"]
      env:
        VECTOR_STORE_TYPE: qdrant
        VECTOR_STORE_URL: "http://localhost:6333"
        CIPHER_LOG_LEVEL: info
        SEARCH_MEMORY_TYPE: both
      scope: project

  # Hooks (continuous learning)
  - id: session-start-hook
    description: "Load context tree on session start"
    hookEvent: SessionStart
    hook:
      source: hooks/session-start.sh
      destination: xgh-session-start.sh

  - id: prompt-submit-hook
    description: "Decision table: auto-query + auto-curate"
    hookEvent: UserPromptSubmit
    hook:
      source: hooks/prompt-submit.sh
      destination: xgh-prompt-submit.sh

  # Skills
  - id: continuous-learning
    description: "Core self-learning loop"
    skill:
      source: skills/continuous-learning
      destination: xgh-continuous-learning

  - id: curate-knowledge
    description: "Knowledge curation patterns"
    skill:
      source: skills/curate-knowledge
      destination: xgh-curate-knowledge

  - id: query-strategies
    description: "Tiered query routing"
    skill:
      source: skills/query-strategies
      destination: xgh-query-strategies

  - id: agent-collaboration
    description: "Multi-agent workflow patterns"
    skill:
      source: skills/agent-collaboration
      destination: xgh-agent-collaboration

  - id: context-tree-maintenance
    description: "Scoring, maturity, archival"
    skill:
      source: skills/context-tree-maintenance
      destination: xgh-context-tree-maintenance

  - id: investigate
    description: "Slack-driven debugging workflow"
    skill:
      source: skills/investigate
      destination: xgh-investigate

  - id: implement-design
    description: "Figma-driven UI implementation"
    skill:
      source: skills/implement-design
      destination: xgh-implement-design

  - id: implement-ticket
    description: "Full-context ticket implementation"
    skill:
      source: skills/implement-ticket
      destination: xgh-implement-ticket

  - id: subagent-pair-programming
    description: "Local TDD via spec writer + implementer subagents"
    skill:
      source: skills/subagent-pair-programming
      destination: xgh-subagent-pair-programming

  # Commands
  - id: query-command
    description: "Search memory + context tree"
    command:
      source: commands/query.md
      destination: xgh-query.md

  - id: curate-command
    description: "Store knowledge"
    command:
      source: commands/curate.md
      destination: xgh-curate.md

  - id: collaborate-command
    description: "Multi-agent workflows"
    command:
      source: commands/collaborate.md
      destination: xgh-collaborate.md

  - id: status-command
    description: "Memory stats and health"
    command:
      source: commands/status.md
      destination: xgh-status.md

  # Agents
  - id: context-curator
    description: "Subagent for context tree maintenance"
    agent:
      source: agents/context-curator.md
      destination: xgh-context-curator.md

  - id: collaboration-dispatcher
    description: "Subagent for multi-agent orchestration"
    agent:
      source: agents/collaboration-dispatcher.md
      destination: xgh-collaboration-dispatcher.md

  # Settings
  - id: settings
    description: "Claude Code settings for xgh"
    isRequired: true
    settingsFile: config/settings.json

  # Gitignore
  - id: gitignore
    description: "Ignore local xgh data"
    isRequired: true
    gitignore:
      - .xgh/local/
      - .xgh/context-tree/_index.md
      - data/cipher-sessions.db*

templates:
  - sectionIdentifier: xgh-instructions
    contentFile: templates/instructions.md

prompts:
  - key: TEAM_NAME
    type: input
    label: "Team name (for workspace memory)"
    default: "my-team"

  - key: CONTEXT_TREE_PATH
    type: input
    label: "Context tree path"
    default: ".xgh/context-tree"
```

## 10. Team Collaboration Skills

These skills leverage the shared Cipher workspace as an async communication bus between teammates' agents. No real-time connection needed — it works like git: write context, others read it later.

### `xgh:pr-context-bridge` — The "why" behind every PR

Today PR reviewers see the diff but not the reasoning. The author's Claude spent hours exploring approaches and making tradeoffs — all lost when the session ends.

```
┌─ Developer A (Author) ──────────────────────────────────┐
│                                                          │
│  Claude works on feature...                              │
│  Hook auto-curates to Cipher workspace:                  │
│    thread: PR-456                                        │
│    type: context                                         │
│    ├── "Considered 3 approaches, chose B because..."     │
│    ├── "Key tradeoff: latency vs consistency"            │
│    ├── "This file was tricky because..."                 │
│    └── "Related to decision from last sprint"            │
│                                                          │
│  `git push` → PR created                                │
│                                                          │
└──────────────────────────────────────────────────────────┘
                         │
                    Cipher Workspace
                    (shared memory)
                         │
┌─ Developer B (Reviewer) ─────────────────────────────────┐
│                                                          │
│  Opens PR, starts review with Claude...                  │
│  Hook auto-queries Cipher workspace:                     │
│    "PR-456 context, decisions, tradeoffs"                │
│                                                          │
│  Claude now knows:                                       │
│    ✓ WHY this approach was chosen                        │
│    ✓ What alternatives were considered                   │
│    ✓ Where the tricky parts are                          │
│    ✓ Related past decisions                              │
│                                                          │
│  Review is deeper, faster, more informed.                │
│  Stores review feedback back to thread.                  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### `xgh:knowledge-handoff` — Seamless context transfer

When developer A finishes a feature and developer B picks up related work:

- Developer A's Claude auto-curates: patterns discovered, gotchas, key files, "watch out for..."
- Stored in context tree + Cipher workspace with `scope: handoff`
- Developer B's Claude auto-queries when touching related files
- Gets full context without meetings or Slack threads

**Trigger**: On branch merge, the hook generates a structured "handoff summary" for the next developer touching that area.

### `xgh:convention-guardian` — Team decisions enforced by memory

```
1. Team decides → /xgh curate "protocol+factory for new VCs.
   Reason: 5+ consumers, need feature flag support."
   → type: convention, scope: team, maturity: core

2. Any developer starts new VC work...
   → Hook queries conventions automatically
   → Claude follows convention without being told

3. Convention evolves? Update, don't delete.
   → History preserved, rationale chain visible
```

### `xgh:cross-team-pollinator` — Breaking silos

Each team's context tree has a `_shared/` directory. Items curated there auto-promote to Cipher workspace with `scope: org`. Other teams' hooks query org-scoped memories alongside their own.

```
Frontend discovers:                    Backend benefits:
"Form validation expects ISO      →   "Frontend expects ISO dates.
 dates, not unix timestamps"           Don't change the format."

Backend decides:                       Frontend benefits:
"UserResponse.role is optional    →   "Handle nil role for
 for backward compat with v1"          backward compat with old API"

Platform team ships:                   All teams benefit:
"New shared auth middleware       →   "Use shared middleware,
 supports OAuth2 + API keys"           don't roll your own"
```

### `xgh:subagent-pair-programming` — Local TDD via two subagents

Inspired by pair programming, but happening locally: Claude dispatches two subagents that coordinate through Cipher memory. One writes tests, one implements — true TDD enforced by architecture.

```
┌─ Claude (orchestrator) ─────────────────────────────────────┐
│                                                              │
│  /xgh pair-program "Add rate limiting to API endpoints"      │
│                                                              │
│  ┌─ Subagent A (Spec Writer) ──┐  ┌─ Subagent B (Impl) ───┐│
│  │                              │  │                         ││
│  │  1. Queries memory for       │  │  3. Queries thread for  ││
│  │     related test patterns    │  │     test specs          ││
│  │  2. Writes failing tests     │  │  4. Writes MINIMAL code ││
│  │     Stores → thread:t-001   │  │     to make tests pass  ││
│  │     type: test-spec          │  │     Stores → thread:t-001││
│  │     status: RED              │  │     type: implementation ││
│  │                              │  │     status: GREEN       ││
│  │  5. Runs tests, verifies    │  │                         ││
│  │     Stores edge cases...    │  │  6. Handles edge cases  ││
│  │                              │  │                         ││
│  └──────────────────────────────┘  └─────────────────────────┘│
│                    │                            │              │
│                    └──── Cipher Memory ─────────┘              │
│                          thread: t-001                        │
│                                                              │
│  7. Orchestrator reviews both subagents' work                │
│  8. Runs full test suite for verification                    │
│  9. Curates learnings to context tree                        │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Why this works better than single-agent TDD:**
- **Separation of concerns**: spec writer can't cheat by peeking at implementation
- **Fresh context per subagent**: no context pollution (Superpowers pattern)
- **Memory as contract**: the test specs in Cipher ARE the interface between agents
- **Learnings persist**: both agents' reasoning traces stored for future sessions

This also works **cross-developer** for async pair programming across timezones — same pattern, different machines, shared Cipher workspace.

### `xgh:onboarding-accelerator` — Years of context in minutes

```
New developer joins → runs setup → first session:

  "Welcome! Querying team knowledge base..."

  → Architecture decisions (12 core entries)
  → Coding conventions (8 entries)
  → Known gotchas (15 entries)
  → Recent incidents & fixes (5 entries)
  → "Who owns what" map

  Developer asks: "How does auth work?"
  → Answer informed by months of team memory
```

## 11. Workflow Skills (MCP-Powered)

These skills integrate with external tools via MCP to create end-to-end development workflows. They combine the Superpowers methodology (systematic debugging, brainstorming, writing plans) with xgh's memory layer and team conventions.

**Prerequisite:** Each skill auto-detects which MCP servers are available. On first use, if a required MCP is missing, the `xgh:mcp-setup` skill triggers an **interactive setup helper** — guiding the user through hassle-free configuration without leaving the terminal. No hard dependencies — skills degrade gracefully if the user chooses to skip setup.

```
┌─ MCP Integrations (user-configured, all optional) ──────┐
│                                                          │
│  Communication    Task Management    Design              │
│  ┌──────────┐    ┌──────────────┐   ┌──────────┐       │
│  │ Slack    │    │ Jira         │   │ Figma    │       │
│  │ Teams    │    │ Linear       │   │ FigJam   │       │
│  │ Discord  │    │ GitHub Issues│   │          │       │
│  └──────────┘    │ Asana        │   └──────────┘       │
│                  │ Shortcut     │                       │
│                  └──────────────┘                       │
│                                                          │
│  xgh auto-detects which MCPs are available and adapts.   │
│  Missing MCP? → Interactive setup helper on first use.   │
│  User can skip → skill degrades gracefully.              │
│  /xgh-setup → full audit of all integrations.            │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### `xgh:investigate` — Slack-Driven Debugging Workflow

A systematic investigation skill inspired by Superpowers' `systematic-debugging`. Starts from a Slack thread (bug report, alert, user complaint) and produces a detailed finding report.

```
┌─ Investigation Flow ────────────────────────────────────────────┐
│                                                                  │
│  TRIGGER: "/xgh investigate <slack-thread-url>"                  │
│           or "/xgh investigate" (prompts for context)            │
│                                                                  │
│  ┌─ Phase 1: Context Gathering ──────────────────────────────┐  │
│  │                                                            │  │
│  │  1. Read Slack thread (via Slack MCP)                      │  │
│  │     → Extract: symptoms, affected users, timestamps,       │  │
│  │       error messages, screenshots, related threads         │  │
│  │                                                            │  │
│  │  2. Search for related Slack discussions                   │  │
│  │     → "Has this happened before?"                          │  │
│  │     → Find prior incidents, workarounds, affected areas    │  │
│  │                                                            │  │
│  │  3. Query xgh memory                                       │  │
│  │     → cipher_memory_search: similar bugs, past fixes       │  │
│  │     → context tree: related architecture decisions         │  │
│  │     → team conventions for this area                       │  │
│  │                                                            │  │
│  │  4. Check task manager (if MCP configured)                 │  │
│  │     → Search Jira/Linear/GitHub for existing tickets       │  │
│  │     → "Is someone already working on this?"                │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 2: Interactive Triage (prompts user) ──────────────┐  │
│  │                                                            │  │
│  │  IF existing ticket found:                                 │  │
│  │    → "Found JIRA-1234: 'Login timeout on mobile'          │  │
│  │       Status: In Progress, Assigned: @alice                │  │
│  │       Want to add context from this thread to it?"         │  │
│  │                                                            │  │
│  │  IF no ticket found:                                       │  │
│  │    → "No existing ticket. Want me to create one?"          │  │
│  │    → Interactive: title, priority, assignee, labels         │  │
│  │    → Creates ticket via task manager MCP                   │  │
│  │                                                            │  │
│  │  IF no task manager MCP:                                   │  │
│  │    → Skips ticket management, continues with investigation │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 3: Systematic Debug (Superpowers methodology) ─────┐  │
│  │                                                            │  │
│  │  Iron Law: NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST │  │
│  │                                                            │  │
│  │  1. Reproduce: trace from symptoms to code paths           │  │
│  │  2. Boundary analysis: log at module transitions           │  │
│  │  3. Pattern analysis: diff working vs broken               │  │
│  │  4. Hypothesis: single theory, minimal isolated test       │  │
│  │  5. Root cause: confirmed with evidence                    │  │
│  │                                                            │  │
│  │  Hard gate: after 3 failed hypotheses → stop,              │  │
│  │  question architecture, ask user for help                  │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 4: Finding Report ─────────────────────────────────┐  │
│  │                                                            │  │
│  │  Structured report (inspired by Superpowers writing):      │  │
│  │                                                            │  │
│  │  # Investigation: [Title]                                  │  │
│  │  ## Source: [Slack thread link]                             │  │
│  │  ## Ticket: [JIRA-1234] (if created/found)                │  │
│  │  ## Summary: [1-2 sentence root cause]                     │  │
│  │  ## Timeline: [when it started, when reported]             │  │
│  │  ## Root Cause: [detailed technical analysis]              │  │
│  │  ## Evidence: [logs, traces, reproduction steps]           │  │
│  │  ## Impact: [affected users, severity]                     │  │
│  │  ## Fix: [proposed solution with code]                     │  │
│  │  ## Prevention: [what would catch this earlier]            │  │
│  │  ## Related: [links to past incidents, decisions]          │  │
│  │                                                            │  │
│  │  → Saved to context tree: investigations/[date]-[title]    │  │
│  │  → Curated to Cipher memory (learnings persist)            │  │
│  │  → Optionally posted back to Slack thread                  │  │
│  │  → Optionally attached to ticket                           │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### `xgh:implement-design` — Figma-Driven UI Implementation

Takes a Figma design URL and produces a complete, convention-compliant implementation by gathering ALL available context from the design file.

```
┌─ Figma Implementation Flow ─────────────────────────────────────┐
│                                                                  │
│  TRIGGER: "/xgh implement-design <figma-url>"                    │
│           or "/xgh implement-design" (prompts for URL)           │
│                                                                  │
│  ┌─ Phase 1: Deep Design Mining ─────────────────────────────┐  │
│  │                                                            │  │
│  │  Via Figma MCP:                                            │  │
│  │                                                            │  │
│  │  1. get_design_context(nodeId, fileKey)                    │  │
│  │     → Code hints, component mappings, design tokens        │  │
│  │                                                            │  │
│  │  2. get_screenshot(nodeId, fileKey)                        │  │
│  │     → Visual reference for layout understanding            │  │
│  │                                                            │  │
│  │  3. get_metadata(fileKey)                                  │  │
│  │     → File structure, pages, component inventory           │  │
│  │                                                            │  │
│  │  4. Search for related FigJam boards:                      │  │
│  │     → get_figjam for linked boards                         │  │
│  │     → Extract: user flows, state diagrams, edge cases,     │  │
│  │       designer notes, acceptance criteria, annotations     │  │
│  │                                                            │  │
│  │  5. get_variable_defs(fileKey)                             │  │
│  │     → Design tokens, color system, spacing, typography     │  │
│  │                                                            │  │
│  │  6. get_code_connect_map(fileKey)                          │  │
│  │     → Existing component ↔ codebase mappings               │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 2: Context Enrichment ─────────────────────────────┐  │
│  │                                                            │  │
│  │  1. Query xgh memory:                                      │  │
│  │     → "How do we implement [component type] in this repo?" │  │
│  │     → Team conventions for UI components                   │  │
│  │     → Past implementations of similar designs              │  │
│  │     → Design system component inventory                    │  │
│  │                                                            │  │
│  │  2. Scan codebase for existing components:                 │  │
│  │     → Match Figma components to code via Code Connect      │  │
│  │     → Identify reusable components vs new ones needed      │  │
│  │                                                            │  │
│  │  3. Check task manager (if MCP configured):                │  │
│  │     → Find ticket for this design work                     │  │
│  │     → Extract acceptance criteria, requirements, notes     │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 3: Interactive State Review (prompts user) ────────┐  │
│  │                                                            │  │
│  │  Present discovered states and ask for confirmation:       │  │
│  │                                                            │  │
│  │  "I found these states in the Figma file:                  │  │
│  │   ✓ Default state (node 34079:43248)                       │  │
│  │   ✓ Loading state (node 34079:43320)                       │  │
│  │   ✓ Error state (node 34256:54416)                         │  │
│  │   ✓ Empty state (node 34256:54400)                         │  │
│  │   ? Offline state — not found. Is there one?"              │  │
│  │                                                            │  │
│  │  "FigJam notes mention:                                    │  │
│  │   - 'Animation on transition between states'               │  │
│  │   - 'Skeleton loading, not spinner'                        │  │
│  │   - 'Error must show retry CTA'                            │  │
│  │   Any additional requirements?"                            │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 4: Implementation Plan + Execute ──────────────────┐  │
│  │                                                            │  │
│  │  Uses Superpowers writing-plans methodology:               │  │
│  │  → 2-5 minute tasks with exact file paths                  │  │
│  │  → TDD: test per state before implementation               │  │
│  │  → Maps Figma tokens → project's design system             │  │
│  │  → Reuses existing components (never reinvent)             │  │
│  │  → Follows team conventions from context tree              │  │
│  │                                                            │  │
│  │  Subagent execution (if user approves):                    │  │
│  │  → Fresh subagent per component/state                      │  │
│  │  → Two-stage review: design fidelity + code quality        │  │
│  │  → Screenshot comparison: Figma vs rendered                │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 5: Curate & Report ────────────────────────────────┐  │
│  │                                                            │  │
│  │  → Curate: new component mappings, design patterns         │  │
│  │  → Update Code Connect: new Figma ↔ code mappings          │  │
│  │  → Context tree: design-system/[component].md              │  │
│  │  → Report: what was implemented, decisions made,           │  │
│  │    components reused vs created, deviations from design    │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### `xgh:implement-ticket` — Full-Context Ticket Implementation

The most comprehensive skill. Takes a ticket from any task manager, gathers ALL available context (ticket, Slack, Figma, memory, codebase), interviews the user for missing context, and produces a complete implementation plan.

```
┌─ Implement Ticket Flow ─────────────────────────────────────────┐
│                                                                  │
│  TRIGGER: "/xgh implement <ticket-id>"                           │
│           "/xgh implement PROJ-1234"                             │
│           "/xgh implement" (searches recent assigned tickets)    │
│                                                                  │
│  ┌─ Phase 1: Ticket Deep Dive ──────────────────────────────┐   │
│  │                                                            │  │
│  │  Via task manager MCP (auto-detected):                     │  │
│  │                                                            │  │
│  │  1. Fetch ticket details:                                  │  │
│  │     → Title, description, acceptance criteria              │  │
│  │     → Status, priority, assignee, sprint                   │  │
│  │     → Comments, attachments, linked tickets                │  │
│  │     → Epic/parent context                                  │  │
│  │                                                            │  │
│  │  2. Traverse linked tickets:                               │  │
│  │     → Blocked by / blocks relationships                    │  │
│  │     → Related tickets (similar work, dependencies)         │  │
│  │     → Epic-level requirements and constraints              │  │
│  │                                                            │  │
│  │  3. Extract structured requirements:                       │  │
│  │     → User stories → testable assertions                   │  │
│  │     → Acceptance criteria → verification checklist          │  │
│  │     → "Definition of done" → completion gate               │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 2: Cross-Platform Context Gathering ───────────────┐  │
│  │                                                            │  │
│  │  Searches ALL available MCPs for related context:          │  │
│  │                                                            │  │
│  │  Slack (if configured):                                    │  │
│  │  → Search for ticket ID mentions in channels               │  │
│  │  → Find design discussions, requirement debates            │  │
│  │  → Extract decisions made in threads                       │  │
│  │                                                            │  │
│  │  Figma (if configured):                                    │  │
│  │  → Search for linked designs in ticket attachments         │  │
│  │  → Fetch design context, states, annotations               │  │
│  │  → Extract FigJam notes and acceptance criteria            │  │
│  │                                                            │  │
│  │  xgh Memory (always):                                      │  │
│  │  → cipher_memory_search: related past work                 │  │
│  │  → Context tree: conventions for this domain               │  │
│  │  → Team decisions that affect this implementation          │  │
│  │  → Past investigations/bugs in this area                   │  │
│  │                                                            │  │
│  │  Codebase (always):                                        │  │
│  │  → Find related files, modules, tests                      │  │
│  │  → Understand existing patterns to follow                  │  │
│  │  → Identify integration points                             │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 3: Context Interview (Superpowers brainstorming) ──┐  │
│  │                                                            │  │
│  │  Present gathered context, then interview ONE question     │  │
│  │  at a time (Superpowers pattern):                          │  │
│  │                                                            │  │
│  │  "Here's what I know about PROJ-1234:                      │  │
│  │   ✓ Ticket: Add rate limiting to public API                │  │
│  │   ✓ AC: 100 req/min per user, 429 response, retry-after   │  │
│  │   ✓ Slack: @bob mentioned Redis for the counter store      │  │
│  │   ✓ Memory: team uses token-bucket (convention #42)        │  │
│  │   ✓ Design: no Figma linked                                │  │
│  │   ? Missing: which endpoints? All public, or subset?"      │  │
│  │                                                            │  │
│  │  Follow-up questions (one at a time):                      │  │
│  │  → "Should rate limits differ per endpoint?"               │  │
│  │  → "Redis or in-memory? (Slack says Redis)"                │  │
│  │  → "Need admin override capability?"                       │  │
│  │                                                            │  │
│  │  Multiple choice preferred (Superpowers pattern):          │  │
│  │  → A) All public endpoints, same limit                     │  │
│  │  → B) Per-endpoint configuration                           │  │
│  │  → C) Tiered by user plan                                  │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 4: Design Proposal (2-3 approaches) ──────────────┐  │
│  │                                                            │  │
│  │  Superpowers brainstorming pattern:                        │  │
│  │  → Propose 2-3 approaches with trade-offs                  │  │
│  │  → Lead with recommendation and reasoning                  │  │
│  │  → Reference team conventions and past decisions            │  │
│  │  → Present design section by section for approval           │  │
│  │                                                            │  │
│  │  Hard gate: NO IMPLEMENTATION WITHOUT APPROVED DESIGN       │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 5: Implementation Plan (Superpowers writing-plans) ┐  │
│  │                                                            │  │
│  │  Detailed plan with:                                       │  │
│  │  → 2-5 minute tasks with exact file paths                  │  │
│  │  → TDD: failing test before each implementation step       │  │
│  │  → Verification command per step                           │  │
│  │  → Complete code (no "add validation here" placeholders)   │  │
│  │  → Follows ALL team conventions from context tree           │  │
│  │                                                            │  │
│  │  Saved to: docs/plans/YYYY-MM-DD-[ticket-id]-plan.md      │  │
│  │  Linked back to ticket via task manager MCP                │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                         │                                        │
│                         ▼                                        │
│  ┌─ Phase 6: Execute + Report ───────────────────────────────┐  │
│  │                                                            │  │
│  │  Subagent-driven execution (Superpowers pattern):          │  │
│  │  → Fresh subagent per task                                 │  │
│  │  → TDD enforced (iron law)                                 │  │
│  │  → Two-stage review per task                               │  │
│  │  → Verification before completion                          │  │
│  │                                                            │  │
│  │  On completion:                                            │  │
│  │  → Update ticket status via MCP                            │  │
│  │  → Post implementation summary to Slack thread             │  │
│  │  → Curate learnings to context tree + Cipher               │  │
│  │  → Generate PR with full context (pr-context-bridge)       │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Skill Interaction Map

All workflow skills compose with each other and the team collaboration skills:

```
                    /xgh implement PROJ-1234
                            │
                ┌───────────┼───────────┐
                ▼           ▼           ▼
          Slack MCP    Figma MCP   Task MCP
          (context)    (designs)   (ticket)
                │           │           │
                └─────┬─────┘───────────┘
                      ▼
              xgh Memory Layer
              (conventions, decisions,
               past work, patterns)
                      │
                      ▼
            Brainstorming Interview
            (one question at a time)
                      │
                      ▼
            Design → Plan → Execute
            (Superpowers methodology)
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
  subagent-pair    convention    pr-context
  -programming     -guardian     -bridge
  (TDD enforce)  (check rules) (share why)
                      │
                      ▼
              Curate Learnings
              (context tree + Cipher)
```

## 12. Installation

### Option A: MCS Tech Pack (recommended)

```bash
mcs pack add xgh && mcs sync
```

Handles everything automatically. See Section 9 for full tech pack manifest.

```
Step 1: Install vllm-mlx (brew)        ✓ auto
Step 2: Start vllm-mlx with models     ✓ manual
Step 4: Install Qdrant (brew)           ✓ auto
Step 5: Configure Cipher MCP server     ✓ auto
Step 6: Install hooks                   ✓ auto
Step 7: Install skills + commands       ✓ auto
Step 8: Initialize .xgh/context-tree/   ✓ auto (via configureProject script)
Step 9: Prompt for team name            ? one question
Step 10: Ready to use                   🐴
```

### Option B: One-Liner Install (no MCS required)

```bash
curl -fsSL https://raw.githubusercontent.com/xgh-dev/xgh/main/install.sh | bash
```

The install script handles everything MCS would do, but standalone:

```bash
#!/usr/bin/env bash
set -euo pipefail

XGH_VERSION="${XGH_VERSION:-latest}"
XGH_TEAM="${XGH_TEAM:-my-team}"
XGH_CONTEXT_PATH="${XGH_CONTEXT_PATH:-.xgh/context-tree}"
XGH_REPO="https://github.com/extreme-go-horse/xgh"

echo "🐴 Installing xgh (extreme-go-horsebot) ${XGH_VERSION}..."

# ── 1. Dependencies ──────────────────────────────────────
echo "→ Checking dependencies..."

if ! command -v brew &>/dev/null; then
  echo "  Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if ! command -v vllm-mlx &>/dev/null; then
  echo "  Installing vllm-mlx..."
  brew install vllm-mlx
fi

if ! command -v qdrant &>/dev/null; then
  echo "  Installing Qdrant..."
  brew install qdrant
fi

# ── 2. Models ────────────────────────────────────────────
echo "→ Models are served by vllm-mlx — ensure it is running with the required models"

# ── 3. Clone xgh ────────────────────────────────────────
echo "→ Fetching xgh..."
XGH_HOME="${HOME}/.xgh"
mkdir -p "${XGH_HOME}"

if [ -d "${XGH_HOME}/pack" ]; then
  git -C "${XGH_HOME}/pack" pull --quiet
else
  git clone --quiet --depth 1 "${XGH_REPO}" "${XGH_HOME}/pack"
fi

# ── 4. Cipher MCP Server ────────────────────────────────
echo "→ Configuring Cipher MCP server..."
CLAUDE_DIR="${PWD}/.claude"
mkdir -p "${CLAUDE_DIR}"

# Project-scoped MCP config (shared via git)
cat > "${CLAUDE_DIR}/.mcp.json" <<MCPEOF
{
  "mcpServers": {
    "cipher": {
      "command": "npx",
      "args": ["-y", "@byterover/cipher"],
      "env": {
        "VECTOR_STORE_TYPE": "qdrant",
        "VECTOR_STORE_URL": "http://localhost:6333",
        "CIPHER_LOG_LEVEL": "info",
        "SEARCH_MEMORY_TYPE": "both",
        "USE_WORKSPACE_MEMORY": "true",
        "XGH_TEAM": "${XGH_TEAM}"
      }
    }
  }
}
MCPEOF

# ── 5. Hooks ────────────────────────────────────────────
echo "→ Installing hooks..."
mkdir -p "${CLAUDE_DIR}/hooks"
cp "${XGH_HOME}/pack/hooks/session-start.sh" "${CLAUDE_DIR}/hooks/xgh-session-start.sh"
cp "${XGH_HOME}/pack/hooks/prompt-submit.sh" "${CLAUDE_DIR}/hooks/xgh-prompt-submit.sh"
chmod +x "${CLAUDE_DIR}/hooks/"xgh-*.sh

# Merge hook events into settings
SETTINGS_FILE="${CLAUDE_DIR}/settings.local.json"
if [ ! -f "${SETTINGS_FILE}" ]; then echo '{}' > "${SETTINGS_FILE}"; fi

# Use node/npx to safely merge JSON (available via cipher dep)
npx -y json-merger@latest \
  "${SETTINGS_FILE}" \
  "${XGH_HOME}/pack/config/hooks-settings.json" \
  -o "${SETTINGS_FILE}" 2>/dev/null || {
    # Fallback: copy hooks settings directly
    cp "${XGH_HOME}/pack/config/settings.json" "${SETTINGS_FILE}"
  }

# ── 6. Skills + Commands + Agents ────────────────────────
echo "→ Installing skills, commands, and agents..."
mkdir -p "${CLAUDE_DIR}/skills" "${CLAUDE_DIR}/commands" "${CLAUDE_DIR}/agents"

for skill_dir in "${XGH_HOME}/pack/skills/"*/; do
  skill_name=$(basename "${skill_dir}")
  cp -r "${skill_dir}" "${CLAUDE_DIR}/skills/xgh-${skill_name}"
done

for cmd in "${XGH_HOME}/pack/commands/"*.md; do
  [ -f "${cmd}" ] && cp "${cmd}" "${CLAUDE_DIR}/commands/xgh-$(basename "${cmd}")"
done

for agent in "${XGH_HOME}/pack/agents/"*.md; do
  [ -f "${agent}" ] && cp "${agent}" "${CLAUDE_DIR}/agents/xgh-$(basename "${agent}")"
done

# ── 7. Context Tree ─────────────────────────────────────
echo "→ Initializing context tree..."
mkdir -p "${PWD}/${XGH_CONTEXT_PATH}"
cat > "${PWD}/${XGH_CONTEXT_PATH}/_manifest.json" <<MANIFESTEOF
{
  "version": 1,
  "team": "${XGH_TEAM}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "domains": []
}
MANIFESTEOF

# ── 8. Gitignore ─────────────────────────────────────────
echo "→ Updating .gitignore..."
GITIGNORE="${PWD}/.gitignore"
touch "${GITIGNORE}"
for pattern in ".xgh/local/" "data/cipher-sessions.db*"; do
  grep -qxF "${pattern}" "${GITIGNORE}" 2>/dev/null || echo "${pattern}" >> "${GITIGNORE}"
done

# ── 9. CLAUDE.local.md ──────────────────────────────────
echo "→ Adding xgh instructions to CLAUDE.local.md..."
if ! grep -q "mcs:begin xgh" "${PWD}/CLAUDE.local.md" 2>/dev/null; then
  cat >> "${PWD}/CLAUDE.local.md" <<CLAUDEEOF

<!-- mcs:begin xgh.instructions -->
# xgh (extreme-go-horsebot) — Self-Learning Memory

This project uses xgh for persistent team memory. Your hooks will
automatically query memory before coding and curate learnings after.

Key tools available via Cipher MCP:
- cipher_memory_search: Search prior knowledge
- cipher_extract_and_operate_memory: Store new knowledge
- cipher_workspace_search: Search team-wide knowledge
- cipher_workspace_store: Share knowledge with the team

Context tree: ${XGH_CONTEXT_PATH}/
Team: ${XGH_TEAM}
<!-- mcs:end xgh.instructions -->
CLAUDEEOF
fi

echo ""
echo "🐴 xgh installed successfully!"
echo ""
echo "  Context tree: ${XGH_CONTEXT_PATH}/"
echo "  Team:         ${XGH_TEAM}"
echo "  Cipher MCP:   configured in .claude/.mcp.json"
echo "  Hooks:        session-start + prompt-submit"
echo ""
echo "  Start Claude Code and your memory layer is active."
echo "  Use /xgh-query and /xgh-curate for manual control."
echo ""
echo "  To customize: XGH_TEAM=my-team XGH_CONTEXT_PATH=.memory/tree bash install.sh"
```

### Usage After Installation (both methods)

**It just works.** After installation, open Claude Code in your project:

```
$ claude

  🐴 xgh active | team: my-team | 47 memories | 12 core conventions

  You: "Add a new API endpoint for user preferences"

  [Hook fires: querying memory for API conventions...]
  [Found: 3 relevant conventions, 2 related decisions]

  Claude: "Based on your team's conventions, I'll use the
  UseCase pattern with protocol+factory. I see the auth
  team recently added Argon2id — I'll ensure the preferences
  endpoint follows the same security patterns..."

  [After implementation, hook fires: curating learnings...]
  [Stored: 2 new knowledge entries, updated 1 existing]
```

**Manual commands:**

```bash
# Query memory
/xgh-query "How does authentication work in this project?"

# Curate knowledge explicitly
/xgh-curate "Rate limiting uses token bucket with 100 req/min per user"

# Curate from files
/xgh-curate -f src/auth/middleware.ts "Auth middleware patterns"

# Check status
/xgh-status

# Multi-agent collaboration
/xgh-collaborate plan-review --agents "claude,codex" --thread feat-123
```

**Environment variables for customization:**

| Variable | Default | Description |
|----------|---------|-------------|
| `XGH_TEAM` | `my-team` | Team name for workspace memory |
| `XGH_CONTEXT_PATH` | `.xgh/context-tree` | Where the context tree lives |
| `XGH_VERSION` | `latest` | Pin to a specific version |
| `MLX_PROXY_URL` | `http://localhost:11434` | Custom vllm-mlx endpoint |
| `VECTOR_STORE_URL` | `http://localhost:6333` | Custom Qdrant endpoint |

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/xgh-dev/xgh/main/uninstall.sh | bash
```

Or manually:
```bash
rm -rf ~/.xgh
rm -f .claude/hooks/xgh-*.sh
rm -rf .claude/skills/xgh-*
rm -rf .claude/commands/xgh-*
rm -rf .claude/agents/xgh-*
# Remove xgh section from CLAUDE.local.md and .claude/.mcp.json manually
```

## 13. Key Influences & Attribution

| Source | What we adopted |
|--------|----------------|
| **ByteRover** | Context tree hierarchy, YAML frontmatter, scoring/maturity, hook decision table, tiered query routing, hub concept |
| **Cipher** | Vector memory, knowledge graph, reasoning traces, dual System 1/2 memory, workspace sharing, MCP server |
| **Superpowers** | Skill methodology (TDD for docs, iron laws, rationalization tables, hard gates), subagent-driven development, fresh-context-per-task, verification-before-completion |
| **ByteRover-Claude-Codex-Collaboration** | Multi-agent communication via shared memory, structured message protocol, workflow templates |
| **MCS** | Tech pack distribution, plug-and-play installation, managed settings composition |
