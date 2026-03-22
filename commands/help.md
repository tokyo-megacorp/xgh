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
3. **Codebase indexed:** Run `lcm_search("repository architecture modules structure")` and check if results exist
4. **MCP connections:** Check if lossless-claude MCP responds (run a simple memory search with `lcm_search`)

## Step 2: Generate Contextual "What to do next"

Based on gaps found in Step 1, generate a recommendation table. Examples:

- If init not done: suggest `/xgh-init`
- If no projects tracked: suggest `/xgh-track`
- If codebase not indexed: suggest `/xgh-index`
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
| `/xgh-briefing` | Morning briefing — Slack, Jira, GitHub summary |
| `/xgh-status` | Memory stats and context tree health |
| `/xgh-ask` | Search your memory with natural language |
| `/xgh-investigate` | Debug from a Slack thread or bug report |
| `/xgh-implement` | Implement a ticket with full context |
| `/xgh-design` | Implement a UI from a Figma design |
| `/xgh-codex` | Dispatch tasks to Codex CLI (exec or review) |
| `/xgh-gemini` | Dispatch tasks to Gemini CLI (exec or review) |
| `/xgh-opencode` | Dispatch tasks to OpenCode CLI (exec or review) |
| `/xgh-seed` | Inject xgh project context into other CLI agents' skill directories |
| `/xgh-copilot-pr-review` | Manage GitHub Copilot PR code reviews — request, re-review, status, comments, reply, delegate |
| `/xgh-collab` | Coordinate with other AI agents |
| `/xgh-curate` | Store knowledge in memory + context tree |
| `/xgh-profile` | Analyze an engineer's Jira throughput |

### Setup & Admin

| Command | What it does |
|---------|-------------|
| `/xgh-init` | First-run onboarding |
| `/xgh-setup` | Audit and configure MCP integrations |
| `/xgh-track` | Add a project to context monitoring |
| `/xgh-index` | Index a codebase into memory |
| `/xgh-doctor` | Validate pipeline health |
| `/xgh-calibrate` | Tune dedup similarity threshold |
| `/xgh-retrieve` | Run retrieval loop (usually automated) |
| `/xgh-analyze` | Run analysis loop (usually automated) |

### Suggested Workflows

**Starting a new session:**
`/xgh-briefing` → see what needs attention → `/xgh-implement` or `/xgh-investigate`

**Onboarding to a project:**
`/xgh-track` → `/xgh-index` → `/xgh-briefing`

**After completing significant work:**
`/xgh-curate` to capture what you learned

*Run `/xgh-help` anytime to see this guide.*
~~~
