---
name: xgh-brief
description: Run a session briefing — checks Slack, Jira, and GitHub and produces an actionable summary of what needs attention right now.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh brief`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-brief — Session Briefing

Run the `xgh:briefing` skill to generate a structured morning/session briefing.

The briefing will:

1. Detect which integrations are available (Slack, Jira, GitHub, lossless-claude)
2. Query each source for urgent items, in-progress work, and incoming tasks
3. Produce a categorised summary with a single Suggested Focus
4. Ask how you'd like to proceed

## Usage

```
/xgh-brief
```

No arguments needed. Run it at the start of any work session to get oriented.

## Tips

- The briefing is always available. Run `/xgh-brief` at the start of any session to get oriented.
- Run `/xgh-setup` first if you haven't configured Slack, Jira, or GitHub integrations yet.
