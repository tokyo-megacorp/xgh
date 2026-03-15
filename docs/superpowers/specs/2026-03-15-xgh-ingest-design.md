# xgh-ingest: Automated Context Ingestion System

> **Date:** 2026-03-15
> **Status:** Design — pending review
> **Author:** Pedro + Claude (brainstorming session)

---

## 1. Overview

xgh-ingest is a **continuous context synchronization layer** — a daemon that bridges the gap between where decisions happen (Slack, meetings, Figma comments, Jira transitions) and where work happens (the IDE, the Claude session). Technically, it's an ETL pipeline for human intent: extract from conversation tools, transform into structured knowledge, load into vector memory.

It runs as two independent timer-driven headless Claude CLI sessions: a lightweight **retriever** (high frequency) and a heavier **analyzer** (lower frequency). On macOS, scheduling uses `launchd`; on Linux, `cron`.

### Vision

The code is the *what*; the Slack threads, Jira comments, and Figma rationale are the *why*. Without the why, AI agents make technically correct but contextually wrong decisions. xgh-ingest feeds the why into memory so every future session starts with the full picture.

What this system externalizes is the **peripheral awareness** that good engineers develop intuitively — the sense of "something changed," "someone needs me," "this decision contradicts what we agreed last week." It takes the background monitoring that lives rent-free in your head and makes it a system.

In one phrase: **ambient project intelligence** — always listening, always synthesizing, always ready when you sit down to work.

### Problem

In a typical engineering org, projects are organized in Slack channel pairs (general + engineering) per topic. Requirements shift frequently, deadlines are short, and critical decisions happen informally in Slack threads — linking out to Jira tickets, Confluence specs, Figma designs, and GitHub PRs. Staying current requires a human brain to continuously monitor 5+ tools, hold context across threads, and notice when a spec shifts. That's not engineering work — it's cognitive overhead. And it scales inversely with the number of projects you're on.

### Goals

1. **Never miss a spec change** — continuously ingest project context from all integrated tools
2. **Urgency-aware** — detect and alert on critical items (blockers, P0s, deadline shifts) with role-aware relevance scoring
3. **Team-shareable** — promote decisions and project status to Cipher workspace memory for cross-agent visibility
4. **Low friction** — projects onboarded via an interactive skill, config auto-enriches over time
5. **Codebase-aware** — index repository architecture, patterns, and conventions into searchable memory

### Non-goals (v1)

- Full knowledge graph (Neo4j) — deferred to future version
- Gmail/Calendar integration — requires corporate approval; v1 parses meeting notes from Confluence/Slack instead
- Multi-user orchestration — v1 is single-user; team sharing happens via workspace collections

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────┐
│  ~/.xgh/ingest.yaml                                     │
│  (profile, keywords, projects, schedule)                │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │   RETRIEVER (*/5 cron)  │
        │   Light Claude session  │
        │   - Scan Slack channels │
        │   - Follow links 1-hop  │
        │   - Stash to inbox/     │
        │   - Detect urgency      │
        │   - Track cursors       │
        └──┬─────────────┬────────┘
           │             │
     ┌─────▼─────┐  ┌───▼──────────────┐
     │ .xgh/     │  │ URGENT?          │
     │ inbox/    │  │ → Slack DM user  │
     │ (raw)     │  │ → Trigger        │
     └─────┬─────┘  │   mini-analyze   │
           │        └──────────────────┘
     ┌─────▼──────────────────┐
     │  ANALYZER (*/30 cron)  │
     │  Heavy Claude session  │
     │  - Read inbox/         │
     │  - Classify content    │
     │  - Extract structured  │
     │    memories            │
     │  - Dedup + TTL mgmt    │
     │  - Write to Cipher     │
     └──┬────────────┬────────┘
        │            │
   ┌────▼─────┐ ┌───▼──────────────┐
   │ Personal │ │ Shared workspace │
   │ knowledge│ │ collection       │
   │ (private)│ │ (team-visible)   │
   └──────────┘ └──────────────────┘
```

### Key design decisions

- **Headless Claude CLI via cron** (`claude -p "/xgh-retrieve"`) — reuses full MCP toolbox (Slack, Jira, Confluence, GitHub, Figma, Cipher) without building a separate API integration layer
- **Filesystem inbox** (`.xgh/inbox/`) — raw content stashed as timestamped markdown files; simple, inspectable, git-ignorable
- **Claude-powered extraction** — the analyzer (a frontier model) does the structuring, not Cipher's 3B extractor. Higher quality, can see full cross-source context
- **Direct Qdrant writes** — bypasses Cipher's internal-only `workspace_store` tool by writing structured payloads directly to Qdrant. Schema risk accepted for PoC; mitigated by centralizing the write function
- **Embedding-aware writes** — the centralized write helper calls the same embedding endpoint (configured in `~/.cipher/cipher.yml`) with the same model/dimensions that Cipher uses internally, ensuring `cipher_workspace_search` returns correct similarity results
- **Config locking** — only the analyzer modifies `ingest.yaml` (auto-enrichment deferred from retriever). The retriever writes discovered references to `.xgh/inbox/.enrichments.json`; the analyzer merges them into `ingest.yaml` during its run, eliminating concurrent write conflicts
- **Scheduling via launchd** — on macOS, uses `launchd` plist files instead of cron for reliable execution during sleep/wake cycles. Cron syntax in this spec is illustrative; actual scheduling adapts to the host OS

---

## 3. Central Configuration

Single file at `~/.xgh/ingest.yaml` — source of truth for both loops, the onboarding skill, and the doctor function.

```yaml
# ~/.xgh/ingest.yaml

profile:
  name: Pedro
  slack_id: U12345ABC
  role: iOS engineer
  squad: Customer Platform
  platforms: [ios]
  also_monitor: [backend]   # informational, no urgency boost

