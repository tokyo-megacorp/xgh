---
name: xgh-init
description: First-run onboarding. Verifies MCP connections, sets up profile, adds first project, runs initial retrieval, and optionally profiles the team and indexes the codebase.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh init`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-init — First-Run Onboarding

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh init`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status.

Run the `xgh:init` skill for the complete first-time setup experience after installing xgh.

## Usage

```
/xgh-init
```

No arguments. The skill walks you through everything interactively.

## What It Does

1. **Verify MCP connections** — checks lossless-claude, Slack, Atlassian, Figma, GitHub CLI
2. **Profile setup** — name, role, squad, platforms
3. **Add first project** — invokes `/xgh-track` for full project onboarding
4. **Initial retrieval** — backfills recent Slack messages and linked resources
5. **Team profiling** (optional) — runs `/xgh-profile` for each team member
6. **Index codebase** (optional) — runs `/xgh-index` in quick mode
7. **Initial curation** (optional) — asks if you want to capture initial knowledge (architecture decisions, team conventions, known gotchas). If yes, invokes `/xgh-curate` interactively.

## Prerequisites

- xgh must be installed (`~/.xgh/ingest.yaml` must exist — created by `/xgh-init`)
- lossless-claude and Slack MCPs must be configured (run `/xgh-setup` if not)

## Related Skills

- `xgh:init` — the full workflow skill this command triggers
- `xgh:mcp-setup` — standalone MCP configuration audit
- `xgh:track` — add additional projects after initial setup
- `xgh:brief` — your first command after init completes
