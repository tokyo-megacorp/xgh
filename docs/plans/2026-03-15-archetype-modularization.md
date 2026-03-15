# Proposal: Archetype-Based Modular Installation

**Date:** 2026-03-15
**Status:** Proposal (not yet specced)

---

## Problem

xgh currently installs all 18 skills regardless of context. A solo developer working on personal projects doesn't have Jira, Slack, or Confluence — yet gets `/xgh-profile`, `/xgh-design`, and 6 ingest pipeline commands they'll never use. This creates skill bloat and a confusing `/xgh-help` surface.

## Idea

Introduce **archetypes** — predefined bundles that control which skills get installed. The archetype is chosen during `/xgh-init`, not during `install.sh`. The installer stays universal (core memory layer). The differentiation happens at onboarding time.

## Archetypes

### Solo Dev
For personal projects. No team tools, no ingest pipeline. Just persistent memory.

| Skill | What it does |
|-------|-------------|
| `/xgh-help` | Contextual guide and command reference |
| `/xgh-init` | First-run onboarding and archetype selection |
| `/xgh-setup` | Audit and configure MCP integrations |
| `/xgh-status` | Memory stats and context tree health |
| `/xgh-ask` | Search memory with natural language |
| `/xgh-curate` | Store knowledge in memory + context tree |
| `/xgh-index` | Index a codebase into memory |
| `/xgh-implement` | Implement a ticket/task with full context |
| `/xgh-investigate` | Systematic debugging from a bug report |

### OSS Contributor
GitHub-centric. PRs, issues, discussions as context sources instead of Slack/Jira.

Core skills + ingest pipeline:

| Skill | What it does |
|-------|-------------|
| `/xgh-brief` | Session briefing from connected sources |
| `/xgh-track` | Add a project to context monitoring |
| `/xgh-retrieve` | Pull new content from tracked sources |
| `/xgh-analyze` | Classify, dedup, and store retrieved content |
| `/xgh-doctor` | Validate pipeline health |
| `/xgh-calibrate` | Tune dedup similarity threshold |

### Enterprise
Full suite. Slack, Jira, Confluence, Figma, multi-agent collaboration.

Core + pipeline + enterprise-specific:

| Skill | What it does |
|-------|-------------|
| `/xgh-design` | Implement a UI from a Figma design |
| `/xgh-collab` | Coordinate with other AI agents |
| `/xgh-profile` | Analyze an engineer's Jira throughput |

### OpenClaw
Personal AI assistant integration. Messaging channels (WhatsApp, Telegram, Discord, etc.) as context sources.

Core + pipeline skills (same as OSS, different sources in `/xgh-track`).

## How It Works

1. **`install.sh`** — unchanged. Installs everything to `~/.xgh/pack/`. All skills live in the pack but are NOT copied to `.claude/skills/` yet.

2. **`/xgh-init`** — asks the archetype question:
   ```
   🐴 What kind of setup?

     1) Solo dev     — just memory, no integrations
     2) OSS          — GitHub-centric (PRs, issues, discussions)
     3) Enterprise   — full suite (Slack, Jira, Figma, multi-agent)
     4) OpenClaw     — personal AI assistant integration
   ```

3. **Installer copies only the selected skills** into `.claude/skills/` and `.claude/commands/` based on archetype. Stored in `~/.xgh/ingest.yaml` under `profile.archetype`.

4. **`/xgh-track`** — adapts its source detection based on archetype:
   - Solo: no sources (manual curate only)
   - OSS: GitHub repos, issues, PRs, discussions
   - Enterprise: Slack, Jira, Confluence, GitHub, Figma
   - OpenClaw: OpenClaw gateway channels

5. **Upgrading archetype** — running `/xgh-init` again lets you switch. It adds/removes skills accordingly.

## `/xgh-track` Source Adapters

The key insight: `/xgh-track` shouldn't hardcode Slack/Jira. It should detect available MCP servers and offer matching sources:

| MCP Available | Sources Offered |
|---------------|----------------|
| Slack | Slack channels |
| Atlassian | Jira projects, Confluence spaces |
| Figma | Figma files |
| GitHub CLI | Repos, issues, PRs, discussions |
| OpenClaw | Gateway channels |
| None | Manual curate only |

This makes `/xgh-track` archetype-aware but not archetype-locked. An OSS user who later connects Slack can use it.

## Open Questions

- Should archetypes be stored in `techpack.yaml` as formal bundles, or just as logic in the init skill?
- Should there be a `custom` archetype where you cherry-pick skills?
- How does this interact with the MCS `mcs sync` managed install path?