urgency:
  keywords:
    critical:
      - hotfix
      - go live
      - go-live
      - golive
      - production issue
      - prod issue
      - release blocker
      - P0
      - p0
      - rollback
      - revert
    deadline:
      - release date
      - code freeze
      - EOD
      - end of day
      - deadline
      - ship date
      - launch date
      - cutoff
    scope:
      - requirement changed
      - spec updated
      - new approach
      - scope change
      - pivot
      - change of plans
    infra:
      - 5xx
      - "502"
      - pods
      - outage
      - downtime
      - broken in prod
      - incident
      - on-call
  relevance:
    my_platform: 2.0
    my_squad: 1.5
    also_monitor: 1.0
    other_platform: 0.3
    other_squad: 0.5
  thresholds:
    log: 0
    digest: 31
    high: 56
    critical: 80

schedule:
  retriever: "*/5 * * * *"
  analyzer: "*/30 * * * *"
  quiet_hours: "22:00-07:00"      # no DMs during these hours; queued for morning
  quiet_days: [saturday, sunday]  # no DMs on weekends; queued for Monday

models:
  retriever: haiku                # fast + cheap for scan-and-stash
  analyzer: sonnet                # strong reasoning for extraction + classification
  urgency: haiku                  # inline scoring during retrieval — speed matters
  indexer: sonnet                 # codebase indexing needs architectural understanding
  # Options: haiku (fastest/cheapest), sonnet (balanced), opus (maximum quality)
  # Override per-project if needed in the project config

budget:
  # Claude CLI supports --max-turns (not --max-tokens). Token caps are enforced
  # via turn limits + timeout, with external tracking for daily budgets.
  retriever_max_turns: 3         # per run — scan + stash is ~2-3 turns
  analyzer_max_turns: 10         # per run — classification + extraction needs more
  indexer_max_turns: 20          # per run — full codebase exploration is multi-step
  retriever_timeout: 60s         # kill if exceeds this wall-clock time
  analyzer_timeout: 300s         # 5 min max per analyzer run
  indexer_timeout: 600s          # 10 min max for codebase indexing
  daily_token_cap: 2_000_000     # soft cap — tracked via usage.csv, DM warning when hit
  warn_at_percent: 80            # DM warning when 80% of daily cap consumed
  cost_tracking: true            # log token usage per run to ~/.xgh/logs/usage.csv
  pause_on_cap: true             # skip scheduled runs when daily cap is exceeded

retriever:
  max_messages_per_channel: 100  # per scan cycle
  max_links_to_follow: 20       # per scan cycle, across all channels
  link_depth: 1                  # hops from Slack message (1 = direct link only)
  stale_cursor_reset: 7d        # if a channel hasn't been scanned in 7d, reset cursor to now
  backoff_on_rate_limit: true   # exponential backoff on 429s
  max_retries: 3                # per channel per cycle

analyzer:
  max_inbox_items: 50            # process at most N items per run (overflow waits)
  dedup_threshold: 0.85          # cosine similarity — above this = duplicate
  min_urgency_to_store: 10      # below this, don't bother storing (noise filter)
  max_memories_per_run: 30       # cap to prevent runaway storage
  promote_after_references: 2   # informal items auto-promote after N re-references

notifications:
  dm_cooldown: 15m               # min time between DMs (prevents spam)
  dm_batch: true                 # batch multiple urgencies into one DM if within cooldown
  digest_time: "08:30"           # when to generate/send daily digest
  digest_channel: null           # optional: post digest to a channel instead of DM

retention:
  inbox_processed: 7d            # purge processed files after 7 days
  digests: 30d                   # keep daily digests for 30 days
  logs: 10MB                     # max log size before rotation
  log_retention: 7d              # keep rotated logs for 7 days
  decayed_memories: 90d          # purge decayed (TTL-expired) memories after 90 days

cipher:
  workspace_mode: shared
  workspace_collection: customer-platform-workspace
  knowledge_collection: pedro-memory
  embedding_batch_size: 10       # vectors per Qdrant upsert batch
  search_top_k: 5                # default results per search query
  similarity_threshold: 0.3      # minimum similarity for search results

content_types:
  decision:
    description: "Locked-in choice (approach, architecture, scope)"
    ttl: null
    promote_to: workspace
  spec_change:
    description: "Requirement or spec modification"
    ttl: null
    promote_to: workspace
  p0:
    description: "Critical priority — blocking release or production"
    ttl: null
    promote_to: workspace
    urgency_floor: 90
  p1:
    description: "High priority — must address this sprint"
    ttl: null
    promote_to: workspace
    urgency_floor: 65
  wip:
    description: "Actively being worked on — bugs, features, tasks"
    ttl: null
    promote_to: workspace
  awaiting_my_reply:
    description: "Someone needs something from me"
    ttl: 7d
    promote_to: personal
    urgency: aging
  awaiting_their_reply:
    description: "I'm blocked waiting on someone else"
    ttl: 14d
    promote_to: personal
    urgency: aging
  informal_request:
    description: "Ask in Slack not yet ticketed"
    ttl: 7d
    promote_to: personal
  qa_feedback:
    description: "Bug report or issue from QA in chat"
    ttl: 14d
    promote_to: personal
  known_issue:
    description: "Acknowledged problem, not yet prioritized"
    ttl: 30d
    promote_to: workspace
  status_update:
    description: "Progress, deploy, merge notifications"
    ttl: 3d
    promote_to: workspace

projects: {}
  # Populated via /xgh-track — see Section 8
