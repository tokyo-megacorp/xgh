# README Variants — xgh Repositioning

Three opening variants for comparison. Each covers: title, tagline, intro, problem/value prop, and "What You Get". Everything below the fold (Install, Architecture, etc.) stays the same across all three.

---

## Variant A — Fastlane-style

> Lead with the developer experience. One command, everything configured.

```markdown
# xgh — Your AI dev stack, one install

**Fastlane for AI-assisted development.** One command wires memory, compression, context efficiency, and dev methodology into your Claude Code — no glue code, no config drift.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-initial%20release-brightgreen)](#implementation-status)

## One command. Full stack.

```bash
curl -fsSL https://raw.githubusercontent.com/extreme-go-horse/xgh/main/install.sh | bash
```

That single line installs and wires together:

| Tool | What it does | Without xgh |
|------|-------------|-------------|
| [**lossless-claude**](https://github.com/extreme-go-horse/lossless-claude) | Persistent memory across sessions | Manual setup, no cross-session recall |
| [**RTK**](https://github.com/rtk-ai/rtk) | 60-90% token compression on CLI output | Full verbosity burns context |
| [**context-mode**](https://github.com/mksglu/context-mode) | Sandboxed execution, ~98% context savings | Every tool call floods your window |
| [**superpowers**](https://github.com/obra/superpowers) | TDD, brainstorming, plans, code review | Ad-hoc methodology, no guardrails |

Plus 21 slash commands, 5 hooks, a context tree, and an ingest pipeline — all pre-configured.

## What changes after install

| Before | After |
|--------|-------|
| Agent forgets everything between sessions | Conventions, decisions, and fixes recalled automatically |
| `git log` dumps 200 lines into context | RTK compresses it to 20 |
| You manually explain project context | Top-5 knowledge files injected at session start |
| Four tools configured separately, if at all | One install, zero drift |

**Prerequisites:** macOS or Linux, Bash 5+, Git. Everything else is installed automatically.
```

---

## Variant B — Cockpit dashboard

> Lead with what you can see and control. The 21 commands as your instrument panel.

```markdown
# xgh — The developer's cockpit

**One install gives your AI agent memory, compression, efficiency, and methodology — controlled from a unified command surface.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-initial%20release-brightgreen)](#implementation-status)

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
| `/xgh-doctor` | Validate the full pipeline — config, connectivity, health |
| `/xgh-track` | Add a project to monitoring (Slack, Jira, GitHub, Figma) |
| `/xgh-index` | Index a codebase into memory |

<details>
<summary>All 21 commands</summary>

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

## What's under the hood

xgh is the glue. It doesn't store your memories or compress your tokens — it wires together the tools that do:

| Layer | Tool | Role |
|-------|------|------|
| Memory | [lossless-claude](https://github.com/extreme-go-horse/lossless-claude) | Persistent cross-session recall via MCP |
| Compression | [RTK](https://github.com/rtk-ai/rtk) | 60-90% token savings on CLI output |
| Efficiency | [context-mode](https://github.com/mksglu/context-mode) | Sandboxed execution, ~98% context reduction |
| Methodology | [superpowers](https://github.com/obra/superpowers) | TDD, brainstorming, plans, code review |

The installer auto-detects your platform, installs what's missing, registers hooks, and wires everything into your Claude Code settings. One command:

```bash
curl -fsSL https://raw.githubusercontent.com/extreme-go-horse/xgh/main/install.sh | bash
```

**Prerequisites:** macOS or Linux, Bash 5+, Git. Everything else is installed automatically.
```

---

## Variant C — Problem/solution narrative

> Lead with the pain. You're juggling tools that don't know about each other.

```markdown
# xgh — The glue for your AI dev stack

**Your AI agent is powerful. Your AI agent stack is a mess.**

You installed RTK for compression, context-mode for efficiency, lossless-claude for memory, superpowers for methodology. Four tools, four configs, four sets of hooks — and none of them know about each other. Every new project, you re-wire the same stack. Every new machine, you start from scratch.

xgh fixes this. One install, one command surface, one coherent stack.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-initial%20release-brightgreen)](#implementation-status)

## What xgh actually is

xgh is not a memory system, a compressor, or a methodology. It's the **orchestration layer** that wires best-in-class tools into a unified dev workflow — like Fastlane did for iOS build/sign/deploy.

| What you need | What does it | Who maintains it |
|---------------|-------------|------------------|
| Persistent memory | [lossless-claude](https://github.com/extreme-go-horse/lossless-claude) | [@extreme-go-horse](https://github.com/extreme-go-horse) |
| Token compression | [RTK](https://github.com/rtk-ai/rtk) | [@rtk-ai](https://github.com/rtk-ai) |
| Context efficiency | [context-mode](https://github.com/mksglu/context-mode) | [@mksglu](https://github.com/mksglu) |
| Dev methodology | [superpowers](https://github.com/obra/superpowers) | [@obra](https://github.com/obra) |
| **The glue** | **xgh** | [@extreme-go-horse](https://github.com/extreme-go-horse) |

xgh installs them, configures their hooks, resolves their conflicts, and exposes 21 slash commands so you interact with one system, not four.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/extreme-go-horse/xgh/main/install.sh | bash
```

That single line:
1. Installs lossless-claude (memory) and RTK (compression)
2. Offers context-mode and superpowers as optional plugins
3. Registers 5 hooks (session-start, prompt-submit, pre-read, post-edit, post-ctx-call)
4. Writes agent instructions for Claude Code, Cursor, Copilot, and Windsurf
5. Sets up a context tree for git-committed knowledge
6. Auto-detects your platform and picks the right LLM backend

**Prerequisites:** macOS or Linux, Bash 5+, Git. Everything else is installed automatically.
```

---

## Comparison

| Aspect | A (Fastlane) | B (Cockpit) | C (Problem/Solution) |
|--------|-------------|-------------|---------------------|
| First impression | Speed, simplicity | Power, control | Honesty, clarity |
| Leads with | Install command | Command table | Pain point |
| Tone | "Look how easy" | "Look what you can do" | "You know this is a mess" |
| Audience pull | Solo devs wanting quick setup | Power users wanting depth | Anyone who's already juggling tools |
| Risk | Undersells depth | Overwhelming at first glance | Assumes reader has all 4 tools already |
