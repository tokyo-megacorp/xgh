# Workflow Skills Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Implement three MCP-powered workflow skills (`xgh:investigate`, `xgh:implement-design`, `xgh:implement-ticket`) that combine Superpowers methodology with xgh memory and auto-detect available MCP servers.

**Architecture:** Each workflow skill is a markdown file in `skills/<name>/<name>.md` with a corresponding command trigger in `commands/<name>.md`. Skills dynamically check for available MCP tools (Slack, Figma, Atlassian/task managers) and gracefully degrade when MCPs are absent. Each skill follows Superpowers patterns (iron laws, hard gates, rationalization tables) and composes with team collaboration skills.

**Tech Stack:** Claude Code skills (markdown), Claude Code commands (markdown), MCP tool references (Slack, Figma, Atlassian, Cipher), Superpowers methodology patterns, Bash tests

**Design doc:** `docs/plans/2026-03-13-xgh-design.md` — Sections 7 and 11

---

## File Structure

```
skills/
├── investigate/
│   └── investigate.md              # xgh:investigate skill
├── implement-design/
│   └── implement-design.md         # xgh:implement-design skill
└── implement-ticket/
    └── implement-ticket.md         # xgh:implement-ticket skill

commands/
├── investigate.md                  # /xgh investigate command
├── implement-design.md             # /xgh implement-design command
└── implement.md                    # /xgh implement command

tests/
└── test-workflow-skills.sh         # Validation tests for all workflow skills
```

---

## Chunk 1: Test Harness and `xgh:investigate` Skill

### Task 1: Create test harness for workflow skills

**Files:**
- Create: `tests/test-workflow-skills.sh`

- [x] **Step 1: Write test for workflow skill structure validation**

```bash
# tests/test-workflow-skills.sh
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then
    ((PASS++))
  else
    echo "FAIL: $1 does not exist"
    ((FAIL++))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    ((PASS++))
  else
    echo "FAIL: $1 does not contain '$2'"
    ((FAIL++))
  fi
}

assert_contains_regex() {
  if grep -qE "$2" "$1" 2>/dev/null; then
    ((PASS++))
  else
    echo "FAIL: $1 does not match regex '$2'"
    ((FAIL++))
  fi
}

# ── Skill files exist ──────────────────────────────────────
echo "=== Skill file existence ==="
assert_file_exists "skills/investigate/investigate.md"
assert_file_exists "skills/implement-design/implement-design.md"
assert_file_exists "skills/implement-ticket/implement-ticket.md"

# ── Command files exist ────────────────────────────────────
echo "=== Command file existence ==="
assert_file_exists "commands/investigate.md"
assert_file_exists "commands/implement-design.md"
assert_file_exists "commands/implement.md"

# ── investigate skill required sections ────────────────────
echo "=== investigate skill sections ==="
INVEST="skills/investigate/investigate.md"
assert_contains "$INVEST" "Phase 1"
assert_contains "$INVEST" "Phase 2"
assert_contains "$INVEST" "Phase 3"
assert_contains "$INVEST" "Phase 4"
assert_contains "$INVEST" "Context Gathering"
assert_contains "$INVEST" "Interactive Triage"
assert_contains "$INVEST" "Systematic Debug"
assert_contains "$INVEST" "Finding Report"

# investigate skill MCP tool references
echo "=== investigate MCP references ==="
assert_contains "$INVEST" "slack_read_thread"
assert_contains "$INVEST" "slack_search_public"
assert_contains "$INVEST" "cipher_memory_search"
assert_contains "$INVEST" "getJiraIssue"
assert_contains "$INVEST" "searchJiraIssuesUsingJql"
assert_contains "$INVEST" "createJiraIssue"

# investigate skill Superpowers patterns
echo "=== investigate Superpowers patterns ==="
assert_contains "$INVEST" "NO FIXES WITHOUT ROOT CAUSE"
assert_contains "$INVEST" "3 failed hypotheses"
assert_contains "$INVEST" "Iron Law"
assert_contains "$INVEST" "Hard gate"

# investigate skill graceful degradation
echo "=== investigate graceful degradation ==="
assert_contains "$INVEST" "auto-detect"
assert_contains_regex "$INVEST" "[Gg]raceful"

# ── implement-design skill required sections ───────────────
echo "=== implement-design skill sections ==="
DESIGN="skills/implement-design/implement-design.md"
assert_contains "$DESIGN" "Phase 1"
assert_contains "$DESIGN" "Phase 2"
assert_contains "$DESIGN" "Phase 3"
assert_contains "$DESIGN" "Phase 4"
assert_contains "$DESIGN" "Phase 5"
assert_contains "$DESIGN" "Deep Design Mining"
assert_contains "$DESIGN" "Context Enrichment"
assert_contains "$DESIGN" "Interactive State Review"
assert_contains "$DESIGN" "Implementation Plan"
assert_contains "$DESIGN" "Curate"

# implement-design skill MCP tool references
echo "=== implement-design MCP references ==="
assert_contains "$DESIGN" "get_design_context"
assert_contains "$DESIGN" "get_screenshot"
assert_contains "$DESIGN" "get_metadata"
assert_contains "$DESIGN" "get_figjam"
assert_contains "$DESIGN" "get_variable_defs"
assert_contains "$DESIGN" "get_code_connect_map"
assert_contains "$DESIGN" "cipher_memory_search"

# implement-design skill Superpowers patterns
echo "=== implement-design Superpowers patterns ==="
assert_contains "$DESIGN" "TDD"
assert_contains "$DESIGN" "writing-plans"

# ── implement-ticket skill required sections ───────────────
echo "=== implement-ticket skill sections ==="
TICKET="skills/implement-ticket/implement-ticket.md"
assert_contains "$TICKET" "Phase 1"
assert_contains "$TICKET" "Phase 2"
assert_contains "$TICKET" "Phase 3"
assert_contains "$TICKET" "Phase 4"
assert_contains "$TICKET" "Phase 5"
assert_contains "$TICKET" "Phase 6"
assert_contains "$TICKET" "Ticket Deep Dive"
assert_contains "$TICKET" "Cross-Platform Context"
assert_contains "$TICKET" "Context Interview"
assert_contains "$TICKET" "Design Proposal"
assert_contains "$TICKET" "Implementation Plan"
assert_contains "$TICKET" "Execute"

# implement-ticket skill MCP tool references
echo "=== implement-ticket MCP references ==="
assert_contains "$TICKET" "getJiraIssue"
assert_contains "$TICKET" "slack_search_public"
assert_contains "$TICKET" "get_design_context"
assert_contains "$TICKET" "cipher_memory_search"
assert_contains "$TICKET" "cipher_extract_and_operate_memory"

# implement-ticket skill Superpowers patterns
echo "=== implement-ticket Superpowers patterns ==="
assert_contains "$TICKET" "NO IMPLEMENTATION WITHOUT APPROVED DESIGN"
assert_contains "$TICKET" "Hard gate"
assert_contains "$TICKET" "brainstorming"
assert_contains "$TICKET" "one question at a time"
assert_contains "$TICKET" "TDD"
assert_contains "$TICKET" "subagent"

# ── Commands reference their skills ────────────────────────
echo "=== Command-skill references ==="
assert_contains "commands/investigate.md" "investigate"
assert_contains "commands/implement-design.md" "implement-design"
assert_contains "commands/implement.md" "implement-ticket"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test-workflow-skills.sh`
Expected: FAIL — no skill or command files exist yet