```

---

## 4. Retriever Loop

**Invocation:** `claude -p "/xgh-retrieve" --allowedTools "mcp__claude_ai_Slack__*,mcp__claude_ai_Atlassian__*,Bash,Read,Write,Glob"`
**Frequency:** Every 5 minutes
**Session cost:** Light — scan + stash, no heavy analysis

### 4.1 Workflow

1. **Read config** — load `~/.xgh/ingest.yaml`, filter to `status: active` projects
2. **Read cursors** — `.xgh/inbox/.cursors.json` tracks last-seen timestamp per Slack channel
3. **Scan Slack channels** — for each project's channels, read messages since last cursor via `slack_read_channel`
4. **Follow links 1-hop** — for each message containing a link:
   - Jira link → `getJiraIssue` (title, description, status, assignee, comments)
   - Confluence link → `getConfluencePage` (content, version)
   - GitHub PR link → `gh pr view` (description, status, review comments)
   - Figma link → `get_metadata` (last modified, component name)
5. **Stash raw content** — one file per item in `.xgh/inbox/`:
   ```
   .xgh/inbox/
     2026-03-15T14-30-00_slack_ptech-31204-eng_msg123.md
     2026-03-15T14-31-00_jira_PTECH-31204.md
     2026-03-15T14-31-00_confluence_12345.md
   ```
6. **Update cursors** — write new high-water marks
7. **Queue enrichments** — if a new Jira key, Confluence space, or GitHub repo was discovered, write it to `.xgh/inbox/.enrichments.json` (the analyzer merges these into `ingest.yaml` during its run — the retriever never modifies `ingest.yaml` directly)
8. **Urgency check** — score messages against urgency detection (Section 5)
9. **Session tracking** — if a Claude session ID or ticket reference pair is detected, stash the association

### 4.2 Urgency trigger

If a message scores ≥ `thresholds.critical` (default 80):
1. Send a Slack DM to the user via `slack_send_message` with a one-liner summary
2. Trigger an immediate mini-analyzer run on just that item (write a `.xgh/inbox/.urgent` marker file)

### 4.3 Awaiting-reply detection

The retriever detects reply-waiting signals per platform:

| Platform | Detection method |
|----------|-----------------|
| Slack | User's `slack_id` in message @mentions; DMs containing `?` or request language; squad tag mentions; `@here`/`@channel` in tracked channels |
| GitHub | PR review requests via `gh api notifications`; comments on user's PRs; CI failures on user's PRs; requested-changes reviews |
| Figma | Comment @mentions via `get_metadata` |
| Confluence | @mentions in page content or comments |
| Jira | Ticket assigned to user; mentioned in comments; watcher notifications |

Each detected item is stashed with `awaiting_direction: my_reply` or `awaiting_direction: their_reply` metadata.

---

## 5. Urgency Detection

### 5.1 Scoring model

Derived from real-world analysis of engineering Slack channels (#workgroup-new-web-login, #psd2-internal, #workgroup-account-recovery-improvements).

**Base scores by category:**

| Category | Base Score | Real example |
|----------|-----------|--------------|
| Blocker (critical keywords) | 90 | "release blocker", "blocking our API integration" |
| Deadline pressure (EOD/today) | 80 | "Deadline is EOD tonight — confirmed with core" |
| Scope change (P0/before go-live) | 75 | "p0 that we need to fix before we can go live" |
| Status change (revert/rollback) | 70 | "fallback to login v1 on web in case of 5xx" |
| Decision (launch date shift) | 65 | "move the Web launch by one day to ensure full QA" |
| Environment incident | 60 | "beta version is broken", "restarting pods" |
| Action request (with @-mention) | 50 | "for Monday: @pedro please have a look at this" |
| Cross-team dependency | 45 | "localisation team is under water, won't get copy this week" |
| Risk mitigation | 40 | "minimise risks", "rollback plan" |
| Status update (deploy/merge) | 30 | "merged to main", "deployed to staging" |
| Availability notice | 20 | "partially off next Monday" |

**Multipliers:**

| Signal | Factor |
|--------|--------|
| Contains `@here` or `@channel` | ×1.5 |
| Contains P0/critical/blocker | ×1.4 |
| Posted outside business hours (before 9am or after 6pm) | ×1.3 |
| Contains "before we can go live" or similar | ×1.3 |
| Posted on weekend | ×1.3 |
| Has thread with >10 replies | ×1.2 |
| Contains multiple @-mentions (>2) | ×1.2 |
| Contains Jira/Confluence links | ×1.1 |
| Message from PM/lead role | ×1.1 |

**Composite score:** `urgency_score = min(base_score × product(applicable_multipliers), 100)`

Scores are capped at 100. Any score ≥80 maps to "critical" regardless of how high the raw composite is.

### 5.2 Role-aware relevance multiplier

Applied after composite scoring based on the user's `profile` config:

| Signal matches... | Multiplier | Rationale |
|-------------------|-----------|-----------|
| User's platform (e.g., `ios`) | ×2.0 | Direct responsibility |
| User's squad | ×1.5 | Team's problem |
| `also_monitor` (e.g., `backend`) | ×1.0 | Informational, no boost |
| Other platform (android, web) | ×0.3 | Heavily dampened |
| Other squad | ×0.5 | Lower relevance |

Platform detection uses keyword matching: "iOS", "Swift", "Xcode", "Android", "Kotlin", "web", "React", plus Jira component labels and GitHub repo names.

### 5.3 Aging urgency (awaiting_reply only)

Items of type `awaiting_my_reply` and `awaiting_their_reply` escalate with time:

| Age | Urgency boost | Action |
|-----|--------------|--------|
| < 2 hours | +0 | Logged |
| 2–8 hours | +15 | In digest |
| 8–24 hours | +30 | Highlighted in digest |
| 24–48 hours | +50 | DM reminder |
| 48+ hours | +70 | DM escalation |

Aging boosts are added to the item's base score, then capped at 100 (same as composite scoring).

### 5.4 Urgency floors

Content types `p0` and `p1` have urgency floors that override scoring. A P0 always triggers a DM (floor: 90) regardless of keyword scores. A P1 always surfaces in the digest (floor: 65).

### 5.5 Thresholds

| Score range | Label | Action |
|-------------|-------|--------|
| 0–30 | Low | Log only |
| 31–55 | Medium | Surface in daily digest |
| 56–79 | High | Include in next analyzer run with priority |
| 80+ | Critical | Immediate Slack DM + mini-analyze |

### 5.6 Key heuristic

The single strongest urgency signal is the **co-occurrence** of: a blocker keyword + an explicit @person assignment + a date/time reference in the same message or thread. This pattern had zero false positives across all sampled channels.

### 5.7 Detection patterns

Atomic keyword matching (shorter keywords that compose):

```yaml
atomic_keywords:
  critical: [hotfix, go live, go-live, golive, production issue,
             prod issue, release blocker, P0, p0, rollback, revert]
  deadline: [release date, code freeze, EOD, end of day,
             deadline, ship date, launch date, cutoff]
  scope:    [requirement changed, spec updated, new approach,
             scope change, pivot, change of plans]
  infra:    [5xx, 502, pods, outage, incident, broken in prod]
