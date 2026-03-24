---
name: xgh:onboarding-accelerator
description: "This skill should be used when a new developer starts their first session, runs /xgh-onboard, or asks for a project overview or team context. Surfaces architecture decisions, conventions, gotchas, incidents, and an ownership map from team memory — years of context in minutes."
---

# xgh:onboarding-accelerator — Onboarding Accelerator

> First session for a new developer: query the team knowledge base and surface architecture decisions, conventions, gotchas, incidents, and a "who owns what" map — years of context in minutes.

## Iron Law

> **NEW DEVELOPERS MUST RECEIVE TEAM CONTEXT BEFORE WRITING THEIR FIRST LINE OF CODE.** The onboarding session is not optional. Without it, the new developer will repeat every mistake the team has already solved.

## When This Skill Activates

- First session for a new developer (detected by: no prior session history in lossless-claude, or explicit `/xgh onboard` command)
- When a developer explicitly asks for a project overview or team context
- When session-start hook detects an unrecognized developer identifier

---

## Knowledge Categories

The onboarding accelerator queries lossless-claude for five categories of team knowledge:

### 1. Architecture Decisions

```
Tool: lcm_search(query)
Parameters:
  query: "architecture decisions design system structure"
  scope: workspace
  filter:
    type: decision
    maturity: core OR validated
```

Surfaces: major architecture choices, system design, module boundaries, data flow, technology choices with rationale.

### 2. Coding Conventions

```
Tool: lcm_search(query)
Parameters:
  query: "convention rules patterns naming style"
  scope: workspace
  filter:
    type: convention
    scope: team
    maturity: core OR validated
```

Surfaces: code style rules, naming conventions, patterns to follow, patterns to avoid, testing requirements.

### 3. Gotchas and Warnings

```
Tool: lcm_search(query)
Parameters:
  query: "gotcha warning trap pitfall edge-case unexpected"
  scope: workspace
  filter:
    type: gotcha OR type: warning OR type: handoff
```

Surfaces: non-obvious behaviors, common mistakes, edge cases, "things that look right but aren't", workarounds.

### 4. Incidents and Fixes

```
Tool: lcm_search(query)
Parameters:
  query: "incident bug fix root-cause investigation"
  scope: workspace
  filter:
    type: incident OR type: investigation
```

Surfaces: past production issues, root causes, fixes applied, prevention measures, monitoring gaps.

### 5. Ownership Map

```
Tool: lcm_search(query)
Parameters:
  query: "ownership module area responsible team member"
  scope: workspace
  filter:
    type: ownership OR type: handoff
```

Surfaces: who owns what modules, who to ask about what, recent handoffs, domain expertise map.

---

## Onboarding Session Flow

### Phase 1: Welcome and Context Load

```
┌─ xgh Onboarding ─────────────────────────────────────────┐
│                                                            │
│  Welcome to [project-name]!                                │
│  Team: [team-name]                                         │
│                                                            │
│  Loading team knowledge base...                            │
│                                                            │
│  Found:                                                    │
│  → [N] architecture decisions                              │
│  → [N] coding conventions                                  │
│  → [N] gotchas and warnings                                │
│  → [N] incidents and fixes                                 │
│  → [N] ownership entries                                   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Phase 2: Architecture Overview

Present the top architecture decisions (sorted by importance), with:
- The decision and its rationale
- Key files and modules involved
- How components connect
- What constraints exist

Format as a guided tour, not a data dump:

```
"This project uses [architecture pattern] because [rationale].

The main modules are:
1. [module] — [purpose] (key files: [paths])
2. [module] — [purpose] (key files: [paths])

Data flows like this: [flow description]

Key constraint: [constraint from team decision]"
```

### Phase 3: Convention Briefing

Present core conventions as a checklist:

```
"Before you write any code, here are the team's conventions:

[CORE] conventions (non-negotiable):
□ [convention 1] — [brief rationale]
□ [convention 2] — [brief rationale]

[VALIDATED] conventions (strong recommendations):
□ [convention 3] — [brief rationale]
□ [convention 4] — [brief rationale]

These are enforced automatically by xgh — I'll remind you during coding."
```

### Phase 4: Gotcha Highlights

Present the most impactful gotchas:

```
"Things that trip up new developers here:

⚠ [gotcha 1]: [what seems right but isn't, and why]
⚠ [gotcha 2]: [non-obvious behavior and how to handle it]
⚠ [gotcha 3]: [common mistake and the correct approach]

These are from real experiences — they'll save you hours."
```

### Phase 5: Recent History

Present recent incidents and fixes:

```
"Recent incidents to be aware of:

- [date]: [incident summary] — caused by [root cause], fixed by [fix]
- [date]: [incident summary] — caused by [root cause], fixed by [fix]

Prevention measures in place: [what's been done]"
```

### Phase 6: Ownership Map

Present who owns what:

```
"Who to ask about what:

- [module/area]: [person/team] (last active: [date])
- [module/area]: [person/team] (last active: [date])

Recent handoffs:
- [area]: handed off from [person] on [date] — see handoff notes for context"
```

### Phase 7: Interactive Q&A

After the briefing, prompt the new developer:

```
"That's the overview. What area are you starting with?
I'll pull up the specific context you need."
```

When the developer asks about a specific area, query lossless-claude for deep context on that domain and present it with full detail.

---

## Storing Onboarding Metadata

Track the onboarding session for future reference:

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: |
    Onboarding session completed for [developer identifier].
    Knowledge delivered: [N] architecture, [N] conventions, [N] gotchas, [N] incidents, [N] ownership.
    Areas of interest: [what the developer asked about]
    Gaps identified: [areas with thin documentation]
  metadata:
    type: onboarding
    scope: team
    developer: [identifier]
    session_date: [ISO timestamp]
```

---

## Tool Reference

| Tool | Usage |
|---|---|
| [SEARCH] → call `lcm_search(query)` | Query all 5 knowledge categories for onboarding briefing |
| [STORE] → call `lcm_store(text, ["reasoning"])` | Store onboarding session metadata and identified gaps |
| Extract 3-7 bullet summary → [STORE] → call `lcm_store(text, context-tag)` | Extract session learnings if developer shares new context |

## Composability

- Consumes from **convention-guardian**: Core conventions surfaced during briefing
- Consumes from **knowledge-handoff**: Handoff summaries contribute to gotchas and ownership map
- Consumes from **cross-team-pollinator**: Org-scope knowledge included in architecture overview
- Consumes from **pr-context-bridge**: Recent PR reasoning contributes to "recent history"
