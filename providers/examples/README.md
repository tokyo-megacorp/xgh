# Provider Examples

Reference configs showing what `/xgh-track` generates. **Don't copy these manually** — run `/xgh-track` and it auto-detects your tools, reads their docs, and generates the right config.

## Examples by Persona

### Corporate Developer
| Example | Mode | Roles | Service |
|---------|------|-------|---------|
| [slack-mcp.yaml](slack-mcp.yaml) | mcp | channels, threads, search | Slack (OAuth) |
| [jira-mcp.yaml](jira-mcp.yaml) | mcp | list, comments, search | Jira (Atlassian OAuth) |
| [figma-mcp.yaml](figma-mcp.yaml) | mcp | files, comments | Figma design files |
| [gmail-mcp.yaml](gmail-mcp.yaml) | mcp | mail, search, threads | Gmail (Google OAuth) |
| [github-cli.yaml](github-cli.yaml) | cli | PRs, issues, actions, security, discussions, releases | GitHub (gh CLI) |

### Open Source Maintainer
| Example | Mode | Roles | Service |
|---------|------|-------|---------|
| [github-cli.yaml](github-cli.yaml) | cli | PRs, issues, discussions, actions, security, releases | GitHub (gh CLI) |
| [discord-cli.yaml](discord-cli.yaml) | api | channels, threads | Discord community server |

### Indie Developer
| Example | Mode | Roles | Service |
|---------|------|-------|---------|
| [sentry-cli.yaml](sentry-cli.yaml) | cli | alerts, releases | Error tracking |
| [vercel-api.yaml](vercel-api.yaml) | api | deployments | Deploy status |
| [appstore-cli.yaml](appstore-cli.yaml) | cli | reviews, releases, metrics | App Store Connect |

### AI Agent Coordination
| Example | Mode | Roles | Service |
|---------|------|-------|---------|
| [claude-agent-cli.yaml](claude-agent-cli.yaml) | cli | sessions, decisions, artifacts | Claude Code / other agents |

### Task Management
| Example | Mode | Roles | Service |
|---------|------|-------|---------|
| [linear-api.yaml](linear-api.yaml) | api | list, comments | Linear issues |

## Access Modes

| Mode | How it works | Generated files | When to use |
|------|-------------|----------------|-------------|
| `cli` | Calls a CLI binary (`gh`, `sentry-cli`, etc.) | `provider.yaml` + `fetch.sh` | Tool has a CLI with `--help` |
| `api` | Calls REST/OpenAPI endpoints with `curl` + `jq` | `provider.yaml` + `fetch.sh` | Service exposes a REST API or OpenAPI spec |
| `mcp` | Uses MCP server tools via Claude session | `provider.yaml` only | MCP server registered (OAuth services) |

## Tool Roles

Roles tell the retrieve skill what a provider can do. Mix and match:

| Category | Roles | What they fetch |
|----------|-------|----------------|
| **Communication** | `channels`, `threads`, `search`, `mail` | Messages, replies, email |
| **Work items** | `list`, `comments`, `reviews` | Tickets, PR reviews, app reviews |
| **Documents** | `files`, `versions` | Design files, doc pages, version history |
| **Operations** | `alerts`, `deployments`, `releases` | Errors, CI/CD, new versions |
| **Activity** | `feeds`, `events`, `metrics` | Notifications, calendar, analytics |
| **AI Agents** | `sessions`, `tasks`, `artifacts`, `decisions` | Agent history, outputs, reasoning |

## Where configs live

```
~/.xgh/user_providers/
├── github-cli/        ← /xgh-track generated this
│   ├── provider.yaml
│   ├── fetch.sh
│   └── cursor
├── slack-mcp/
│   ├── provider.yaml
│   └── cursor
└── sentry-cli/
    ├── provider.yaml
    ├── fetch.sh
    └── cursor
```

This directory is **never touched** by plugin installs or updates. It's your data.

## Regeneration

When a CLI or API changes:
```
/xgh-track --regenerate github-cli
```
Re-reads the tool's documentation, updates the fetch script, preserves your config.