```

Novel categories discovered from real channel analysis:

```yaml
novel_categories:
  cross_team_dependency:
    pattern: "team name + constraint language"
    examples: ["localisation team is under water", "synced with Compliance"]
  environment_incident:
    pattern: "infra action + real-time narration"
    examples: ["restarting pods", "beta version is broken"]
  risk_mitigation:
    pattern: "fallback planning language"
    examples: ["fallback to v1", "minimise risks", "rollback plan"]
  availability_absence:
    pattern: "capacity signal near deadline"
    examples: ["partially off next Monday", "OOO Thursday"]
  readiness_probe:
    pattern: "launch-readiness check"
    examples: ["any blockers?", "are we good for Monday?"]
  workaround_compromise:
    pattern: "forced decision under pressure"
    examples: ["for p0: let's use our current copy"]
```

---

## 6. Analyzer Loop

**Invocation:** `claude -p "/xgh-analyze" --allowedTools "mcp__cipher__*,Bash,Read,Write,Glob"`
**Frequency:** Every 30 minutes (or immediately on urgent trigger)
**Session cost:** Heavy — full Claude reasoning for extraction + dedup + writing

### 6.1 Workflow

1. **Read inbox** — scan `.xgh/inbox/` for unprocessed files (exclude `.cursors.json` and `processed/`)
2. **Check for urgent marker** — if `.xgh/inbox/.urgent` exists, process those items first
3. **Classify each item** — assign a `content_type` from the config (decision, spec_change, p0, p1, wip, awaiting_my_reply, awaiting_their_reply, informal_request, qa_feedback, known_issue, status_update)
4. **Extract structured memory** — for each item, produce a structured payload matching the Cipher workspace payload schema:
   ```yaml
   type: spec_change
   project: passcode-feature
   summary: "PIN entry now requires biometric fallback after 3 failed attempts"
   source: slack:#ptech-31204-engineering/thread-1710504600
   source_links:
     - jira:PTECH-31204
     - confluence:pages/12345
   participants: ["@lucas", "@pedro"]
   timestamp: 2026-03-15T14:30:00Z
   urgency_score: 45
   ```
5. **Dedup** — search existing Cipher memories for similarity (threshold 0.85). If a near-duplicate exists, update rather than create
6. **TTL management** — check all existing memories for expired TTLs. Mark expired items as `status: decayed` in Qdrant metadata. If a decayed item's topic is re-referenced in new content, reset its TTL
7. **Write to Cipher** — route based on `content_type.promote_to`:
   - `workspace` → write to shared workspace collection (team-visible)
   - `personal` → write to personal knowledge collection
8. **Session tracking** — index any Claude session ID ↔ ticket/project associations found in inbox content
9. **Move processed files** — move stashed files from `.xgh/inbox/` to `.xgh/inbox/processed/`
10. **Generate digest** — append to `.xgh/digests/YYYY-MM-DD.md`

### 6.2 Informal-to-formal promotion

When the analyzer finds a Jira ticket that matches an existing `informal_request` memory (by semantic similarity or explicit ticket ID mention), it links them and upgrades the content type to whatever the ticket represents. The informal request served its purpose — it gave early warning before the ticket existed.

### 6.3 Digest output

Daily human-readable summary at `.xgh/digests/YYYY-MM-DD.md`, accumulated throughout the day. Uses Obsidian-compatible formatting (YAML frontmatter, `[[wikilinks]]`, `#tags`) so the `~/.xgh/` directory works as an Obsidian vault with zero adaptation.

```markdown
---
date: 2026-03-15
type: digest
projects: [passcode-feature]
open_replies: 3
urgency_peak: 82
tags: [digest, daily]
---

# Digest — 2026-03-15

## [[passcode-feature|Passcode Feature]]
- **[SPEC_CHANGE]** PIN entry now requires biometric fallback (14:30) #spec-change
- **[DECISION]** Going with approach B for token storage (11:15) #decision
- **[WIP]** Lucas working on backend endpoint (10:00) #wip

## Awaiting Your Reply (3)
- 🔴 PR review: passcode-service#142 from [[lucas]] (31h) #awaiting-reply
- 🟡 Slack: @pedro question about token expiry in #ptech-eng (6h) #awaiting-reply
- 🟢 Jira: [[PTECH-456]] assigned to you (1h) #awaiting-reply

## Awaiting Their Reply (1)
- 🟡 You asked [[lucas]] about API contract in #ptech-eng (28h) #awaiting-theirs
```

### 6.4 Obsidian-compatible output format

All markdown files generated by the analyzer (digests, inbox stashes, processed items) follow these conventions to enable Obsidian vault usage:

- **YAML frontmatter** on every file — `type`, `date`, `project`, `tags`, `urgency_score`, `content_type`
- **Wikilinks** (`[[target]]`) for cross-references: projects, people, tickets, other digests
- **Tags** (`#tag`) for content type classification — enables Obsidian tag-based filtering
- **Consistent naming** — files named by date + source for natural Obsidian sorting

This is a v1 format constraint (cheap to implement, high payoff) that enables the Obsidian dashboard layer (v1.5) to work with zero migration.

---

## 7. Cipher Workspace Memory Integration

### 7.1 Collection architecture

Cipher's `MultiCollectionVectorManager` manages three independent collections:

