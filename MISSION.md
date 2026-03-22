# xgh — Mission & Vision

## Mission

Make AI agents first-class citizens of software development teams — with the same reliability, consistency, and repeatability we expect from infrastructure.

## Vision

A world where every developer can declare how their AI agents should behave — across every tool, every session, every platform — and trust that reality matches the declaration.

No drift. No re-explaining context. No per-platform setup. Just code.

---

## The Problem

AI coding agents are powerful but stateless. Every session starts from zero. Every platform needs its own setup. Conventions get lost. Decisions get repeated. Context evaporates.

The result: agents that are brilliant in isolation but unreliable as teammates. You can't build a workflow on a colleague who forgets everything overnight.

Meanwhile, infrastructure solved this problem decades ago. Terraform, Ansible, Kubernetes — all built on the same insight: **declare the desired state, converge reality to match, detect drift early**. The tools don't forget. The config is the memory.

AI ops hasn't caught up yet.

## The Insight

**xgh is declarative AI ops.**

The same primitives that tamed infrastructure complexity apply directly to AI agent behavior:

| Infrastructure problem | Infrastructure solution | AI ops equivalent |
|------------------------|------------------------|-------------------|
| Servers drift from spec | Declare in Terraform, apply | Agents drift from conventions | declare in YAML, seed |
| Config scattered across teams | Single source of truth | Agent behavior scattered across platforms | `config/project.yaml` |
| Environment differences cause bugs | Immutable infra, reproducible state | Platform differences cause inconsistency | `/xgh-seed` normalizes all platforms |
| Runbooks go stale | Infrastructure as code | Agent instructions go stale | Generated `AGENTS.md` from live config |
| New engineer onboarding takes days | `terraform apply` spins up everything | New agent session loses context | session-start hook injects top knowledge |

## How We Get There

### 1. Config is the source of truth

Everything about how agents should behave lives in versioned YAML. Not in scattered prompt files, not in platform-specific settings, not in someone's head. One repo, one config, one source of truth.

### 2. Apply, don't copy-paste

`/xgh-seed` is `terraform apply` for AI platforms. Run it once: Codex, Gemini, OpenCode, and Claude all get the same project context. Run it again after changing config: they converge.

### 3. Memory is infrastructure

Decisions, conventions, patterns, and past work are stored in a git-committed knowledge base — reviewable in PRs, searchable in CI, readable without xgh. Not locked in a proprietary format. Not dependent on a cloud service. Infrastructure you own.

### 4. Drift is the enemy

AGENTS.md is a generated artifact, not a hand-maintained doc. Platform skill files are derived outputs, not sources of truth. The config is authoritative; everything else is a view. When reality drifts, you re-apply — not re-explain.

### 5. Works with the tools you already use

xgh doesn't replace Claude Code, Codex, Gemini, or OpenCode. It orchestrates them. Each tool does what it's best at; xgh ensures they all start from the same ground truth.

---

## Who This Is For

**Solo developers** who want their AI agent to remember across sessions — architecture decisions, naming conventions, past bugs, team patterns — without maintaining prompt files by hand.

**Small teams** who want every engineer's AI agent to share the same project context and follow the same conventions — without a shared server, without a vendor, without drift.

**Teams adopting multi-agent workflows** who need Codex running implementations, Gemini reviewing designs, and Claude orchestrating — all from a single declaration of what the project is and how it works.

---

## What Success Looks Like

- A developer opens a new session. Their agent already knows the project architecture, the active conventions, the last three decisions, and what's in the inbox. Zero re-explaining.

- A new engineer joins. They run `/xgh-init`. Their agent is immediately calibrated to the team's conventions, patterns, and pitfalls. Onboarding takes minutes, not days.

- A team switches from Codex to Gemini for a task. They run `/xgh-seed`. Gemini starts with the same project context Codex had. No manual migration.

- A convention changes. One YAML edit. One `apply`. Every platform is updated. No drift.

---

## Principles

**Declare, don't configure.** Behavior should be expressed as desired state, not imperative setup steps.

**Derive, don't duplicate.** AGENTS.md, platform skill files, and session context are all derived from config — never maintained independently.

**Local first.** Memory, config, and context stay on your machine. No telemetry, no cloud sync, no account required.

**Git-native.** Everything that matters is committed to the repo — reviewable in PRs, auditable in history, portable across machines.

**Composable, not monolithic.** xgh orchestrates tools you already trust. It doesn't replace them.

---

*xgh: Claude on the fastlane.*