- [x] **Step 3: Commit test file**

```bash
git add tests/test-workflow-skills.sh
git commit -m "test: add workflow skills validation test harness"
```

---

### Task 2: Create the `xgh:investigate` skill

**Files:**
- Create: `skills/investigate/investigate.md`

- [x] **Step 1: Create the investigate skill directory**

```bash
mkdir -p skills/investigate
```

- [x] **Step 2: Write the investigate skill file**

```markdown
# skills/investigate/investigate.md
```

Full content of `skills/investigate/investigate.md`:

````markdown
---
name: xgh:investigate
description: "Slack-driven systematic debugging workflow — from Slack thread to root cause finding report"
trigger: "/xgh investigate"
mcp_dependencies:
  required: []
  optional:
    - slack: "Slack MCP — read threads, search discussions, post findings"
    - atlassian: "Atlassian MCP — search/create Jira tickets"
    - cipher: "Cipher MCP — search past bugs, store findings"
---

# xgh:investigate — Slack-Driven Debugging Workflow

A systematic investigation skill that starts from a bug report (Slack thread, user description, or alert) and produces a detailed finding report with root cause analysis. Combines Superpowers systematic-debugging methodology with xgh memory.

## Trigger

```
/xgh investigate <slack-thread-url>
/xgh investigate
```

If no URL is provided, prompt the user to describe the issue or paste a Slack thread URL.

---

## MCP Auto-Detection

Before starting, auto-detect which MCP servers are available. The skill adapts based on what is configured — no hard dependencies.

**Detection procedure:**

1. Check if Slack MCP tools are available (look for `slack_read_thread` in available tools)
2. Check if Atlassian/task manager MCP tools are available (look for `getJiraIssue` in available tools)
3. Check if Cipher MCP tools are available (look for `cipher_memory_search` in available tools)

**Graceful degradation rules:**
- No Slack MCP → Skip Slack thread reading. Ask user to paste the bug report content directly.
- No task manager MCP → Skip ticket search/creation. Note in report that no ticket was created.
- No Cipher MCP → Skip memory search. Proceed with codebase-only investigation. Save report to context tree only.
- No MCPs at all → Still works. User provides context manually. Full Superpowers debug methodology applies.

Report which MCPs were detected at the start:
```
Available integrations:
  [x] Slack — will read thread and search related discussions
  [ ] Jira — not configured, skipping ticket management
  [x] Cipher Memory — will search past bugs and store findings
```

---

## Phase 1: Context Gathering

Gather all available context before investigating. Run these in parallel where possible.

### Step 1.1: Read Slack Thread (if Slack MCP available)

Use `mcp__claude_ai_Slack__slack_read_thread` to read the full Slack thread.

Extract from the thread:
- **Symptoms:** What is broken? Error messages, unexpected behavior
- **Affected users:** Who reported it? How many affected?
- **Timestamps:** When did it start? When was it reported?
- **Error messages:** Exact error text, stack traces, screenshots
- **Related threads:** Links to other discussions mentioned
- **Environment:** Production/staging? Browser/device? Version?

If no Slack URL was provided but Slack MCP is available, use `mcp__claude_ai_Slack__slack_search_public` to search for related recent discussions.

### Step 1.2: Search Related Discussions (if Slack MCP available)

Use `mcp__claude_ai_Slack__slack_search_public` or `mcp__claude_ai_Slack__slack_search_public_and_private` to find:
- Prior reports of the same issue ("Has this happened before?")
- Related incidents and workarounds
- Design discussions about the affected area
- Deploy notifications around the incident time

Search queries to try:
- Error message text (exact match)
- Affected feature/component name
- "broken" or "bug" + feature name
- Recent deploy notifications in engineering channels

### Step 1.3: Query xgh Memory (if Cipher MCP available)

Use `mcp__cipher__cipher_memory_search` to search for:
- Similar bugs that were investigated before
- Past fixes in the affected code area
- Architecture decisions that may be relevant
- Team conventions for the affected module

Search queries:
- Symptom description
- Affected file paths or module names
- Error message patterns
- Component or feature name

Also check the context tree (`.xgh/context-tree/`) for:
- Related architecture decisions
- Known limitations or tech debt
- Past investigation reports in `investigations/` domain

### Step 1.4: Check Task Manager (if Atlassian MCP available)

Use `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` to search for existing tickets:
- Search by error message text
- Search by component/module name
- Search by reporter or recent date range

JQL query patterns:
```
text ~ "error message excerpt" ORDER BY created DESC
summary ~ "feature name" AND status != Done ORDER BY created DESC
labels = bug AND component = "affected-component" AND created >= -7d
```

If tickets are found, use `mcp__claude_ai_Atlassian__getJiraIssue` to fetch full details including:
- Title, description, acceptance criteria
- Status, assignee, priority
- Comments (may contain prior investigation notes)
- Linked tickets (related bugs, epics)

---

## Phase 2: Interactive Triage

Present gathered context to the user and triage the issue interactively.

### Scenario A: Existing Ticket Found

```
I found an existing ticket that may be related:

  PROJ-1234: "Login timeout on mobile Safari"
  Status: In Progress | Assigned: @alice | Priority: High
  Created: 3 days ago | Comments: 4

  Summary: Users on mobile Safari experience 30s timeout when
  attempting to log in via OAuth. Affects ~12% of mobile users.

Options:
  A) This is the same issue — add context from this thread to PROJ-1234
  B) This is a different issue — continue investigation as new
  C) This is related but distinct — create a linked ticket

Which option?
```

If user chooses A: Use `mcp__claude_ai_Atlassian__addCommentToJiraIssue` to add Slack thread context.
If user chooses C: Create new ticket (see Scenario B) and use `mcp__claude_ai_Atlassian__createIssueLink` to link them.