| Collection | Env var | Scope | Contents |
|-----------|---------|-------|----------|
| Knowledge | `VECTOR_STORE_COLLECTION_NAME` | Personal | Technical knowledge, code patterns, personal notes |
| Reflection | `REFLECTION_VECTOR_STORE_COLLECTION` | Personal | Reasoning traces, evaluations |
| Workspace | `WORKSPACE_VECTOR_STORE_COLLECTION` | Shared | Decisions, spec changes, project status, WIP, P0/P1 |

### 7.2 Workspace configuration

Enable workspace memory in the Cipher MCP config:

```yaml
# Added to .claude/.mcp.json cipher env vars
USE_WORKSPACE_MEMORY: "true"
CIPHER_WORKSPACE_MODE: "shared"
CIPHER_USER_ID: "pedro"
CIPHER_PROJECT_NAME: "customer-platform"
WORKSPACE_VECTOR_STORE_COLLECTION: "customer-platform-workspace"
```

All team members' Cipher instances with matching `CIPHER_USER_ID` + `CIPHER_PROJECT_NAME` + `CIPHER_WORKSPACE_MODE=shared` share the same workspace collection.

### 7.3 Writing strategy

Since `cipher_workspace_store` is internal-only (not agent-callable), the analyzer writes directly to Qdrant using the workspace payload schema:

```javascript
// Payload structure matching Cipher's workspace schema
{
  text: "PIN entry now requires biometric fallback after 3 failed attempts",
  teamMember: "pedro",
  domain: "iOS",
  project: "passcode-feature",
  progressStatus: "spec_change",
  bugs: [],
  workContext: {
    repository: "acme-corp/acme-ios",
    branch: "feature/passcode-biometric",
    jiraTicket: "PTECH-31204"
  },
  // xgh-specific extensions
  xgh_content_type: "spec_change",
  xgh_urgency_score: 45,
  xgh_ttl: null,
  xgh_source: "slack:#ptech-31204-engineering/thread-1710504600",
  xgh_timestamp: "2026-03-15T14:30:00Z",
  xgh_schema_version: 1
}
```

Reading uses `cipher_workspace_search` (agent-accessible), which works regardless of how data entered the collection.

### 7.4 Embedding generation

The write helper must generate embedding vectors using the **same model and dimensions** as Cipher's internal pipeline. It reads the embedding config from `~/.cipher/cipher.yml` (model name, endpoint, dimensions) and calls the embedding API directly. This ensures that vectors written by the analyzer are searchable via `cipher_workspace_search` with correct cosine similarity.

```javascript
// workspace-write.js reads Cipher's embedding config
const cipherConfig = yaml.parse(fs.readFileSync('~/.cipher/cipher.yml'));
const { model, endpoint, dimensions } = cipherConfig.embedding;
// Calls the same vllm-mlx endpoint Cipher uses
const vector = await embed(text, { model, endpoint, dimensions });
await qdrant.upsert(collection, { id, vector, payload });
```

### 7.5 Schema risk mitigation

The write function is centralized in a single helper (`~/.xgh/lib/workspace-write.js`). If Cipher's workspace payload schema changes, only this file needs updating. The helper validates payloads against the known schema before writing.

---

## 8. Project Onboarding: `/xgh-track`

Interactive skill for adding new projects to the ingestion system.

### 8.1 Flow

```
$ /xgh-track

> Project name: Passcode Feature
> Slack channels (comma-separated): #ptech-31204-general, #ptech-31204-engineering
  ✓ Both channels found and accessible

> Jira project key (optional): PTECH-31204
  ✓ Found: "Passcode Feature" — 23 open issues

> RFC/spec links (optional, one per line):
  https://confluence.internal/spaces/PTECH/pages/rfc-passcode-v2
  ✓ Fetched and indexed to Cipher: "RFC: Passcode V2 Architecture"

> Figma links (optional):
  https://figma.com/design/abc123/passcode-screens
  ✓ Stored reference

> GitHub repos (optional):
  acme-corp/acme-ios
  ✓ Found. Index codebase now? [y/n]: y
  → Running /xgh-index-repo quick mode...

> Starting initial scan of Slack channels...
  Scanned 200 messages across 2 channels
  Found 12 Jira links, 3 Confluence pages, 2 GitHub PRs
  Auto-enriched project config with discovered references

✓ Project "passcode-feature" added to ~/.xgh/ingest.yaml
  Next retriever run will include this project.
```

### 8.2 Config output

```yaml
# Appended to projects: in ingest.yaml
projects:
  passcode-feature:
    status: active
    slack:
      - "#ptech-31204-general"
      - "#ptech-31204-engineering"
    jira: PTECH-31204
    confluence:
      - /spaces/PTECH/pages/rfc-passcode-v2
    github:
      - acme-corp/acme-ios
    figma:
      - https://figma.com/design/abc123/passcode-screens
    rfcs:
      - https://confluence.internal/spaces/PTECH/pages/rfc-passcode-v2
    index:
      last_full: 2026-03-15T09:00:00Z
      schedule: weekly
      watch_paths:
        - "AppPackages/Sources/**"
        - "Package.swift"
    last_scan: null
```

### 8.3 Initial backfill

On project creation, the skill reads recent history from the listed Slack channels (up to 200 messages per channel) so the system doesn't start from zero. Any discovered links are followed 1-hop and stashed to the inbox for the next analyzer run.

---

## 9. Codebase Indexing: `/xgh-index-repo`

Reusable skill that systematically scans a repository and stores architectural knowledge in Cipher memory. Based on the methodology proven during prior codebase indexing.

### 9.1 What it extracts

