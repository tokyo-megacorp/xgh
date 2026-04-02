---
name: implement
description: "Implement a ticket with full cross-platform context gathering and Superpowers methodology"
usage: "/xgh implement [ticket-id]"
aliases: ["impl", "ticket"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh implement`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh implement

Implement a ticket end-to-end. Gathers context from every available source (ticket, Slack, Figma, xgh memory, codebase), interviews for missing context, proposes a design with trade-offs, generates a TDD implementation plan, and executes with subagent-driven development.

## Usage

```
/xgh implement <ticket-id>
/xgh implement PROJ-1234
/xgh implement
```

## Behavior

1. Load the `xgh:implement` skill from `skills/implement/implement.md`
2. Auto-detect available MCP integrations (Jira, Slack, Figma, MAGI)
3. If a ticket ID was provided, fetch it immediately
4. If no ticket ID was provided:
   - If task manager MCP available: search for recently assigned tickets
   - If not: ask user to describe the task
5. Execute all 6 phases of the implement-ticket workflow:
   - Phase 1: Ticket Deep Dive (fetch details, linked tickets, requirements)
   - Phase 2: Cross-Platform Context (Slack, Figma, memory, codebase)
   - Phase 3: Context Interview (Superpowers brainstorming, one question at a time)
   - Phase 4: Design Proposal (2-3 approaches, hard gate: approval required)
   - Phase 5: Implementation Plan (Superpowers writing-plans, TDD, exact paths)
   - Phase 6: Execute + Report (subagent-driven, update ticket, Slack, curate)

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `ticket-id` | No | Ticket ID (e.g., PROJ-1234). If omitted, searches assigned tickets or asks. |

## Examples

```
/xgh implement PROJ-1234
/xgh implement
```

## Related Skills

- `xgh:implement` — the full workflow skill this command triggers
- `xgh:design` — delegates to this skill for UI-heavy tickets
- `xgh:investigate` — delegates to this skill when ticket references a bug needing root cause