### Scenario B: No Existing Ticket Found

```
No existing ticket found for this issue. Want me to create one?

Options:
  A) Yes, create a ticket now (I'll ask a few questions)
  B) No, just investigate — I'll create one later
  C) Skip — we don't use tickets for this type of issue
```

If user chooses A, ask interactively (one question at a time, Superpowers brainstorming pattern):
1. **Title:** Suggest a title based on symptoms. "Proposed title: '[symptom summary]' — ok or want to change?"
2. **Priority:** "Based on [N] affected users and [severity], I'd suggest [priority]. Agree?"
3. **Labels/Component:** "This seems to affect [component]. Labels: [suggested]. Adjust?"

Create ticket via `mcp__claude_ai_Atlassian__createJiraIssue`.

### Scenario C: No Task Manager MCP

Skip ticket management entirely. Note in final report:
```
Ticket: Not created (no task manager configured)
```

---

## Phase 3: Systematic Debug (Superpowers Methodology)

### Iron Law: NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST

Do not suggest fixes, patches, or workarounds until root cause is confirmed with evidence. This is non-negotiable.

### Step 3.1: Reproduce

Trace from symptoms to code paths:
- Identify the entry point (API endpoint, UI action, cron job, etc.)
- Trace the execution path through the codebase
- Identify where the expected behavior diverges from actual behavior
- If possible, write a minimal reproduction case

Present findings:
```
Reproduction trace:
  1. User clicks "Login" on mobile Safari
  2. → POST /api/auth/oauth/start
  3. → OAuthService.initiateFlow() in src/services/oauth.ts:42
  4. → Redirects to provider with callback URL
  5. → Provider callback hits /api/auth/oauth/callback
  6. → OAuthService.handleCallback() in src/services/oauth.ts:89
  7. ✗ TIMEOUT HERE — token exchange takes >30s on mobile Safari
```

### Step 3.2: Boundary Analysis

Log at module transitions to isolate the problem:
- Which module/service is responsible?
- Is the issue at the boundary between two systems?
- What are the inputs and outputs at each boundary?
- Where does the data transform incorrectly or the timing degrade?

### Step 3.3: Pattern Analysis

Compare working vs broken:
- What changed recently? (git log, deploy history)
- Does it work in some environments but not others?
- Is it intermittent or consistent?
- What is the minimal diff between working and broken?

### Step 3.4: Hypothesis Formation

Form a single, testable hypothesis:
```
Hypothesis #1:
  "The OAuth token exchange timeout is caused by a missing
  keep-alive header on mobile Safari, which closes the TCP
  connection during the provider's processing time."

  Test: Check if the fetch() call in handleCallback() includes
  keep-alive headers. Compare network traces between Chrome
  (working) and Safari (broken).
```

**Rules:**
- ONE hypothesis at a time
- Must be testable with a minimal, isolated check
- Must explain ALL observed symptoms
- Must predict what we would see if it is correct vs incorrect

### Step 3.5: Hypothesis Verification

Test the hypothesis. Report result:
```
Hypothesis #1 result: CONFIRMED / REJECTED

Evidence:
  - [specific evidence that confirms or rejects]
  - [file:line references]
  - [log output or test results]
```

### Hard gate: After 3 failed hypotheses, STOP.

```
⚠ Three hypotheses have been rejected. This suggests the problem
may be architectural or involves an interaction I haven't considered.

Failed hypotheses:
  1. [hypothesis] — rejected because [reason]
  2. [hypothesis] — rejected because [reason]
  3. [hypothesis] — rejected because [reason]

I need your help. Questions:
  - Is there a recent infrastructure change I should know about?
  - Are there external services involved that may have changed?
  - Is there a team member who knows this area deeply I should consult?

Please provide additional context before I continue.
```

Do NOT proceed past this gate without user input.

### Step 3.6: Root Cause Confirmation

Once a hypothesis is confirmed:
```
Root Cause: CONFIRMED

  The OAuth token exchange in handleCallback() uses fetch()
  without a Connection: keep-alive header. Mobile Safari
  defaults to Connection: close, causing the TCP connection
  to drop during the provider's 5-8 second processing time.

  Evidence:
  - Network trace shows Safari sends Connection: close
  - Chrome sends Connection: keep-alive by default
  - Provider average response time: 6.2s (within Safari's close window)
  - Adding keep-alive header in test: resolves the timeout

  Affected code: src/services/oauth.ts:89-112
```

---

## Phase 4: Finding Report

Generate a structured investigation report.

### Report Template

```markdown
# Investigation: [Title]

**Date:** [YYYY-MM-DD]
**Investigator:** xgh:investigate (agent-assisted)
**Duration:** [time from start to root cause]

## Source
[Slack thread link or user report description]

## Ticket
[PROJ-1234 link, or "Not created (no task manager configured)"]

## Summary
[1-2 sentence root cause summary in plain language]

## Timeline
- **[timestamp]** — Issue first observed / reported
- **[timestamp]** — Investigation started
- **[timestamp]** — Root cause identified
- **[timestamp]** — Fix proposed

## Root Cause
[Detailed technical analysis — what went wrong and why]

## Evidence
- [Specific evidence item 1 — file paths, log output, test results]
- [Specific evidence item 2]
- [Reproduction steps]

## Impact
- **Affected users:** [count, percentage, user segments]
- **Severity:** [critical/high/medium/low]
- **Duration:** [how long the issue has existed]
- **Data impact:** [any data loss or corruption]

## Fix
[Proposed solution with specific code changes]

```[language]
// Before
[broken code]

// After
[fixed code]
```

## Prevention
- [What would catch this earlier — test, lint rule, monitoring]
- [Process change if applicable]
- [Architecture improvement if applicable]

## Related
- [Link to past investigations/incidents]
- [Link to architecture decisions]
- [Link to related tickets]
```

### Report Distribution

1. **Context tree:** Save to `.xgh/context-tree/investigations/[YYYY-MM-DD]-[slug].md`
   - YAML frontmatter: `importance: 70`, `maturity: validated`, `tags: [bug, investigation, <component>]`

2. **Cipher memory** (if available): Use `mcp__cipher__cipher_extract_and_operate_memory` to store:
   - Root cause pattern (for future similar bug detection)
   - Fix pattern (for future similar fix suggestions)
   - Prevention learnings

3. **Slack** (if available and user approves): Post a condensed summary back to the original Slack thread using `mcp__claude_ai_Slack__slack_send_message`.

4. **Ticket** (if created/found): Attach full report as a comment via `mcp__claude_ai_Atlassian__addCommentToJiraIssue`.

---

## Rationalization Table

