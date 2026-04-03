# xgh — Declarative AI Ops

**Declare your agent behavior in YAML. Converge every AI platform to match.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-initial%20release-brightgreen)](#implementation-status)

---

The same way Terraform lets you declare infrastructure and converge reality to match, xgh lets you declare AI agent behavior and converge every platform to match.

```yaml
# config/project.yaml — your variables.tf
preferences:
  pair_programming:
    enabled: true
    tool: "xgh:codex"
    effort: high
  superpowers:
    implementation_model: sonnet
    review_model: opus
```

```bash
/xgh-seed    # terraform apply — pushes state to Codex, Gemini, OpenCode
/xgh-brief   # what needs attention right now
/xgh-init    # first-time setup
```

## The Stack

| Layer | Role | xgh equivalent |
|-------|------|----------------|
| `config/project.yaml` | workspace variables | `variables.tf` |
| `config/agents.yaml` | platform registry | `providers.tf` |
| `config/triggers.yaml` | event sources | event bridge rules |
| `preferences:` block | workspace defaults | workspace vars |
| `/xgh-seed` | converge platforms to config | `terraform apply` |
| `AGENTS.md` | rendered view of current config | plan output |
| `.xgh/context-tree/` | persistent knowledge base | state + history |

The hard problem — as always — is **drift**. Platform skill files go stale, AGENTS.md gets hand-edited, hooks fail silently. xgh solves this the same way Terraform does: one source of truth, derived outputs, explicit apply.

## What it wires together

| What you need | What does it |
|---------------|-------------|
| Persistent memory across sessions | [MAGI](https://github.com/katsuragi-corp/magi) — SQLite + FTS5 |
| Context tree search | BM25/TF-IDF over `.xgh/context-tree/` |
| Multi-platform dispatch | Codex CLI, Gemini CLI, OpenCode, GLM — all driven from one config |
| Session-start injection | Top knowledge files injected automatically at session start |
| Proactive alerts | Trigger engine — fires on urgency score, patterns, or schedule |
| Dev methodology | [superpowers](https://github.com/obra/superpowers) — optional plugin |

## Commands

| Command | What it does |
|---------|-------------|
| `/xgh-init` | First-run setup — verify connections, seed config, generate AGENTS.md |
| `/xgh-seed` | Push project context to all detected AI platforms |
| `/xgh-brief` | Session briefing — Slack, Jira, GitHub, what needs attention now |
| `/xgh-ask` | Search memory and context tree |
| `/xgh-implement` | Ticket to working code — full context gathering first |
| `/xgh-investigate` | Systematic debugging from a bug report |
| `/xgh-doctor` | Validate pipeline health |
| `/xgh-track` | Add a project to monitoring |
| `/xgh-analyze` | Classify inbox, extract memories, generate digest |
| `/xgh-retrieve` | Pull context from Slack, Jira, GitHub |

<details>
<summary><b>All commands</b></summary>

| Command | What it does |
|---------|-------------|
| `/xgh-setup` | Audit and configure MCP integrations |
| `/xgh-help` | Contextual guide and command reference |
| `/xgh-curate` | Store knowledge in memory and context tree |
| `/xgh-collab` | Multi-agent collaboration |
| `/xgh-dispatch` | Auto-route tasks to the best agent + model based on task type |
| `/xgh-codex` | Dispatch to Codex CLI |
| `/xgh-gemini` | Dispatch to Gemini CLI |
| `/xgh-opencode` | Dispatch to OpenCode |
| `/xgh-glm` | Dispatch to Z.AI GLM models via OpenCode |
| `/xgh-watch-prs` | Passively monitor PRs — surfaces review changes and merge-readiness |
| `/xgh-ship-prs` | Shepherd PRs through review cycles and auto-merge when ready |
| `/xgh-design` | Figma to implementation |
| `/xgh-index` | Index a codebase into memory |
| `/xgh-profile` | Engineer throughput analysis |
| `/xgh-schedule` | Manage background scheduler |
| `/xgh-trigger` | Manage trigger engine |
| `/xgh-calibrate` | Calibrate dedup threshold |
| `/xgh-status` | Memory stats and system health |
| `/xgh-command-center` | Cross-project triage and dispatch |

</details>

## Install

```bash
claude plugin install xgh@tokyo-megacorp
/xgh-init
```

Takes about 5 minutes. Sets up memory, hooks, profile, and seeds your first project.

<details>
<summary><b>Other platforms</b></summary>

xgh installs via Claude Code and then seeds instructions into every other platform automatically:

| Platform | File | Written by |
|----------|------|------------|
| All agents (canonical) | `AGENTS.md` | `/xgh-init` |
| Claude Code | `CLAUDE.md` | `/xgh-init` |
| Codex CLI | `.agents/skills/xgh/context.md` + `SKILL.md` | `/xgh-seed` |
| Gemini CLI | `.gemini/skills/xgh/context.md` + `SKILL.md` | `/xgh-seed` |
| OpenCode | `.opencode/skills/xgh/context.md` + `SKILL.md` | `/xgh-seed` |
| GitHub Copilot | `.github/copilot-instructions.md` | `/xgh-init` |

</details>

<details>
<summary><b>Uninstall</b></summary>

```bash
claude plugin uninstall xgh
```

</details>

## Before / After

| Before | After |
|--------|-------|
| Agent forgets decisions between sessions | Conventions, decisions, and fixes recalled automatically |
| Re-explain project context every session | Top knowledge files injected at session start |
| Configure Codex, Gemini, OpenCode separately | One YAML, one `apply`, all platforms in sync |
| Drift between platforms | `/xgh-seed` converges everything to config |

All knowledge is stored as human-readable markdown in `.xgh/context-tree/` — reviewable in PRs, greppable in CI, readable without xgh.

<details>
<summary><b>Architecture</b></summary>

### Config is code

```
config/
  project.yaml   ← workspace identity + preferences (variables.tf)
  agents.yaml    ← platform registry: codex, gemini, opencode (providers.tf)
  triggers.yaml  ← event sources: PR opened, Jira assigned, digest ready
  team.yaml      ← conventions, iron laws, pitfalls
  workflow.yaml  ← phases, test commands, superpowers table
```

All five files feed `scripts/gen-agents-md.sh`, which emits `AGENTS.md` — the human-readable plan output. Edit the YAML; regenerate the doc.

### Runtime injection

At session start, `hooks/session-start.sh` injects top-ranked context tree entries into the system prompt. Skills read `config/project.yaml` at dispatch time for preferences. `/xgh-seed` writes snapshots to platform skill directories.

The YAML is the source of truth. AGENTS.md is a view. Platform skill files are derived artifacts.

### Tech stack

| Layer | Technology |
|-------|-----------|
| Install & hooks | Bash (`set -euo pipefail`) |
| Config | YAML |
| Skills / commands / agents | Markdown (Claude Code format) |
| Context tree search | Python 3 (BM25/TF-IDF) |
| Persistent memory | MAGI (SQLite + FTS5) |
| Tests | Bash `assert_*` helpers |

</details>

<details>
<summary><b>Implementation Status</b></summary>

| Plan | Scope | Status |
|------|-------|--------|
| 1 — Foundation | Scaffold, installer | Done |
| 2 — Context Tree Engine | CRUD, BM25, scoring, sync | Done |
| 3 — Hooks & Core Skills | Session-start hooks, core skills | Done |
| 4 — Team Collaboration | Team skills, dispatcher agent | Done |
| 5 — Multi-Agent Bus | Agent registry, workflow templates | Done |
| 6 — Workflow Skills | investigate, design, implement | Done |
| 7 — Briefing | Session briefing | Done |
| 8 — Ollama / Linux | Cross-platform backend support | Done |
| 9 — Remote Backend | `XGH_BACKEND=remote` | Done |

</details>

## Trust & Privacy

- **Nothing leaves your machine.** All memory and context stay local. No telemetry, no cloud sync.
- **Git-native knowledge.** Context tree is plain markdown in your repo — reviewable in PRs, greppable in CI.
- **Fully open source.** MIT licensed.

## Contributing

1. Read [`AGENTS.md`](AGENTS.md) for conventions
2. Write a failing test first (`tests/`)
3. Run tests: `bash tests/test-config.sh && bash tests/test-skills.sh && bash tests/test-commands.sh`
4. Open a PR targeting `develop`

## License

MIT — see [LICENSE](LICENSE).

---

*Inspired by [Fastlane](https://fastlane.tools), [Terraform](https://terraform.io), and the [Superpowers methodology](https://www.claudesuperpowers.com).*
