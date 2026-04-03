# README Redesign — xgh as "The Developer's Cockpit"

**Date:** 2026-03-19
**Status:** Approved (post-review fixes applied)
**Goal:** Reposition xgh from "persistent memory for AI agents" to "the glue layer / developer's cockpit that orchestrates best-in-class AI dev tools"

---

## Positioning Shift

| Aspect | Old | New |
|--------|-----|-----|
| Identity | "The brain" — persistent memory system | "The glue" — orchestration layer |
| Tagline | "Persistent memory for AI coding agents" | "One install wires memory, compression, context efficiency, and dev methodology into your AI agent" |
| Analogy | None explicit | Fastlane for AI-assisted development |
| Hero element | Self-learning loop diagram | Command table (cockpit controls) |
| Dependency framing | lossless-claude is xgh's memory | lossless-claude is one of four best-in-class tools xgh wires together |

## Full README Structure

### Section 1 — Title + Positioning

```markdown
# xgh — The developer's cockpit

**One install wires memory, compression, context efficiency, and dev methodology into your AI agent.** No glue code. No config drift. No re-setup per project.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-initial%20release-brightgreen)](#implementation-status)
```

### Section 2 — What xgh wires together + Your controls

```markdown
## What xgh wires together

| What you need | What does it | Installed by xgh |
|---------------|-------------|------------------|
| Persistent memory | [lossless-claude](https://github.com/tokyo-megacorp/lossless-claude) | Automatic |
| Token compression | [RTK](https://github.com/rtk-ai/rtk) | Automatic |
| Context efficiency | [context-mode](https://github.com/mksglu/context-mode) | Optional plugin |
| Dev methodology | [superpowers](https://github.com/obra/superpowers) | Optional plugin |

## Your controls

| Command | What it does |
|---------|-------------|
| `/xgh-init` | First-run onboarding — verify connections, set up profile |
| `/xgh-brief` | Morning briefing — Slack, Jira, GitHub, what needs attention now |
| `/xgh-command-center` | Cross-project triage and dispatch |
| `/xgh-ask` | Search memory and context tree |
| `/xgh-implement` | Ticket to working code — full context gathering first |
| `/xgh-investigate` | Systematic debugging from a bug report |
| `/xgh-design` | Figma to implementation |
| `/xgh-doctor` | Validate pipeline health — config, connectivity, scheduler |
| `/xgh-track` | Add a project to monitoring (Slack, Jira, GitHub, Figma) |
| `/xgh-index` | Index a codebase into memory |

<details>
<summary><b>All commands</b></summary>

| Command | What it does |
|---------|-------------|
| `/xgh-setup` | Audit and configure MCP integrations |
| `/xgh-help` | Contextual guide and command reference |
| `/xgh-curate` | Store knowledge in memory and context tree |
| `/xgh-collab` | Multi-agent collaboration |
| `/xgh-profile` | Engineer throughput analysis from Jira history |
| `/xgh-retrieve` | Run context retrieval loop |
| `/xgh-analyze` | Run context analysis loop |
| `/xgh-schedule` | Manage background scheduler jobs |
| `/xgh-calibrate` | Calibrate dedup threshold with F1 scoring |
| `/xgh-status` | Memory stats and system health |

</details>
```

### Section 3 — Install

```markdown
## Install

<details open>
<summary><b>Claude Code</b> (recommended)</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/tokyo-megacorp/xgh/main/install.sh | bash
```

