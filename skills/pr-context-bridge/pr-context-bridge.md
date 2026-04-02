---
name: xgh:pr-context-bridge
description: "This skill should be used when the user runs /xgh-pr-context-bridge, opens a PR, or asks to 'capture PR reasoning', 'document this PR', 'store PR context'. Auto-curates PR reasoning to MAGI workspace so reviewers get deep context — approaches considered, tradeoffs made, tricky parts flagged — without meetings."
---

# xgh:pr-context-bridge — PR Context Bridge

> Auto-curate PR reasoning to MAGI workspace so reviewers get deep context without meetings.

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

As the author works on a feature branch, the following reasoning is auto-curated to MAGI workspace:

**Step 1: Initialize PR thread**

When work begins on a feature branch, create a MAGI note:

```
Tool: magi_store(path, title, body, tags)
Parameters:
  path: "pr-context/PR-[branch-name]/init.md"
  title: "PR started: [branch-name]"
  body: "Starting work on [branch-name]: [ticket/description]. Status: in_progress"
  tags: "pr-context,reasoning"
```

**Step 2: Capture decision points**

Whenever a non-trivial decision is made (approach selection, tradeoff, architecture choice):

```
Tool: magi_store(path, title, body, tags)
Parameters:
  path: "pr-context/PR-[branch-name]/decision-[N].md"
  title: "Decision: [what was decided]"
  body: |
    Decision: [what was decided]
    Alternatives considered:
    - A: [approach A] — rejected because [reason]
    - B: [approach B] — chosen because [reason]
    - C: [approach C] — rejected because [reason]
    Key tradeoff: [e.g., latency vs consistency]
    Confidence: [high/medium/low]
    Files: [list of affected files]
  tags: "pr-context,reasoning,decision"
```

**Step 3: Flag tricky parts**

When implementation involves non-obvious logic, subtle edge cases, or workarounds:

```
Tool: magi_store(path, title, body, tags)
Parameters:
  path: "pr-context/PR-[branch-name]/tricky-[N].md"
  title: "Tricky part: [file:line or function name]"
  body: |
    Tricky part: [file:line or function name]
    What's non-obvious: [explanation]
    Why it's done this way: [reasoning]
    What could go wrong: [edge cases, failure modes]
    Related: [links to docs, issues, past decisions]
    Files: [affected files]
  tags: "pr-context,reasoning,tricky-part"
```

**Step 4: Capture related prior knowledge**

When memory queries during development surface relevant past decisions:

```
Tool: magi_store(path, title, body, tags)
Parameters:
  path: "pr-context/PR-[branch-name]/related-context.md"
  title: "Related prior knowledge: [branch-name]"
  body: |
    This PR relates to prior decision: [summary]
    How it connects: [explanation]
    Consistency check: [does this PR align or intentionally diverge?]
  tags: "pr-context,reasoning"
```

### Phase 2: Pre-Push Summary

Before pushing (or when the author signals the PR is ready):

**Step 5: Generate PR reasoning summary**

```
Tool: magi_query(query)
Parameters:
  query: "PR-[branch-name] reasoning decisions tradeoffs"
  limit: 20
```

Compile all thread entries into a structured summary and store:

```
Tool: magi_store(path, title, body, tags)
Parameters:
  path: "pr-context/PR-[branch-name]/summary.md"
  title: "PR Context Summary: [branch-name]"
  body: |
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
    Status: ready_for_review
  tags: "pr-context,reasoning,summary"
```

---

## Reviewer Flow

### Phase 1: Context Loading

When a reviewer's Claude session detects PR review context (PR URL, `gh pr checkout`, review request):

**Step 1: Query for PR reasoning**

```
Tool: magi_query(query)
Parameters:
  query: "PR-[branch-name] context decisions tradeoffs tricky-parts summary"
  limit: 20
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
Tool: magi_store(path, title, body, tags)
Parameters:
  path: "pr-context/PR-[branch-name]/review-feedback-[N].md"
  title: "Review feedback: [what was found]"
  body: |
    Review feedback: [what was found]
    Question: [if applicable]
    Suggestion: [if applicable]
    Applies to: [file:line]
  tags: "pr-context,review-feedback"
```

**Step 4: Author reads review context**

When the author returns to address review comments, their Claude queries the thread for new feedback entries, getting the reviewer's reasoning alongside GitHub comments.

---

## Tool Reference

| Tool | Usage |
|---|---|
| [STORE] → call `magi_store(path, title, body, tags)` | Store decisions, tricky parts, summaries, and review feedback to PR thread |
| `magi_query` | Query PR thread for reasoning context (reviewer side) |
| Extract 3-7 bullet summary → [STORE] → call `magi_store(path, title, body, tags)` | Extract reasoning from session for auto-curation |

## Composability

- Works with **convention-guardian**: PR reasoning includes which conventions were followed
- Works with **knowledge-handoff**: PR context feeds into post-merge handoff
- Works with **subagent-pair-programming**: Spec writer and implementer reasoning both stored to PR thread
