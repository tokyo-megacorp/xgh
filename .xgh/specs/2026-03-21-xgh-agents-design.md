# xgh Agents — Design Spec

> **Goal:** Expand xgh's agent roster from 2 to 8, following lossless-claude's proven patterns: narrow scope, YAML frontmatter, model selection, restricted tools, color tags.

## Design Principles (from lossless-claude)

| Principle | Application |
|-----------|-------------|
| **Narrow scope** | Each agent does ONE thing well — investigation, review, curation, etc. |
| **Frontmatter contract** | YAML frontmatter: `name`, `description` (with examples), `model`, `color`, `tools` |
| **Model selection** | Concrete frontmatter models by capability tier: `haiku` for lightweight tasks, `sonnet` for most collaboration/review work, `opus` for the deepest investigations. `inherit` was considered but rejected. |
| **Minimal tools** | Only grant tools the agent actually needs |
| **Dispatch examples** | `<example>` blocks in description teach Claude when to use each agent |
| **Output format** | Standardized sections with headers |
| **Read-only default** | Agents diagnose/report; they don't modify unless explicitly designed to |

---

## Existing Agents (upgrade to frontmatter format)

### 1. `code-reviewer` (exists)

**Change:** Add YAML frontmatter (`model: sonnet`, `color: yellow`, `tools: [Read, Grep, Glob, Bash]`) with `<example>` dispatch blocks. Clean up stale references to `config/workflows/` (directory doesn't exist). Scope clarification: handles **in-session file-level review** within collaboration workflows — does NOT touch GitHub PR artifacts.

### 2. `collaboration-dispatcher` (exists)

**Change:** Add YAML frontmatter (`model: sonnet`, `color: green`, `tools: [Read, Grep, Glob]`) with `<example>` dispatch blocks. Clean up stale references to `config/agents.yaml` agent types that don't exist yet.

---

## New Agents

### 3. `pipeline-doctor`

| Field | Value |
|-------|-------|
| **model** | `sonnet` |
| **color** | `orange` |
| **tools** | `[Read, Grep, Glob, Bash]` |
| **scope** | Deep investigation of xgh **retrieval/scheduling/inbox/trigger pipeline** (beyond basic `/xgh-doctor`) |

**When to dispatch:** Doctor skill reports failures but cause isn't obvious. Provider fetches silently failing. Scheduler not running. Inbox empty despite active sources.

**Scope boundary:** Strictly the retrieval pipeline: providers, scheduler, inbox, triggers, and their interconnections. For code-level bugs or non-pipeline issues, use `investigation-lead` instead.

**Investigation areas:** Provider fetch logs, scheduler state, inbox integrity, trigger evaluation, memory connectivity (lcm_doctor/lcm_stats), hook registration.

**Output:** Root cause + evidence + fix steps + prevention advice.

---

### 4. `context-curator`

| Field | Value |
|-------|-------|
| **model** | `haiku` |
| **color** | `blue` |
| **tools** | `[Read, Grep, Glob]` |
| **scope** | Reviews context tree for freshness, completeness, and relevance |

**When to dispatch:** After significant project changes. When briefings surface stale context. Periodic maintenance. When onboarding new team members.

**Responsibilities:**
- Walk `.xgh/context-tree/` and score each entry for freshness (git blame age, reference count)
- Identify stale or outdated entries
- Flag missing coverage areas (e.g., new components without architecture docs)
- Suggest promotions from lossless-claude memory to permanent context tree entries
- Check manifest consistency

**Output:** Curation report with stale entries, gaps, and recommended actions.

---

### 5. `investigation-lead`

| Field | Value |
|-------|-------|
| **model** | `opus` |
| **color** | `red` |
| **tools** | `[Read, Grep, Glob, Bash]` |
| **scope** | Systematic debugging of **code-level bugs and non-pipeline issues** |

**When to dispatch:** User reports a bug in xgh code. Test failures with non-obvious cause. Unexpected behavior in skills, hooks, or agents (not the retrieval pipeline — use `pipeline-doctor` for that).

**Scope boundary:** Code, tests, skills, hooks, agent logic. NOT retrieval/scheduling/inbox/triggers (that's pipeline-doctor's domain).

**Process:**
1. Gather evidence (logs, recent changes, related code)
2. Form hypotheses ranked by likelihood
3. Test each hypothesis systematically
4. Isolate the root cause
5. Propose fix with confidence level

**Output:** Investigation report with hypotheses tested, root cause, evidence, and proposed fix.

---

### 6. `pr-reviewer`

| Field | Value |
|-------|-------|
| **model** | `sonnet` |
| **color** | `green` |
| **tools** | `[Read, Grep, Glob, Bash]` |
| **scope** | Full PR review with cross-referencing (Jira, Slack, conventions) |

**When to dispatch:** PR ready for review. User asks for review of a specific PR. Before merge on significant changes.

**Scope boundary:** Handles **GitHub PR artifacts exclusively** — PR diff, metadata, cross-references. For in-session file-level review within workflows, use `code-reviewer` instead.

**Responsibilities:**
- Fetch PR diff via `gh pr diff`
- Cross-reference with Jira ticket (if linked)
- Check context tree conventions
- Search lossless-claude for related past decisions
- Verify test coverage for changed code
- Check for breaking changes

**Output:** Structured review with: summary, cross-references found, issues by severity, verdict.

---

### 7. `retrieval-auditor`

| Field | Value |
|-------|-------|
| **model** | `haiku` |
| **color** | `blue` |
| **tools** | `[Read, Grep, Glob, Bash]` |
| **scope** | Monitors provider health and retrieval quality |

**When to dispatch:** After retrieval runs with failures. Periodically to assess coverage quality. When adding new providers. When inbox items seem low-quality or duplicated.

**Checks:**
- Provider fetch logs: success/failure rates, error patterns
- Inbox quality: dedup rates, urgency score distribution, staleness
- Coverage gaps: tracked projects without recent items
- Provider config validity: credentials, endpoints, query parameters
- Retrieval timing: how long each provider takes

**Output:** Audit report with provider health matrix, quality metrics, and recommendations.

---

### 8. `onboarding-guide`

| Field | Value |
|-------|-------|
| **model** | `sonnet` |
| **color** | `purple` |
| **tools** | `[Read, Grep, Glob]` |
| **scope** | Helps new developers or agents get oriented in the codebase and xgh system |

**When to dispatch:** New team member's first session. Agent needs codebase context. User asks "how does X work" about xgh internals.

**Responsibilities:**
- Surface architecture decisions from context tree
- Explain provider/skill/hook relationships
- Highlight active conventions and patterns
- Identify gotchas and common pitfalls
- Tailor depth to the person's background (senior dev vs junior)

**Output:** Personalized orientation guide with architecture overview, key conventions, and "watch out for" section.

---

## Agent Roster Summary

| # | Agent | Model | Color | Tools | Status |
|---|-------|-------|-------|-------|--------|
| 1 | `code-reviewer` | sonnet | yellow | R,Grep,Glob,Bash | Upgrade frontmatter + cleanup |
| 2 | `collaboration-dispatcher` | sonnet | green | R,Grep,Glob | Upgrade frontmatter + cleanup |
| 3 | `pipeline-doctor` | sonnet | orange | R,Grep,Glob,Bash | **New** |
| 4 | `context-curator` | haiku | blue | R,Grep,Glob,Write,Edit | **New** |
| 5 | `investigation-lead` | opus | red | R,Grep,Glob,Bash,Agent | **New** |
| 6 | `pr-reviewer` | sonnet | green | R,Grep,Glob,Bash | **New** |
| 7 | `retrieval-auditor` | haiku | blue | R,Grep,Glob | **New** |
| 8 | `onboarding-guide` | sonnet | purple | R,Grep,Glob | **New** |

**Naming:** Follows lossless-claude pattern — kebab-case, descriptive nouns (not verbs).

**Models are assigned concretely by capability tier** — `sonnet/haiku/opus`. Sonnet handles coordination, review, and onboarding work; Haiku covers lightweight curation and auditing; Opus is reserved for deep investigations that need the most reasoning headroom.

**Each agent MUST include `<example>` dispatch blocks** in the YAML `description` field — this is how Claude Code learns when to invoke each agent automatically.

**Scope boundaries are explicit** — pipeline-doctor vs investigation-lead, code-reviewer vs pr-reviewer — to prevent ambiguous dispatch.

---

*Spec date: 2026-03-21*
