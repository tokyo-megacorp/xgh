---
name: implement-design
description: "Implement a UI component from a Figma design with full context extraction"
usage: "/xgh implement-design [figma-url]"
aliases: ["design", "figma"]
---

# /xgh implement-design

Implement a UI component from a Figma design. Extracts ALL available context (design tokens, states, FigJam notes, Code Connect mappings), enriches with xgh memory and codebase conventions, reviews interactively, then generates and executes a TDD implementation plan.

## Usage

```
/xgh implement-design <figma-url>
/xgh implement-design
```

## Behavior

1. Load the `xgh:implement-design` skill from `skills/implement-design/implement-design.md`
2. Auto-detect available MCP integrations (Figma, Cipher, Jira, Slack)
3. If a Figma URL was provided, begin design mining immediately
4. If no URL was provided, ask the user for a Figma file or node URL
5. Execute all 5 phases of the implement-design workflow:
   - Phase 1: Deep Design Mining (Figma MCP extraction)
   - Phase 2: Context Enrichment (memory + codebase)
   - Phase 3: Interactive State Review (confirm with user)
   - Phase 4: Implementation Plan + Execute (TDD, Superpowers writing-plans)
   - Phase 5: Curate & Report (Code Connect, context tree, report)

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `figma-url` | No | URL to a Figma file or node. If omitted, prompts for URL. |

## Examples

```
/xgh implement-design https://www.figma.com/file/abc123/MyDesign?node-id=34079:43248
/xgh implement-design https://www.figma.com/design/abc123/MyDesign
/xgh implement-design
```

## Related Skills

- `xgh:implement-design` — the full workflow skill this command triggers
- `xgh:implement-ticket` — if the design is linked to a ticket, use implement instead
