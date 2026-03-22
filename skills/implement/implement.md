---
name: xgh:implement
description: "This skill should be used when the user runs /xgh-implement or asks to implement a ticket, 'implement this Jira ticket', 'build this feature', 'start on this task'. Full-context ticket implementation — gathers context from Jira, Slack, Figma, and lossless-claude memory, then drives a complete implementation from ticket to PR."
---

## Preamble — Execution mode

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('implement')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **implement** in background (returns summary when done) or interactive? [b/i, default: i]"
- If "b": "Check in with a quick question before starting, or fire-and-forget? [c/f, default: c]"

**Step P3 — Write preference:**
```bash
python3 -c "
import json, os, sys
mode, autonomy = sys.argv[1], sys.argv[2]
path = os.path.expanduser('~/.xgh/prefs.json')
os.makedirs(os.path.dirname(path), exist_ok=True)
try: p = json.load(open(path))
except: p = {}
p.setdefault('skill_mode', {})
entry = {'mode': mode} if mode == 'interactive' else {'mode': mode, 'autonomy': autonomy}
p['skill_mode']['implement'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` → use background mode
- contains `--interactive` or `--fg` → use interactive mode
- contains `--checkin` → use check-in autonomy
- contains `--auto` → use fire-and-forget autonomy
- contains `--reset` → run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('implement',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** → proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context: user's request verbatim, current branch (`git branch --show-current`), recent log (`git log --oneline -5`), any relevant file paths mentioned.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply: "Implementation running in background — I'll post findings when done."
5. When agent completes: post a ≤5-bullet summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions).
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "Implementation running in background — I'll post findings when done."
4. When agent completes: post a ≤5-bullet summary.

---

# xgh:implement — Full-Context Ticket Implementation

The most comprehensive workflow skill. Takes a ticket from any task manager, gathers ALL available context (ticket details, Slack discussions, Figma designs, xgh memory, codebase patterns), interviews the user for missing context using Superpowers brainstorming, proposes a design with trade-offs, generates a detailed TDD implementation plan, and executes it with subagent-driven development.

## Trigger

```
/xgh implement <ticket-id>
/xgh implement PROJ-1234
/xgh implement
```

If no ticket ID is provided:
- If task manager MCP is available: search for recently assigned tickets and offer selection
- If not: ask user to describe the task or paste ticket details

---

## MCP Auto-Detection

Before starting, auto-detect which MCP servers are available. The skill adapts based on what is configured — no hard dependencies.

**MCP detection:** Run the MCP Auto-Detection Protocol from the `xgh:mcp-setup` skill.
Available integrations are discovered automatically on first invocation.

**Graceful degradation rules (implement-specific):**
- No task manager MCP → Ask user to paste ticket details (title, description, acceptance criteria). Skip ticket updates.
- No Slack MCP → Skip discussion search. Ask user about team decisions verbally.
- No Figma MCP → Skip design extraction. Ask user to describe UI requirements or confirm no UI changes.
- No lossless-claude MCP → Skip memory search. Rely on codebase scanning only. Save plan to docs/ only.
- No MCPs at all → Still works. User provides all context manually. Full Superpowers methodology applies.

---

## Phase 1: Ticket Deep Dive

Extract comprehensive information from the ticket.

### Step 1.1: Fetch Ticket Details (if Atlassian MCP available)

Use `mcp__claude_ai_Atlassian__getJiraIssue` with the ticket ID to fetch:
- **Title and description** — the core requirement
- **Acceptance criteria** — what "done" looks like
- **Status, priority, assignee** — current state
- **Sprint and epic** — broader context
- **Comments** — discussion, clarifications, decisions
- **Attachments** — screenshots, design links, documents
- **Labels and components** — categorization
- **Story points / estimate** — expected effort

### Step 1.2: Traverse Linked Tickets (if Atlassian MCP available)

Use `mcp__claude_ai_Atlassian__getJiraIssueRemoteIssueLinks` and follow links:

**Link types to check:**
- **Blocked by** — must be resolved first (hard dependency)
- **Blocks** — other work waiting on this (priority signal)
- **Related to** — similar work, shared context
- **Is part of / Epic** — parent requirements and constraints
- **Duplicates** — avoid duplicate work

For each linked ticket, fetch summary and status. Flag blockers:
```
Linked tickets:
  ✓ PROJ-1230 "Add Redis client" — Done (dependency satisfied)
  ⚠ PROJ-1236 "Update API schema" — In Progress (may affect this work)
  ℹ PROJ-1210 "Rate limiting design doc" — Done (context reference)

  ⚠ Warning: PROJ-1236 is in progress and may affect the API schema
  this ticket depends on. Consider waiting or coordinating.
```

### Step 1.3: Extract Structured Requirements

Parse ticket description and acceptance criteria into testable assertions:

