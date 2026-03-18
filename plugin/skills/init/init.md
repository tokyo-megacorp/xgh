---
name: xgh:init
description: >
  First-run onboarding after install. Verifies MCP connections, sets up profile,
  adds first project, runs initial retrieval, and optionally profiles the team
  and indexes the codebase. Run once per project setup.
type: flexible
triggers:
  - when invoked via /xgh-init command
  - when the user says "set up xgh" or "initialize xgh" or "get started"
mcp_dependencies:
  required:
    - lossless-claude: "lossless-claude MCP — core memory (lcm_search)"
  optional:
    - slack: "Slack MCP — channel access (slack_read_channel)"
    - atlassian: "Atlassian MCP — Jira/Confluence (getJiraIssue)"
    - figma: "Figma MCP — design files (get_design_context)"
    - github: "GitHub CLI — gh command available"
---

# xgh:init — First-Run Onboarding

Welcome the user to xgh and walk them through the full first-run setup. This is their first experience with the system, so keep it conversational and clear. Ask one thing at a time, confirm each step before moving on.

Start with:

```
Welcome to xgh — eXtreme Go Horse for AI Teams.

I'll walk you through first-time setup. This takes about 5 minutes and covers:
  1. Verify MCP connections
  2. Set up your profile
  3. Add your first project
  4. Run initial retrieval
  5. (Optional) Profile your team
  6. (Optional) Index your codebase
  7. (Optional) Curate initial knowledge
  8. Enable background scheduling

Let's get started.
```

---

## Step 0: Dependency Check (run before scaffolding)

Check each dependency below in order. Respond per the instructions for each result.

### lossless-claude MCP

Run in Bash: `claude mcp list 2>/dev/null | grep -i lossless-claude`

- **Found** → continue
- **Not found** → report: "lossless-claude MCP not configured. Run `install.sh` to configure it."

### Qdrant

Run in Bash: `curl -sf --max-time 3 "${QDRANT_URL:-http://localhost:6333}/healthz"`

- **Responds** → continue
- **Unreachable** → report: "Qdrant is not running. To fix: run `install.sh` to install it locally, or set `XGH_BACKEND=remote` and `XGH_REMOTE_URL=<url>` to use a remote endpoint."

### Inference backend

Run in Bash: `curl -sf --max-time 3 "${XGH_REMOTE_URL:-http://localhost:11434}/v1/models"`

- **Responds** → continue
- **Unreachable** → report: "Inference backend not running. To fix: run `install.sh` to install vllm-mlx (macOS) or Ollama (Linux), or set `XGH_BACKEND=remote`."

### Partial mode (all three checks fail)

Proceed with scaffolding anyway. After completing, tell the user:

> "xgh memory tools are not yet configured — context tree scaffolded successfully. Run `install.sh` or `/plugin install github:ipedro/xgh` to complete setup. lossless-claude search will not work until the daemon is running."

---

## Step 0b: Stale Install Cleanup

Check for old-style per-project skill copies from pre-plugin installs:

Run in Bash:

```bash
ls .claude/skills/ 2>/dev/null | grep "^xgh-"
ls .claude/commands/ 2>/dev/null | grep "^xgh-"
```

If any `xgh-*` entries are found:

1. Remove them:
   ```bash
   rm -rf .claude/skills/xgh-* .claude/commands/xgh-* 2>/dev/null || true
   ```

2. Report: "Removed legacy per-project skill copies. Skills now load from the user-level plugin at `~/.claude/plugins/cache/ipedro/xgh/`."

If none found → continue silently.

---

## Step 1 — Verify MCP Connections

Run the MCP detection protocol from the `xgh:mcp-setup` skill before proceeding.

---

## Step 2 — Profile Setup

### Check prerequisites

Check if `~/.xgh/ingest.yaml` exists. If not, stop:

```
~/.xgh/ingest.yaml not found. Run install.sh first:

  XGH_LOCAL_PACK=. bash install.sh

Then come back and run /xgh-init again.
```

### Check if profile is already configured

Read `~/.xgh/ingest.yaml` and check if `profile.name` exists and is not the template default (`"Your Name"`). If the profile is already filled in, show what's there and ask:

```
Profile already configured:
  Name: Pedro
  Role: engineer
  Squad: mobile

Keep this? [Y/n]
```

