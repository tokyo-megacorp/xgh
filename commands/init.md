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

1. **Verify MCP connections** — checks memory, Slack, Atlassian, Figma, GitHub CLI
2. **Profile setup** — name, role, squad, platforms
3. **Add first project** — invokes `/xgh-track` for full project onboarding
4. **Initial retrieval** — backfills recent Slack messages and linked resources
5. **Provider initialization** (optional) — runs `/xgh-init-providers` after project setup
6. **Seed secondary agents** (optional) — runs `/xgh-seed` to refresh cross-tool context
7. **Initial retrieval** (optional) — runs `/xgh-retrieve` to backfill current project context.

## Prerequisites

- xgh must be installed (`~/.xgh/ingest.yaml` must exist — created by `/xgh-init`)
- Memory and Slack integrations should be configured for the full experience (run `/xgh-init` if not)

## Related Skills

- `xgh:init` — the full workflow skill this command triggers
- `xgh:doctor` — standalone configuration and connectivity audit
- `xgh:track` — add additional projects after initial setup
- `xgh:brief` — your first command after init completes