```
Requirements extracted from PROJ-1234:

User Stories → Testable Assertions:
  1. "As a user, I can see rate limit headers" →
     → Response includes X-RateLimit-Limit header
     → Response includes X-RateLimit-Remaining header
     → Response includes X-RateLimit-Reset header

  2. "As a user, I get 429 when rate limited" →
     → 101st request within 1 minute returns 429
     → 429 response includes Retry-After header
     → Retry-After value matches reset time

Acceptance Criteria → Verification Checklist:
  [x] AC1: 100 requests per minute per user
  [x] AC2: 429 response with Retry-After header
  [x] AC3: Rate limit headers on every response
  [ ] AC4: Admin override capability (not clear — will ask)

Definition of Done → Completion Gate:
  - All tests pass
  - API documentation updated
  - Monitoring dashboard updated
```

---

## Phase 2: Cross-Platform Context Gathering

Search ALL available MCPs for related context. Run searches in parallel.

### Step 2.1: Slack Discussions (if Slack MCP available)

Use `mcp__claude_ai_Slack__slack_search_public` to search for:
- Ticket ID mentions (e.g., "PROJ-1234")
- Feature name mentions (e.g., "rate limiting")
- Design discussions about the feature
- Recent deploy/incident context

For each relevant thread found, use `mcp__claude_ai_Slack__slack_read_thread` to get full context.

Extract:
- Decisions made in discussion ("Bob said use Redis")
- Requirements clarified ("PM confirmed: all public endpoints")
- Concerns raised ("Alice worried about Redis latency")
- Related links shared (docs, PRs, designs)

### Step 2.2: Figma Designs (if Figma MCP available)

Check if the ticket has linked Figma designs:
- Look for Figma URLs in ticket attachments and description
- Search Figma by feature name

If designs found, use `mcp__claude_ai_Figma__get_design_context` and `mcp__claude_ai_Figma__get_screenshot` to extract:
- UI components needed
- States and interactions
- Design tokens
- FigJam notes and acceptance criteria

Consider delegating to `xgh:design` if the ticket is UI-heavy.

### Step 2.3: xgh Memory (if lossless-claude MCP available)

Use `lcm_search(query)` to search for:
- Related past work (e.g., "rate limiting", "middleware", "API")
- Team conventions for the affected area
- Architecture decisions that constrain the implementation
- Past investigations or bugs in related code
- Similar features implemented before

Search queries:
- Ticket title and key terms
- Affected module/component names
- Technical domain (e.g., "rate limiting", "authentication", "caching")
- File paths mentioned in ticket

After implementing, extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store.

### Step 2.4: Codebase Analysis (always)

Search the codebase to understand:
- Related files and modules
- Existing patterns to follow (middleware patterns, test patterns, etc.)
- Integration points (where does the new code connect?)
- Dependencies and imports
- Existing test infrastructure

```
Codebase analysis for "rate limiting":

  Related files:
    src/middleware/auth.ts          — existing middleware pattern
    src/middleware/cors.ts          — existing middleware pattern
    src/config/limits.ts           — existing config pattern
    tests/middleware/auth.test.ts  — existing test pattern

  Integration points:
    src/app.ts:23                  — middleware registration
    src/config/index.ts            — config loading

  Patterns to follow:
    - Middleware: export function, register in app.ts
    - Config: YAML + env var override
    - Tests: Jest + supertest, describe/it pattern
```

---

## Phase 3: Context Interview (Superpowers Brainstorming)

Present ALL gathered context, then interview the user one question at a time to fill gaps.

This phase uses Superpowers brainstorming methodology: one question at a time, multiple choice preferred, lead with recommendation.

### Step 3.1: Present Gathered Context

```
Here's everything I found about PROJ-1234: "Add rate limiting to public API"

  ✓ Ticket: 100 req/min per user, 429 response, Retry-After header
  ✓ AC: 4 acceptance criteria (3 clear, 1 ambiguous)
  ✓ Slack: @bob recommended Redis for counter store (thread 3/8)
  ✓ Slack: @pm confirmed all public endpoints, same limit (thread 3/10)
  ✓ Memory: Team convention #42 — use token-bucket algorithm
  ✓ Memory: Past work — similar rate limiter in /admin API (6 months ago)
  ✓ Codebase: Middleware pattern in src/middleware/, Jest + supertest tests
  ✗ Figma: No design linked (API-only feature)
  ? Ambiguous: AC4 says "admin override" — what does this mean exactly?
```

### Step 3.2: Interview for Missing Context (one question at a time)

Follow the Superpowers brainstorming pattern — ONE question at a time, multiple choice preferred. Maximum 5 questions.

```
Question 1 of 3:

AC4 mentions "admin override capability." What should this mean?

  A) Admin users bypass rate limiting entirely
  B) Admin users have a higher limit (e.g., 1000 req/min)
  C) Admins can temporarily disable rate limiting for specific users
  D) Something else (please describe)

Your choice?
```

