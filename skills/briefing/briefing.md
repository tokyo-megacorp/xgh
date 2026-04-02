---
name: xgh:briefing
description: "This skill should be used when the user runs /xgh-briefing, /xgh-briefing compact, or /xgh-briefing focus, or asks for a morning briefing or session summary. Aggregates Slack, Jira, GitHub, Gmail, Calendar, Figma, and xgh team memory into a prioritized executive summary with a suggested focus."
---

# xgh:briefing — Intelligent Session Briefing

Give the user a **prioritized executive summary** of everything relevant to their work right now, then recommend exactly one thing to focus on this session.

🐴🤖 **xgh briefing engaged**

**Goal:** Not a notification dump — a concise briefing that answers "what's the most valuable thing I can work on right now?"

## Configuration

The briefing is always available on demand. Run `/xgh-briefing` at any time; it does not require any environment variable to be set.

The briefing respects `XGH_TEAM` from the environment for workspace memory queries.

**Optional Automation:** Set `XGH_BRIEFING=1` in your environment to enable automatic briefing at SessionStart. This is useful for command center mode where you want immediate context on every session.

## Iron Law

> **NEVER show everything — show what matters.** A briefing that lists 40 items is noise. Surface the top 3-5 actionable items per section. If a section is empty or irrelevant, omit it entirely. The user's time is the constraint.

## MCP Detection

Follow the shared detection protocol in `skills/_shared/references/mcp-auto-detection.md`. Run `/xgh-setup` for any missing MCP the user wants to configure. Proceed with whatever is available — the briefing works with any combination.

**Briefing-specific tool aliases used in this skill:**
- **MAGI**: [SEARCH] → call `magi_query(query)`, `magi_store`
- **Slack**: `slack_search_public_and_private`, `slack_list_channels`
- **Atlassian/Jira**: `searchJiraIssuesUsingJQL`, `getJiraIssue`
- **GitHub**: `gh pr list`, `gh issue list`, `gh run list`
- **Gmail**: `gmail_search_messages`, `gmail_read_message`
- **Figma**: `figma_get_file`, `figma_get_comments`

## Project Scope

Determine which projects this briefing covers:

