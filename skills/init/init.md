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
    - cipher: "Cipher MCP — core memory (cipher_memory_search)"
    - slack: "Slack MCP — channel access (slack_read_channel)"
  optional:
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

Let's get started.
```

---

## Step 1 — Verify MCP Connections

Run the same checks as the `xgh:mcp-setup` skill: verify that each MCP integration is configured and responsive.

### Critical (must pass to continue)

| MCP | Detection | Test |
|-----|-----------|------|
| **Cipher** | `cipher_memory_search` tool available | Run `cipher_memory_search` with query "xgh init test" — any response (including empty results) means it works |
| **Slack** | `slack_read_channel` tool available | Run `slack_search_channels` with a common term — any response means it works |

If either critical MCP fails, stop and tell the user:

```
Cipher/Slack MCP is not configured. This is required for xgh to work.
Run /xgh-setup to configure it, then come back and run /xgh-init again.
```

### Optional (note and continue)

| MCP | Detection | On failure |
|-----|-----------|------------|
| **Atlassian** | `getJiraIssue` tool available | "Atlassian not configured — Jira/Confluence features will be skipped. Run /xgh-setup later to add it." |
| **Figma** | `get_design_context` tool available | "Figma not configured — design file tracking will be skipped." |
| **GitHub CLI** | `command -v gh && gh auth status` | "GitHub CLI not configured — repo features will be limited." |

### Output

```
MCP Connection Status:

  [pass/fail] Cipher        — core memory
  [pass/fail] Slack         — channel access
  [pass/fail] Atlassian     — Jira & Confluence
  [pass/fail] Figma         — design files
  [pass/fail] GitHub CLI    — repos & PRs

[N/N critical passed. M/M optional passed.]
```

If all critical passed, proceed. If any optional failed, note which features will be limited and continue.

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

Follow the `xgh:ingest-retrieve` skill logic:
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
You can skip this and do it later with /xgh-team-profile.

Profile team now? [y/N]
```

If **yes**:

1. Ask: "Enter engineer names (comma-separated):"
2. Verify Atlassian MCP is available. If not:
   ```
   Atlassian MCP is required for team profiling. Skipping for now.
   Run /xgh-setup to add Atlassian, then /xgh-team-profile to profile your team.
   ```
3. For each name provided, invoke the `xgh:team-profile` skill workflow.
4. Show a summary of profiles generated.

If **no** (or user skips): Continue to Step 6.

---

## Step 6 — Index Codebase (Optional)

Ask:

```
Want to index your codebase into Cipher memory?
This makes your code searchable for future tasks and investigations.
You can skip this and do it later with /xgh-ingest-index-repo.

Index codebase now? [y/N]
```

If **yes**:

1. Invoke the `xgh:ingest-index-repo` skill in **quick mode**.
2. Show indexing progress and summary.

If **no** (or user skips): Continue to Step 7.

---

## Step 7 — Summary

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

  Next steps:
    - Run /xgh-briefing to get your first daily briefing
    - Run /xgh-retrieve to trigger a manual retrieval cycle
    - Run /xgh-setup to add any missing MCP integrations
```

### Store in Cipher

If Cipher is available, store the onboarding completion:

```
cipher_store_reasoning_memory:
  type: setup
  content: "xgh init completed for <name> (<role>, <squad>). Project: <project>. Team profiles: <yes/no>. Codebase indexed: <yes/no>."
  metadata:
    event: xgh-init-complete
    timestamp: <now>
```

---

## Error Handling

- **install.sh not run:** Detect by missing `~/.xgh/ingest.yaml`. Tell user to run install first.
- **MCP not responding:** If a tool call times out or errors, retry once. If it fails again, mark that integration as unavailable and continue.
- **User wants to stop mid-flow:** At any point, if the user says "stop" or "skip the rest", jump to Step 7 with whatever was completed so far.
- **Partial completion:** If the user has already done some steps (profile filled, project exists), detect that and skip with a note. Never re-do work that's already been done unless the user asks.

---

## Composability

This skill chains together existing skills rather than duplicating their logic:

| Step | Delegates to |
|------|-------------|
| Step 1 — MCP checks | `xgh:mcp-setup` detection protocol |
| Step 3 — Add project | `xgh:ingest-track` full flow |
| Step 4 — Retrieval | `xgh:ingest-retrieve` single cycle |
| Step 5 — Team profiles | `xgh:team-profile` per engineer |
| Step 6 — Index codebase | `xgh:ingest-index-repo` quick mode |