If they say yes, skip to Step 3. If no, re-ask the questions below.

### Collect profile info

Ask each question one at a time:

1. **Name** — "What's your name?" (free text)

2. **Slack user ID** — "What's your Slack user ID? (e.g., U01ABCDEF)"
   - If Slack MCP is available, offer: "I can try to look it up — what's your Slack display name?"
   - Use `slack_search_users` with their display name to find the user ID
   - Let them confirm or type it manually

3. **Role** — "What's your role? (engineer / lead / manager)"
   - Default to `engineer` if they skip

4. **Squad/team** — "What squad or team are you on?" (free text)

5. **Platforms** — "What platforms do you work on? (comma-separated: ios, android, web, backend)"

### Write profile

Use python3 to safely read, modify, and write `~/.xgh/ingest.yaml`:

```python
import yaml
with open(os.path.expanduser('~/.xgh/ingest.yaml'), 'r') as f:
    config = yaml.safe_load(f)
config['profile'] = {
    'name': '<name>',
    'slack_user_id': '<slack_id>',
    'role': '<role>',
    'squad': '<squad>',
    'platforms': ['ios', 'android']
}
with open(os.path.expanduser('~/.xgh/ingest.yaml'), 'w') as f:
    yaml.dump(config, f, default_flow_style=False)
```

Confirm:

```
Profile saved:
  Name: Pedro
  Slack: U01ABCDEF
  Role: engineer
  Squad: mobile
  Platforms: ios, android
```

---

## Step 3 — Add First Project

Check if `projects:` in `~/.xgh/ingest.yaml` already has entries. If so:

```
You already have projects configured:
  - passcode-feature (active)

Add another project? [y/N]
```

If no existing projects (or user wants to add one), invoke the `/xgh-track` workflow. Follow that skill's full interactive flow:
- Collect project name, Slack channels, Jira, Confluence, GitHub, Figma sources
- Ask for `my_role` and `my_intent`
- Ask for default provider access level
- Run initial backfill

Wait for the `/xgh-track` flow to complete before proceeding.

---

## Step 4 — Initial Retrieval

Run a single retrieval cycle to backfill recent messages from the configured channels.

```
Running initial retrieval to catch up on recent activity...
```

Follow the `xgh:retrieve` skill logic:
- Scan each configured Slack channel for recent messages
- Follow links 1-hop to Jira/Confluence/GitHub/Figma
- Stash raw content to `~/.xgh/inbox/`

Show progress:

```
Scanning #ptech-31204-general... 45 messages, 8 links found
Scanning #ptech-31204-engineering... 62 messages, 14 links found
Stashed 22 items to ~/.xgh/inbox/

Initial retrieval complete.
```

---

## Step 5 — Team Profiling (Optional)

Ask:

```
Want to profile your team members for smart task assignment?
This analyzes their Jira history to build throughput and affinity profiles.
You can skip this and do it later with /xgh-profile.

Profile team now? [y/N]
```

If **yes**:

1. Ask: "Enter engineer names (comma-separated):"
2. Verify Atlassian MCP is available. If not:
   ```
   Atlassian MCP is required for team profiling. Skipping for now.
   Run /xgh-setup to add Atlassian, then /xgh-profile to profile your team.
   ```
3. For each name provided, invoke the `xgh:profile` skill workflow.
4. Show a summary of profiles generated.

If **no** (or user skips): Continue to Step 6.

---

## Step 6 — Index Codebase (Optional)

Ask:

```
Want to index your codebase into lossless-claude memory?
This makes your code searchable for future tasks and investigations.
You can skip this and do it later with /xgh-index.

Index codebase now? [y/N]
```

If **yes**:

1. Invoke the `xgh:index` skill in **quick mode**.
2. Show indexing progress and summary.

If **no** (or user skips): Continue to Step 7.

---

## Step 7 — Initial Curation (Optional)

Ask:

```
Want to curate any initial knowledge? (architecture decisions, team conventions, known gotchas)
This captures important context that helps future sessions work better.
You can skip this and do it later with /xgh-curate.

Curate initial knowledge now? [y/N]
```

If **yes**:

1. Invoke the `xgh:curate` skill interactively.
2. Let the user capture as many items as they want.
3. When done, show a summary of what was stored.

