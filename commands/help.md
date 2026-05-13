---
name: xgh-help
description: Contextual guide and command reference — lists all available commands with workflow suggestions
---

# /xgh-help — Guide and Command Reference

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh help`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

When the user invokes `/xgh-help`, follow this procedure:

## Step 1: Check Current State

Run these checks silently (do not show the checks, only the results):

1. **Init status:** Check if `~/.xgh/ingest.yaml` exists and has a profile name that is NOT `YOUR_NAME`
2. **Project tracking:** Check if `~/.xgh/ingest.yaml` has any entries under `projects:` (not empty `{}`)
3. **Codebase indexed:** Search memory for `"repository architecture modules structure"` and check if results exist
4. **MCP connections:** Check whether configured provider and memory connectors respond to a simple read-only probe

## Step 2: Generate Contextual "What to do next"

Based on gaps found in Step 1, generate a recommendation table. Examples:

- If init not done: suggest `/xgh-init`
- If no projects tracked: suggest `/xgh-track`
- If secondary-agent context is stale: suggest `/xgh-seed`
- If everything is set up: suggest `/xgh-briefing`

## Step 3: Display Output

Output using this exact format:

~~~markdown
## 🐴🤖 xgh help

### What to do next

<contextual message based on state checks>

| Step | Command | Why |
|------|---------|-----|
| 1 | `/xgh-<cmd>` | <reason> |
| ... | ... | ... |

### Everyday Commands

| Command | What it does |
|---------|-------------|
| `/xgh-brief` | Quick session briefing alias |
| `/xgh-briefing` | Full briefing — Slack, Jira, GitHub, memory, and suggested focus |
| `/xgh-status` | Memory stats and context tree health |
| `/xgh-command-center` | Cross-project briefing, triage, and dispatch view |
| `/xgh-seed` | Inject xgh project context into other CLI agents' skill directories |
| `/xgh-track` | Add a project to context monitoring |
| `/xgh-trigger` | Manage trigger definitions and firing history |

### Setup & Admin

| Command | What it does |
|---------|-------------|
| `/xgh-init` | First-run onboarding |
| `/xgh-init-providers` | Generate provider scripts from ingest config |
| `/xgh-config` | Show, set, validate, and edit the xgh ingest manifest |
| `/xgh-doctor` | Validate pipeline health |
| `/xgh-calibrate` | Tune dedup similarity threshold |
| `/xgh-retrieve` | Run retrieval loop (usually automated) |
| `/xgh-analyze` | Run analysis loop (usually automated) |
| `/xgh-schedule` | Manage background scheduler and per-skill execution modes |
| `/xgh-token-window` | Check token budget state |

### Suggested Workflows

**Starting a new session:**
`/xgh-briefing` → see what needs attention → `/xgh-command-center` for cross-project triage

**Onboarding to a project:**
`/xgh-track` → `/xgh-init-providers` → `/xgh-retrieve` → `/xgh-briefing`

**After completing significant work:**
Store the key learnings in memory and rerun `/xgh-seed` if secondary-agent context changed.

*Run `/xgh-help` anytime to see this guide.*
~~~