Wait for answer. Then ask next question:

```
Question 2 of 3:

@bob recommended Redis in Slack, and we have convention #42 for
token-bucket. For the counter store:

  A) Redis (recommended by @bob, production-ready, shared across instances)
  B) In-memory (simpler, but per-instance — requires sticky sessions)
  C) Use the existing Redis if one is configured, fall back to in-memory

Your choice?
```

**Rules for the interview:**
- Maximum 5 questions
- One question at a time (never batch)
- Multiple choice preferred (A/B/C/D)
- Lead with recommendation and rationale
- Reference gathered context in each question
- If user says "you decide" — pick the option most aligned with team conventions

---

## Phase 4: Design Proposal

Present 2-3 implementation approaches with trade-offs.

### Hard gate: NO IMPLEMENTATION WITHOUT APPROVED DESIGN

Do not write ANY code until the user approves the design. This is non-negotiable.

### Step 4.1: Propose Approaches

```
Based on everything gathered, here are 3 approaches:

## Approach A: Middleware + Redis (Recommended)
  - New middleware: src/middleware/rate-limit.ts
  - Redis client: reuse existing or add ioredis
  - Token-bucket algorithm (convention #42)
  - Config in src/config/rate-limits.yaml
  Pros: Production-ready, shared across instances, matches convention
  Cons: Redis dependency, more complex setup
  Effort: ~3 hours

## Approach B: Middleware + In-Memory
  - Same middleware pattern
  - In-memory Map with TTL cleanup
  - Token-bucket algorithm
  Pros: Simpler, no new dependencies
  Cons: Per-instance (lost on restart), no sharing across pods
  Effort: ~2 hours

## Approach C: API Gateway (nginx/cloudflare)
  - Configure at infrastructure level
  - No application code changes
  Pros: Zero code, handles any endpoint
  Cons: Less granular, no per-user limits, harder to test
  Effort: ~1 hour (if infra access available)

I recommend Approach A because:
  - @bob recommended Redis (Slack 3/8)
  - Convention #42 specifies token-bucket
  - Production deployment uses multiple pods (in-memory won't work)
  - Past /admin limiter used Redis successfully

Which approach? Or want to modify one?
```

### Step 4.2: Detailed Design (for approved approach)

Once user approves, present detailed design section by section:

```
Detailed design for Approach A:

## File Structure
  src/middleware/rate-limit.ts        — middleware function
  src/middleware/rate-limit.test.ts   — unit tests
  src/config/rate-limits.yaml         — rate limit configuration
  src/lib/token-bucket.ts             — token-bucket implementation
  src/lib/token-bucket.test.ts        — algorithm tests
  tests/integration/rate-limit.test.ts — integration tests

## API Contract
  Headers on every response:
    X-RateLimit-Limit: 100
    X-RateLimit-Remaining: 42
    X-RateLimit-Reset: 1609459200

  When rate limited:
    HTTP 429 Too Many Requests
    Retry-After: 23
    Body: { "error": "rate_limited", "retryAfter": 23 }

## Admin Override
  - Check user role from auth middleware
  - Admin users get limit from config (default: 1000)
  - Config: rate-limits.yaml has per-role limits

Does this design look correct? Any changes?
```

Wait for approval before proceeding to Phase 5.

---

## Phase 5: Implementation Plan (Superpowers writing-plans)

Generate a detailed, executable plan following Superpowers writing-plans methodology.

### Plan Generation Rules

- Each task: 2-5 minutes with exact file paths
- TDD: write a failing test BEFORE each implementation step
- Verification command per step (the exact command to run)
- Complete code — no "add validation here" placeholders
- Follow ALL team conventions from context tree
- Reference specific line numbers where code integrates

### Plan Template

