---
name: xgh:command-center
description: "This skill should be used when the user runs /xgh-command-center or says 'open command center', 'global view', 'orchestrate'. Global orchestrator view — runs a full cross-project briefing, triages signals, and dispatches work to the right project session. Hub-and-spoke for morning reviews and continuous monitoring."
---

> **Output format:** Follow the [xgh output style guide](../../templates/output-style.md). Start with `## 🐴🤖 xgh command center`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# xgh:command-center — Global Orchestrator

You are the hub-and-spoke orchestrator across all active xgh projects. Unlike per-project sessions, command center has no project scope — it sees everything.

## Dispatch Heuristic (baked in as `auto_dispatch` default)

| Task type | Method |
|-----------|--------|
| Investigate, triage, summarize, search memory | In-session background Agent (returns to command center) |
| Implement, write code, create PRs, long-running work | Separate `claude` session launched in project directory |

---

## Routing

Parse the invocation to determine mode:

| Invocation | Mode |
|------------|------|
| `/xgh-command-center` | Full command center (briefing + triage) |
| `/xgh-command-center morning` | Morning ritual (full briefing, then await commands) |
| `/xgh-command-center pulse` | Compact one-line-per-project status |
| `/xgh-command-center dispatch` | List in-flight subagents and their status |

---

## Preamble — Mode Detection

Check if the session is scoped to a project by looking for `activeProject` in session context, or if the current working directory is a known project directory (i.e., contains a `.xgh/context-tree` folder).

If a project scope is detected, warn:

```
⚠️ You're in a project directory. Command center works best from a neutral
   directory (e.g., ~). Continue anyway? [y/N]
```

If the user says N or does not respond, stop. If yes, proceed.

---

## Step 1 — Load Config

Read `~/.xgh/ingest.yaml`:
- Collect ALL entries under `projects:` where `status: active` (no scope filtering)
- Read the `command_center:` config section; use defaults if absent:
  - `dispatch_mode: auto_triage`
  - `morning_briefing: "0 8 * * 1-5"`
  - `pulse: "*/15 * * * *"`
  - `quiet_hours: "22:00-07:00"` (or inherit from `schedule.quiet_hours`)

---

## Step 2 — Global Briefing

For each active project, run `xgh:briefing` logic in parallel using background Agents.

Gather from every project:
- GitHub: `gh pr list --state open`, `gh issue list --assignee @me --state open`, `gh pr list --review-requested @me --state open`
- lossless-claude: `lcm_search("in progress OR blocked OR needs review", { limit: 3 })`

Output format adds a **project label** to every item:

```
## 🐴🤖 xgh command center — [date] [time]

### NEEDS YOU NOW
- [project-name] Issue #143: ctx_batch_execute passes commands as string — urgency 60
- [project-name] PR review requested on #18

### IN PROGRESS
- [project-name] Implementing dispatch-file handoff

### INCOMING
- [project-name] Release 2.1.0 scheduled Friday

### TEAM PULSE
- [project-name] Convention change: use ctx_execute_file for large outputs
```

Hard cap: **5 items per section** across all projects. Sort by urgency within each section.

---

## Step 3 — Triage Loop

Behaviour depends on `dispatch_mode` from config:

### `alert_only`
Display items only. Ask user: "What would you like to do with these?"

### `auto_triage` (default)

For each NEEDS-YOU-NOW item, dispatch an in-session background Agent:

```
Agent task: "Read [issue/PR URL], check linked PRs/commits, form a triage recommendation.
Post back: { project, ref, root_cause, suggested_action, confidence }"
```

When each agent returns, surface:

```
[project] #143 investigated ✅
  Root cause: X
  Suggested action: Y
  Implement? [y/N]
```

### `auto_dispatch`

After triage, for items where user confirmed implement, launch a separate Claude session:

```bash
mkdir -p ~/.xgh/inbox
cat > ~/.xgh/inbox/.dispatch.md << 'EOF'
---
type: dispatch
project: <project>
action: implement
ref: "<ref>"
context: "<root_cause>. Suggested approach: <suggested_action>."
---
EOF

cd ~/Developer/<project-dir>
claude --session-name "<project>: implement <ref>"
```

Session naming uses `command_center.session_name_template` from config, defaulting to `"{project}: {action} {ref}"`.

Examples:
- `"context-mode: implement #143"`
- `"xgh: investigate PR #18"`

---

## Step 4 — Scheduler Setup

Register CronCreate jobs for this session:

1. **Morning briefing**: `cron: "0 8 * * 1-5"`, `prompt: "/xgh-command-center morning"`, `recurring: true`
2. **Pulse**: `cron: "*/15 * * * *"`, `prompt: "/xgh-command-center pulse"`, `recurring: true`

Only register if not already present (check CronList first).

---

## Step 5 — Scheduler Nudge

Check CronList for `/xgh-retrieve` and `/xgh-analyze` jobs. The scheduler is always-on; if jobs are missing they may be paused.

If neither is active:

```
⚠️ Background retriever not active — command center data may be stale.
   /xgh-schedule resume    (removes ~/.xgh/scheduler-paused and re-registers jobs)
```

---

## Pulse Mode (`/xgh-command-center pulse`)

Compact output — one line per project, counts only:

```
🐴🤖 pulse — context-mode: 2 new · xgh: quiet · inspector: quiet · lossless-claude: quiet
```

For each project, fetch only the count of new/open items from GitHub (unread PRs + assigned issues). Skip memory and Slack for pulse. Output on a single line.

---

## Morning Mode (`/xgh-command-center morning`)

Full briefing (Step 2) + triage (Step 3), then enter an await loop:
- Output: "Ready. Type a project name or item ref to dispatch, or `pulse` for a quick check."
- Wait for user input.

---

## Dispatch Mode (`/xgh-command-center dispatch`)

Call CronList and check for running background Agents in this session.

Display:

```
## 🐴🤖 xgh command center — in-flight

| Ref | Project | Action | Status |
|-----|---------|--------|--------|
| #143 | context-mode | investigate | ✅ complete |
| #18 | xgh | triage | ⏳ running |
```

---

## Rationalization Table

| If you see | Do this |
|------------|---------|
| No active projects | "⚠️ No active projects in ~/.xgh/ingest.yaml. Run /xgh-track to add one." |
| `command_center:` section missing from ingest.yaml | Use defaults silently |
| Agent returns no result | Mark as ❌ failed, surface to user |
| quiet_hours active | Skip triage, show briefing only |
| lossless-claude unavailable | Skip memory sections, note "Run /xgh-setup to enable memory" |
