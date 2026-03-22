---
title: "Core Values Interview in /xgh-init → Injected into Agent Prompts"
type: decision
status: proposed
importance: 88
tags: [vision, init, onboarding, prompts, injection, values]
keywords: [core-values, mission, vision, init-interview, prompt-injection, seed]
created: 2026-03-21
updated: 2026-03-21
---

## The Idea

During `/xgh-init`, interview the user to capture their project's **core values** — why this project exists, what it stands for, what it refuses to do. Store the result in `config/project.yaml` under a `values:` block.

The session-start hook and `/xgh-seed` then inject this into agent prompts so every agent — Claude, Codex, Gemini, OpenCode — reasons from the right frame from the first token.

## Why This Matters

An agent that knows your tech stack will write code. An agent that knows your *values* will write the *right* code. It won't suggest the wrong architectural trade-off. It won't add telemetry you'd never ship. It won't optimize for the wrong metric.

This is the "why" behind every decision. xgh's own MISSION.md exists for this reason — agents working on xgh should know they're building declarative AI ops, not just a plugin with a lot of commands.

## The Interview (proposed questions)

Asked during `/xgh-init`, Step 2 (Profile) or a new Step 2a:

```
What does this project do in one sentence?
→ stored as: project.tagline (already exists)

Why does it exist? What problem does it solve that nothing else solves well?
→ stored as: project.values.mission

What does this project refuse to do? (anti-goals, non-starters)
→ stored as: project.values.anti_goals[]

What are the 2-3 principles that should guide every decision?
→ stored as: project.values.principles[]

What does "done well" look like here? How do you know when something is right?
→ stored as: project.values.done_well
```

## Config Schema

```yaml
# config/project.yaml
values:
  mission: "Make AI agents first-class teammates — reliable, consistent, context-aware."
  anti_goals:
    - "No cloud sync, no telemetry, no vendor lock-in"
    - "Not a wrapper around other tools — xgh orchestrates, not replaces"
    - "Never require a running server to function"
  principles:
    - "Declare desired state, converge reality to match (declarative AI ops)"
    - "One source of truth — YAML is authoritative, everything else is derived"
    - "Drift is the enemy — seeded context must always be re-generatable"
  done_well: "An agent opens a session, immediately knows the project context, makes decisions consistent with past ones, and never asks the same question twice."
```

## Injection Points

### session-start hook
Prepend a `## Why this project exists` section to the injected context, drawn from `values.mission` + `values.principles`. Short — 3-5 lines max. Enough to frame all subsequent reasoning.

### /xgh-seed
Include `values:` block in every platform's `context.md`. This is the most important part of context — more durable than recent activity or session state.

### AGENTS.md generator
Add a `## Core Values` section (from `values:`), positioned near the top — before Tech Stack, after the project description.

## Implementation

- Add to `/xgh-init` as Step 2a: "What does this project stand for?"
- Questions are optional — user can skip any or all
- Pre-populate from README/MISSION.md if present (Claude reads them and proposes answers)
- `/xgh-init --regenerate-values` re-runs the interview without full reinit

## Why Init Interview (not manual YAML edit)

The interview forces the user to articulate values out loud. Writing YAML directly produces copy-paste boilerplate. Answering three questions produces something real. The agent then reflects those answers back — the user sees immediately whether the phrasing is right.

It's the same reason good design tools ask "what are you trying to accomplish?" before showing options.
