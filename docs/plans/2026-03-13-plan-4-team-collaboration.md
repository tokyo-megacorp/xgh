# Team Collaboration Skills Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Implement the 6 team collaboration skills, the `/xgh-collaborate` command, and the collaboration-dispatcher agent that together enable async team knowledge sharing through Cipher workspace memory.

**Architecture:** Each skill is a markdown file in `skills/<name>/<name>.md` with structured sections (Iron Law, Rationalization Table, Process, Tool References). The `/xgh-collaborate` command dispatches multi-agent workflows. The collaboration-dispatcher agent orchestrates inter-agent messaging through Cipher workspace. All skills reference Cipher MCP tools by name and compose with each other.

**Tech Stack:** Markdown (skills, commands, agents), Bash (tests), Cipher MCP tools (cipher_memory_search, cipher_extract_and_operate_memory, cipher_store_reasoning_memory, cipher_search_reasoning_patterns)

**Design doc:** `docs/plans/2026-03-13-xgh-design.md` — Sections 5, 6, 10

---

## File Structure

```
skills/
├── pr-context-bridge/
│   └── pr-context-bridge.md          # Skill: auto-curate PR reasoning
├── knowledge-handoff/
│   └── knowledge-handoff.md          # Skill: structured handoff on merge
├── convention-guardian/
│   └── convention-guardian.md        # Skill: enforce team conventions
├── cross-team-pollinator/
│   └── cross-team-pollinator.md      # Skill: org-wide knowledge sharing
├── subagent-pair-programming/
│   └── subagent-pair-programming.md  # Skill: TDD via spec writer + implementer
├── onboarding-accelerator/
│   └── onboarding-accelerator.md     # Skill: new dev context bootstrapping
commands/
├── collaborate.md                     # /xgh-collaborate command
agents/
├── collaboration-dispatcher.md        # Subagent for multi-agent orchestration
tests/
├── test-team-skills.sh               # Tests for all 6 skills
├── test-collaborate-command.sh        # Tests for the collaborate command
├── test-collaboration-agent.sh        # Tests for the dispatcher agent
```

---

## Chunk 1: PR Context Bridge & Knowledge Handoff Skills

### Task 1: Write tests for pr-context-bridge and knowledge-handoff skills

**Files:**
- Create: `tests/test-team-skills.sh`

- [x] **Step 1: Write test harness for all 6 team collaboration skills**

Create the test file with assertions for file existence, required sections, and key content for all skills. We write the full test file now so each subsequent task can run the relevant subset.

```bash
cat > tests/test-team-skills.sh << 'TESTEOF'
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

assert_section() {
  if grep -q "^## $2" "$1" 2>/dev/null || grep -q "^### $2" "$1" 2>/dev/null; then
    ((PASS++))
  else
    echo "FAIL: $1 missing section '$2'"
    ((FAIL++))
  fi
}

echo "=== Team Collaboration Skills Tests ==="

# ── pr-context-bridge ──────────────────────────────────
echo ""
echo "--- pr-context-bridge ---"
SKILL="skills/pr-context-bridge/pr-context-bridge.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_contains "$SKILL" "Rationalization Table"
assert_section "$SKILL" "Author Flow"
assert_section "$SKILL" "Reviewer Flow"
assert_contains "$SKILL" "cipher_store_reasoning_memory"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "thread"
assert_contains "$SKILL" "type: context"
assert_contains "$SKILL" "tradeoff"

# ── knowledge-handoff ──────────────────────────────────
echo ""
echo "--- knowledge-handoff ---"
SKILL="skills/knowledge-handoff/knowledge-handoff.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_contains "$SKILL" "Rationalization Table"
assert_section "$SKILL" "Handoff Summary Structure"
assert_section "$SKILL" "Trigger"
assert_contains "$SKILL" "cipher_extract_and_operate_memory"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "scope: handoff"
assert_contains "$SKILL" "gotcha"
assert_contains "$SKILL" "pattern"

# ── convention-guardian ────────────────────────────────
echo ""
echo "--- convention-guardian ---"
SKILL="skills/convention-guardian/convention-guardian.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_contains "$SKILL" "Rationalization Table"
assert_section "$SKILL" "Convention Storage Format"
assert_section "$SKILL" "Query Process"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "type: convention"
assert_contains "$SKILL" "scope: team"
assert_contains "$SKILL" "maturity: core"
assert_contains "$SKILL" "history"

# ── cross-team-pollinator ─────────────────────────────
echo ""
echo "--- cross-team-pollinator ---"
SKILL="skills/cross-team-pollinator/cross-team-pollinator.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_section "$SKILL" "Promotion Rules"
assert_section "$SKILL" "Query Merging"
assert_contains "$SKILL" "_shared/"
assert_contains "$SKILL" "scope: org"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "cipher_store_reasoning_memory"

# ── subagent-pair-programming ─────────────────────────
echo ""
echo "--- subagent-pair-programming ---"
SKILL="skills/subagent-pair-programming/subagent-pair-programming.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_contains "$SKILL" "Rationalization Table"
assert_section "$SKILL" "Spec Writer"
assert_section "$SKILL" "Implementer"
assert_section "$SKILL" "Orchestrator"
assert_contains "$SKILL" "cipher_store_reasoning_memory"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "thread"
assert_contains "$SKILL" "type: test-spec"
assert_contains "$SKILL" "status: RED"
assert_contains "$SKILL" "status: GREEN"

# ── onboarding-accelerator ────────────────────────────
echo ""
echo "--- onboarding-accelerator ---"
SKILL="skills/onboarding-accelerator/onboarding-accelerator.md"
assert_file_exists "$SKILL"
assert_contains "$SKILL" "Iron Law"
assert_section "$SKILL" "Knowledge Categories"
assert_section "$SKILL" "Onboarding Session Flow"
assert_contains "$SKILL" "cipher_memory_search"
assert_contains "$SKILL" "architecture"
assert_contains "$SKILL" "convention"
assert_contains "$SKILL" "gotcha"
assert_contains "$SKILL" "incident"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
TESTEOF
chmod +x tests/test-team-skills.sh
```

- [x] **Step 2: Run tests — verify all fail (no skill files exist yet)**

```bash
bash tests/test-team-skills.sh
# Expected: 0 passed, ~50 failed (all assertions fail)
```

### Task 2: Implement pr-context-bridge skill

**Files:**
- Create: `skills/pr-context-bridge/pr-context-bridge.md`

- [x] **Step 3: Create pr-context-bridge skill**

```bash
mkdir -p skills/pr-context-bridge
cat > skills/pr-context-bridge/pr-context-bridge.md << 'SKILLEOF'
# xgh:pr-context-bridge

> Auto-curate PR reasoning to Cipher workspace so reviewers get deep context without meetings.

## Iron Law

> **EVERY PR MUST CARRY ITS REASONING.** Code diffs show WHAT changed. This skill ensures the WHY is never lost — approaches considered, tradeoffs made, tricky parts flagged.

## Rationalization Table

| Agent Thought | Reality |
|---|---|
| "The diff is self-explanatory" | Diffs show what changed, never why approach B was chosen over A |
| "I'll just write a good PR description" | PR descriptions are written once; reasoning traces capture the journey |
| "This is a small change, no context needed" | Small changes with non-obvious reasoning cause the longest review debates |
| "The reviewer can just ask me" | Async teams can't ask — and by next week, even the author forgets |
| "Storing reasoning slows me down" | 30 seconds of curation saves 30 minutes of review back-and-forth |

## When This Skill Activates

- **Author side**: Automatically during development when working on a branch that will become a PR
- **Reviewer side**: Automatically when opening/reviewing a PR (detected by context: PR URL, branch name, review request)

---

## Author Flow

### Phase 1: Continuous Reasoning Capture (during development)

As the author works on a feature branch, the following reasoning is auto-curated to Cipher workspace:

**Step 1: Initialize PR thread**

When work begins on a feature branch, create a Cipher thread:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: "Starting work on [branch-name]: [ticket/description]"
  metadata:
    thread: PR-[branch-name]
    type: context
    scope: pr
    status: in_progress
    from_agent: claude-code
```

**Step 2: Capture decision points**

Whenever a non-trivial decision is made (approach selection, tradeoff, architecture choice):

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Decision: [what was decided]
    Alternatives considered:
    - A: [approach A] — rejected because [reason]
    - B: [approach B] — chosen because [reason]
    - C: [approach C] — rejected because [reason]
    Key tradeoff: [e.g., latency vs consistency]
    Confidence: [high/medium/low]
  metadata:
    thread: PR-[branch-name]
    type: context
    subtype: decision
    files: [list of affected files]