If **no** (or user skips): Continue to Step 7b.

---

## Step 7b — Scheduler Setup

Check if background scheduling is configured:

1. Check `XGH_SCHEDULER` in the environment:
   ```bash
   python3 -c "import os; print(os.environ.get('XGH_SCHEDULER', ''))"
   ```
2. Call CronList — check for jobs where prompt is `/xgh-retrieve` or `/xgh-analyze`.

**If already configured** (env var is `on` OR both cron jobs exist): show `✅ Scheduler active` and continue to Step 8.

**If not configured**: Ask:

```
Enable background scheduling?
  retrieve: every 5 min  (scans Slack, GitHub for new items)
  analyze:  every 30 min (classifies and stores to memory)

Jobs auto-expire after 3 days and are re-created each session when XGH_SCHEDULER=on.

Enable? [Y/n]
```

If **yes**:
1. Detect shell profile (prefer `~/.zshrc`, fall back to `~/.zprofile`, then `~/.bash_profile`):
   ```bash
   python3 -c "
   import os
   for f in ['~/.zshrc', '~/.zprofile', '~/.bash_profile', '~/.profile']:
       p = os.path.expanduser(f)
       if os.path.exists(p): print(p); break
   "
   ```
2. Append `export XGH_SCHEDULER=on` if not already present:
   ```bash
   grep -q 'XGH_SCHEDULER=on' <profile_file> || echo 'export XGH_SCHEDULER=on' >> <profile_file>
   ```
3. Register CronCreate jobs immediately:
   - retrieve: `cron: "*/5 * * * *"`, `prompt: "/xgh-retrieve"`, `recurring: true`
   - analyze: `cron: "*/30 * * * *"`, `prompt: "/xgh-analyze"`, `recurring: true`
4. Report: `✅ Scheduler enabled — retrieve (*/5) and analyze (*/30) registered. Added XGH_SCHEDULER=on to <profile>.`

If **no**: `⚠️ Scheduler not enabled. Run /xgh-schedule resume anytime, or add export XGH_SCHEDULER=on to your shell profile.`

---

## Step 8 — Summary

Print a final recap of everything that was configured:

```
xgh setup complete!

  Profile
    Name: Pedro
    Role: engineer
    Squad: mobile
    Platforms: ios, android

  Project: passcode-feature
    Channels: #ptech-31204-general, #ptech-31204-engineering
    Jira: PTECH-31204
    Confluence: 1 page linked
    GitHub: acme-corp/acme-ios

  Team Profiles: [generated for Alice, Bob / skipped]
  Codebase Index: [indexed / skipped]
  Scheduler:     [✅ active (*/5, */30) / ⚠️ not enabled]

  Next steps:
    - Run /xgh-brief to get your first daily briefing
    - Run /xgh-setup to add any missing MCP integrations
```

### Store in lossless-claude

If lossless-claude is available, store the onboarding completion:

```
Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the
summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store.
Use tags: ["session"]
Content: "xgh init completed for <name> (<role>, <squad>). Project: <project>. Team profiles: <yes/no>. Codebase indexed: <yes/no>."
```

---

## Error Handling

- **install.sh not run:** Detect by missing `~/.xgh/ingest.yaml`. Tell user to run install first.
- **MCP not responding:** If a tool call times out or errors, retry once. If it fails again, mark that integration as unavailable and continue.
- **User wants to stop mid-flow:** At any point, if the user says "stop" or "skip the rest", jump to Step 8 (Summary) with whatever was completed so far.
- **Partial completion:** If the user has already done some steps (profile filled, project exists), detect that and skip with a note. Never re-do work that's already been done unless the user asks.

---

## Composability

This skill chains together existing skills rather than duplicating their logic:

| Step | Delegates to |
|------|-------------|
| Step 1 — MCP checks | `xgh:mcp-setup` detection protocol |
| Step 3 — Add project | `xgh:track` full flow |
| Step 4 — Retrieval | `xgh:retrieve` single cycle |
| Step 5 — Team profiles | `xgh:profile` per engineer |
| Step 6 — Index codebase | `xgh:index` quick mode |
| Step 7 — Initial curation | `xgh:curate` interactive |
| Step 7b — Scheduler | CronList + CronCreate + shell profile write |