| Pass | What it extracts | Example |
|------|-----------------|---------|
| Structure | Module/package organization, directory conventions | SPM layout, feature module boundaries |
| Architecture | Patterns, coordination, DI | Coordinator pattern, `@Dependency` injection |
| Navigation | User journeys, screen flows, entry points | MainCoordinator → 8 journey flows |
| Feature flags | Declaration patterns, dependency chains, gating | `TRFourEnabled` gates Junior, SavingsPatron |
| Naming conventions | Terminology, naming rules per domain | passcode=umbrella, password=alphanumeric |
| Protocols/interfaces | Key abstractions, conformance hierarchies | `CardFeatureFlagsNG`, `CashFeatureFlags` |
| Entry points | Where things start, triggers | `AppCoordinator` → auth → home |

### 9.2 Modes

**Quick mode** (~5 min):
- Directory structure scan
- Key file identification (manifests, configs, entry points)
- Naming convention sampling
- Stores ~10–15 memories

**Full mode** (~20–30 min):
- Everything in quick, plus:
- Multi-agent parallel exploration (dispatches subagents per module)
- User journey tracing
- Feature flag dependency graph
- Protocol/interface hierarchy mapping
- Cross-module dependency analysis
- Stores ~30–50 structured memories

### 9.3 Language awareness

The skill detects the stack and adjusts extraction:

| Stack | Focus areas |
|-------|-------------|
| Swift/iOS | Coordinators, SPM modules, feature flags, UIKit/SwiftUI patterns |
| Kotlin/Android | Activities, Fragments, Dagger/Hilt modules, Compose patterns |
| TypeScript/React | Component trees, hooks, state management, route structure |
| Backend (any) | API routes, service layers, DB schemas, middleware chains |

### 9.4 Periodic re-indexing

Configured per project in `ingest.yaml`:

```yaml
index:
  last_full: 2026-03-15T08:40:00Z
  schedule: weekly              # full re-index
  watch_paths:                  # trigger quick re-index on changes
    - "AppPackages/Sources/Core/**"
    - "Package.swift"
    - "**/FeatureFlags*"
```

When the retriever detects a merged PR touching watched paths, it flags the analyzer to run a targeted re-index on just those modules. The codebase knowledge stays fresh.

---

## 10. Health Check: `/xgh-doctor`

Validates the full pipeline — config, connectivity, pipeline status, workspace.

### 10.1 Output

```
$ claude -p "/xgh-doctor"

xgh Ingest Health Check
═══════════════════════

Config
  ✓ ~/.xgh/ingest.yaml exists and parses
  ✓ Profile section complete (iOS engineer, Customer Platform)
  ✓ 2 active projects configured

Connectivity
  ✓ Slack MCP responding
  ✓ Channel #ptech-31204-general accessible
  ✓ Channel #ptech-31204-engineering accessible
  ✗ Channel #payments-revamp not found — check name
  ✓ Jira MCP responding — PTECH-31204 exists
  ✓ Qdrant running at localhost:6333
  ✓ Cipher MCP responding

Pipeline
  ✓ Retriever cron installed (*/5 * * * *)
  ✓ Analyzer cron installed (*/30 * * * *)
  ✓ Inbox directory exists (.xgh/inbox/)
  ✓ Last retriever run: 3 min ago (healthy)
  ✗ Last analyzer run: 47 min ago (overdue — threshold: 45 min)

Workspace
  ✓ Workspace collection "customer-platform-workspace" exists
  ✓ 142 vectors stored
  ✓ Last write: 28 min ago

Codebase Index
  ✓ acme-ios: last indexed 2 days ago (schedule: weekly — OK)
  ✗ passcode-service: never indexed — run /xgh-index-repo
```

### 10.2 Checks performed

1. **Config validation** — YAML parses, required fields present, content types valid
2. **Slack channels** — each listed channel is accessible
3. **Jira projects** — each listed key resolves
4. **Qdrant** — host reachable, collections exist
5. **Cipher MCP** — server responds to a test search
6. **Cron jobs** — installed and running on schedule
7. **Pipeline freshness** — last run timestamps within expected thresholds
8. **Workspace** — collection exists, has data, recent writes
9. **Codebase index** — last index date vs configured schedule

---

## 11. Session Tracking

### 11.1 Problem

Finding the right Claude Code session for a given ticket is a struggle. Sessions accumulate unnamed and searching through them is manual.

### 11.2 Solution

The analyzer indexes session-to-ticket associations in the workspace collection:

```yaml
type: session_index
session_id: "abc123def"
session_date: 2026-03-15
tickets: [PTECH-31204, PTECH-456]
projects: [passcode-feature]
summary: "Implemented biometric fallback for PIN entry"
```

**Detection sources:**
- Claude sessions that use `/xgh-implement` with a ticket reference
- Slack messages referencing a session ID or mentioning work on a ticket
- `cipher_memory_search` queries within sessions that reference ticket IDs

**Querying:** "Which session was working on PTECH-31204?" → `cipher_workspace_search` returns the session index entry.

---

## 12. Content Type Lifecycle

### 12.1 TTL and decay

Each content type has a time-to-live. When TTL expires, the memory gets `xgh_status: decayed` in its Qdrant metadata — it stops appearing in normal searches but isn't deleted.

**Re-reference reset:** If a decayed item's topic is mentioned again in new content, the analyzer resets its TTL. A casual "we should add caching" lives for 7 days then fades, but if someone mentions caching again 5 days later, the clock resets.

### 12.2 Type summary

| Type | TTL | Scope | Urgency model |
|------|-----|-------|---------------|
| `decision` | permanent | workspace | static scoring |
| `spec_change` | permanent | workspace | static scoring |
| `p0` | permanent | workspace | floor: 90 (always DM) |
| `p1` | permanent | workspace | floor: 65 (always digest) |
| `wip` | permanent | workspace | static scoring |
| `awaiting_my_reply` | 7 days | personal | aging escalation |
| `awaiting_their_reply` | 14 days | personal | aging escalation |
| `informal_request` | 7 days | personal | static scoring |
| `qa_feedback` | 14 days | personal | static scoring |
| `known_issue` | 30 days | workspace | static scoring |
| `status_update` | 3 days | workspace | static scoring |

### 12.3 Auto-promotion

