---
name: investigate
description: "Start a systematic debugging investigation from a Slack thread or bug report"
usage: "/xgh investigate [slack-thread-url]"
aliases: ["debug", "inv"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh investigate`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh investigate

Start a systematic investigation of a bug or incident. Reads context from Slack, task managers, and xgh memory, then applies Superpowers systematic-debugging methodology to find the root cause.

## Usage

```
/xgh investigate <slack-thread-url>
/xgh investigate
```

## Behavior

1. Load the `xgh:investigate` skill from `skills/investigate/investigate.md`
2. Auto-detect available MCP integrations (Slack, Jira, MAGI)
3. If a Slack thread URL was provided, read the thread immediately
4. If no URL was provided, ask the user to describe the issue or paste a URL
5. Execute all 4 phases of the investigate workflow:
   - Phase 1: Context Gathering (Slack + Memory + Tickets)
   - Phase 2: Interactive Triage (find/create tickets)
   - Phase 3: Systematic Debug (Superpowers methodology)
   - Phase 4: Finding Report (structured output + distribution)

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `slack-thread-url` | No | URL to a Slack thread containing the bug report. If omitted, prompts for context. |

## Examples

```
/xgh investigate https://myteam.slack.com/archives/C01ABC/p1234567890
/xgh investigate
```

## Related Skills

- `xgh:investigate` — the full workflow skill this command triggers
- `xgh:implement` — after investigation, implement the fix via ticket