| Decision | Rationale |
|----------|-----------|
| Iron Law: no fixes without root cause | Prevents band-aid fixes that mask deeper issues. Forces understanding. |
| 3-hypothesis hard gate | Prevents infinite rabbit holes. Forces the agent to seek human expertise. |
| One hypothesis at a time | Forces focus. Prevents shotgun debugging. |
| Report saved to context tree | Future investigations can reference past findings. Searchable by team. |
| Curated to Cipher | Semantic search finds similar bugs even with different keywords. |
| Interactive triage before debug | Avoids duplicate work. Connects to existing team workflows. |
| Graceful degradation | Works for any team regardless of MCP configuration. |
````

- [x] **Step 3: Run test to verify investigate-related assertions pass**

Run: `bash tests/test-workflow-skills.sh 2>&1 | head -30`
Expected: investigate skill assertions PASS, others still FAIL

- [x] **Step 4: Commit**

```bash
git add skills/investigate/
git commit -m "feat: add xgh:investigate workflow skill — Slack-driven systematic debugging"
```

---

### Task 3: Create the `/xgh investigate` command

**Files:**
- Create: `commands/investigate.md`

- [x] **Step 1: Write the investigate command file**

```markdown
# commands/investigate.md
```

Full content of `commands/investigate.md`:

````markdown
---
name: investigate
description: "Start a systematic debugging investigation from a Slack thread or bug report"
usage: "/xgh investigate [slack-thread-url]"
aliases: ["debug", "inv"]
---

# /xgh investigate

Start a systematic investigation of a bug or incident. Reads context from Slack, task managers, and xgh memory, then applies Superpowers systematic-debugging methodology to find the root cause.

## Usage

```
/xgh investigate <slack-thread-url>
/xgh investigate
```

## Behavior

1. Load the `xgh:investigate` skill from `skills/investigate/investigate.md`
2. Auto-detect available MCP integrations (Slack, Jira, Cipher)
3. If a Slack thread URL was provided, read the thread immediately
4. If no URL was provided, ask the user to describe the issue or paste a URL
5. Execute all 4 phases of the investigate workflow:
   - Phase 1: Context Gathering (Slack + Memory + Tickets)
   - Phase 2: Interactive Triage (find/create tickets)
   - Phase 3: Systematic Debug (Superpowers methodology)
   - Phase 4: Finding Report (structured output + distribution)

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `slack-thread-url` | No | URL to a Slack thread containing the bug report. If omitted, prompts for context. |

## Examples

```
/xgh investigate https://myteam.slack.com/archives/C01ABC/p1234567890
/xgh investigate
```

## Related Skills

- `xgh:investigate` — the full workflow skill this command triggers
- `xgh:implement-ticket` — after investigation, implement the fix via ticket
````

- [x] **Step 2: Run test to check command assertions**

Run: `bash tests/test-workflow-skills.sh 2>&1 | grep "commands/investigate"`
Expected: investigate command assertions PASS

- [x] **Step 3: Commit**

```bash
git add commands/investigate.md
git commit -m "feat: add /xgh investigate command trigger"
```

---

## Chunk 2: `xgh:implement-design` Skill

### Task 4: Create the `xgh:implement-design` skill

**Files:**
- Create: `skills/implement-design/implement-design.md`

- [x] **Step 1: Create the implement-design skill directory**

```bash
mkdir -p skills/implement-design
```

- [x] **Step 2: Write the implement-design skill file**

Full content of `skills/implement-design/implement-design.md`:

````markdown
---
name: xgh:implement-design
description: "Figma-driven UI implementation — from design file to convention-compliant code"
trigger: "/xgh implement-design"
mcp_dependencies:
  required: []
  optional:
    - figma: "Figma MCP — read designs, screenshots, variables, Code Connect"
    - atlassian: "Atlassian MCP — find related tickets, acceptance criteria"
    - cipher: "Cipher MCP — search UI conventions, component patterns"
    - slack: "Slack MCP — find design discussions"
---

# xgh:implement-design — Figma-Driven UI Implementation

Takes a Figma design URL and produces a complete, convention-compliant implementation. Gathers ALL available context from the design file, enriches with xgh memory and team conventions, confirms states interactively, then generates and executes a Superpowers writing-plans implementation plan with TDD.

## Trigger

```
/xgh implement-design <figma-url>
/xgh implement-design
```

If no URL is provided, prompt the user for a Figma file URL or node URL.

---

## MCP Auto-Detection

Before starting, auto-detect which MCP servers are available. The skill adapts based on what is configured — no hard dependencies.

**Detection procedure:**

1. Check if Figma MCP tools are available (look for `get_design_context` in available tools)
2. Check if Cipher MCP tools are available (look for `cipher_memory_search` in available tools)
3. Check if Atlassian MCP tools are available (look for `getJiraIssue` in available tools)
4. Check if Slack MCP tools are available (look for `slack_search_public` in available tools)

**Graceful degradation rules:**
- No Figma MCP → Cannot auto-extract design. Ask user to describe the design, paste screenshots, or provide component specs manually. Skip Code Connect and variable extraction.
- No Cipher MCP → Skip memory search for conventions. Rely on codebase scanning only.
- No task manager MCP → Skip ticket lookup. Ask user for acceptance criteria directly.
- No Slack MCP → Skip design discussion search.

Report which MCPs were detected at the start:
```
Available integrations:
  [x] Figma — will extract design context, states, tokens, Code Connect
  [x] Cipher Memory — will search UI conventions and component patterns
  [ ] Jira — not configured, will ask for acceptance criteria directly
  [ ] Slack — not configured, skipping design discussion search
```

---

## Phase 1: Deep Design Mining

Extract everything possible from the Figma design file.

### Step 1.1: Parse Figma URL

Extract `fileKey` and `nodeId` from the URL:
- `https://www.figma.com/file/<fileKey>/...` → file-level
- `https://www.figma.com/file/<fileKey>?node-id=<nodeId>` → node-level
- `https://www.figma.com/design/<fileKey>/...` → design-level (same as file)

### Step 1.2: Get Design Context (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_design_context` with the extracted `fileKey` and `nodeId`.

Extract:
- Component structure and hierarchy
- Code hints (if designers added implementation notes)
- Component mappings (Figma component → code component)
- Design tokens (colors, spacing, typography, shadows)
- Layout information (flex, grid, absolute positioning)
- Responsive breakpoints and constraints

### Step 1.3: Get Screenshot (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_screenshot` to get a visual reference.

Use this for:
- Layout understanding (spatial relationships)
- Visual verification during implementation
- Identifying states not captured in component structure

