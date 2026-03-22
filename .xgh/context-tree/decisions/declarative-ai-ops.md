---
title: "xgh is Declarative AI Ops"
type: decision
status: validated
importance: 95
tags: [vision, architecture, positioning, decision]
keywords: [declarative, ai-ops, terraform, infrastructure-as-code, drift, state]
created: 2026-03-21
updated: 2026-03-21
---

## Core Insight

**xgh is literally declarative AI ops.**

The same way Terraform lets you declare infrastructure and converge reality to match, xgh lets you declare AI agent behavior and converge every platform to match.

## The Terraform Analogy

| Terraform | xgh |
|-----------|-----|
| `variables.tf` | `config/project.yaml` |
| `providers.tf` | `config/agents.yaml` |
| Event sources | `config/triggers.yaml` |
| Workspace-level defaults | `preferences:` block |
| `terraform apply` | `/xgh-seed` — pushes state to each platform |
| `terraform plan` output | `gen-agents-md.sh` — human-readable view of what's configured |
| State file | `AGENTS.md` |

## The Hard Problem is Drift

Just like Terraform, the tool isn't the hard part — **drift is**. Platform skill files go stale, AGENTS.md gets hand-edited, hooks fail silently.

This is why the architecture decision ([runtime-injection-as-source-of-truth](./runtime-injection-preferences.md)) matters: don't store machine-consumed state in the plan output. `config/project.yaml` is the source of truth; AGENTS.md is the rendered view.

## Why This Framing Matters

- **Explains the preferences: block** — it's workspace variables, not documentation
- **Explains /xgh-seed** — it's `apply`, not a one-time setup script
- **Explains AGENTS.md** — it's a plan output, not an authoritative config
- **Explains runtime injection** — you don't hardcode state into the plan output
- **Explains the generator** — `gen-agents-md.sh` is `terraform plan`, not the source of truth

## Positioning

xgh started as "persistent memory for Claude Code." The deeper framing is:

> **xgh: declarative AI ops** — declare your agent behavior in YAML, converge every AI platform to match.
