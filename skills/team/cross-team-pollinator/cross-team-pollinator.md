---
name: xgh:cross-team-pollinator
description: "This skill should be used when curating knowledge to the _shared/ directory, when querying memory that should include org-scoped results, or when implementation touches a cross-team API boundary or shared library. Breaks knowledge silos between teams — auto-promotes _shared/ directory entries to org-scope in lossless-claude workspace so other teams benefit."
---

# xgh:cross-team-pollinator — Cross-Team Pollinator

> Break knowledge silos between teams. The `_shared/` directory in each team's context tree auto-promotes to `scope: org` in lossless-claude workspace. Other teams' hooks query org-scoped memories alongside their own.

## Iron Law

> **CROSS-TEAM KNOWLEDGE MUST FLOW BOTH WAYS.** When you discover something that affects other teams, share it. When querying memory, always include org-scope results. Silos form by default — sharing requires intention.

## When This Skill Activates

- **Promotion**: When knowledge is curated to the `_shared/` directory of the context tree
- **Query enrichment**: On every `lcm_search` call, org-scoped results are merged alongside team-scoped results
- **Discovery**: When implementation touches an API boundary, shared library, or cross-team contract

---

## Promotion Rules

### What gets promoted to org-scope

Knowledge qualifies for org-scope promotion when it:
1. Lives in the `_shared/` directory of the context tree
2. Has `maturity: validated` or `maturity: core`
3. Describes an interface, contract, or convention that affects other teams

### Automatic promotion

When a file is written to or moved to `_shared/`:

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: [the shared knowledge content]
  metadata:
    type: [original type]
    scope: org
    origin_team: [team name from config]
    origin_path: [context tree path]
    maturity: [validated or core]
    tags: [original tags + "cross-team"]
```

### What belongs in `_shared/`

```
.xgh/context-tree/
├── _shared/                          # Auto-promotes to scope: org
│   ├── api-contracts/
│   │   └── user-response-format.md   # "UserResponse.role is optional"
│   ├── conventions/
│   │   └── date-format-iso.md        # "All dates must be ISO 8601"
│   ├── infrastructure/
│   │   └── auth-middleware.md         # "Use shared auth middleware v2"
│   └── warnings/
│       └── legacy-api-v1-compat.md   # "Don't break v1 backward compat"
├── authentication/                    # Team-only (scope: team)
│   └── ...
└── api-design/                        # Team-only (scope: team)
    └── ...
```

---

## Query Merging

### How org-scope memories are included

Every `lcm_search(query)` call in an xgh-enabled project includes BOTH scopes:

**Step 1: Team-scope query**

```
Tool: lcm_search(query)
Parameters:
  query: "[the user's question or task context]"
  scope: workspace
  filter:
    scope: team
    team: [current team name]
```

**Step 2: Org-scope query**

```
Tool: lcm_search(query)
Parameters:
  query: "[the user's question or task context]"
  scope: workspace
  filter:
    scope: org
```

**Step 3: Merge and rank results**

Results from both queries are merged with the following ranking:
```
score = (0.5 * relevance_score + 0.3 * maturity_boost + 0.2 * recency)
```

Where:
- Team-scope results with `maturity: core` get a 1.15x boost
- Org-scope results get a 1.0x baseline (no penalty for being org-level)
- Origin team is displayed so the developer knows who shared it

### Presentation

```
┌─ Cross-Team Knowledge ───────────────────────────────────┐
│                                                            │
│  From your team (my-team):                                 │
│  [CORE] Use token-bucket for rate limiting                 │
│                                                            │
│  From other teams:                                         │
│  [ORG/backend-team] UserResponse.role is optional          │
│                      for backward compat with v1           │
│  [ORG/platform-team] New shared auth middleware supports   │
│                      OAuth2 + API keys — use it            │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## Sharing Workflow

### When a developer discovers cross-team knowledge

1. **Recognize it**: "This affects other teams" — API format changes, shared library updates, contract changes
2. **Curate to `_shared/`**: Write or move the knowledge file to `_shared/[category]/`
3. **Auto-promotion fires**: The file is stored to lossless-claude with `scope: org`
4. **Other teams benefit**: Their next `lcm_search` includes this knowledge

### Promoting existing team knowledge to org

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: |
    [Existing team knowledge that should be shared]
    Origin: [team name]
    Why shared: [reason this matters to other teams]
  metadata:
    type: [original type]
    scope: org
    origin_team: [team name]
    maturity: [current maturity]
    promoted_from: [context tree path]
```

---

## Tool Reference

| Tool | Usage |
|---|---|
| `lcm_search(query)` | Query both team-scope and org-scope memories |
| `lcm_store(text, ["reasoning"])` | Store org-promoted knowledge to workspace |
| Extract 3-7 bullet summary → `lcm_store(text, context-tag)` | Extract cross-team relevant learnings |

## Composability

- Consumes from **convention-guardian**: Team conventions may promote to org-scope
- Consumes from **knowledge-handoff**: Handoff discoveries that affect other teams
- Feeds into **onboarding-accelerator**: Org-scope knowledge surfaced during onboarding
- Works with **pr-context-bridge**: Cross-team context included in PR reasoning