- `wip` → `p0` or `p1`: if a WIP item is mentioned alongside blocker language, the analyzer upgrades it
- `informal_request` → ticket type: when a Jira ticket matching the request is found, the analyzer links and upgrades
- `awaiting_my_reply` → `completed`: when the analyzer detects a response was given (follow-up message from the user in the same thread)

---

## 13. File and Directory Structure

```
~/.xgh/
├── ingest.yaml                  # Central config (Section 3)
├── inbox/                       # Raw retriever stash
│   ├── .cursors.json            # High-water marks per channel
│   ├── .enrichments.json        # Discovered refs queued for config merge
│   ├── .urgent                  # Urgent trigger marker (transient)
│   ├── processed/               # Moved here after analysis (purged after 7 days)
│   └── *.md                     # Raw stashed content
├── digests/                     # Daily human-readable summaries
│   └── YYYY-MM-DD.md
├── logs/                        # Cron output
│   ├── retriever.log
│   └── analyzer.log
├── calibration/                 # Dedup calibration reports
│   └── YYYY-MM-DD.md
└── lib/                         # Shared helpers
    └── workspace-write.js       # Centralized Qdrant write function
```

---

## 14. Scheduling

On macOS, uses `launchd` plist files for reliable execution across sleep/wake cycles. On Linux, uses `cron`. The schedule intervals below are illustrative:

**Intervals:** Retriever every 5 min, Analyzer every 30 min.

**macOS launchd** (installed to `~/Library/LaunchAgents/`):

```xml
<!-- com.xgh.retriever.plist -->
<plist version="1.0">
<dict>
  <key>Label</key><string>com.xgh.retriever</string>
  <key>ProgramArguments</key>
  <array>
    <string>claude</string>
    <string>-p</string>
    <string>/xgh-retrieve</string>
    <string>--allowedTools</string>
    <string>mcp__claude_ai_Slack__*,mcp__claude_ai_Atlassian__*,Bash,Read,Write,Glob</string>
  </array>
  <key>StartInterval</key><integer>300</integer>
  <key>StandardOutPath</key><string>~/.xgh/logs/retriever.log</string>
  <key>StandardErrorPath</key><string>~/.xgh/logs/retriever.log</string>
</dict>
</plist>
```

**Linux cron** (equivalent):

```bash
*/5 * * * * claude -p "/xgh-retrieve" --allowedTools "mcp__claude_ai_Slack__*,mcp__claude_ai_Atlassian__*,Bash,Read,Write,Glob" >> ~/.xgh/logs/retriever.log 2>&1
*/30 * * * * claude -p "/xgh-analyze" --allowedTools "mcp__cipher__*,Bash,Read,Write,Glob" >> ~/.xgh/logs/analyzer.log 2>&1
```

The doctor function monitors both — if the analyzer hasn't run in >45 min or the retriever in >10 min, it flags as overdue.

---

## 15. Future Extensions

Ideas from multi-perspective brainstorm session (PO, Engineer, Designer). Detailed proposals in `docs/plans/2026-03-15-*.md`.

### 15.0 Obsidian Dashboard (v1.5 — design for now, build after core loops proven)

The `~/.xgh/` directory is already shaped like an Obsidian vault — digests, inbox files, and project configs are all markdown with YAML frontmatter. Obsidian adds a GUI layer with zero new infrastructure:

| Capability | How |
|-----------|-----|
| **Digest browser** | Open `~/.xgh/` as vault → digests are immediately browsable with frontmatter metadata |
| **Live urgency dashboard** | Obsidian Dataview queries over frontmatter: `TABLE urgency_peak, open_replies FROM "digests" SORT date DESC` |
| **Awaiting-reply board** | Dataview task board filtering on `#awaiting-reply` and `#awaiting-theirs` tags |
| **Project graph** | Obsidian's graph view visualizes `[[wikilinks]]` between projects, people, tickets, and sessions |
| **Manual annotation** | Add personal notes to any ingested item — the analyzer preserves user-added content on re-processing |
| **Mobile access** | Obsidian Sync gives digest access on phone (review on commute) |
| **Search** | Full-text search across all digests, inbox history, and project configs |

**v1 constraint** (already in spec): all analyzer output uses Obsidian-compatible frontmatter, wikilinks, and tags (§6.4). This means Obsidian "just works" when pointed at the directory — the dashboard templates and Dataview queries are the only v1.5 deliverable.

### 15.1 High priority (v2 candidates)

| Extension | Perspective | Description |
|-----------|------------|-------------|
| **Commitment Drift Detector** | PO | Snapshot ticket state at sprint start, alert when what's being built diverges from what was agreed |
| **Meeting-to-Memory Bridge** | All three | Gmail/Calendar integration for extracting decisions and action items from meetings (requires corporate approval) |
| **Spec-to-Ship Traceability Chain** | PO | Directed graph from Confluence spec → Jira epic → GitHub PR → merge; compliance-ready audit reports |
| **Pipeline Archaeologist** | Engineer | Reconstruct causal chain behind CI failures from logs + merges + Slack + Jira |
| **Design Rationale Weaver** | Designer | Capture WHY behind design choices by correlating Figma links in Slack + meeting notes + Confluence |

### 15.2 Medium priority

| Extension | Perspective | Description |
|-----------|------------|-------------|
| **The Debt Collector** | Engineer | Track informal tech debt signals; auto-draft Jira tickets when the same area gets 5+ complaints in 30 days |
| **Blast Radius Radar** | Engineer | Cross-repo dependency graph; alert when upstream changes may break your repos |
| **Figma Comment Materializer** | Designer | Capture micro-decisions from resolved Figma comment threads before they vanish |
| **Design Drift Sentinel** | Designer | Monitor Figma design tokens, diff against code tokens across iOS/Android/Web |
| **Stakeholder Sentiment Radar** | PO | Track engagement frequency and detect silence from key approvers |

### 15.3 Lower priority

