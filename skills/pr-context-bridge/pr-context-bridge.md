---
name: xgh:pr-context-bridge
description: "This skill should be used when the user runs /xgh-pr-context-bridge, opens a PR, or asks to 'capture PR reasoning', 'document this PR', 'store PR context'. Auto-curates PR reasoning to lossless-claude workspace so reviewers get deep context — approaches considered, tradeoffs made, tricky parts flagged — without meetings."
---

# xgh:pr-context-bridge — PR Context Bridge

> Auto-curate PR reasoning to lossless-claude workspace so reviewers get deep context without meetings.

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

As the author works on a feature branch, the following reasoning is auto-curated to lossless-claude workspace:

**Step 1: Initialize PR thread**

When work begins on a feature branch, create a lossless-claude thread:

```
Tool: lcm_store(text, ["reasoning"])
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
Tool: lcm_store(text, ["reasoning"])
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
Tool: lcm_store(text, ["reasoning"])
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
Tool: lcm_store(text, ["reasoning"])
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
Tool: lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })
Parameters:
  query: "thread:PR-[branch-name] reasoning decisions tradeoffs"
  scope: workspace
```

Compile all thread entries into a structured summary and store:

```
Tool: lcm_store(text, ["reasoning"])
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
Tool: lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })
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
Tool: lcm_store(text, ["reasoning"])
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
| [STORE] → call `lcm_store(text, ["reasoning"])` | Store decisions, tricky parts, summaries, and review feedback to PR thread |
| `lcm_search` | Query PR thread for reasoning context (reviewer side) |
| Extract 3-7 bullet summary → [STORE] → call `lcm_store(text, ["workspace"])` | Extract reasoning from session for auto-curation |

## Composability

- Works with **convention-guardian**: PR reasoning includes which conventions were followed
- Works with **knowledge-handoff**: PR context feeds into post-merge handoff
- Works with **subagent-pair-programming**: Spec writer and implementer reasoning both stored to PR thread