That single line:
1. Installs [lossless-claude](https://github.com/tokyo-megacorp/lossless-claude) (memory) and [RTK](https://github.com/rtk-ai/rtk) (compression)
2. Offers [context-mode](https://github.com/mksglu/context-mode) and [superpowers](https://github.com/obra/superpowers) as optional plugins
3. Registers 5 hooks (session-start, prompt-submit, pre-read, post-edit, post-ctx-call)
4. Writes agent instructions for Claude Code, Cursor, Copilot, and Windsurf
5. Sets up a context tree for git-committed knowledge
6. Auto-detects your platform and picks the right LLM backend

**Prerequisites:** macOS or Linux, Bash 5+, Git. Everything else is installed automatically.

#### Cloud presets

```bash
# OpenAI (~$0.01/session)
XGH_PRESET=openai curl -fsSL https://raw.githubusercontent.com/tokyo-megacorp/xgh/main/install.sh | bash

# Anthropic (~$0.01/session)
XGH_PRESET=anthropic curl -fsSL https://raw.githubusercontent.com/tokyo-megacorp/xgh/main/install.sh | bash
```

#### Force a specific backend

```bash
# Ollama on any platform
XGH_BACKEND=ollama bash install.sh

# Remote inference server (e.g. Mac Mini → another machine)
XGH_BACKEND=remote XGH_REMOTE_URL=http://192.168.1.x:11434 bash install.sh
```

</details>

<details>
<summary><b>Cursor</b></summary>

1. Install xgh into your project using the Claude Code one-liner above
2. xgh writes `.cursor/rules/xgh.md` with agent instructions
3. Configure the lossless-claude MCP server in Cursor's MCP settings (see `.claude/.mcp.json` for the config)

</details>

<details>
<summary><b>Windsurf</b></summary>

1. Install xgh into your project using the Claude Code one-liner above
2. xgh writes `.windsurfrules` with agent instructions
3. Configure the lossless-claude MCP server in Windsurf's MCP settings (see `.claude/.mcp.json` for the config)

</details>

<details>
<summary><b>GitHub Copilot</b></summary>

1. Install xgh into your project using the Claude Code one-liner above
2. xgh writes `.github/copilot-instructions.md` and `.copilot/instructions.md` with agent instructions
3. Configure the lossless-claude MCP server in your Copilot setup (see `.claude/.mcp.json` for the config)

</details>

<details>
<summary><b>Uninstall</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/tokyo-megacorp/xgh/main/uninstall.sh | bash
```

</details>
```

### Section 4 — What changes after install

```markdown
## What changes after install

| Before | After |
|--------|-------|
| Agent forgets everything between sessions | Conventions, decisions, and fixes recalled automatically |
| CLI output dumps 200 lines into context | RTK compresses to ~20 |
| You explain project context every session | Top-5 knowledge files injected at session start |
| Four tools configured separately, if at all | One install, zero drift |

All knowledge is stored as human-readable markdown in `.xgh/context-tree/` — reviewable in PRs, greppable in CI, readable without xgh.
```

### Section 5 — Try It

Keep existing content verbatim — it's good as-is:

```markdown
## Try It

After installing, open a Claude Code session and try these:

```bash
# First-run onboarding
/xgh-init

# Get a session briefing
/xgh-brief

# Ask about past decisions
/xgh-ask "How did we handle auth token refresh?"

# Store a new convention
/xgh-curate "Always use UTC timestamps in API responses"

# Implement a ticket with full context
/xgh-implement PROJ-1234

# Debug a production issue
/xgh-investigate "Users seeing 500 errors on /api/checkout"
```
```

### Section 6 — BYOP + Platform matrix

Keep existing content — the provider/backend tables are accurate and well-structured. Move inside a `<details>` fold to reduce top-level noise. Keep the Configuration Reference `<details>` nested inside.

### Section 7 — Architecture

Update the ASCII diagram to position xgh as the orchestration layer. The key change: xgh sits at the top as the "cockpit", with the four tools as modules underneath.

```
┌─────────────────────────────────────────────────────────────┐
│                    xgh — developer's cockpit                 │
│              25 commands · 5 hooks · context tree            │
├──────────┬──────────────┬───────────────┬───────────────────┤
│          │              │               │                   │
│  lossless-claude   context-mode      RTK          superpowers
│  (memory)          (efficiency)   (compression)  (methodology)
│  lcm_search        ctx_execute    rtk rewrite    brainstorming
│  lcm_store         ctx_search    rtk git/gh/..   writing-plans
│  lcm_grep          ctx_batch      rtk read        TDD, review
│          │              │               │                   │
├──────────┴──────────────┴───────────────┴───────────────────┤
│                                                             │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Vector DB │  │  SQLite    │  │  LLM + Emb │            │
│  │  (Qdrant)  │  │ (sessions) │  │  (BYOP)    │            │
│  └────────────┘  └────────────┘  └────────────┘            │
│                         │                                   │
│  ┌──────────────────────┴────────────────────────────────┐  │
│  │         .xgh/context-tree/  (git-committed)            │  │
│  │  ├── domain/ → topic/ → entry.md                       │  │
│  │  └── _manifest.json (flat entries[] registry)          │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Keep the tech stack table and agent instruction files table inside the Architecture `<details>` fold.

### Section 8 — Trust & Privacy

Keep verbatim — it's concise and accurate.

### Section 9 — Contributing

Keep verbatim.

### Section 10 — Footer

```markdown
---

*xgh is inspired by [Fastlane](https://fastlane.tools), [ByteRover](https://byterover.dev), and the [Superpowers methodology](https://www.claudesuperpowers.com). It is an open, self-hosted, provider-agnostic alternative.*
```

Note: Added Fastlane to the inspiration credits since it's now the explicit analogy.

### Section 11 — License

```markdown
## License

MIT — see [LICENSE](LICENSE).
```

---

## What's removed

| Old section | Reason |
|-------------|--------|
| "The Problem" (zero memory narrative) | Replaced by "What changes after install" — shows the shift without lecturing |
| "The self-learning loop" | Implementation detail, not a selling point for the cockpit framing |
| "Dual-engine search" | Too deep for README — belongs in AGENTS.md or docs/ |
| "Context tree knowledge" | Mentioned in architecture, no longer a hero section |
| "Session Stats" table | Replaced by before/after table which is more concrete |
| "Multi-agent support" section | Kept as part of Architecture fold, not a top-level section |

## What's restructured

| Change | Why |
|--------|-----|
| Commands table promoted to top-level hero | Cockpit framing — controls come first |
| Top 10 commands visible, rest in fold | Avoid overwhelming first-time readers |
| Install section moved below "Your controls" | Reader sees value before being asked to install |
| BYOP/Platform matrix moved to `<details>` | Important but not first-impression material |
| Architecture diagram shows xgh as orchestrator | Reflects new positioning as glue, not brain |
| Plugins section removed as standalone | Absorbed into "What xgh wires together" table |