### Step 1.4: Get File Metadata (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_metadata` to understand file structure.

Extract:
- Pages in the file (find related pages like "States", "Mobile", "Dark Mode")
- Component inventory (all components used in the design)
- File structure (how the designer organized the work)

### Step 1.5: Search FigJam Boards (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_figjam` to find linked FigJam boards.

Extract from FigJam:
- User flows and state diagrams
- Edge cases documented by designers
- Designer notes and annotations
- Acceptance criteria written on stickies
- Animation/interaction specifications
- Accessibility requirements

### Step 1.6: Get Design Variables (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_variable_defs` to extract design tokens.

Map to project design system:
- Colors → project color tokens/CSS variables
- Spacing → project spacing scale
- Typography → project font definitions
- Border radius, shadows, etc.

### Step 1.7: Get Code Connect Map (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_code_connect_map` to find existing component mappings.

This tells us:
- Which Figma components already have code equivalents
- What code to import/reuse vs what to create new
- Existing prop mappings (Figma variants → code props)

---

## Phase 2: Context Enrichment

Supplement Figma data with xgh memory and codebase analysis.

### Step 2.1: Query xgh Memory (if Cipher MCP available)

Use `mcp__cipher__cipher_memory_search` to search for:
- "How do we implement [component type] in this repo?"
- Team conventions for UI components (naming, file structure, test patterns)
- Past implementations of similar designs
- Design system component inventory
- Known UI pitfalls or gotchas in this codebase

Search queries:
- Component type (e.g., "modal", "data table", "form")
- Design pattern (e.g., "loading state", "error boundary")
- Feature area (e.g., "settings page", "user profile")

### Step 2.2: Scan Codebase for Existing Components

Search the codebase to understand existing patterns:
- Find similar components already implemented
- Identify the design system / component library in use
- Check import patterns and file organization conventions
- Look for shared hooks, utilities, and patterns

Match Figma components to code using Code Connect map (Step 1.7) and codebase search:
```
Figma Component        → Code Component           → Action
─────────────────────────────────────────────────────────────
Button/Primary         → src/components/Button     → REUSE (exists)
DataTable              → src/components/Table       → EXTEND (needs new props)
UserAvatar             → (none found)              → CREATE NEW
StatusBadge            → src/components/Badge      → REUSE (exists)
```

### Step 2.3: Check Task Manager (if Atlassian MCP available)

Search for a ticket related to this design work:
- Use `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` with Figma URL or design name
- Fetch ticket details for acceptance criteria, requirements, notes
- Check for linked tickets (related features, dependencies)

---

## Phase 3: Interactive State Review

Present everything discovered and get user confirmation.

### Step 3.1: Present Discovered States

```
I found these states in the Figma design:

  [x] Default state (node 34079:43248) — main view with data loaded
  [x] Loading state (node 34079:43320) — skeleton loader pattern
  [x] Error state (node 34256:54416) — error message with retry CTA
  [x] Empty state (node 34256:54400) — no data illustration + CTA
  [ ] Hover states — found on buttons and table rows
  [ ] Focus states — found on form inputs

  ? Missing states I'd expect:
    - Offline/disconnected state — is there one?
    - Permission denied state — needed?
    - Mobile/responsive view — separate page or responsive?

Which states should I implement? Are there any I missed?
```

### Step 3.2: Present FigJam Notes

```
FigJam notes from the design board:

  - "Animation on transition between loading and loaded states"
  - "Skeleton loading pattern, NOT a spinner"
  - "Error state must show retry CTA that retries the failed request"
  - "Empty state CTA links to /settings/import"
  - "Table rows are clickable — navigate to detail view"

Any additional requirements or changes to these notes?
```

### Step 3.3: Present Component Mapping

```
Component mapping (Figma → Code):

  REUSE existing:
    Button/Primary   → <Button variant="primary" />
    Badge/Status     → <Badge status={...} />
    Icon/Search      → <Icon name="search" />

  CREATE new:
    DataTable        → New component (no existing table component found)
    EmptyState       → New component (illustration + CTA pattern)

  EXTEND existing:
    Card             → <Card /> needs new "compact" variant

Does this mapping look correct? Any components I should reuse instead of creating?
```

### Step 3.4: Confirm Design Token Mapping

```
Design token mapping (Figma → Project):

  Colors:
    Primary/500     → var(--color-primary-500)     ✓ exact match
    Neutral/100     → var(--color-neutral-100)      ✓ exact match
    Error/600       → var(--color-error-600)        ✓ exact match
    Custom/#7C3AED  → ⚠ no match — suggest adding to palette?

  Spacing:
    16px            → var(--space-4)                ✓ matches 4-unit scale
    24px            → var(--space-6)                ✓ matches 4-unit scale
    10px            → ⚠ not on scale — use var(--space-2.5) or round to 8/12?

  Typography:
    Heading/H2      → text-xl font-semibold         ✓ matches
    Body/Regular    → text-base                     ✓ matches

Any adjustments to the token mapping?
```

---

## Phase 4: Implementation Plan + Execute

Generate and execute a Superpowers writing-plans implementation plan.

### Step 4.1: Generate Implementation Plan

Follow the Superpowers writing-plans methodology:
- Each task is 2-5 minutes
- Exact file paths for every file to create/modify
- TDD: write a failing test for each state BEFORE implementing
- Complete code — no "add logic here" placeholders
- Map all Figma tokens to project design system tokens
- Reuse existing components (never reinvent)
- Follow ALL team conventions from context tree

Plan structure:
```
## Implementation Plan: [Component Name]

### Task 1: Create component skeleton + default state test
  Files: src/components/[Name]/[Name].tsx, src/components/[Name]/[Name].test.tsx
  - [x] Write failing test for default state rendering
  - [x] Verify test fails
  - [x] Implement default state
  - [x] Verify test passes
  - [x] Commit

### Task 2: Loading state
  Files: src/components/[Name]/[Name].tsx, src/components/[Name]/[Name].test.tsx
  - [x] Write failing test for loading state
  - [x] Verify test fails
  - [x] Implement loading state (skeleton pattern)
  - [x] Verify test passes
  - [x] Commit

### Task 3: Error state
  ...

### Task N: Integration + Storybook
  ...
```

### Step 4.2: Execute Plan (Subagent-Driven)

If the user approves the plan, execute it:
- Use Superpowers subagent-driven-development if subagents are available
- Fresh subagent per component/state
- TDD enforced as an iron law — no implementation without a failing test first
- Two-stage review per task: design fidelity + code quality
- After each component: visual comparison (if screenshot available)

### Step 4.3: Design Fidelity Check

