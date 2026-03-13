---
name: xgh:mcp-setup
description: Interactive MCP server setup helper. Called by workflow skills when a required MCP is not configured. Guides the user through hassle-free first-time setup.
type: flexible
triggers:
  - when a workflow skill detects a missing MCP dependency
  - when the user runs /xgh setup
---

# xgh:mcp-setup — Interactive MCP Setup Helper

When a workflow skill needs an MCP server that isn't configured, don't just skip it — **offer to set it up right now**. The goal is zero-friction first use: the user should never have to leave their terminal or read docs to configure an MCP.

## Supported MCP Servers

| MCP | Detection | Required For |
|-----|-----------|-------------|
| **Cipher** | `cipher_memory_search` in tools | All xgh skills (core dependency) |
| **Slack** | `slack_read_thread` in tools | `investigate`, `implement-ticket` |
| **Figma** | `get_design_context` in tools | `implement-design`, `implement-ticket` |
| **Atlassian** | `getJiraIssue` in tools | `investigate`, `implement-ticket` |
| **GitHub** | `gh` CLI available | `implement-ticket` (Issues) |

## Detection Protocol

At the start of any workflow skill that needs external MCPs, run this check:

```
For each required MCP:
  1. Check if the MCP's tools are available in the current session
  2. If available → proceed normally
  3. If NOT available → trigger the Setup Flow for that MCP
```

## Setup Flow

When a missing MCP is detected:

### Step 1: Inform the user

```
"I need [MCP name] to [specific capability, e.g., 'read the Slack thread'].
It's not configured yet. Want me to set it up? (takes ~30 seconds)"

Options:
  A) Yes, set it up now
  B) Skip — I'll provide the context manually
  C) Skip — don't need this feature
```

### Step 2: If user chooses A — Interactive Setup

Each MCP has a predetermined setup recipe:

#### Slack MCP
The Slack MCP is a Claude.ai first-party integration. It requires:
1. Check if the user has Claude.ai Slack integration enabled
2. If not, guide them:
   ```
   "The Slack MCP is a Claude.ai first-party integration.
   To enable it:
   1. Open Claude Code settings: /settings
   2. Go to 'MCP Servers'
   3. Enable 'Slack' from the built-in integrations
   4. Authorize with your Slack workspace when prompted

   Once done, restart this session and I'll pick up where we left off."
   ```

#### Figma MCP
The Figma MCP is a Claude.ai first-party integration. Setup:
1. Guide the user:
   ```
   "The Figma MCP is a Claude.ai first-party integration.
   To enable it:
   1. Open Claude Code settings: /settings
   2. Go to 'MCP Servers'
   3. Enable 'Figma' from the built-in integrations
   4. Authorize with your Figma account when prompted

   Once done, restart this session and I'll detect it automatically."
   ```

#### Atlassian MCP (Jira/Confluence)
The Atlassian MCP is a Claude.ai first-party integration. Setup:
1. Guide the user:
   ```
   "The Atlassian MCP is a Claude.ai first-party integration.
   To enable it:
   1. Open Claude Code settings: /settings
   2. Go to 'MCP Servers'
   3. Enable 'Atlassian' from the built-in integrations
   4. Authorize with your Atlassian account when prompted

   This gives access to Jira and Confluence.
   Once done, restart this session."
   ```

#### Cipher MCP
Cipher should already be configured by xgh install. If missing:
1. Check if `.claude/.mcp.json` exists with cipher config
2. If not, run the install script:
   ```
   "Cipher MCP is missing. This is xgh's core memory server.
   Let me fix that — running the xgh installer..."
   ```
3. Execute: `XGH_DRY_RUN=0 bash /path/to/install.sh` (or guide manual setup)

#### GitHub Issues (via gh CLI)
Not an MCP — uses `gh` CLI directly:
1. Check: `command -v gh`
2. If missing: `"Install GitHub CLI: brew install gh && gh auth login"`
3. If present but not authed: `gh auth status` → guide through `gh auth login`

#### Linear / Shortcut / Asana / Other Task Managers
These use community MCP servers. Setup pattern:
1. Ask which task manager the user uses
2. Provide the appropriate `npx` command for `.claude/.mcp.json`:
   ```json
   {
     "mcpServers": {
       "linear": {
         "command": "npx",
         "args": ["-y", "@anthropic/mcp-linear"],
         "env": {
           "LINEAR_API_KEY": "${LINEAR_API_KEY}"
         }
       }
     }
   }
   ```
3. Guide through API key generation if needed
4. Offer to add to `.claude/.mcp.json` automatically

### Step 3: Verify Setup

After setup instructions:
1. Ask the user to confirm they've completed the steps
2. If MCP requires session restart, inform the user:
   ```
   "Setup complete! Please restart Claude Code for the new MCP to be available.
   When you restart, run the same command again — I'll remember where we left off
   via Cipher memory."
   ```
3. If MCP is immediately available (no restart needed), verify:
   - Try a simple MCP tool call
   - If it works → continue with the workflow
   - If it fails → troubleshoot (auth expired, wrong workspace, etc.)

### Step 4: Remember the Setup

After successful first-time setup:
1. Store in Cipher memory:
   ```
   cipher_store_reasoning_memory:
     type: setup
     content: "[MCP name] configured for [user/team]"
     metadata:
       mcp: slack|figma|atlassian|linear|...
       configured_at: [timestamp]
       workspace: [workspace name if applicable]
   ```
2. Future sessions skip the "want to set it up?" prompt — the MCP is expected to be available

## Composability

This skill is called BY other skills, never directly by the user (though `/xgh setup` can trigger a full audit). The calling skill:

1. Checks for required MCPs
2. If missing, invokes this skill's setup flow
3. Gets back: `available` (proceed) or `skipped` (degrade gracefully)
4. Continues its own flow

## Full Audit Mode (`/xgh setup`)

When triggered manually, audit ALL MCP integrations:

```
"🐴🤖 xgh MCP Integration Status:

  ✅ Cipher        — configured (core memory)
  ❌ Slack         — not configured
  ✅ Figma         — configured
  ❌ Atlassian     — not configured
  ✅ GitHub CLI    — authenticated

  Want me to set up the missing integrations?"
```

Then walk through each missing MCP interactively.