```markdown
## Implementation Plan: [Ticket ID] — [Title]

**Approach:** [A/B/C as approved]
**Files:** [all files that will be created or modified]

### Task 1: Token-bucket algorithm + tests
  Files: src/lib/token-bucket.ts, src/lib/token-bucket.test.ts

  - [ ] Write failing test for token-bucket consume()
  - [ ] Verify fail: `npm test -- token-bucket`
  - [ ] Implement TokenBucket class with consume() and refill()
  - [ ] Verify pass: `npm test -- token-bucket`
  - [ ] Commit: "feat(rate-limit): add token-bucket algorithm"

### Task 2: Rate limit config
  Files: src/config/rate-limits.yaml, src/config/rate-limits.ts

  - [ ] Write failing test for config loading
  - [ ] Verify fail: `npm test -- rate-limits`
  - [ ] Create YAML config and TypeScript loader
  - [ ] Verify pass: `npm test -- rate-limits`
  - [ ] Commit: "feat(rate-limit): add rate limit configuration"

### Task 3: Rate limit middleware + unit tests
  Files: src/middleware/rate-limit.ts, src/middleware/rate-limit.test.ts

  - [ ] Write failing test for middleware (returns headers)
  - [ ] Verify fail: `npm test -- rate-limit.test`
  - [ ] Implement middleware with Redis client
  - [ ] Write failing test for 429 response
  - [ ] Implement 429 logic
  - [ ] Write failing test for admin override
  - [ ] Implement admin override
  - [ ] Verify all pass: `npm test -- rate-limit`
  - [ ] Commit: "feat(rate-limit): add rate limit middleware"

### Task 4: Integration tests
  Files: tests/integration/rate-limit.test.ts

  - [ ] Write integration test (supertest, real Redis or mock)
  - [ ] Verify pass: `npm test -- integration/rate-limit`
  - [ ] Commit: "test(rate-limit): add integration tests"

### Task 5: Wire up + documentation
  Files: src/app.ts, docs/api/rate-limiting.md

  - [ ] Register middleware in app.ts
  - [ ] Update API documentation
  - [ ] Run full test suite: `npm test`
  - [ ] Commit: "feat(rate-limit): register middleware and update docs"
```

Save plan to: `docs/plans/YYYY-MM-DD-[ticket-id]-plan.md`

If task manager MCP is available, link plan to ticket via `mcp__claude_ai_Atlassian__addCommentToJiraIssue`.

---

## Phase 6: Execute + Report

### Step 6.1: Execute Plan (Subagent-Driven)

Execute using Superpowers subagent-driven-development:
- Fresh subagent per task
- Each subagent receives: task description, relevant file paths, test commands, team conventions
- TDD enforced — iron law: no implementation without a failing test first
- Two-stage review per task: correctness + convention compliance
- Verification before marking complete

### Step 6.2: Update Ticket (if Atlassian MCP available)

Use `mcp__claude_ai_Atlassian__transitionJiraIssue` to move ticket to "In Review" or appropriate status.
Use `mcp__claude_ai_Atlassian__addCommentToJiraIssue` to post implementation summary.

### Step 6.3: Post to Slack (if Slack MCP available)

If the ticket was discussed in Slack, use `mcp__claude_ai_Slack__slack_send_message` to post a summary:

```
Implementation complete for PROJ-1234: "Add rate limiting to public API"

Approach: Token-bucket + Redis middleware (Approach A)
Files changed: 7 (3 new, 4 modified)
Tests: 24 new tests, all passing
PR: #456

Key decisions:
- Token-bucket per convention #42 (not sliding-window)
- Redis for shared state across pods
- Admin override: configurable per-role limits

Ready for review.
```

### Step 6.4: Curate Learnings (if lossless-claude MCP available)

Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store. Use tags: ["session"]. Store:
- Implementation patterns used (middleware pattern, config pattern)
- Decisions made and rationale (token-bucket vs sliding-window)
- New conventions established (rate limit config format)
- Integration points discovered

Save to context tree: `.xgh/context-tree/api-design/rate-limiting.md` (or appropriate domain)

### Step 6.5: Generate PR Context

Generate a PR with full context for reviewers:
- Link to ticket
- Design decision rationale
- Test coverage summary
- Files changed with purpose annotations
- Reviewer guidance (what to look for)

---

## Skill Composition

`xgh:implement` composes with other xgh skills:

| Skill | When Used | Purpose |
|-------|-----------|---------|
| `xgh:design` | When Figma designs are linked to the ticket | Delegates UI implementation |
| `xgh:investigate` | When ticket references a bug that needs root cause analysis first | Runs investigation before implementation |
| `xgh:subagent-pair-programming` | During Phase 6 execution | TDD enforcement and two-stage review |

---

## Rationalization Table

| Decision | Rationale |
|----------|-----------|
| Hard gate: no implementation without approved design | Prevents wasted work. Forces alignment before coding. |
| One question at a time interview | Superpowers brainstorming pattern. Prevents overwhelm. Gets thoughtful answers. |
| Multiple choice preferred | Reduces cognitive load. Speeds up decision making. Still allows freeform. |
| 2-3 approaches with trade-offs | Forces consideration of alternatives. Prevents tunnel vision. |
| Reference conventions in proposals | Grounds decisions in team history. Builds on past work. |
| Cross-platform context gathering | Slack discussions often contain critical decisions not in tickets. |
| Subagent-driven execution | Fresh context per task. Prevents state pollution. Better TDD compliance. |
| Curate learnings after completion | Future implementations benefit from this experience. Team knowledge grows. |
| Graceful degradation without any MCP | The skill is useful even with zero MCPs — just less automated. |
| Maximum 5 interview questions | Respects user time. Forces the skill to make reasonable defaults. |
