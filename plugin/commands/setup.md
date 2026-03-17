---
name: xgh-setup
description: Audit and configure MCP integrations for xgh workflow skills
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh setup`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-setup — MCP Integration Setup

Run the `xgh:mcp-setup` skill in **full audit mode**:

1. Check all supported MCP servers (lossless-claude, Slack, Figma, Atlassian, GitHub CLI)
2. Report which are configured and which are missing
3. Offer interactive setup for each missing integration
4. Verify each setup works before moving on

This ensures all xgh workflow skills (`investigate`, `implement-design`, `implement-ticket`) have their optional dependencies ready.

## Usage

Just run `/xgh-setup` — no arguments needed. The skill will walk you through everything interactively.
