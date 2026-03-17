---
name: xgh:mcp-setup
description: Interactive MCP server setup helper. Called by workflow skills when a required MCP is not configured. Guides the user through hassle-free first-time setup.
type: flexible
triggers:
  - when a workflow skill detects a missing MCP dependency
  - when the user runs /xgh-setup
---

# xgh:mcp-setup — Interactive MCP Setup Helper

When a workflow skill needs an MCP server that isn't configured, don't just skip it — **offer to set it up right now**. The goal is zero-friction first use: the user should never have to leave their terminal or read docs to configure an MCP.

## How MCPs Work in Claude Code

Claude Code has two kinds of MCP servers:

1. **Remote MCPs** — first-party, managed by Anthropic (`claude.ai *` in `claude mcp list`). Zero config, OAuth-based. Examples: Gmail, Google Calendar. These come and go as Anthropic adds them.
2. **Local MCPs** — configured in `.claude/mcp.json`, run via `npx` or a local binary. Require API keys. Examples: Slack, Atlassian, Figma, Linear.

**Detection is runtime-only.** Don't assume which remote MCPs exist — check `claude mcp list` for what's actually connected. The landscape changes as Anthropic adds new connectors.

## Supported Integrations

| Service | Detection (tool name) | Required For | Setup |
|---------|----------------------|-------------|-------|
| **lossless-claude** | `mcp__lossless-claude__lcm_search` | All xgh skills (core) | Installed by xgh |
| **GitHub** | `gh` CLI or remote MCP | `implement`, `investigate` | `brew install gh && gh auth login` |
| **Slack** | `slack_*` tools | `investigate`, `brief`, `retrieve` | Community MCP |
| **Atlassian** | `getJiraIssue`, `confluence_*` | `implement`, `investigate` | Community MCP |
| **Figma** | `get_design_context` | `design` | Community MCP |
| **Linear** | `linear_*` tools | `implement` | Community MCP |
| **Asana** | `asana_*` tools | `implement` | Community MCP |
| **Shortcut** | `shortcut_*` tools | `implement` | Community MCP |

## Detection Protocol

At the start of any workflow skill that needs external MCPs:

```
For each required MCP:
  1. Check if the MCP's tools are available in the current session
  2. If available → proceed normally
  3. If NOT available → trigger the Setup Flow
```

## MCP Auto-Detection Protocol

This is the canonical first-use detection procedure used by all workflow skills (`xgh:design`, `xgh:implement`, `xgh:investigate`, etc.).

**Procedure (run at the start of every workflow skill invocation):**

1. Test each relevant MCP by checking if its sentinel tool appears in the current session
2. For any missing MCP: inform the user — "Want me to set up [MCP name]? Run `xgh:mcp-setup` for [mcp]"
3. If user skips: proceed with graceful degradation (skill-specific rules apply)
4. If user sets up: verify tools appear, then continue with full capability
5. Report detected integrations before proceeding:

```
Available integrations:
  [x] <Integration A> — <what this skill will do with it>
  [x] <Integration B> — <what this skill will do with it>
  [ ] <Integration C> — not configured, <graceful fallback description>
  [ ] <Integration D> — not configured, skipping <feature>
```

**Rules:**
- Never hard-fail on a missing optional MCP — always degrade gracefully
- Always report the integration status before starting work
- Sentinel tools by integration: Figma → `get_design_context`, lossless-claude → `mcp__lossless-claude__lcm_search`, Atlassian/Jira → `getJiraIssue`, Slack → `slack_search_public`, Linear → `linear_*`

## Setup Flow

### Step 1: Inform the user

```
"I need [capability, e.g., 'to read the Slack thread'] but [MCP name] isn't configured.
Want me to help set it up? (takes ~30 seconds)"

Options:
  A) Yes, set it up now
  B) Skip — I'll provide the context manually
  C) Skip — don't need this feature
```

### Step 2: Check for remote MCP first

