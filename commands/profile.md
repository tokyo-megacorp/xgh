---
name: xgh-team-profile
description: "Analyze an engineer's Jira history to produce throughput profiles, ticket affinity, and data-driven estimates for task assignment."
usage: "/xgh-team-profile <engineer name> [project key]"
aliases: ["team-profile", "profile"]
---

# /xgh-team-profile — Engineer Throughput & Affinity Analysis

Run the `xgh:team-profile` skill to analyze an engineer's Jira history and produce actionable throughput metrics, ticket affinity data, and data-driven time estimates.

## Usage

```
/xgh-team-profile <engineer name>
/xgh-team-profile <engineer name> <project key>
/xgh-team-profile <name1>,<name2>,<name3> <project key>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `engineer name` | Yes | Engineer's Jira display name. Use commas for multiple names (team view). |
| `project key` | No | Jira project key (e.g., PTECH). Enables estimation and assignment recommendations. |

## Examples

```
/xgh-team-profile Alice
/xgh-team-profile Alice PTECH
/xgh-team-profile Alice,Bob,Carol PTECH
```

## What It Does

1. **Throughput Profile** — Cycle times (median, P75, P90) grouped by issue type, labels, and story point complexity. Throughput rates over 30/60/90-day windows.
2. **Ticket Affinity** — Distribution of work by type, label, component, and epic. Identifies the engineer's "sweet spot" (high volume + fast cycle time).
3. **Data-Driven Estimates** (requires project key) — Matches open backlog tickets to similar completed work and estimates duration with confidence levels.
4. **Assignment Recommendations** (requires project key) — Ranks open tickets by affinity score based on label overlap, type match, SP sweet spot, and epic continuity.
5. **Team View** (requires multiple names + project key) — Produces an assignment matrix and optimal assignment across engineers.

## Output

- Full report written to `docs/research/<engineer-name-slug>-profile.md`
- Summary printed to conversation
- Profile cached to Cipher memory (if available) for future reference

## Prerequisites

- Atlassian MCP must be configured. Run `/xgh-setup` if not yet connected.

## Related Skills

- `xgh:team-profile` — the full workflow skill this command triggers
- `xgh:briefing` — session briefing that can surface capacity issues
- `xgh:implement-ticket` — uses profile data to inform assignment decisions