After implementation:
```
Design fidelity check:

  [x] Default state matches Figma layout and spacing
  [x] Loading state uses skeleton pattern (not spinner)
  [x] Error state shows retry CTA
  [x] Empty state shows illustration + CTA to /settings/import
  [x] Colors match design token mapping
  [x] Typography matches design token mapping
  [x] Spacing matches 4-unit grid
  [ ] Animation between states — TODO (requires additional work)

Deviations from design:
  - Used var(--space-3) instead of 10px (designer used non-standard spacing)
  - Rounded corner on empty state illustration: 8px instead of 10px (matches grid)
```

---

## Phase 5: Curate & Report

### Step 5.1: Curate New Component Mappings

Store new Figma → code mappings via `mcp__cipher__cipher_extract_and_operate_memory`:
- New components created and their Figma node IDs
- Design token mappings established
- Convention decisions made during implementation

### Step 5.2: Update Code Connect (if Figma MCP available)

Use `mcp__claude_ai_Figma__send_code_connect_mappings` to register new component mappings:
- Map newly created components back to Figma nodes
- Map props to Figma variants
- Enable future designers/developers to find the code for any Figma component

Use `mcp__claude_ai_Figma__add_code_connect_map` to add new entries to the mapping.

### Step 5.3: Update Context Tree

Save implementation details to `.xgh/context-tree/design-system/[component-name].md`:
- Component purpose and when to use
- Props and variants
- Figma node references
- Design token mappings
- Test coverage summary

YAML frontmatter: `importance: 65`, `maturity: validated`, `tags: [ui, component, design-system, <component-type>]`

### Step 5.4: Generate Report

```markdown
# Implementation Report: [Component Name]

**Design:** [Figma URL]
**Ticket:** [PROJ-1234 or "N/A"]
**Date:** [YYYY-MM-DD]

## Components
| Component | Action | Files |
|-----------|--------|-------|
| DataTable | Created | src/components/DataTable/DataTable.tsx |
| EmptyState | Created | src/components/EmptyState/EmptyState.tsx |
| Card | Extended | src/components/Card/Card.tsx (added "compact" variant) |

## States Implemented
- [x] Default, Loading, Error, Empty
- [x] Animation transitions (deferred)

## Design Decisions
- Used skeleton loading per FigJam note (not spinner)
- Rounded 10px spacing to 12px to match 4-unit grid
- Added aria-label to retry CTA for accessibility

## Test Coverage
- 14 tests across 4 states
- Snapshot tests for visual regression
- Interaction tests for retry CTA and table row clicks

## Code Connect Updates
- DataTable → node 34079:43248
- EmptyState → node 34256:54400
```

---

## Rationalization Table

| Decision | Rationale |
|----------|-----------|
| Deep design mining (6 Figma MCP calls) | Extracts ALL context before coding. Prevents back-and-forth with designers. |
| Interactive state review | Catches missing states early. Gets user buy-in before implementation. |
| TDD per state | Each state is independently testable. Prevents regressions. |
| Map Figma tokens → project tokens | Maintains design system consistency. No magic numbers. |
| Code Connect updates | Future implementations of similar designs auto-discover reusable components. |
| Reuse over reinvent | Convention from most mature design systems. Less code, fewer bugs. |
| Graceful degradation without Figma MCP | Still works — user provides specs manually. Less automated but same methodology. |
````

- [x] **Step 3: Run test to verify implement-design assertions pass**

Run: `bash tests/test-workflow-skills.sh 2>&1 | grep "implement-design"`
Expected: implement-design skill assertions PASS

- [x] **Step 4: Commit**

```bash
git add skills/implement-design/
git commit -m "feat: add xgh:implement-design workflow skill — Figma-driven UI implementation"
```

---

### Task 5: Create the `/xgh implement-design` command

**Files:**
- Create: `commands/implement-design.md`

- [x] **Step 1: Write the implement-design command file**

Full content of `commands/implement-design.md`:

````markdown
---
name: implement-design
description: "Implement a UI component from a Figma design with full context extraction"
usage: "/xgh implement-design [figma-url]"
aliases: ["design", "figma"]
---

# /xgh implement-design

Implement a UI component from a Figma design. Extracts ALL available context (design tokens, states, FigJam notes, Code Connect mappings), enriches with xgh memory and codebase conventions, reviews interactively, then generates and executes a TDD implementation plan.

## Usage

```
/xgh implement-design <figma-url>
/xgh implement-design
```

## Behavior

1. Load the `xgh:implement-design` skill from `skills/implement-design/implement-design.md`
2. Auto-detect available MCP integrations (Figma, Cipher, Jira, Slack)
3. If a Figma URL was provided, begin design mining immediately
4. If no URL was provided, ask the user for a Figma file or node URL
5. Execute all 5 phases of the implement-design workflow:
   - Phase 1: Deep Design Mining (Figma MCP extraction)
   - Phase 2: Context Enrichment (memory + codebase)
   - Phase 3: Interactive State Review (confirm with user)
   - Phase 4: Implementation Plan + Execute (TDD, Superpowers writing-plans)
   - Phase 5: Curate & Report (Code Connect, context tree, report)

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `figma-url` | No | URL to a Figma file or node. If omitted, prompts for URL. |

## Examples

```
/xgh implement-design https://www.figma.com/file/abc123/MyDesign?node-id=34079:43248
/xgh implement-design https://www.figma.com/design/abc123/MyDesign
/xgh implement-design
```

## Related Skills

- `xgh:implement-design` — the full workflow skill this command triggers
- `xgh:implement-ticket` — if the design is linked to a ticket, use implement instead
````

- [x] **Step 2: Run test to check command assertions**

Run: `bash tests/test-workflow-skills.sh 2>&1 | grep "commands/implement-design"`
Expected: command assertions PASS

- [x] **Step 3: Commit**

```bash
git add commands/implement-design.md
git commit -m "feat: add /xgh implement-design command trigger"
```

---

## Chunk 3: `xgh:implement-ticket` Skill

### Task 6: Create the `xgh:implement-ticket` skill

**Files:**
- Create: `skills/implement-ticket/implement-ticket.md`

- [x] **Step 1: Create the implement-ticket skill directory**

```bash
mkdir -p skills/implement-ticket
```

- [x] **Step 2: Write the implement-ticket skill file**

Full content of `skills/implement-ticket/implement-ticket.md`:

````markdown
---
name: xgh:implement-ticket
description: "Full-context ticket implementation — from ticket to PR with cross-platform context gathering"
trigger: "/xgh implement"
mcp_dependencies:
  required: []
  optional:
    - atlassian: "Atlassian MCP — fetch ticket details, linked tickets, update status"
    - slack: "Slack MCP — search for ticket discussions, post implementation summary"
    - figma: "Figma MCP — fetch linked designs"
    - cipher: "Cipher MCP — search past work, conventions, store learnings"
