# MCP Auto-Detection Protocol

## Detection Protocol

Before starting any skill, auto-detect which MCP servers are available. Skills adapt based on what is configured — no hard dependencies.

**How to detect** (method depends on integration type — see table below):
- **MCP integrations:** Check whether the named tool function is present in the current tool list.
- **CLI integrations (e.g. GitHub):** Check binary availability via `command -v gh` or a lightweight help command. These have no MCP server — the table row's "Detection signal" column specifies the CLI check.
Available integrations are discovered automatically on first invocation. Run `/xgh-setup` to configure any missing MCP integrations.

## Common Tool Signatures by Integration

MCP tool names follow the pattern `mcp__<server-slug>__<tool-name>`. The exact prefix varies by how the MCP server is registered — use the tool name suffix as a fallback if the full prefixed name isn't found.

| Integration | Detection signal | Capability |
|-------------|-----------------|------------|
| lossless-claude | `mcp__lossless-claude__lcm_search` tool available | xgh memory, session state, conventions |
| Slack MCP | `mcp__claude_ai_Slack__slack_read_thread` tool available | Thread reading, message search |
| Atlassian/Jira | `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJQL` tool available | Ticket history, task management |
| GitHub | `gh pr list` / `gh issue list` available (CLI detection; no standard MCP server for GitHub) | PRs, issues, Actions |
| Figma MCP | `mcp__claude_ai_Figma__get_design_context` tool available | Design extraction, Code Connect |
| Gmail | `mcp__claude_ai_Gmail__gmail_search_messages` tool available (fallback: `gmail_search_messages`) | Email search and reading |

## Status Reporting Format

After detection, surface which integrations are available so the user understands what is active:

```
✓ lossless-claude — memory and conventions available
✓ Slack — thread reading and search available
✓ Atlassian — Jira ticket access available
✗ Figma — not configured (will ask for manual input if needed)
```

## Graceful Degradation Principle

Skills should always work, even with zero MCPs. When a tool is unavailable:
1. Skip the step that depends on it
2. Fall back to asking the user for the missing information directly
3. Note any limitations in the output (e.g., "no ticket created — task manager not configured")

## Skill-Specific Degradation Rules

Each skill defines its own degradation rules inline — what specifically to skip or substitute when each integration is absent. These rules are skill-specific and live in each skill's `## MCP Auto-Detection` section after a reference to this protocol.
