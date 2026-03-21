# Provider Examples

These are reference configurations showing what `/xgh-track` generates. **Do NOT copy these manually** — run `/xgh-track` and it auto-detects your tools, reads their docs, and generates the right config for you.

---

## Examples by Persona

### Corporate Developer (Jira + Slack + GitHub)

You're part of a team using enterprise tools. You need:
- **Jira** to track assigned work and blockers
- **Slack** to catch mentions and urgent incidents
- **GitHub** for code reviews and releases

Start with: `jira-api.yaml` + `slack-mcp.yaml` + `github-cli.yaml`

Then run: `/xgh-track` to configure your org instance URLs and auth.

---

### Open Source Maintainer (GitHub + Discussions)

You manage repos and want to stay on top of community activity:
- **GitHub** for PRs, issues, discussions, releases, security alerts
- Multiple repos with different importance levels
- Watch patterns for specific topics (bugs, features, security)

Start with: `github-cli.yaml`

The example shows: watching multiple repos, filtering by search patterns, handling notifications.

---

### Indie Developer / Solo Maker (GitHub + Linear)

You ship fast and need your task list + code in sync:
- **Linear** for planning and task management
- **GitHub** for building and shipping
- Quick feedback loop between commits and issues

Start with: `linear-api.yaml` + `github-cli.yaml`

The examples show: assigned items, high-priority issues, completed work (for learning).

---

### Ops / Incident Responder (Slack + Monitoring)

You need real-time visibility into incidents and alerts:
- **Slack** with critical channels, alerts, thread following
- Incident tracking (Jira, Linear, custom)
- High urgency for critical channels + @mentions

Start with: `slack-mcp.yaml`

The example shows: channel priorities, alert patterns, 1h lookback for critical channels.

---

### Product Manager (Linear + Slack + GitHub)

You coordinate across engineering and design:
- **Linear** for roadmap and PRs
- **Slack** for team alignment and feedback
- **GitHub** for release tracking

Start with: `linear-api.yaml` + `slack-mcp.yaml` + `github-cli.yaml`

Focus on: high-priority issues, design decisions, release notes.

---

## Access Modes

| Mode | Example | Best For | Auth |
|------|---------|----------|------|
| **cli** | GitHub, Discord | Native tools installed on your machine | Existing logins (`gh auth`, `discord login`) |
| **api** | Linear, Jira, Vercel | REST/GraphQL APIs with token auth | Bearer tokens in `~/.xgh/tokens.env` |
| **mcp** | Slack | Anthropic's MCP servers with OAuth | OAuth session (seamless, no token needed) |

---

## Tool Roles

Providers declare what they can do via **tool roles**. The retrieve skill checks which roles exist and adjusts its behavior:

| Role | What it does | Examples |
|------|-------------|----------|
| **channels** | Scan messages in channels | Slack #engineering, Discord #general |
| **threads** | Follow thread replies (enables deep lookback) | Slack thread replies, Discord threads |
| **search** | Free-text search across workspace | Slack "mention:me", GitHub "search:architecture" |
| **assigned** | Items assigned to you | Jira issues, Linear tasks, GitHub PRs |
| **comments** | Comments mentioning you | Jira, GitHub discussions |
| **alerts** | System/infrastructure alerts | Vercel errors, GitHub security alerts |
| **events** | Activity/analytics events | Deployments, releases, metrics |

---

## What Gets Generated Where

```
~/.xgh/user_providers/
├── github-cli/
│   ├── provider.yaml    # Config: repos, sources, watch patterns
│   ├── fetch.sh         # Script: runs `gh` CLI, writes inbox items
│   └── cursor           # State: timestamp of last fetch
├── slack-mcp/
│   ├── provider.yaml    # Config: channels, searches
│   └── cursor           # State: unix timestamp
├── linear-api/
│   ├── provider.yaml    # Config: endpoints, teams, queries
│   ├── fetch.sh         # Script: runs GraphQL queries
│   └── cursor           # State: ISO8601 timestamp
└── jira-api/
    ├── provider.yaml
    ├── fetch.sh
    └── cursor
```

**Never edit these by hand.** Use `/xgh-track --regenerate <provider>` to update.

---

## Regeneration

Tools and APIs change. When that happens:

```bash
/xgh-track --regenerate github-cli
```

This:
1. Re-reads the tool's docs (`gh --help`, API spec, MCP tool list)
2. Generates a new fetch script (or updates provider.yaml)
3. Runs a validation fetch to confirm it works
4. Replaces the old version only if validation passes

Your config and cursor are preserved.

---

## Using These Examples

1. **Pick your personas** — which tools do you use?
2. **Find matching examples** — click the ones in the table above
3. **Read the comments** — each file explains the pattern
4. **Run `/xgh-track`** — it generates the config for your setup
5. **Customize if needed** — edit `~/.xgh/user_providers/` after generation

---

## Common Patterns

### Watch for mentions
```yaml
watch_prs: ["search:@me mentions"]
search_terms: ["mention:me", "@me has:star"]
```

### Priority-based lookback
```yaml
channels:
  - name: critical
    lookback_hours: 1    # High-volume, short window
  - name: general
    lookback_hours: 24   # Low-volume, wider window
```

### High-urgency filtering
```yaml
urgency_score: "4 if priority == 'P1' else 1"  # API
priority: critical  # Slack
```

### Dedup & state tracking
The provider system auto-deduplicates using stable IDs (GitHub PR numbers, Jira keys, Linear IDs). Cursors prevent refetching old items.

---

## Troubleshooting

**"Config doesn't work for my setup"** → Run `/xgh-track` to generate the right one. These examples are references, not copy-paste templates.

**"Cursor keeps resetting"** → Check your internet connection during fetch. Cursor is only written on success.

**"Getting old items I've already seen"** → Cursors are timestamp-based. If you delete the cursor file (`~/.xgh/user_providers/<name>/cursor`), next fetch will rescan everything.

**"Tool changed its API"** → Run `/xgh-track --regenerate <name>`. It re-reads the docs.

---

Happy fetching! 🚀