| Extension | Perspective | Description |
|-----------|------------|-------------|
| **Cross-Project Dependency Graph** | PO | Monitor upstream teams' Jira boards; alert when their reprioritization threatens your deadlines |
| **Session Replay Context** | Engineer | Capture not just what a session did, but WHY each architectural choice was made |
| **Design Review Outcome Tracker** | Designer | Formal approval chain from calendar events + Figma timestamps |
| **Accessibility & Regulatory Pattern Library** | Designer | Codified BaFin/PSD2/WCAG patterns validated against implementations |

---

## 16. Prerequisites

Before implementation begins, these must be validated:

1. **Claude CLI headless mode** — Verify that `claude -p "/skill-name"` works from a non-interactive shell (cron/launchd) with the current auth setup. Test: `claude -p "echo hello" --allowedTools Bash` from a launchd plist. If it requires TTY or session tokens that expire, the entire architecture needs an alternative invocation method.

## 17. Resolved Design Decisions

These were raised during review and resolved in the spec:

| Question | Resolution | Section |
|----------|-----------|---------|
| Cron vs launchd on macOS | Use launchd; cron syntax is illustrative only | §2 |
| Config concurrent access | Only the analyzer writes `ingest.yaml`; retriever queues enrichments to `.enrichments.json` | §2, §4.1 |
| Embedding for direct Qdrant writes | Write helper reads Cipher's `cipher.yml` config and calls the same embedding endpoint | §7.4 |
| Urgency score can exceed 100 | Capped at 100 via `min()` | §5.1 |
| Obsidian support timing | v1 outputs Obsidian-compatible format (frontmatter, wikilinks, tags); dashboard is v1.5 | §6.4, §15.0 |
| Cost management mechanism | `--max-turns` + `timeout` per session; daily soft cap via usage tracking; no native `--max-tokens` in Claude CLI | §3 budget, §18 |
| All open questions | Resolved — each has configurable parameters in `ingest.yaml` | §18 |

## 18. Resolved Open Questions

All formerly open questions are now resolved with configurable parameters:

| # | Question | Resolution | Config reference |
|---|----------|-----------|-----------------|
| 1 | Qdrant schema versioning | All payloads include `xgh_schema_version: 1` | §7.3 |
| 2 | Cost management | Claude CLI uses `--max-turns` + `timeout` per session (no native `--max-tokens`). Daily soft cap tracked via `usage.csv`, DM at 80%, auto-pause on cap. All configurable. | `budget.*` in §3 |
| 3 | Log rotation | Configurable: max size, rotation period, retention days. Implementation uses `newsyslog` on macOS. | `retention.logs`, `retention.log_retention` in §3 |
| 4 | Inbox cleanup | Analyzer purges `processed/` files older than configurable retention period (default 7d). | `retention.inbox_processed` in §3 |
| 5 | MCP rate limiting | Retriever implements exponential backoff on 429s. Configurable: backoff toggle, max retries per channel per cycle. | `retriever.backoff_on_rate_limit`, `retriever.max_retries` in §3 |
| 6 | Dedup calibration | Default threshold 0.85, configurable. Automated calibration via `/xgh-calibrate` skill. | `analyzer.dedup_threshold` in §3, §19 |

---

## 19. Dedup Calibration: `/xgh-calibrate`

Automated skill for tuning the dedup similarity threshold against the user's actual data and embedding model. Supports both interactive and headless modes.

### 19.1 Problem

The dedup threshold (cosine similarity above which two memories are considered duplicates) is model-dependent. A threshold of 0.85 with one embedding model might be too aggressive (merging distinct items) or too loose (keeping near-duplicates) with another. The only way to know is to test against real data.

### 19.2 Modes

**Interactive mode** (`/xgh-calibrate`):
1. Pull N sample pairs from the user's Cipher memory (configurable, default 50)
2. For each pair, show both texts side by side with their similarity score
3. Ask: "Are these duplicates? [y/n/skip]"
4. After all pairs, compute optimal threshold that maximizes agreement with user judgments
5. Offer to update `analyzer.dedup_threshold` in `ingest.yaml`
6. Store calibration results for future reference

**Headless mode** (`/xgh-calibrate --auto`):
1. Pull N sample pairs from Cipher memory
2. Use a Claude session to judge each pair (is this a semantic duplicate?)
3. Compute optimal threshold from AI judgments
4. Write a calibration report to `.xgh/calibration/YYYY-MM-DD.md`
5. Update config if confidence > 90%, otherwise flag for human review

**Comparison mode** (`/xgh-calibrate --compare`):
1. Run headless calibration
2. Then run interactive on the same pairs
3. Show agreement rate between AI and human judgments
4. Helps validate whether headless mode is trustworthy for future auto-calibrations

### 19.3 Config

```yaml
calibration:
  sample_size: 50                # pairs to evaluate per calibration run
  auto_update: false             # if true, headless mode updates config without confirmation
  auto_confidence_threshold: 0.9 # only auto-update if AI judgment confidence exceeds this
  schedule: monthly              # suggest recalibration on this interval
  last_run: null                 # set by the skill after each run
  last_threshold: null           # the threshold that came out of the last calibration
```

### 19.4 Output

Calibration report at `.xgh/calibration/YYYY-MM-DD.md`:

```markdown
---
date: 2026-03-15
type: calibration
mode: interactive
sample_size: 50
---

# Dedup Calibration Report

## Results
- Pairs evaluated: 50
- User said "duplicate": 18
- User said "not duplicate": 29
- Skipped: 3

## Threshold Analysis
| Threshold | Precision | Recall | F1 |
|-----------|-----------|--------|-----|
| 0.80 | 0.72 | 0.94 | 0.82 |
| 0.85 | 0.89 | 0.83 | 0.86 |
| 0.88 | 0.94 | 0.72 | 0.82 |
| 0.90 | 1.00 | 0.61 | 0.76 |

## Recommendation
Optimal threshold: **0.85** (F1: 0.86)
Previous threshold: 0.85 (no change needed)
```
