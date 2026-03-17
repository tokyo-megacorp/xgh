---
name: xgh:briefing
description: Intelligent session briefing. Aggregates Slack, Jira, GitHub, Gmail, Calendar, Figma, and xgh team memory into a prioritized executive summary with a suggested focus.
type: flexible
triggers:
  - SessionStart (when XGH_BRIEFING=auto or XGH_BRIEFING=compact)
  - /xgh-briefing command
  - /xgh-briefing compact
  - /xgh-briefing focus
---

# xgh:briefing — Intelligent Session Briefing

Give the user a **prioritized executive summary** of everything relevant to their work right now, then recommend exactly one thing to focus on this session.

🐴🤖 **xgh briefing engaged**

**Goal:** Not a notification dump — a concise briefing that answers "what's the most valuable thing I can work on right now?"

## Configuration

Controlled by `XGH_BRIEFING` environment variable:

| Value | Behavior |
|-------|----------|
| `off` (default) | Never auto-trigger; `/xgh-briefing` still works on demand |
| `auto` | Full briefing on every session start |
| `compact` | One-line status on session start, full on demand |

The briefing respects `XGH_TEAM` from the environment for workspace memory queries.

## Iron Law

> **NEVER show everything — show what matters.** A briefing that lists 40 items is noise. Surface the top 3-5 actionable items per section. If a section is empty or irrelevant, omit it entirely. The user's time is the constraint.

## MCP Detection

Before gathering data, check which MCPs are available. Call `xgh:mcp-setup` for any missing MCP the user wants to configure. Proceed with whatever is available — the briefing works with any combination.

Available MCP tools by integration:
- **lossless-claude**: `lcm_search(query)`, `lcm_store`
- **Slack**: `slack_search_public_and_private`, `slack_list_channels`
- **Atlassian/Jira**: `searchJiraIssuesUsingJQL`, `getJiraIssue`
- **GitHub**: `gh pr list`, `gh issue list`, `gh run list`
- **Gmail**: `gmail_search_messages`, `gmail_read_message`
- **Figma**: `figma_get_file`, `figma_get_comments`

## Data Gathering

### 1. xgh Memory (always — lossless-claude)

Search for recent session state and pending work:

```
lcm_search("last session", { limit: 3 })
lcm_search("in progress", { limit: 3 })
lcm_search("blocked", { limit: 2 })
```

### 2. Slack (if available)

```
slack_search_public_and_private("to:me is:unread", limit=10)
slack_search_public_and_private("urgent OR ASAP OR blocked", limit=5)
```

### 3. Jira/Atlassian (if available)

```
searchJiraIssuesUsingJQL("assignee = currentUser() AND status != Done ORDER BY priority DESC", limit=10)
searchJiraIssuesUsingJQL("assignee = currentUser() AND status = 'In Progress'", limit=5)
```

### 4. GitHub (if available)

```
gh pr list --author @me --state open
gh issue list --assignee @me --state open
gh pr list --review-requested @me --state open
```

### 5. Gmail (if available)

```
gmail_search_messages("to:me is:unread from:teammate", limit=10)
gmail_search_messages("subject:deadline OR subject:urgent is:unread", limit=5)
```

### 6. Figma (if available)

```
figma_get_comments(file_key, limit=10)
```

### 7. Team Pulse (always — from lossless-claude workspace)

```
lcm_search("team update", { limit: 3 })
lcm_search("convention change", { limit: 2 })
```

## Prioritization Engine

Score each item: `urgency × impact` (each 1–7).

| Score | Section |
|-------|---------|
| ≥35   | **NEEDS YOU NOW** |
| 20–34 | **IN PROGRESS** |
| 10–19 | **INCOMING** |
| Any   | **TEAM PULSE** (team updates) |

Hard cap: **5 items per section**. If a section is empty, omit it.

## Output Format

```
🐴🤖 **xgh briefing** — [date] [time]

### NEEDS YOU NOW
- [Item] — *why it scores high*

### IN PROGRESS
- [Item] — *where you left off*

### INCOMING
- [Item] — *ETA or trigger*

### TEAM PULSE
- [Team update or convention change]

### TODAY
- [Calendar events if available]

### SUGGESTED FOCUS
> **[Single recommended task]** — [one sentence rationale]
```

## Compact Mode (`XGH_BRIEFING=compact` or `/xgh-briefing compact`)

Single line:

```
🐴🤖 [N] needs attention · [N] in flight · focus: [task]
```

## Focus Mode (`/xgh-briefing focus`)

Just the suggested focus, no other sections:

```
🐴🤖 **Focus:** [task] — [rationale]
```

## Pre-Meeting Mode

If the user says `/xgh-briefing meeting [name]`, filter output to items relevant to that meeting.

## After the Briefing

Once the briefing is delivered:
1. Ask: "Ready to start on [SUGGESTED FOCUS]? Or pick a different item."
2. If user confirms: load context for that ticket/PR and invoke `xgh:implement-ticket` or `xgh:investigate` as appropriate.
3. Store the session start state: Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store. Use tags: ["session"]

## Rationalization Table

| If you see | Do this |
|------------|---------|
| lossless-claude unavailable | Skip memory sections, note "Run /xgh-setup to enable memory" |
| No Slack/Jira | Skip those sections silently |
| No items in any section | Output "🐴🤖 All clear — no urgent items. Pick something from your backlog." |
| >5 items in a section | Show top 5, add "…and N more" |

## Composability

- Uses `xgh:mcp-setup` when a source MCP is missing (optional setup, not blocking)
- Feeds into `xgh:implement-ticket` (pre-loaded context for chosen ticket)
- Feeds into `xgh:investigate` (pre-loaded context for chosen incident)
- Informs `xgh:convention-guardian` (team pulse surfaces new conventions)
