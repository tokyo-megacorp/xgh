---
name: xgh:track
description: >
  Interactive project onboarding. Prompts for Slack channels, Jira, Confluence, Figma,
  and GitHub refs, validates connectivity, runs initial backfill of recent Slack history,
  and appends the project to ~/.xgh/ingest.yaml.
type: flexible
triggers:
  - when the user runs /xgh-track
  - when the user says "add project", "track project", "monitor new project"
mcp_dependencies:
  - mcp__claude_ai_Slack__slack_search_channels
  - mcp__claude_ai_Atlassian__getJiraIssue
  - mcp__claude_ai_Atlassian__getConfluencePage
---
> **Context-mode:** Use `ctx_execute_file` for analysis reads; `Read` only for files you will
> Edit within 1-2 tool calls. Use `ctx_batch_execute` for multi-command research. Full routing
> rules: `plugin/references/context-mode-routing.md`


## Preamble — Execution mode

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('track')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **track** in background (returns summary when done) or interactive? [b/i, default: i]"
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
p['skill_mode']['track'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` → use background mode
- contains `--interactive` or `--fg` → use interactive mode
- contains `--checkin` → use check-in autonomy
- contains `--auto` → use fire-and-forget autonomy
- contains `--reset` → run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('track',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** → proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context: user's request verbatim, current branch (`git branch --show-current`), recent log (`git log --oneline -5`), any relevant file paths mentioned.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply: "Track running in background — I'll post findings when done."
5. When agent completes: post a ≤5-bullet summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions).
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "Track running in background — I'll post findings when done."
4. When agent completes: post a ≤5-bullet summary.

---

# xgh:track — Project Onboarding

Interactive skill to add a new project to xgh monitoring. Ask one question at a time.

## Step 1 — Collect project details

Ask each question below separately. Validate before moving to the next.

1. **Project name** — free text. Derive config key: lowercase, spaces → hyphens, no special chars.
   Example: "Passcode Feature" → `passcode-feature`

2. **Your role in this project** (`my_role`) — suggest common values: `ios-lead`, `mobile-lead`, `engineer`, `reviewer`, `observer`. Let the user type any value. Default to `engineer` if they skip.

3. **What you own / coordinate** (`my_intent`) — free text describing what the user owns, delegates, or coordinates in this project. Example: "I own the iOS implementation, delegate QA to the platform team, and coordinate with backend on API changes." Let the user skip with empty.

4. **Slack channels** — comma-separated channel names (with or without `#`).
   For each, verify accessibility via `slack_search_channels`. If not found, show error and re-ask.

5. **Jira project key** (optional) — e.g. `PTECH-31204`. If provided, call `getJiraIssue` with a search to verify. Show count of open issues if found.

6. **Confluence links** (optional) — paste RFC/spec/wiki URLs one per line. For each, call `getConfluencePage` to verify access, then extract key learnings as a concise summary (3-7 bullets), call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store. Use tags: ["session"].

7. **Figma links** (optional) — store as plain refs (no indexing in v1).

8. **GitHub repos** (optional) — `org/repo` format. Store as refs. If provided, ask:
   `Index codebase now? [y/n]` — if yes, invoke the xgh:index skill in quick mode.

9. **Default access level** — ask: "Default access level for all providers? (`read` / `ask` / `auto`)" Default to `read` if the user skips.
   - `read` — observe only; can fetch data, never writes back to the provider.
   - `ask` — can propose write actions, but must confirm with the user first.
   - `auto` — fully autonomous writes (e.g., auto-post digests, transition tickets).
   Set all five providers (slack, jira, confluence, github, figma) to the chosen level. Note that the user can customize per-provider later in `~/.xgh/ingest.yaml`.

## Step 2 — Initial backfill

Read the last 200 messages from each Slack channel using `slack_read_channel`. For each message containing a Jira/Confluence/GitHub link, stash it to `~/.xgh/inbox/` and add the ref to the enrichment list.

Show progress:
```
Scanning #ptech-31204-engineering... found 12 Jira links, 3 Confluence pages, 2 PRs
Auto-enriching project config with discovered references.
```

## Step 3 — Write to ingest.yaml

Use python3 to safely read, update, and write `~/.xgh/ingest.yaml` (read → modify dict → yaml.dump):

```yaml
projects:
  passcode-feature:
    status: active
    my_role: ios-lead
    my_intent: "Own iOS implementation, delegate QA to platform team, coordinate backend API changes"
    providers:
      slack:      { access: read }
      jira:       { access: read }
      confluence: { access: read }
      github:     { access: read }
      figma:      { access: read }
    slack:
      - "#ptech-31204-general"
      - "#ptech-31204-engineering"
    jira: PTECH-31204
    confluence:
      - /spaces/PTECH/pages/rfc-passcode-v2
    github:
      - acme-corp/acme-ios
    figma:
      - https://figma.com/design/abc123/passcode-screens
    rfcs: []
    index:
      last_full: null
      schedule: weekly
      watch_paths: []
    last_scan: null
```

## Step 4 — Confirm

```
✓ Project "passcode-feature" added to ~/.xgh/ingest.yaml
  Role: ios-lead
  Channels: #ptech-31204-general, #ptech-31204-engineering
  Initial backfill: 15 items queued in ~/.xgh/inbox/
  Next retriever run will include this project.

Run /xgh-doctor to verify the full pipeline is healthy.
```

## Step 5 — Scheduler Setup

Check if background scheduling is active:

1. Call CronList — check for jobs where prompt is `/xgh-retrieve` or `/xgh-analyze`.
2. Check if `~/.xgh/scheduler-paused` exists (pauses the scheduler).

**If both cron jobs exist**: show `✅ Scheduler active` and stop here.

**If jobs missing**: Ask:

```
Enable background scheduling?
  retrieve: every 5 min  (scans Slack, GitHub for new items)
  analyze:  every 30 min (classifies and stores to memory)

Jobs auto-expire after 3 days and are re-created each session automatically.

Enable? [Y/n]
```

If **yes**:
1. Register CronCreate jobs immediately:
   - retrieve: `cron: "*/5 * * * *"`, `prompt: "/xgh-retrieve"`, `recurring: true`
   - analyze: `cron: "*/30 * * * *"`, `prompt: "/xgh-analyze"`, `recurring: true`
2. Remove pause file if present: `rm -f ~/.xgh/scheduler-paused`
3. Report: `✅ Scheduler enabled — retrieve (*/5) and analyze (*/30) registered.`

If **no**: `⚠️ Scheduler not enabled. Run /xgh-schedule resume anytime.`