Before guiding community MCP setup, check if the service is already available as a remote MCP:

```bash
claude mcp list 2>/dev/null | grep -i "[service]"
```

If it shows `✓ Connected` — the user already has it. Just use it.

If it shows as available but not connected, or the service might be available as a remote MCP:

```
"[Service] might be available as a Claude connector (zero config, no API key).
Check: Claude.ai → Settings → Connectors → look for [Service].

If it's there, enable it and restart this session.
If not, I'll set up the community MCP instead."
```

### Step 3: Community MCP Setup

For services that need a local MCP server:

```
"[Service] needs a community MCP server with an API key.

Steps:
  1. Get your API token from [specific URL]
  2. I'll add the MCP config to .claude/mcp.json
  3. Restart this session

Ready? I'll need your [TOKEN_NAME]."
```

Then add to `.claude/mcp.json`:
```json
{
  "mcpServers": {
    "[service]": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "[package]"],
      "env": {
        "[ENV_VAR]": "[user-provided-token]"
      }
    }
  }
}
```

**Community MCP packages and API key sources:**

| Service | Package | Env Vars | Token URL |
|---------|---------|----------|-----------|
| Slack | `@anthropic/mcp-slack` | `SLACK_BOT_TOKEN` | https://api.slack.com/apps |
| Atlassian | `@anthropic/mcp-atlassian` | `ATLASSIAN_API_TOKEN`, `ATLASSIAN_SITE_URL`, `ATLASSIAN_EMAIL` | https://id.atlassian.com/manage-profile/security/api-tokens |
| Figma | `@anthropic/mcp-figma` | `FIGMA_ACCESS_TOKEN` | https://www.figma.com/developers/api#access-tokens |
| Linear | `@anthropic/mcp-linear` | `LINEAR_API_KEY` | https://linear.app/settings/api |
| Asana | `@anthropic/mcp-asana` | `ASANA_ACCESS_TOKEN` | https://app.asana.com/0/developer-console |
| Shortcut | `@anthropic/mcp-shortcut` | `SHORTCUT_API_TOKEN` | https://app.shortcut.com/settings/account/api-tokens |

### lossless-claude MCP

lossless-claude should already be configured by xgh install. If missing:
1. Check if `.claude/mcp.json` exists with lossless-claude config
2. If not: `XGH_LOCAL_PACK=. bash install.sh`

### GitHub

Check in order:
1. Remote MCP connected? (`claude mcp list | grep -i github`) → use it
2. `gh` CLI available and authed? (`gh auth status`) → use it
3. Neither → `brew install gh && gh auth login`

### Step 4: Verify Setup

After setup instructions:
1. If MCP requires session restart:
   ```
   "Setup complete! Restart Claude Code for the new MCP to load.
   Run the same command again — I'll pick up where we left off via lossless-claude memory."
   ```
2. If immediately available, try a simple tool call to verify.

### Step 5: Remember the Setup

After successful setup, store in lossless-claude:
```
Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the
summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store.
Use tags: ["session"]
Content: "[MCP name] configured for [user/team]"
```

## Composability

This skill is called BY other skills, never directly by the user (though `/xgh-setup` can trigger a full audit). The calling skill:

1. Checks for required MCPs
2. If missing, invokes this skill's setup flow
3. Gets back: `available` (proceed) or `skipped` (degrade gracefully)
4. Continues its own flow

## Full Audit Mode (`/xgh-setup`)

When triggered manually, audit ALL MCP integrations by running `claude mcp list` and checking tool availability:

```
"🐴 xgh Integration Status:

  Connected:
    ✅ lossless-claude — core memory
    ✅ Gmail         — remote MCP
    ✅ Calendar      — remote MCP

  Not configured:
    ❌ Slack         — community MCP (needs API key)
    ❌ Atlassian     — community MCP (needs API key)
    ❌ Figma         — community MCP (needs API key)

  Want me to help set up the missing integrations?"
```

Walk through each missing MCP interactively.