---

# xgh:implement-ticket — Full-Context Ticket Implementation

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

**Detection procedure:**

1. Check if Atlassian MCP tools are available (look for `getJiraIssue` in available tools)
2. Check if Slack MCP tools are available (look for `slack_search_public` in available tools)
3. Check if Figma MCP tools are available (look for `get_design_context` in available tools)
4. Check if Cipher MCP tools are available (look for `cipher_memory_search` in available tools)

**Graceful degradation rules:**
- No task manager MCP → Ask user to paste ticket details (title, description, acceptance criteria). Skip ticket updates.
- No Slack MCP → Skip discussion search. Ask user about team decisions verbally.
- No Figma MCP → Skip design extraction. Ask user to describe UI requirements or confirm no UI changes.
- No Cipher MCP → Skip memory search. Rely on codebase scanning only. Save plan to docs/ only.
- No MCPs at all → Still works. User provides all context manually. Full Superpowers methodology applies.

Report which MCPs were detected at the start:
```
Available integrations:
  [x] Jira — will fetch ticket PROJ-1234, linked tickets, update status
  [x] Slack — will search for ticket discussions
  [ ] Figma — not configured, will ask about design requirements
  [x] Cipher Memory — will search past work and store learnings
```

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

Consider delegating to `xgh:implement-design` if the ticket is UI-heavy.

### Step 2.3: xgh Memory (if Cipher MCP available)

Use `mcp__cipher__cipher_memory_search` to search for:
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

Follow Superpowers brainstorming pattern — ONE question at a time, multiple choice preferred.

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

Wait for answer. Then:

```
Question 3 of 3:

The team convention #42 specifies token-bucket. The past /admin
rate limiter used sliding-window. Which algorithm?

  A) Token-bucket (matches convention #42)
  B) Sliding-window (matches existing /admin implementation)
  C) Fixed-window (simplest, but less smooth)

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

## Configuration
  ```yaml
  # src/config/rate-limits.yaml
  default:
    limit: 100
    window: 60  # seconds
    algorithm: token-bucket
  roles:
    admin:
      limit: 1000
  redis:
    key_prefix: "rl:"
    ttl: 60
  ```

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

  - [x] Write failing test for token-bucket consume()
  - [x] Verify fail: `npm test -- token-bucket`
  - [x] Implement TokenBucket class with consume() and refill()
  - [x] Verify pass: `npm test -- token-bucket`
  - [x] Commit: "feat(rate-limit): add token-bucket algorithm"

### Task 2: Rate limit config
  Files: src/config/rate-limits.yaml, src/config/rate-limits.ts

  - [x] Write failing test for config loading
  - [x] Verify fail: `npm test -- rate-limits`
  - [x] Create YAML config and TypeScript loader
  - [x] Verify pass: `npm test -- rate-limits`
  - [x] Commit: "feat(rate-limit): add rate limit configuration"

### Task 3: Rate limit middleware + unit tests
  Files: src/middleware/rate-limit.ts, src/middleware/rate-limit.test.ts

  - [x] Write failing test for middleware (returns headers)
  - [x] Verify fail: `npm test -- rate-limit.test`
  - [x] Implement middleware with Redis client
  - [x] Write failing test for 429 response
  - [x] Verify fail
  - [x] Implement 429 logic
  - [x] Write failing test for admin override
  - [x] Verify fail
  - [x] Implement admin override
  - [x] Verify all pass: `npm test -- rate-limit`
  - [x] Commit: "feat(rate-limit): add rate limit middleware"

### Task 4: Integration tests
  Files: tests/integration/rate-limit.test.ts

  - [x] Write integration test (supertest, real Redis or mock)
  - [x] Verify pass: `npm test -- integration/rate-limit`
  - [x] Commit: "test(rate-limit): add integration tests"

### Task 5: Wire up + documentation
  Files: src/app.ts, docs/api/rate-limiting.md

  - [x] Register middleware in app.ts
  - [x] Update API documentation
  - [x] Run full test suite: `npm test`
  - [x] Commit: "feat(rate-limit): register middleware and update docs"
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

### Step 6.4: Curate Learnings (if Cipher MCP available)

Use `mcp__cipher__cipher_extract_and_operate_memory` to store:
- Implementation patterns used (middleware pattern, config pattern)
- Decisions made and rationale (token-bucket vs sliding-window)
- New conventions established (rate limit config format)
- Integration points discovered

Save to context tree: `.xgh/context-tree/api-design/rate-limiting.md` (or appropriate domain)

### Step 6.5: Generate PR Context (compose with pr-context-bridge)

Generate a PR with full context for reviewers:
- Link to ticket
- Design decision rationale
- Test coverage summary
- Files changed with purpose annotations
- Reviewer guidance (what to look for)

---

## Skill Composition

`xgh:implement-ticket` composes with other xgh skills:

| Skill | When Used | Purpose |
|-------|-----------|---------|
| `xgh:implement-design` | When Figma designs are linked to the ticket | Delegates UI implementation |
| `xgh:investigate` | When ticket references a bug that needs root cause analysis first | Runs investigation before implementation |
| `xgh:subagent-pair-programming` | During Phase 6 execution | TDD enforcement and two-stage review |
| `xgh:convention-guardian` | During Phase 6 review | Checks implementation against team conventions |
| `xgh:pr-context-bridge` | During Phase 6 PR generation | Enriches PR with full context |

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
````

- [x] **Step 3: Run test to verify implement-ticket assertions pass**

Run: `bash tests/test-workflow-skills.sh 2>&1 | grep "implement-ticket"`
Expected: implement-ticket skill assertions PASS

- [x] **Step 4: Commit**

```bash
git add skills/implement-ticket/
git commit -m "feat: add xgh:implement-ticket workflow skill — full-context ticket implementation"
```

---

### Task 7: Create the `/xgh implement` command

**Files:**
- Create: `commands/implement.md`

- [x] **Step 1: Write the implement command file**

Full content of `commands/implement.md`:

````markdown
---
name: implement
description: "Implement a ticket with full cross-platform context gathering and Superpowers methodology"
usage: "/xgh implement [ticket-id]"
aliases: ["impl", "ticket"]
---

# /xgh implement

Implement a ticket end-to-end. Gathers context from every available source (ticket, Slack, Figma, xgh memory, codebase), interviews for missing context, proposes a design with trade-offs, generates a TDD implementation plan, and executes with subagent-driven development.

## Usage

```
/xgh implement <ticket-id>
/xgh implement PROJ-1234
/xgh implement
```

## Behavior

1. Load the `xgh:implement-ticket` skill from `skills/implement-ticket/implement-ticket.md`
2. Auto-detect available MCP integrations (Jira, Slack, Figma, Cipher)
3. If a ticket ID was provided, fetch it immediately
4. If no ticket ID was provided:
   - If task manager MCP available: search for recently assigned tickets
   - If not: ask user to describe the task
5. Execute all 6 phases of the implement-ticket workflow:
   - Phase 1: Ticket Deep Dive (fetch details, linked tickets, requirements)
   - Phase 2: Cross-Platform Context (Slack, Figma, memory, codebase)
   - Phase 3: Context Interview (Superpowers brainstorming, one question at a time)
   - Phase 4: Design Proposal (2-3 approaches, hard gate: approval required)
   - Phase 5: Implementation Plan (Superpowers writing-plans, TDD, exact paths)
   - Phase 6: Execute + Report (subagent-driven, update ticket, Slack, curate)

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `ticket-id` | No | Ticket ID (e.g., PROJ-1234). If omitted, searches assigned tickets or asks. |

## Examples

```
/xgh implement PROJ-1234
/xgh implement
```

## Related Skills

- `xgh:implement-ticket` — the full workflow skill this command triggers
- `xgh:implement-design` — delegates to this skill for UI-heavy tickets
- `xgh:investigate` — delegates to this skill when ticket references a bug needing root cause
````

- [x] **Step 2: Run test to check command assertions**

Run: `bash tests/test-workflow-skills.sh 2>&1 | grep "commands/implement"`
Expected: command assertions PASS

- [x] **Step 3: Commit**

```bash
git add commands/implement.md
git commit -m "feat: add /xgh implement command trigger"
```

---

## Chunk 4: Final Validation and Integration

### Task 8: Run full test suite and validate all files

- [x] **Step 1: Run the complete workflow skills test**

Run: `bash tests/test-workflow-skills.sh`
Expected output:
```
=== Skill file existence ===
=== Command file existence ===
=== investigate skill sections ===
=== investigate MCP references ===
=== investigate Superpowers patterns ===
=== investigate graceful degradation ===
=== implement-design skill sections ===
=== implement-design MCP references ===
=== implement-design Superpowers patterns ===
=== implement-ticket skill sections ===
=== implement-ticket MCP references ===
=== implement-ticket Superpowers patterns ===
=== Command-skill references ===

