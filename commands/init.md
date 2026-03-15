---
name: xgh-init
description: First-run onboarding. Verifies MCP connections, sets up profile, adds first project, runs initial retrieval, and optionally profiles the team and indexes the codebase.
---

# /xgh-init — First-Run Onboarding

Run the `xgh:init` skill for the complete first-time setup experience after installing xgh.

## Usage

```
/xgh-init
```

No arguments. The skill walks you through everything interactively.

## What It Does

1. **Verify MCP connections** — checks Cipher, Slack, Atlassian, Figma, GitHub CLI
2. **Profile setup** — name, role, squad, platforms
3. **Add first project** — invokes `/xgh-track` for full project onboarding
4. **Initial retrieval** — backfills recent Slack messages and linked resources
5. **Team profiling** (optional) — runs `/xgh-team-profile` for each team member
6. **Index codebase** (optional) — runs `/xgh-ingest-index-repo` in quick mode

## Prerequisites

- `install.sh` must have been run first (`~/.xgh/ingest.yaml` must exist)
- Cipher and Slack MCPs must be configured (run `/xgh-setup` if not)

## Related Skills

- `xgh:init` — the full workflow skill this command triggers
- `xgh:mcp-setup` — standalone MCP configuration audit
- `xgh:ingest-track` — add additional projects after initial setup
- `xgh:briefing` — your first command after init completes