1. Run `bash ~/.xgh/scripts/detect-project.sh` and read `XGH_PROJECT` and `XGH_PROJECT_SCOPE`
2. If `XGH_PROJECT` is non-empty:
   - Show in header: `🐴🤖 **xgh briefing** — [date] [time] — project: **[name]** (+[N] deps)`
   - Scope ALL data gathering queries to projects in `XGH_PROJECT_SCOPE`:
     - Memory queries: add project name to search terms
     - Slack: only scan channels belonging to in-scope projects
     - Jira: filter JQL to in-scope project keys
     - GitHub: only check repos belonging to in-scope projects
     - Figma: only check files belonging to in-scope projects
   - Gmail and Calendar are NOT scoped (they're personal, not project-specific)
3. If `XGH_PROJECT` is empty:
   - Show in header: `🐴🤖 **xgh briefing** — [date] [time] — all projects`
   - Proceed with all active projects (current behavior — command center mode)

**Override:** `/xgh-briefing --all` forces all-projects mode regardless of cwd.

## Teams Mode Detection

Before gathering data, check if `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is active:

1. Read `~/.claude/settings.json` and check for `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` in the `env` block.
   - This env var is injected by Claude Code into the Claude process — it cannot be read via `$VAR` in Bash.
   - If `settings.json` contains `"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"`, set `TEAMS_MODE=true`.
   - Otherwise, set `TEAMS_MODE=false`.

2. Use the appropriate gather strategy below based on `TEAMS_MODE`.

> **Constraint (UNBREAKABLE_RULES §2):** Never spawn more than 5 concurrent subagents. The parallel path below respects this limit exactly.

## Data Gathering

### Parallel Path (TEAMS_MODE=true)

When teams mode is active, launch 5 Haiku workers simultaneously. Each worker is independent and read-only — no shared state, no cursor dependencies.

**Worker assignments:**

| Worker | Sources | Model |
|--------|---------|-------|
| Worker 1 | xgh Memory + Team Pulse (magi_query calls) | haiku |
| Worker 2 | Slack (if available) | haiku |
| Worker 3 | Jira/Atlassian (if available) | haiku |
| Worker 4 | GitHub (if available) | haiku |
| Worker 5 | Gmail + Figma (if available) | haiku |

**Worker prompt template:**

Each worker receives:
- Its assigned source list
- The project scope context (project name + scope list if project-scoped)
- The exact tool calls to run (see Sequential Path below for per-source details)
- Instruction: "Return a JSON object `{ source: string, items: [...] }`. Do not synthesize — just gather raw results. If a source is unavailable, return `{ source, items: [], unavailable: true }`."

**After all workers complete:**

Pass all worker results to the current (Sonnet) instance for the Prioritization Engine and Output Format steps. Do not spawn a separate synthesis agent — the current session handles synthesis.

**Token note:** Parallel path costs ~25% more tokens than sequential but reduces wall-clock time by 3–5x. Worth it for interactive sessions; skip for background/cron invocations (use sequential path instead).

### Sequential Path (TEAMS_MODE=false, or background/cron mode)

Gather from each source in order. Skip unavailable sources silently.

#### 1. xgh Memory (always — MAGI)

Search for recent session state and pending work:

```
magi_query("last session", { limit: 3 })
magi_query("in progress", { limit: 3 })
magi_query("blocked", { limit: 2 })
```

If project-scoped, prepend project name to search queries (e.g., "xgh last session").

#### 2. Slack (if available)

```
slack_search_public_and_private("to:me is:unread", limit=10)
slack_search_public_and_private("urgent OR ASAP OR blocked", limit=5)
```

#### 3. Jira/Atlassian (if available)

```
searchJiraIssuesUsingJQL("assignee = currentUser() AND status != Done ORDER BY priority DESC", limit=10)
searchJiraIssuesUsingJQL("assignee = currentUser() AND status = 'In Progress'", limit=5)
```

If project-scoped, append `AND project IN (KEY1, KEY2)` to JQL queries using Jira keys from in-scope projects.

#### 4. GitHub (if available)

```
gh pr list --author @me --state open
gh issue list --assignee @me --state open
gh pr list --review-requested @me --state open
```

If project-scoped, only run these commands for repos belonging to in-scope projects.

#### 5. Gmail (if available)

```
gmail_search_messages("to:me is:unread from:teammate", limit=10)
gmail_search_messages("subject:deadline OR subject:urgent is:unread", limit=5)
```

#### 6. Figma (if available)

```
figma_get_comments(file_key, limit=10)
```

If project-scoped, only check file keys belonging to in-scope projects.

#### 7. Team Pulse (always — from MAGI workspace)

```
magi_query("team update", { limit: 3 })
magi_query("convention change", { limit: 2 })
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

## Compact Mode (`/xgh-briefing compact`)

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
3. Store the session start state: Extract key learnings as a concise summary (3-7 bullets), then [STORE] → call magi_store with the summary text and context-appropriate tags. Do not pass raw conversation content to magi_store. Use tags: "session"

## Scheduler nudge

After delivering the briefing, call CronList and look for jobs with prompt `/xgh-retrieve` or `/xgh-analyze`.

Also check if the pause file exists: `~/.xgh/scheduler-paused`.

If no active CronCreate jobs are found or the pause file exists, append to the briefing output:

```
⚠️ Scheduler not active — briefing data may be stale.
   /xgh-schedule resume    (removes pause file and re-registers jobs)
```

## Rationalization Table

| If you see | Do this |
|------------|---------|
| MAGI backend unavailable | Skip memory sections, note "Run /xgh-setup to enable memory" |
| No Slack/Jira | Skip those sections silently |
| No items in any section | Output "🐴🤖 All clear — no urgent items. Pick something from your backlog." |
| >5 items in a section | Show top 5, add "…and N more" |

## Composability

- Suggests `/xgh-setup` when a source MCP is missing (optional setup, not blocking)
- Feeds into `xgh:implement-ticket` (pre-loaded context for chosen ticket)
- Feeds into `xgh:investigate` (pre-loaded context for chosen incident)
- Informs `xgh:convention-guardian` (team pulse surfaces new conventions)

## Output discipline

When invoked by CronCreate or as a background task:
1. Return the briefing summary inline — concise, structured, no raw API payloads.