Results: NN passed, 0 failed
```

- [x] **Step 2: Verify all files are well-formed markdown**

```bash
# Check all skill files have YAML frontmatter
for f in skills/*//*.md; do
  head -1 "$f" | grep -q "^---" || echo "FAIL: $f missing frontmatter"
done

# Check all command files have YAML frontmatter
for f in commands/*.md; do
  head -1 "$f" | grep -q "^---" || echo "FAIL: $f missing frontmatter"
done

echo "All files validated"
```

- [x] **Step 3: Verify directory structure matches spec**

```bash
# Expected structure
ls -la skills/investigate/investigate.md
ls -la skills/implement-design/implement-design.md
ls -la skills/implement-ticket/implement-ticket.md
ls -la commands/investigate.md
ls -la commands/implement-design.md
ls -la commands/implement.md
```

Expected: All 6 files exist

- [x] **Step 4: Run any existing project tests to check for regressions**

```bash
# Run existing tests if they exist
for test in tests/test-*.sh; do
  [ -f "$test" ] && echo "Running $test..." && bash "$test"
done
```

Expected: All existing tests still pass

- [x] **Step 5: Final commit with all workflow skill files**

```bash
git add skills/ commands/ tests/test-workflow-skills.sh
git status  # Verify no secrets or large files
git commit -m "feat: complete workflow skills — investigate, implement-design, implement-ticket"
```

---

## Summary

After completing this plan, xgh has:

| Artifact | Status |
|----------|--------|
| `skills/investigate/investigate.md` | Complete — 4-phase Slack-driven debugging |
| `skills/implement-design/implement-design.md` | Complete — 5-phase Figma-driven UI implementation |
| `skills/implement-ticket/implement-ticket.md` | Complete — 6-phase full-context ticket implementation |
| `commands/investigate.md` | Complete — `/xgh investigate` command trigger |
| `commands/implement-design.md` | Complete — `/xgh implement-design` command trigger |
| `commands/implement.md` | Complete — `/xgh implement` command trigger |
| `tests/test-workflow-skills.sh` | Complete — validates all skills and commands |

### MCP Tools Referenced

| MCP | Tools Used |
|-----|-----------|
| **Slack** | `slack_read_thread`, `slack_search_public`, `slack_search_public_and_private`, `slack_send_message` |
| **Atlassian** | `getJiraIssue`, `searchJiraIssuesUsingJql`, `createJiraIssue`, `addCommentToJiraIssue`, `createIssueLink`, `getJiraIssueRemoteIssueLinks`, `transitionJiraIssue` |
| **Figma** | `get_design_context`, `get_screenshot`, `get_metadata`, `get_figjam`, `get_variable_defs`, `get_code_connect_map`, `send_code_connect_mappings`, `add_code_connect_map` |
| **Cipher** | `cipher_memory_search`, `cipher_extract_and_operate_memory`, `cipher_store_reasoning_memory` |

### Superpowers Patterns Used

| Pattern | Where |
|---------|-------|
| Iron Law: no fixes without root cause | investigate Phase 3 |
| Hard gate: 3 failed hypotheses | investigate Phase 3 |
| Hard gate: no implementation without approved design | implement-ticket Phase 4 |
| Brainstorming: one question at a time | implement-ticket Phase 3 |
| Writing-plans: 2-5 min tasks, TDD, exact paths | implement-design Phase 4, implement-ticket Phase 5 |
| Subagent-driven development | implement-design Phase 4, implement-ticket Phase 6 |
| Two-stage review | implement-design Phase 4, implement-ticket Phase 6 |

### Skill Composition Map

```
/xgh implement PROJ-1234
        │
        ├── Phase 2: If Figma linked → delegates to xgh:implement-design
        ├── Phase 2: If bug ticket → delegates to xgh:investigate
        │
        ├── Phase 6: xgh:subagent-pair-programming (TDD enforcement)
        ├── Phase 6: xgh:convention-guardian (convention checks)
        └── Phase 6: xgh:pr-context-bridge (PR enrichment)
```

**Next:** Integration testing with live MCP servers (Slack, Figma, Atlassian) to verify tool calls work end-to-end.