```

**Step 3: Flag tricky parts**

When implementation involves non-obvious logic, subtle edge cases, or workarounds:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Tricky part: [file:line or function name]
    What's non-obvious: [explanation]
    Why it's done this way: [reasoning]
    What could go wrong: [edge cases, failure modes]
    Related: [links to docs, issues, past decisions]
  metadata:
    thread: PR-[branch-name]
    type: context
    subtype: tricky-part
    files: [affected files]
```

**Step 4: Capture related prior knowledge**

When memory queries during development surface relevant past decisions:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    This PR relates to prior decision: [summary]
    How it connects: [explanation]
    Consistency check: [does this PR align or intentionally diverge?]
  metadata:
    thread: PR-[branch-name]
    type: context
    subtype: related-context
```

### Phase 2: Pre-Push Summary

Before pushing (or when the author signals the PR is ready):

**Step 5: Generate PR reasoning summary**

```
Tool: cipher_memory_search
Parameters:
  query: "thread:PR-[branch-name] reasoning decisions tradeoffs"
  scope: workspace
```

Compile all thread entries into a structured summary and store:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    # PR Context Summary: [branch-name]

    ## What this PR does
    [1-2 sentence summary]

    ## Key decisions
    [Numbered list of decisions with brief rationale]

    ## Tradeoffs made
    [What was traded for what, and why]

    ## Tricky parts (reviewer: pay attention here)
    [List of files/functions that need careful review, with explanation]

    ## Related prior decisions
    [Links to team knowledge that informed this work]

    ## What I'd do differently
    [Hindsight notes, if any]
  metadata:
    thread: PR-[branch-name]
    type: context
    subtype: summary
    status: ready_for_review
```

---

## Reviewer Flow

### Phase 1: Context Loading

When a reviewer's Claude session detects PR review context (PR URL, `gh pr checkout`, review request):

**Step 1: Query for PR reasoning**

```
Tool: cipher_memory_search
Parameters:
  query: "thread:PR-[branch-name] context decisions tradeoffs tricky-parts summary"
  scope: workspace
```

**Step 2: Present context to reviewer**

Format the retrieved reasoning as a briefing:

```
┌─ PR Context Bridge ──────────────────────────────────────┐
│                                                            │
│  PR: [title] by [author]                                   │
│  Branch: [branch-name]                                     │
│                                                            │
│  Key decisions:                                            │
│  1. [decision] — because [reason]                          │
│  2. [decision] — because [reason]                          │
│                                                            │
│  Tricky parts (review carefully):                          │
│  - [file:function] — [why it's tricky]                     │
│                                                            │
│  Tradeoffs:                                                │
│  - [traded X for Y because Z]                              │
│                                                            │
│  Related team knowledge:                                   │
│  - [prior decision that informed this work]                │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Phase 2: Review Feedback Loop

**Step 3: Store review feedback back to thread**

When the reviewer identifies issues, questions, or insights:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Review feedback: [what was found]
    Question: [if applicable]
    Suggestion: [if applicable]
    Applies to: [file:line]
  metadata:
    thread: PR-[branch-name]
    type: feedback
    subtype: review
    from_agent: claude-code
    for_agent: "*"
```

**Step 4: Author reads review context**

When the author returns to address review comments, their Claude queries the thread for new feedback entries, getting the reviewer's reasoning alongside GitHub comments.

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_store_reasoning_memory` | Store decisions, tricky parts, summaries, and review feedback to PR thread |
| `cipher_memory_search` | Query PR thread for reasoning context (reviewer side) |
| `cipher_extract_and_operate_memory` | Extract reasoning from session for auto-curation |

## Composability

- Works with **convention-guardian**: PR reasoning includes which conventions were followed
- Works with **knowledge-handoff**: PR context feeds into post-merge handoff
- Works with **subagent-pair-programming**: Spec writer and implementer reasoning both stored to PR thread
SKILLEOF
```

- [x] **Step 4: Run pr-context-bridge tests — verify pass**

```bash
bash tests/test-team-skills.sh 2>&1 | grep -A1 "pr-context-bridge"
# Expected: all pr-context-bridge assertions pass
```

### Task 3: Implement knowledge-handoff skill

**Files:**
- Create: `skills/knowledge-handoff/knowledge-handoff.md`

- [x] **Step 5: Create knowledge-handoff skill**

```bash
mkdir -p skills/knowledge-handoff
cat > skills/knowledge-handoff/knowledge-handoff.md << 'SKILLEOF'
# xgh:knowledge-handoff

> On branch merge, generate a structured handoff summary so the next developer touching that area gets full context — patterns, gotchas, key files, warnings — without meetings.

## Iron Law

> **EVERY MERGE MUST LEAVE A TRAIL.** When your work merges, the next person touching those files deserves your hard-won context. No handoff = knowledge lost forever.

## Rationalization Table

| Agent Thought | Reality |
|---|---|
| "The code is clean enough to speak for itself" | Clean code shows current state, not the gotchas discovered getting there |
| "Nobody else will touch this area soon" | You don't know that. And when they do, you won't remember the details |
| "The PR description covers it" | PR descriptions describe one change; handoffs describe the territory |
| "This is just a refactor, nothing to hand off" | Refactors are the most important to document — they change the map |
| "Generating a handoff summary takes too long" | 60 seconds now prevents 2 hours of archaeology later |

## Trigger

This skill activates when:
1. A branch is merged to the main/default branch
2. The merged changes touch files in a recognized domain area
3. The session-end hook fires after merge-related work

The hook detects merge context via:
- `git log --merges` showing recent merge commits
- Branch deletion after merge
- PR merge event (if working with GitHub/GitLab)

---

## Handoff Summary Structure

The handoff summary follows a fixed structure optimized for the next developer's Claude to consume:

```yaml
---
title: "Handoff: [area/feature name]"
tags: [handoff, area-tag-1, area-tag-2]
keywords: [specific-terms, file-names, function-names]
importance: 75
maturity: validated
type: handoff
scope: handoff
source: auto-curate
fromAgent: claude-code
createdAt: [ISO timestamp]
mergedBranch: [branch-name]
affectedFiles: [list of key files]
---
```

### Content Sections

```markdown
## What Changed
[1-3 sentence summary of the merged work]

## Patterns Discovered
- [Pattern 1]: [description + where it applies]
- [Pattern 2]: [description + where it applies]
(Patterns the next developer should follow when extending this area)

