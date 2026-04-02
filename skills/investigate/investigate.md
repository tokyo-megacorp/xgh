---
name: xgh:investigate
description: "This skill should be used when the user runs /xgh-investigate or asks to investigate a bug, 'debug this issue', 'find root cause', 'investigate this Slack thread'. Slack-driven systematic debugging workflow — from Slack thread to root cause finding report."
---

## Preamble — Execution mode

Follow the shared execution mode protocol in `skills/_shared/references/execution-mode-preamble.md`. Apply it to this skill's command name.

- `<SKILL_NAME>` = `investigate`
- `<SKILL_LABEL>` = `Investigation`

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

Follow the shared detection protocol in `skills/_shared/references/mcp-auto-detection.md`.

**Graceful degradation rules (investigate-specific):**
- No Slack MCP → Skip Slack thread reading. Ask user to paste the bug report content directly.
- No task manager MCP → Skip ticket search/creation. Note in report that no ticket was created.
- No memory backend → Skip memory search. Proceed with codebase-only investigation. Save report to context tree only.
- No MCPs at all → Still works. User provides context manually. Full Superpowers debug methodology applies.

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

### Step 1.3: Query xgh Memory (if memory backend available (see `_shared/references/memory-backend.md`))

Use [SEARCH] → call `magi_query(query)` to search for:
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

2. **MAGI memory** (if available): Extract key learnings as a concise summary (3-7 bullets), then [STORE] → call magi_store with the summary text and context-appropriate tags. Do not pass raw conversation content to magi_store. Use tags: "session". Store:
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
| 3 failed hypotheses hard gate | Prevents infinite rabbit holes. Forces the agent to seek human expertise. |
| One hypothesis at a time | Forces focus. Prevents shotgun debugging. |
| Report saved to context tree | Future investigations can reference past findings. Searchable by team. |
| Curated to MAGI | Semantic search finds similar bugs even with different keywords. |
| Interactive triage before debug | Avoids duplicate work. Connects to existing team workflows. |
| Graceful degradation | Works for any team regardless of MCP configuration. |
