---
name: xgh-profile
description: "Analyze an engineer's Jira history to produce throughput profiles, ticket affinity, and data-driven estimates for task assignment."
usage: "/xgh-profile <engineer name> [project key]"
aliases: ["team-profile", "profile"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh profile`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-profile — Engineer Throughput & Affinity Analysis

Run the `xgh:profile` skill to analyze an engineer's Jira history and produce actionable throughput metrics, ticket affinity data, and data-driven time estimates.

## Usage

```
/xgh-profile <engineer name>
/xgh-profile <engineer name> <project key>
/xgh-profile <name1>,<name2>,<name3> <project key>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `engineer name` | Yes | Engineer's Jira display name. Use commas for multiple names (team view). |
| `project key` | No | Jira project key (e.g., PTECH). Enables estimation and assignment recommendations. |

## Examples

```
/xgh-profile Alice
/xgh-profile Alice PTECH
/xgh-profile Alice,Bob,Carol PTECH
```

## What It Does

1. **Throughput Profile** — Cycle times (median, P75, P90) grouped by issue type, labels, and story point complexity. Throughput rates over 30/60/90-day windows.
2. **Ticket Affinity** — Distribution of work by type, label, component, and epic. Identifies the engineer's "sweet spot" (high volume + fast cycle time).
3. **Data-Driven Estimates** (requires project key) — Matches open backlog tickets to similar completed work and estimates duration with confidence levels.
4. **Assignment Recommendations** (requires project key) — Ranks open tickets by affinity score based on label overlap, type match, SP sweet spot, and epic continuity.
5. **Team View** (requires multiple names + project key) — Produces an assignment matrix and optimal assignment across engineers.

## Output

- Full report written to `.xgh/research/<engineer-name-slug>-profile.md`
- Summary printed to conversation
- Profile cached to MAGI memory (if available) for future reference

## Prerequisites

- Atlassian MCP must be configured. Run `/xgh-setup` if not yet connected.

## Related Skills

- `xgh:profile` — the full workflow skill this command triggers
- `xgh:brief` — session briefing that can surface capacity issues
- `xgh:implement` — uses profile data to inform assignment decisions