## Gotchas and Warnings
- [Gotcha 1]: [what seems obvious but isn't, and why]
- [Gotcha 2]: [edge case that bit you, and how to avoid it]
(Things that will waste the next developer's time if not known)

## Key Files
- `[path/to/file.ts]` — [role: what this file does and why it matters]
- `[path/to/other.ts]` — [role: entry point / config / critical path]
(The files the next developer should read first)

## Architecture Decisions
- [Decision]: [what was decided + rationale]
- [Decision]: [what was decided + rationale]
(Decisions that constrain future work in this area)

## Testing Notes
- [What's tested and how]
- [What's NOT tested and why]
- [How to run relevant tests]

## Open Questions
- [Question the next developer might face]
- [Known limitation that needs future work]
```

---

## Process

### Step 1: Gather merge context

When merge is detected:

```
Tool: cipher_memory_search
Parameters:
  query: "[branch-name] decisions patterns implementation"
  scope: workspace
```

Also gather from the PR context bridge thread (if available):

```
Tool: cipher_memory_search
Parameters:
  query: "thread:PR-[branch-name] context summary"
  scope: workspace
```

### Step 2: Analyze affected files

Identify which domain areas were touched by the merge. Use git diff to find:
- Files changed
- Directories affected
- Modules/domains impacted

### Step 3: Extract learnings from session

```
Tool: cipher_extract_and_operate_memory
Parameters:
  operation: extract
  context: "Merge of [branch-name]. Extract patterns, gotchas, key files, architecture decisions, and warnings for the next developer."
```

### Step 4: Generate and store handoff summary

Compile the gathered information into the handoff structure above.

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: [compiled handoff summary in the structure above]
  metadata:
    type: handoff
    scope: handoff
    thread: handoff-[branch-name]
    domain: [detected domain]
    affectedFiles: [list of changed files]
    status: completed
```

### Step 5: Sync to context tree

Write the handoff to the context tree at the appropriate domain path:
```
.xgh/context-tree/[domain]/handoffs/[date]-[branch-name].md
```

### Step 6: Auto-query for next developer

When any developer's Claude touches files that were part of a recent handoff, the session-start hook queries:

```
Tool: cipher_memory_search
Parameters:
  query: "handoff [file-path] gotchas patterns warnings"
  scope: workspace
  filter:
    type: handoff
    affectedFiles: [current file]
```

The retrieved handoff context is injected into the developer's session automatically.

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_extract_and_operate_memory` | Extract session learnings for handoff summary generation |
| `cipher_store_reasoning_memory` | Store the compiled handoff summary to workspace |
| `cipher_memory_search` | Query PR thread context; auto-query handoffs for next developer |

## Composability

- Consumes from **pr-context-bridge**: Uses PR reasoning thread as input for handoff
- Feeds into **onboarding-accelerator**: Handoff summaries are surfaced during onboarding
- Feeds into **convention-guardian**: Patterns discovered in handoffs may become conventions
SKILLEOF
```

- [x] **Step 6: Run knowledge-handoff tests — verify pass**

```bash
bash tests/test-team-skills.sh 2>&1 | grep -A1 "knowledge-handoff"
# Expected: all knowledge-handoff assertions pass
```

- [x] **Step 7: Run full test suite — verify pr-context-bridge and knowledge-handoff pass**

```bash
bash tests/test-team-skills.sh
# Expected: ~20 passed (pr-context-bridge + knowledge-handoff), remaining fail
```

- [x] **Step 8: Commit chunk 1**

```bash
git add skills/pr-context-bridge/ skills/knowledge-handoff/ tests/test-team-skills.sh
git commit -m "feat: add pr-context-bridge and knowledge-handoff skills

Implements the first two team collaboration skills:
- pr-context-bridge: auto-curates PR reasoning (decisions, tradeoffs,
  tricky parts) to Cipher workspace for reviewer context
- knowledge-handoff: generates structured handoff summaries on merge
  with patterns, gotchas, key files, and warnings

Includes test harness for all 6 team collaboration skills."
```

---

## Chunk 2: Convention Guardian & Cross-Team Pollinator Skills

### Task 4: Implement convention-guardian skill

**Files:**
- Create: `skills/convention-guardian/convention-guardian.md`

- [x] **Step 1: Create convention-guardian skill**

```bash
mkdir -p skills/convention-guardian
cat > skills/convention-guardian/convention-guardian.md << 'SKILLEOF'
# xgh:convention-guardian

> Automatically query and enforce team conventions before coding. Conventions are stored as structured memories in Cipher with `type: convention, scope: team` and enforced by the continuous-learning hook.

## Iron Law

> **NO CODE WITHOUT CHECKING CONVENTIONS FIRST.** Before writing ANY code, query Cipher for team conventions that apply to the current domain. Conventions are team decisions — not suggestions.

## Rationalization Table

| Agent Thought | Reality |
|---|---|
| "I know the standard patterns for this" | Your training data patterns are NOT this team's conventions |
| "This is a simple utility, no conventions apply" | Naming, error handling, and testing conventions apply to ALL code |
| "The convention seems wrong for this case" | Raise the question — don't silently deviate. Conventions evolve through discussion |
| "I already checked conventions at session start" | Conventions are domain-specific. Check again when switching domains |
| "There are no conventions for this area yet" | That's useful to know. Flag it and propose one after implementation |

## Convention Storage Format

Conventions are stored in Cipher with structured metadata:

```yaml
type: convention
scope: team          # team-wide convention
maturity: core       # core = non-negotiable, validated = strong recommendation, draft = proposal
domain: [area]       # e.g., "api-design", "testing", "error-handling", "naming"
tags: [relevant tags]
version: [n]         # incremented on updates, history preserved
supersedes: [id]     # if this convention replaces an older one
```

### Convention Content Structure

```markdown
## Convention: [Short Name]

**Rule:** [The convention stated as a clear, actionable rule]

**Rationale:** [Why this convention exists — the problem it prevents]

**Examples:**
- Correct: [code example following the convention]
- Incorrect: [code example violating the convention]

**Exceptions:** [When it's acceptable to deviate, if ever]

**History:**
- v1 (date): [Original convention]
- v2 (date): [Updated because...] (supersedes: [old-id])
```

---

## Query Process

### Step 1: Identify applicable domains

Before writing code, determine which convention domains apply:
- What kind of code is being written? (API endpoint, UI component, test, migration, etc.)
- What domain area? (authentication, payments, data-access, etc.)
- What language/framework patterns? (React, Go, Swift, etc.)

### Step 2: Query conventions

```
Tool: cipher_memory_search
Parameters:
  query: "[domain] [code-type] convention rules patterns"
  scope: workspace
  filter:
    type: convention
    scope: team
    maturity: core OR validated
```

### Step 3: Present applicable conventions

Format discovered conventions as a checklist:

```
┌─ Convention Guardian ────────────────────────────────────┐
│                                                            │
│  Applicable conventions for [domain/code-type]:            │
│                                                            │
│  [CORE] Use protocol+factory for ViewControllers           │
│         → 5+ consumers, need feature flag support          │
│                                                            │
│  [CORE] All API errors return structured ErrorResponse     │
│         → { code, message, details, requestId }            │
│                                                            │
│  [VALIDATED] Prefer composition over inheritance for       │
│              data transformers                             │
│                                                            │
│  No conventions found for: [subdomain]                     │
│  → Consider proposing one after implementation             │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Step 4: Enforce during implementation

As code is written, verify each convention is followed. If a deviation is necessary:

1. **State the deviation explicitly** — never deviate silently
2. **Document the reason** — why this case is an exception
3. **Store as a question** — flag for team discussion

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Convention deviation detected:
    Convention: [name] (maturity: [core/validated])
    Deviation: [what was done differently]
    Reason: [why]
    Recommendation: [update convention / add exception / revert deviation]
  metadata:
    type: convention-deviation
    scope: team
    thread: [current branch/PR thread]
    convention_id: [id of the convention]
```

### Step 5: Propose new conventions

When patterns emerge during implementation that should become conventions:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    ## Convention Proposal: [Short Name]

    **Rule:** [proposed rule]
    **Rationale:** [why this should be a convention]
    **Evidence:** [where this pattern was discovered/validated]
    **Examples:** [code examples]
  metadata:
    type: convention
    scope: team
    maturity: draft
    domain: [area]
    status: proposed
```

---

## Convention Evolution

Conventions evolve. They are NEVER silently deleted.

### Updating a convention

1. Create the new version with `supersedes: [old-id]`
2. Increment the `version` field
3. Add history entry explaining the change
4. Old version remains searchable for audit trail

### Promoting conventions

- `draft` → `validated`: Convention has been followed successfully in 3+ PRs
- `validated` → `core`: Convention has been followed for 2+ sprints with no exceptions needed

### Demoting conventions

- Only through explicit team decision
- Old convention marked `deprecated` with reason
- New convention (or removal) documented with rationale

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_memory_search` | Query conventions by domain, type, scope, and maturity |
| `cipher_store_reasoning_memory` | Store new conventions, deviations, and proposals |
| `cipher_extract_and_operate_memory` | Extract emerging patterns that may become conventions |

## Composability

- Works with **continuous-learning hook**: Hook triggers convention check on every prompt
- Feeds from **knowledge-handoff**: Handoff patterns may become conventions
- Feeds into **pr-context-bridge**: PR reasoning includes which conventions were followed
- Feeds into **cross-team-pollinator**: Team conventions may promote to org-scope
- Feeds into **onboarding-accelerator**: Core conventions surfaced during onboarding
SKILLEOF
```

- [x] **Step 2: Run convention-guardian tests — verify pass**

```bash
bash tests/test-team-skills.sh 2>&1 | grep -A1 "convention-guardian"
# Expected: all convention-guardian assertions pass
```

### Task 5: Implement cross-team-pollinator skill

**Files:**
- Create: `skills/cross-team-pollinator/cross-team-pollinator.md`

- [x] **Step 3: Create cross-team-pollinator skill**

```bash
mkdir -p skills/cross-team-pollinator
cat > skills/cross-team-pollinator/cross-team-pollinator.md << 'SKILLEOF'
# xgh:cross-team-pollinator

> Break knowledge silos between teams. The `_shared/` directory in each team's context tree auto-promotes to `scope: org` in Cipher workspace. Other teams' hooks query org-scoped memories alongside their own.

## Iron Law

> **CROSS-TEAM KNOWLEDGE MUST FLOW BOTH WAYS.** When you discover something that affects other teams, share it. When querying memory, always include org-scope results. Silos form by default — sharing requires intention.

## When This Skill Activates

- **Promotion**: When knowledge is curated to the `_shared/` directory of the context tree
- **Query enrichment**: On every `cipher_memory_search` call, org-scoped results are merged alongside team-scoped results
- **Discovery**: When implementation touches an API boundary, shared library, or cross-team contract

---

## Promotion Rules

### What gets promoted to org-scope

Knowledge qualifies for org-scope promotion when it:
1. Lives in the `_shared/` directory of the context tree
2. Has `maturity: validated` or `maturity: core`
3. Describes an interface, contract, or convention that affects other teams

### Automatic promotion

When a file is written to or moved to `_shared/`:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: [the shared knowledge content]
  metadata:
    type: [original type]
    scope: org
    origin_team: [team name from config]
    origin_path: [context tree path]
    maturity: [validated or core]
    tags: [original tags + "cross-team"]
```

### What belongs in `_shared/`

```
.xgh/context-tree/
├── _shared/                          # Auto-promotes to scope: org
│   ├── api-contracts/
│   │   └── user-response-format.md   # "UserResponse.role is optional"
│   ├── conventions/
│   │   └── date-format-iso.md        # "All dates must be ISO 8601"
│   ├── infrastructure/
│   │   └── auth-middleware.md         # "Use shared auth middleware v2"
│   └── warnings/
│       └── legacy-api-v1-compat.md   # "Don't break v1 backward compat"
├── authentication/                    # Team-only (scope: team)
│   └── ...
└── api-design/                        # Team-only (scope: team)
    └── ...
```

---

## Query Merging

### How org-scope memories are included

Every `cipher_memory_search` call in an xgh-enabled project includes BOTH scopes:

**Step 1: Team-scope query**

```
Tool: cipher_memory_search
Parameters:
  query: "[the user's question or task context]"
  scope: workspace
  filter:
    scope: team
    team: [current team name]
```

**Step 2: Org-scope query**

```
Tool: cipher_memory_search
Parameters:
  query: "[the user's question or task context]"
  scope: workspace
  filter:
    scope: org
```

**Step 3: Merge and rank results**

Results from both queries are merged with the following ranking:
```
score = (0.5 * relevance_score + 0.3 * maturity_boost + 0.2 * recency)
```

Where:
- Team-scope results with `maturity: core` get a 1.15x boost
- Org-scope results get a 1.0x baseline (no penalty for being org-level)
- Origin team is displayed so the developer knows who shared it

### Presentation

```
┌─ Cross-Team Knowledge ───────────────────────────────────┐
│                                                            │
│  From your team (my-team):                                 │
│  [CORE] Use token-bucket for rate limiting                 │
│                                                            │
│  From other teams:                                         │
│  [ORG/backend-team] UserResponse.role is optional          │
│                      for backward compat with v1           │
│  [ORG/platform-team] New shared auth middleware supports   │
│                      OAuth2 + API keys — use it            │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## Sharing Workflow

### When a developer discovers cross-team knowledge

1. **Recognize it**: "This affects other teams" — API format changes, shared library updates, contract changes
2. **Curate to `_shared/`**: Write or move the knowledge file to `_shared/[category]/`
3. **Auto-promotion fires**: The file is stored to Cipher with `scope: org`
4. **Other teams benefit**: Their next `cipher_memory_search` includes this knowledge

### Promoting existing team knowledge to org

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    [Existing team knowledge that should be shared]
    Origin: [team name]
    Why shared: [reason this matters to other teams]
  metadata:
    type: [original type]
    scope: org
    origin_team: [team name]
    maturity: [current maturity]
    promoted_from: [context tree path]
```

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_memory_search` | Query both team-scope and org-scope memories |
| `cipher_store_reasoning_memory` | Store org-promoted knowledge to workspace |
| `cipher_extract_and_operate_memory` | Extract cross-team relevant learnings |

## Composability

- Consumes from **convention-guardian**: Team conventions may promote to org-scope
- Consumes from **knowledge-handoff**: Handoff discoveries that affect other teams
- Feeds into **onboarding-accelerator**: Org-scope knowledge surfaced during onboarding
- Works with **pr-context-bridge**: Cross-team context included in PR reasoning
SKILLEOF
```

- [x] **Step 4: Run cross-team-pollinator tests — verify pass**

```bash
bash tests/test-team-skills.sh 2>&1 | grep -A1 "cross-team-pollinator"
# Expected: all cross-team-pollinator assertions pass
```

- [x] **Step 5: Run full test suite — verify 4 skills pass**

```bash
bash tests/test-team-skills.sh
# Expected: ~35 passed (4 skills), remaining fail
```

- [x] **Step 6: Commit chunk 2**

```bash
git add skills/convention-guardian/ skills/cross-team-pollinator/
git commit -m "feat: add convention-guardian and cross-team-pollinator skills

- convention-guardian: auto-queries team conventions before coding,
  enforces them during implementation, tracks history and evolution
- cross-team-pollinator: _shared/ directory auto-promotes to org-scope
  in Cipher workspace, query merging includes both team and org results"
```

---

## Chunk 3: Subagent Pair Programming & Onboarding Accelerator Skills

### Task 6: Implement subagent-pair-programming skill

**Files:**
- Create: `skills/subagent-pair-programming/subagent-pair-programming.md`

- [x] **Step 1: Create subagent-pair-programming skill**

```bash
mkdir -p skills/subagent-pair-programming
cat > skills/subagent-pair-programming/subagent-pair-programming.md << 'SKILLEOF'
# xgh:subagent-pair-programming

> Dispatch two subagents — a Spec Writer and an Implementer — that coordinate through Cipher memory. The Spec Writer writes failing tests; the Implementer writes minimal code to pass. TDD enforced by architecture, not willpower.

## Iron Law

> **THE SPEC WRITER AND IMPLEMENTER MUST NEVER BE THE SAME AGENT.** Separation of concerns is physical, not logical. The spec writer cannot see the implementation; the implementer cannot modify the tests. Cipher memory is the contract between them.

## Rationalization Table

| Agent Thought | Reality |
|---|---|
| "I can do TDD in a single agent — just write tests first" | Single agents cheat by peeking at implementation while writing specs |
| "Two subagents is overkill for a small feature" | Small features are where TDD habits form. Skip it here, skip it everywhere |
| "The spec writer doesn't have enough context to write good tests" | That's exactly the point — specs should be writeable from requirements alone |
| "Coordinating through Cipher is slower than just coding" | Slower per-task, but catches design flaws that would cost 10x to fix later |
| "The implementer needs to modify tests for edge cases" | Edge cases go back to the spec writer. Round-trip is the feature, not the bug |

## When This Skill Activates

- Explicitly via `/xgh pair-program "[task description]"`
- Automatically for large implementation tasks (configurable threshold)
- When the `implement-ticket` skill dispatches TDD execution

---

## Orchestrator

The orchestrator (the main Claude session) manages the pair programming workflow:

### Step 1: Task decomposition

Break the work into TDD-sized units. Each unit should:
- Be testable in isolation
- Take 2-5 minutes to implement
- Have clear inputs and outputs

### Step 2: Initialize thread

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Pair programming session started.
    Task: [description]
    Units:
    1. [unit description]
    2. [unit description]
    ...
  metadata:
    thread: pair-[session-id]
    type: orchestration
    status: in_progress
```

### Step 3: Dispatch Spec Writer (per unit)

Dispatch a fresh subagent with ONLY these inputs:
- The unit description (what to test)
- Team conventions from Cipher (testing patterns)
- The thread ID for storing specs

The spec writer has NO access to:
- Existing implementation code
- The implementer's work
- Other units' implementations

### Step 4: Dispatch Implementer (per unit)

Dispatch a fresh subagent with ONLY these inputs:
- The test specs from the Cipher thread
- Team conventions from Cipher (coding patterns)
- The thread ID for storing implementation

The implementer has NO access to:
- The spec writer's reasoning (only the test code)
- Future unit specs
- The orchestrator's full plan

### Step 5: Review both outputs

The orchestrator reviews:
- Do tests actually fail before implementation? (RED)
- Does implementation make tests pass? (GREEN)
- Is implementation minimal (no gold-plating)?
- Are conventions followed?

### Step 6: Iterate or advance

If review finds issues:
- Send feedback to the appropriate subagent via Cipher thread
- Subagent re-does their work with the feedback

If review passes:
- Mark unit complete
- Advance to next unit

---

## Spec Writer

The spec writer subagent follows this process:

### Phase 1: Context gathering

```
Tool: cipher_memory_search
Parameters:
  query: "[domain] testing patterns conventions"
  scope: workspace
  filter:
    type: convention
    domain: testing
```

### Phase 2: Write failing tests

Write tests based ONLY on the unit description and requirements. Tests must:
- Be runnable
- Fail for the right reason (missing implementation, not syntax errors)
- Cover the happy path and key edge cases
- Follow team testing conventions

### Phase 3: Store specs to thread

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    ## Test Spec: [unit name]

    ### Test file: [path]
    ```[language]
    [complete test code]
    ```

    ### Expected behavior:
    - [assertion 1]: [why]
    - [assertion 2]: [why]

    ### Edge cases covered:
    - [edge case 1]
    - [edge case 2]

    ### Run command:
    [exact command to run tests]
  metadata:
    thread: pair-[session-id]
    type: test-spec
    unit: [unit-number]
    status: RED
    files: [test file path]
```

### Phase 4: Verify RED

Run the tests and confirm they fail:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: "Tests verified RED. [N] tests, [N] failures. Failures are for the right reason: [missing implementation]."
  metadata:
    thread: pair-[session-id]
    type: test-spec
    unit: [unit-number]
    status: RED
    verified: true
```

---

## Implementer

The implementer subagent follows this process:

### Phase 1: Read specs from thread

```
Tool: cipher_memory_search
Parameters:
  query: "thread:pair-[session-id] unit:[unit-number] test-spec"
  scope: workspace
  filter:
    type: test-spec
    status: RED
```

### Phase 2: Query conventions

```
Tool: cipher_memory_search
Parameters:
  query: "[domain] implementation patterns conventions"
  scope: workspace
  filter:
    type: convention
```

### Phase 3: Write minimal implementation

Write ONLY enough code to make the failing tests pass. Rules:
- No code that isn't required by a test
- No premature optimization
- No speculative features
- Follow team conventions

### Phase 4: Store implementation to thread

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    ## Implementation: [unit name]

    ### File: [path]
    ```[language]
    [complete implementation code]
    ```

    ### Decisions made:
    - [decision 1]: [why]

    ### Conventions followed:
    - [convention 1]
  metadata:
    thread: pair-[session-id]
    type: implementation
    unit: [unit-number]
    status: GREEN
    files: [implementation file path]
```

### Phase 5: Verify GREEN

Run the tests and confirm they pass:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: "Tests verified GREEN. [N] tests, [N] passed."
  metadata:
    thread: pair-[session-id]
    type: implementation
    unit: [unit-number]
    status: GREEN
    verified: true
```

---

## Edge Case Round-Trip

When the implementer discovers an edge case not covered by tests:

1. Implementer stores a request back to thread:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Edge case discovered: [description]
    Why it matters: [explanation]
    Request: spec writer to add test for this case
  metadata:
    thread: pair-[session-id]
    type: edge-case-request
    unit: [unit-number]
    for_agent: spec-writer
```

2. Orchestrator dispatches spec writer again for the edge case
3. Spec writer adds test, verifies RED
4. Implementer handles edge case, verifies GREEN

---

## Session Wrap-Up

After all units complete:

### Step 1: Full test suite

The orchestrator runs the complete test suite to verify all units work together.

### Step 2: Curate learnings

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Pair programming session complete.
    Task: [description]
    Units completed: [N]
    Total tests: [N]
    Patterns discovered: [list]
    Conventions followed: [list]
    Edge cases found via round-trip: [list]
  metadata:
    thread: pair-[session-id]
    type: orchestration
    status: completed
```

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_store_reasoning_memory` | Store test specs (RED), implementations (GREEN), edge case requests, and session results |
| `cipher_memory_search` | Read test specs (implementer), query conventions (both), discover edge case requests |
| `cipher_extract_and_operate_memory` | Extract session learnings for context tree curation |

## Composability

- Works with **convention-guardian**: Both subagents query conventions before their work
- Feeds into **pr-context-bridge**: Spec/implementation reasoning stored to PR thread
- Works with **implement-ticket**: Ticket implementation dispatches pair programming for TDD phases
- Feeds into **knowledge-handoff**: Patterns discovered during pair programming included in handoff
SKILLEOF
```

- [x] **Step 2: Run subagent-pair-programming tests — verify pass**

```bash
bash tests/test-team-skills.sh 2>&1 | grep -A1 "subagent-pair-programming"
# Expected: all subagent-pair-programming assertions pass
```

### Task 7: Implement onboarding-accelerator skill

**Files:**
- Create: `skills/onboarding-accelerator/onboarding-accelerator.md`

- [x] **Step 3: Create onboarding-accelerator skill**

```bash
mkdir -p skills/onboarding-accelerator
cat > skills/onboarding-accelerator/onboarding-accelerator.md << 'SKILLEOF'
# xgh:onboarding-accelerator

> First session for a new developer: query the team knowledge base and surface architecture decisions, conventions, gotchas, incidents, and a "who owns what" map — years of context in minutes.

## Iron Law

> **NEW DEVELOPERS MUST RECEIVE TEAM CONTEXT BEFORE WRITING THEIR FIRST LINE OF CODE.** The onboarding session is not optional. Without it, the new developer will repeat every mistake the team has already solved.

## When This Skill Activates

- First session for a new developer (detected by: no prior session history in Cipher, or explicit `/xgh onboard` command)
- When a developer explicitly asks for a project overview or team context
- When session-start hook detects an unrecognized developer identifier

---

## Knowledge Categories

The onboarding accelerator queries Cipher for five categories of team knowledge:

### 1. Architecture Decisions
```
Tool: cipher_memory_search
Parameters:
  query: "architecture decisions design system structure"
  scope: workspace
  filter:
    type: decision
    maturity: core OR validated
```

Surfaces: major architecture choices, system design, module boundaries, data flow, technology choices with rationale.

### 2. Coding Conventions
```
Tool: cipher_memory_search
Parameters:
  query: "convention rules patterns naming style"
  scope: workspace
  filter:
    type: convention
    scope: team
    maturity: core OR validated
```

Surfaces: code style rules, naming conventions, patterns to follow, patterns to avoid, testing requirements.

### 3. Gotchas and Warnings
```
Tool: cipher_memory_search
Parameters:
  query: "gotcha warning trap pitfall edge-case unexpected"
  scope: workspace
  filter:
    type: gotcha OR type: warning OR type: handoff
```

Surfaces: non-obvious behaviors, common mistakes, edge cases, "things that look right but aren't", workarounds.

### 4. Incidents and Fixes
```
Tool: cipher_memory_search
Parameters:
  query: "incident bug fix root-cause investigation"
  scope: workspace
  filter:
    type: incident OR type: investigation
```

Surfaces: past production issues, root causes, fixes applied, prevention measures, monitoring gaps.

### 5. Ownership Map
```
Tool: cipher_memory_search
Parameters:
  query: "ownership module area responsible team member"
  scope: workspace
  filter:
    type: ownership OR type: handoff
```

Surfaces: who owns what modules, who to ask about what, recent handoffs, domain expertise map.

---

## Onboarding Session Flow

### Phase 1: Welcome and Context Load

```
┌─ xgh Onboarding ─────────────────────────────────────────┐
│                                                            │
│  Welcome to [project-name]!                                │
│  Team: [team-name]                                         │
│                                                            │
│  Loading team knowledge base...                            │
│                                                            │
│  Found:                                                    │
│  → [N] architecture decisions                              │
│  → [N] coding conventions                                  │
│  → [N] gotchas and warnings                                │
│  → [N] incidents and fixes                                 │
│  → [N] ownership entries                                   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Phase 2: Architecture Overview

Present the top architecture decisions (sorted by importance), with:
- The decision and its rationale
- Key files and modules involved
- How components connect
- What constraints exist

Format as a guided tour, not a data dump:

```
"This project uses [architecture pattern] because [rationale].

The main modules are:
1. [module] — [purpose] (key files: [paths])
2. [module] — [purpose] (key files: [paths])

Data flows like this: [flow description]

Key constraint: [constraint from team decision]"
```

### Phase 3: Convention Briefing

Present core conventions as a checklist:

```
"Before you write any code, here are the team's conventions:

[CORE] conventions (non-negotiable):
□ [convention 1] — [brief rationale]
□ [convention 2] — [brief rationale]

[VALIDATED] conventions (strong recommendations):
□ [convention 3] — [brief rationale]
□ [convention 4] — [brief rationale]

These are enforced automatically by xgh — I'll remind you during coding."
```

### Phase 4: Gotcha Highlights

Present the most impactful gotchas:

```
"Things that trip up new developers here:

⚠ [gotcha 1]: [what seems right but isn't, and why]
⚠ [gotcha 2]: [non-obvious behavior and how to handle it]
⚠ [gotcha 3]: [common mistake and the correct approach]

These are from real experiences — they'll save you hours."
```

### Phase 5: Recent History

Present recent incidents and fixes:

```
"Recent incidents to be aware of:

- [date]: [incident summary] — caused by [root cause], fixed by [fix]
- [date]: [incident summary] — caused by [root cause], fixed by [fix]

Prevention measures in place: [what's been done]"
```

### Phase 6: Ownership Map

Present who owns what:

```
"Who to ask about what:

- [module/area]: [person/team] (last active: [date])
- [module/area]: [person/team] (last active: [date])

Recent handoffs:
- [area]: handed off from [person] on [date] — see handoff notes for context"
```

### Phase 7: Interactive Q&A

After the briefing, prompt the new developer:

```
"That's the overview. What area are you starting with?
I'll pull up the specific context you need."
```

When the developer asks about a specific area, query Cipher for deep context on that domain and present it with full detail.

---

## Storing Onboarding Metadata

Track the onboarding session for future reference:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Onboarding session completed for [developer identifier].
    Knowledge delivered: [N] architecture, [N] conventions, [N] gotchas, [N] incidents, [N] ownership.
    Areas of interest: [what the developer asked about]
    Gaps identified: [areas with thin documentation]
  metadata:
    type: onboarding
    scope: team
    developer: [identifier]
    session_date: [ISO timestamp]
```

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_memory_search` | Query all 5 knowledge categories for onboarding briefing |
| `cipher_store_reasoning_memory` | Store onboarding session metadata and identified gaps |
| `cipher_extract_and_operate_memory` | Extract session learnings if developer shares new context |

## Composability

- Consumes from **convention-guardian**: Core conventions surfaced during briefing
- Consumes from **knowledge-handoff**: Handoff summaries contribute to gotchas and ownership map
- Consumes from **cross-team-pollinator**: Org-scope knowledge included in architecture overview
- Consumes from **pr-context-bridge**: Recent PR reasoning contributes to "recent history"
SKILLEOF
```

- [x] **Step 4: Run onboarding-accelerator tests — verify pass**

```bash
bash tests/test-team-skills.sh 2>&1 | grep -A1 "onboarding-accelerator"
# Expected: all onboarding-accelerator assertions pass
```

- [x] **Step 5: Run full test suite — verify all 6 skills pass**

```bash
bash tests/test-team-skills.sh
# Expected: ~50 passed, 0 failed — all 6 skills complete
```

- [x] **Step 6: Commit chunk 3**

```bash
git add skills/subagent-pair-programming/ skills/onboarding-accelerator/
git commit -m "feat: add subagent-pair-programming and onboarding-accelerator skills

- subagent-pair-programming: dispatches spec writer + implementer subagents
  coordinating through Cipher memory, TDD enforced by architecture
- onboarding-accelerator: surfaces architecture, conventions, gotchas,
  incidents, and ownership map for new developer first sessions"
```

---

## Chunk 4: Collaborate Command & Collaboration Dispatcher Agent

### Task 8: Write tests for collaborate command and dispatcher agent

**Files:**
- Create: `tests/test-collaborate-command.sh`
- Create: `tests/test-collaboration-agent.sh`

- [x] **Step 1: Write test for collaborate command**

```bash
cat > tests/test-collaborate-command.sh << 'TESTEOF'
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

assert_section() {
  if grep -q "^## $2" "$1" 2>/dev/null || grep -q "^### $2" "$1" 2>/dev/null; then
    ((PASS++))
  else
    echo "FAIL: $1 missing section '$2'"
    ((FAIL++))
  fi
}

echo "=== Collaborate Command Tests ==="

CMD="commands/collaborate.md"
assert_file_exists "$CMD"
assert_contains "$CMD" "/xgh-collaborate"
assert_contains "$CMD" "plan-review"
assert_contains "$CMD" "parallel-impl"
assert_contains "$CMD" "validation"
assert_contains "$CMD" "security-review"
assert_contains "$CMD" "cipher_store_reasoning_memory"
assert_contains "$CMD" "cipher_memory_search"
assert_section "$CMD" "Usage"
assert_section "$CMD" "Workflow Templates"
assert_contains "$CMD" "thread"
assert_contains "$CMD" "from_agent"
assert_contains "$CMD" "for_agent"
assert_contains "$CMD" "status"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
TESTEOF
chmod +x tests/test-collaborate-command.sh
```

- [x] **Step 2: Write test for collaboration-dispatcher agent**

```bash
cat > tests/test-collaboration-agent.sh << 'TESTEOF'
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

assert_section() {
  if grep -q "^## $2" "$1" 2>/dev/null || grep -q "^### $2" "$1" 2>/dev/null; then
    ((PASS++))
  else
    echo "FAIL: $1 missing section '$2'"
    ((FAIL++))
  fi
}

echo "=== Collaboration Dispatcher Agent Tests ==="

AGENT="agents/collaboration-dispatcher.md"
assert_file_exists "$AGENT"
assert_contains "$AGENT" "collaboration-dispatcher"
assert_contains "$AGENT" "cipher_memory_search"
assert_contains "$AGENT" "cipher_store_reasoning_memory"
assert_section "$AGENT" "Role"
assert_section "$AGENT" "Message Protocol"
assert_section "$AGENT" "Dispatch Loop"
assert_contains "$AGENT" "thread"
assert_contains "$AGENT" "from_agent"
assert_contains "$AGENT" "for_agent"
assert_contains "$AGENT" "pending"
assert_contains "$AGENT" "completed"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
TESTEOF
chmod +x tests/test-collaboration-agent.sh
```

- [x] **Step 3: Run both tests — verify all fail**

```bash
bash tests/test-collaborate-command.sh; bash tests/test-collaboration-agent.sh
# Expected: all assertions fail (files don't exist yet)
```

### Task 9: Implement the collaborate command

**Files:**
- Create: `commands/collaborate.md`

- [x] **Step 4: Create the /xgh-collaborate command**

```bash
cat > commands/collaborate.md << 'CMDEOF'
# /xgh-collaborate

Start a multi-agent collaboration workflow using Cipher workspace as the async communication bus.

## Usage

```
/xgh-collaborate <workflow> [options]
```

### Arguments

| Argument | Required | Description |
|---|---|---|
| `workflow` | Yes | One of: `plan-review`, `parallel-impl`, `validation`, `security-review`, or a custom workflow name |
| `--thread <id>` | No | Thread ID for grouping messages (default: auto-generated) |
| `--agents <list>` | No | Comma-separated agent names (default: workflow-specific) |
| `--task <description>` | Yes | Description of the work to be done |

### Examples

```bash
# Plan-review: one agent plans, another reviews
/xgh-collaborate plan-review --task "Add rate limiting to API endpoints"

# Parallel implementation: split work across agents
/xgh-collaborate parallel-impl --task "Implement user preferences CRUD" --agents "claude,codex"

# Validation: implement then validate
/xgh-collaborate validation --task "Refactor auth middleware"

# Security review chain
/xgh-collaborate security-review --task "Add file upload endpoint"
```

---

## Workflow Templates

### plan-review (2 agents)

```
Agent A → PLAN (store to thread) → Agent B → REVIEW (store feedback) → Agent A → IMPLEMENT
```

**Flow:**

1. **Agent A (Planner)** receives the task, queries memory for context, and writes a detailed plan:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    ## Plan: [task description]

    ### Context gathered:
    [relevant memory, conventions, past work]

    ### Approach:
    [detailed implementation plan]

    ### Files to change:
    [list with rationale]

    ### Risks:
    [identified risks]
  metadata:
    thread: [thread-id]
    type: plan
    status: pending
    from_agent: claude-code
    for_agent: reviewer
    priority: normal
    created_at: [ISO timestamp]
```

2. **Agent B (Reviewer)** queries the thread for the plan and stores review feedback:

```
Tool: cipher_memory_search
Parameters:
  query: "thread:[thread-id] type:plan status:pending"
  scope: workspace
```

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    ## Review: [task description]

    ### Feedback:
    [specific feedback on the plan]

    ### Concerns:
    [risks identified, gaps found]

    ### Approved: [yes/no/with-changes]

    ### Required changes:
    [if applicable]
  metadata:
    thread: [thread-id]
    type: review
    status: completed
    from_agent: reviewer
    for_agent: claude-code
    priority: normal
```

3. **Agent A** reads feedback, adjusts plan, and implements.

### parallel-impl (N agents)

```
Agent A → SPLIT tasks → Agents B,C,D → IMPLEMENT (parallel) → Agent A → MERGE + REVIEW
```

**Flow:**

1. **Orchestrator** splits the task into independent units and stores each as a work item:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Work item [N]: [description]
    Files: [file list]
    Dependencies: [none / depends on item M]
    Acceptance criteria: [criteria]
  metadata:
    thread: [thread-id]
    type: plan
    subtype: work-item
    item_number: [N]
    status: pending
    from_agent: orchestrator
    for_agent: [assigned agent]
```

2. **Worker agents** pick up their assigned items, implement, and store results.

3. **Orchestrator** reviews all results and merges.

### validation (2 agents)

```
Agent A → IMPLEMENT (store) → Agent B → VALIDATE (store) → feedback loop until pass
```

**Flow:**

1. **Agent A (Implementer)** writes the implementation and stores it.
2. **Agent B (Validator)** reviews the implementation against requirements, runs tests, checks conventions.
3. If validation fails, feedback loop continues until pass.

### security-review (chain)

```
Agent A → IMPLEMENT → Agent B → SECURITY_REVIEW → Agent A → FIX → Agent B → RE-REVIEW
```

**Flow:**

1. **Agent A** implements the feature.
2. **Agent B** performs security-focused review (input validation, auth, injection, data exposure).
3. **Agent A** fixes identified issues.
4. **Agent B** re-reviews fixes.

---

## Message Protocol

All inter-agent messages in the Cipher workspace follow this structure:

```yaml
type: plan | review | feedback | result | decision | question
status: pending | in_progress | completed
from_agent: [who wrote it]
for_agent: [who should read it, or "*" for broadcast]
thread: [groups related messages]
priority: normal | high | urgent
created_at: [ISO timestamp]
```

### Message Types

| Type | Description | Expected Response |
|---|---|---|
| `plan` | Detailed implementation plan | `review` or `feedback` |
| `review` | Review of a plan or implementation | `result` or `feedback` |
| `feedback` | Specific feedback on work | `result` (addressing feedback) |
| `result` | Completed work output | `review` or completion |
| `decision` | A decision that needs acknowledgment | `feedback` (agree/disagree) |
| `question` | A question needing an answer | `result` (the answer) |

---

## Dispatch Mechanism

The collaborate command dispatches the collaboration-dispatcher agent, which:

1. Creates the thread in Cipher workspace
2. Stores the initial task with workflow metadata
3. Dispatches subagents according to the workflow template
4. Monitors the thread for message progression
5. Reports completion back to the user

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Collaboration workflow started.
    Workflow: [template name]
    Task: [description]
    Agents: [list]
    Thread: [thread-id]
  metadata:
    thread: [thread-id]
    type: orchestration
    status: in_progress
    from_agent: orchestrator
    for_agent: "*"
```

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_store_reasoning_memory` | Store plans, reviews, feedback, results, decisions, and questions to thread |
| `cipher_memory_search` | Query thread for messages, check for new responses |
| `cipher_extract_and_operate_memory` | Extract learnings from completed collaboration |

## Composability

- Dispatches **subagent-pair-programming** for TDD workflows within collaboration
- Uses **convention-guardian** for all agents in the workflow
- Feeds into **pr-context-bridge** when collaboration produces a PR
- Feeds into **knowledge-handoff** when collaboration completes
CMDEOF
```

- [x] **Step 5: Run collaborate command tests — verify pass**

```bash
bash tests/test-collaborate-command.sh
# Expected: all assertions pass
```

### Task 10: Implement the collaboration-dispatcher agent

**Files:**
- Create: `agents/collaboration-dispatcher.md`

- [x] **Step 6: Create the collaboration-dispatcher agent**

```bash
cat > agents/collaboration-dispatcher.md << 'AGENTEOF'
# collaboration-dispatcher

A subagent that orchestrates multi-agent workflows through Cipher workspace memory. It manages the lifecycle of collaboration threads: dispatching work, monitoring progress, routing messages, and reporting completion.

## Role

The collaboration-dispatcher is the traffic controller for multi-agent workflows. It:

1. **Creates** collaboration threads in Cipher workspace
2. **Dispatches** work items to agents according to workflow templates
3. **Monitors** thread progress and routes messages between agents
4. **Enforces** workflow rules (ordering, dependencies, gates)
5. **Reports** completion and curates learnings

The dispatcher does NOT do implementation work itself. It coordinates others.

---

## Message Protocol

All messages in a collaboration thread use structured metadata:

```yaml
type: plan | review | feedback | result | decision | question
status: pending | in_progress | completed
from_agent: [who wrote it]         # e.g., "claude-code", "codex", "spec-writer"
for_agent: [who should read it]    # e.g., "reviewer", "*" for broadcast
thread: [thread-id]                # groups all messages in one collaboration
priority: normal | high | urgent
created_at: [ISO timestamp]
```

### Status Transitions

```
pending → in_progress → completed
                     ↘ blocked (waiting on dependency)
```

### Routing Rules

- Messages with `for_agent: "*"` are visible to all agents in the thread
- Messages with `for_agent: [specific]` are targeted — only that agent acts on them
- Messages with `priority: urgent` are surfaced immediately
- Messages with `status: pending` are work items waiting to be picked up

---

## Dispatch Loop

The dispatcher runs a simple loop:

### Step 1: Initialize thread

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Collaboration thread initialized.
    Workflow: [template]
    Task: [description]
    Participants: [agent list]
    Created by: [requesting user/agent]
  metadata:
    thread: [thread-id]
    type: orchestration
    status: in_progress
    from_agent: dispatcher
    for_agent: "*"
```

### Step 2: Dispatch first work item

Based on the workflow template, create the first work item:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Work assignment: [description of what this agent should do]
    Context: [relevant context from memory]
    Constraints: [conventions, requirements, dependencies]
    Expected output: [what should be stored back to thread]
  metadata:
    thread: [thread-id]
    type: plan
    status: pending
    from_agent: dispatcher
    for_agent: [target agent]
    priority: normal
    step: 1
```

### Step 3: Monitor for completion

Poll the thread for responses:

```
Tool: cipher_memory_search
Parameters:
  query: "thread:[thread-id] status:completed step:1"
  scope: workspace
```

### Step 4: Route to next step

When step N completes, dispatch step N+1 according to the workflow template:
- **plan-review**: plan complete → dispatch review → review complete → dispatch implementation
- **parallel-impl**: all items complete → dispatch merge review
- **validation**: implementation complete → dispatch validation → if fail, loop back
- **security-review**: implementation complete → dispatch security review → if issues, dispatch fixes

### Step 5: Handle failures

If a step produces an error or rejection:
1. Store the failure with context
2. Determine if retry, escalate, or abort based on workflow rules
3. Dispatch corrective action

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Step [N] requires revision.
    Reason: [feedback from reviewer/validator]
    Action: [retry with feedback / escalate to user / abort]
  metadata:
    thread: [thread-id]
    type: feedback
    status: pending
    from_agent: dispatcher
    for_agent: [original agent]
    priority: high
    step: [N]
```

### Step 6: Report completion

When all steps complete:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Collaboration workflow completed.
    Workflow: [template]
    Task: [description]
    Steps completed: [N]
    Participants: [agent list]
    Duration: [time]
    Outcome: [summary of results]
    Learnings: [what was discovered]
  metadata:
    thread: [thread-id]
    type: orchestration
    status: completed
    from_agent: dispatcher
    for_agent: "*"
```

---

## Workflow Rules

### Ordering

Each workflow template defines a step ordering. The dispatcher enforces:
- Sequential steps run one at a time
- Parallel steps may run concurrently
- Dependencies must complete before dependents start

### Gates

Certain transitions require explicit approval:
- `plan → implement`: review must approve (plan-review workflow)
- `implement → merge`: validation must pass (validation workflow)
- `security-review → approve`: all security findings must be addressed

### Timeouts

If a step does not complete within a reasonable time:
1. Store a reminder to the thread
2. Notify the orchestrating user
3. After 3 reminders, escalate or abort

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_store_reasoning_memory` | Store work items, status updates, failures, and completion reports |
| `cipher_memory_search` | Monitor thread for completions, query agent responses |
| `cipher_search_reasoning_patterns` | Analyze collaboration patterns across past workflows |

## Composability

- Dispatched by **/xgh-collaborate** command
- Dispatches **subagent-pair-programming** for TDD-based work items
- All dispatched agents use **convention-guardian** for convention compliance
- Completed workflows feed into **pr-context-bridge** and **knowledge-handoff**
AGENTEOF
```

- [x] **Step 7: Run collaboration-dispatcher agent tests — verify pass**

```bash
bash tests/test-collaboration-agent.sh
# Expected: all assertions pass
```

- [x] **Step 8: Run all test suites**

```bash
bash tests/test-team-skills.sh && bash tests/test-collaborate-command.sh && bash tests/test-collaboration-agent.sh
# Expected: all pass — 0 failures across all test files
```

- [x] **Step 9: Commit chunk 4**

```bash
git add commands/collaborate.md agents/collaboration-dispatcher.md tests/test-collaborate-command.sh tests/test-collaboration-agent.sh
git commit -m "feat: add /xgh-collaborate command and collaboration-dispatcher agent

- collaborate command: dispatches multi-agent workflows (plan-review,
  parallel-impl, validation, security-review) via Cipher workspace
- collaboration-dispatcher agent: orchestrates thread lifecycle,
  message routing, step sequencing, failure handling, and completion"
```

---

## Chunk 5: Integration Test & Final Verification

### Task 11: Write integration test and verify everything

**Files:**
- Create: `tests/test-plan4-integration.sh`

- [x] **Step 1: Write integration test that verifies all Plan 4 deliverables**

```bash
cat > tests/test-plan4-integration.sh << 'TESTEOF'
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

assert_dir_exists() {
  if [ -d "$1" ]; then
    ((PASS++))
  else
    echo "FAIL: directory $1 does not exist"
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

echo "=== Plan 4: Team Collaboration Integration Test ==="

# ── Skill directories exist ───────────────────────────
echo ""
echo "--- Skill directories ---"
assert_dir_exists "skills/pr-context-bridge"
assert_dir_exists "skills/knowledge-handoff"
assert_dir_exists "skills/convention-guardian"
assert_dir_exists "skills/cross-team-pollinator"
assert_dir_exists "skills/subagent-pair-programming"
assert_dir_exists "skills/onboarding-accelerator"

# ── Skill files exist ─────────────────────────────────
echo ""
echo "--- Skill files ---"
assert_file_exists "skills/pr-context-bridge/pr-context-bridge.md"
assert_file_exists "skills/knowledge-handoff/knowledge-handoff.md"
assert_file_exists "skills/convention-guardian/convention-guardian.md"
assert_file_exists "skills/cross-team-pollinator/cross-team-pollinator.md"
assert_file_exists "skills/subagent-pair-programming/subagent-pair-programming.md"
assert_file_exists "skills/onboarding-accelerator/onboarding-accelerator.md"

# ── Command file exists ───────────────────────────────
echo ""
echo "--- Command file ---"
assert_file_exists "commands/collaborate.md"

# ── Agent file exists ─────────────────────────────────
echo ""
echo "--- Agent file ---"
assert_file_exists "agents/collaboration-dispatcher.md"

# ── All skills have Iron Law ──────────────────────────
echo ""
echo "--- Iron Law in all skills ---"
for skill in pr-context-bridge knowledge-handoff convention-guardian cross-team-pollinator subagent-pair-programming onboarding-accelerator; do
  assert_contains "skills/$skill/$skill.md" "Iron Law"
done

# ── All skills reference Cipher tools ─────────────────
echo ""
echo "--- Cipher tool references ---"
for skill in pr-context-bridge knowledge-handoff convention-guardian cross-team-pollinator subagent-pair-programming onboarding-accelerator; do
  assert_contains "skills/$skill/$skill.md" "cipher_memory_search"
done

# ── All skills have Composability section ─────────────
echo ""
echo "--- Composability sections ---"
for skill in pr-context-bridge knowledge-handoff convention-guardian cross-team-pollinator subagent-pair-programming onboarding-accelerator; do
  assert_contains "skills/$skill/$skill.md" "Composability"
done

# ── Command has workflow templates ────────────────────
echo ""
echo "--- Workflow templates in command ---"
assert_contains "commands/collaborate.md" "plan-review"
assert_contains "commands/collaborate.md" "parallel-impl"
assert_contains "commands/collaborate.md" "validation"
assert_contains "commands/collaborate.md" "security-review"

# ── Agent has dispatch loop ───────────────────────────
echo ""
echo "--- Agent dispatch loop ---"
assert_contains "agents/collaboration-dispatcher.md" "Dispatch Loop"
assert_contains "agents/collaboration-dispatcher.md" "Message Protocol"

# ── Cross-references between skills ───────────────────
echo ""
echo "--- Skill cross-references ---"
assert_contains "skills/pr-context-bridge/pr-context-bridge.md" "convention-guardian"
assert_contains "skills/pr-context-bridge/pr-context-bridge.md" "knowledge-handoff"
assert_contains "skills/knowledge-handoff/knowledge-handoff.md" "pr-context-bridge"
assert_contains "skills/knowledge-handoff/knowledge-handoff.md" "onboarding-accelerator"
assert_contains "skills/convention-guardian/convention-guardian.md" "cross-team-pollinator"
assert_contains "skills/cross-team-pollinator/cross-team-pollinator.md" "onboarding-accelerator"
assert_contains "skills/subagent-pair-programming/subagent-pair-programming.md" "convention-guardian"
assert_contains "skills/onboarding-accelerator/onboarding-accelerator.md" "convention-guardian"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
TESTEOF
chmod +x tests/test-plan4-integration.sh
```

- [x] **Step 2: Run integration test**

```bash
bash tests/test-plan4-integration.sh
# Expected: all pass — full Plan 4 verified
```

- [x] **Step 3: Run ALL test suites one final time**

```bash
bash tests/test-team-skills.sh && \
bash tests/test-collaborate-command.sh && \
bash tests/test-collaboration-agent.sh && \
bash tests/test-plan4-integration.sh
# Expected: all pass — 0 failures
```

- [x] **Step 4: Commit integration test**

```bash
git add tests/test-plan4-integration.sh
git commit -m "test: add Plan 4 integration test

Verifies all 6 team collaboration skills, the /xgh-collaborate command,
and the collaboration-dispatcher agent are present with required sections,
Iron Laws, Cipher tool references, and cross-skill composability links."
```

---

## Summary

| Deliverable | File | Description |
|---|---|---|
| pr-context-bridge skill | `skills/pr-context-bridge/pr-context-bridge.md` | Auto-curate PR reasoning to Cipher workspace |
| knowledge-handoff skill | `skills/knowledge-handoff/knowledge-handoff.md` | Structured handoff summaries on branch merge |
| convention-guardian skill | `skills/convention-guardian/convention-guardian.md` | Auto-query and enforce team conventions |
| cross-team-pollinator skill | `skills/cross-team-pollinator/cross-team-pollinator.md` | Org-wide knowledge sharing via `_shared/` |
| subagent-pair-programming skill | `skills/subagent-pair-programming/subagent-pair-programming.md` | TDD via spec writer + implementer subagents |
| onboarding-accelerator skill | `skills/onboarding-accelerator/onboarding-accelerator.md` | New developer context bootstrapping |
| /xgh-collaborate command | `commands/collaborate.md` | Multi-agent workflow dispatch |
| collaboration-dispatcher agent | `agents/collaboration-dispatcher.md` | Workflow orchestration subagent |
| Skill tests | `tests/test-team-skills.sh` | Tests for all 6 skills |
| Command tests | `tests/test-collaborate-command.sh` | Tests for collaborate command |
| Agent tests | `tests/test-collaboration-agent.sh` | Tests for dispatcher agent |
| Integration tests | `tests/test-plan4-integration.sh` | Full Plan 4 verification |
