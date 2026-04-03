# AGENTS.md Generator Design

**Date:** 2026-03-21
**Source:** lossless-claude `develop` branch — `WORKFLOW.md` + `agents/*.md`
**Goal:** Replace hand-maintained `AGENTS.md` with a generated artifact derived from structured YAML sources.

---

## What lossless-claude does (and why it works)

lossless-claude's develop branch has converged on a clean three-file pattern:

| File | Role |
|------|------|
| `AGENTS.md` | Thin wrapper — just `@WORKFLOW.md` include + PR merge rules |
| `WORKFLOW.md` | Living dev workflow doc — phases, defaults table, branch strategy, Copilot interaction, common pitfalls |
| `agents/*.md` | One file per agent — YAML frontmatter (`name`, `description`, `model`, `color`, `tools`) + instruction body |

**Why this works:**
- `AGENTS.md` never gets stale because it has no real content — it just delegates
- `WORKFLOW.md` is a living doc with an explicit "update after every feature cycle" contract
- Agent files are the single source of truth for each agent's contract — no duplication between the file and any registry
- The frontmatter schema is rich enough to be machine-readable (model, color, tools) AND human-readable (description with examples)

---

## xgh's current pain point

`AGENTS.md` is a 185-line hand-maintained document that covers:
- Project overview
- Tech stack table
- Repository structure
- 8 agent descriptions
- Development guidelines
- Test commands
- Implementation status
- Superpowers methodology

This gets stale fast. When a new skill is added or an agent changes, `AGENTS.md` either lags behind or requires a separate manual update. Claude's native `/init` command regenerates it from scratch, losing all carefully crafted content.

---

## Proposed design

### Source of truth: structured YAML files

Instead of one big markdown doc, split into machine-readable sources:

```
config/
  project.yaml        — project overview, tech stack, install command
  workflow.yaml       — dev phases, defaults table, test commands
  agents.yaml         — existing agent registry (already here, extend it)
  team.yaml           — conventions, coding standards, pitfalls
```

### Generated artifact: AGENTS.md

A script reads all YAML sources and produces `AGENTS.md` — fully regenerable, never hand-edited.

```
scripts/gen-agents-md.sh  →  AGENTS.md (generated)
```

Add to top of generated AGENTS.md:

```markdown
<!-- AUTO-GENERATED — do not edit. Run `bash scripts/gen-agents-md.sh` to regenerate. -->
```

### What each YAML covers

**`config/project.yaml`** (new)
```yaml
name: xgh
tagline: "xgh: Claude on the fastlane"
description: |
  xgh is a Model Context Server (MCS) tech pack for Claude Code...
install: |
  claude plugin install xgh@tokyo-megacorp
  /xgh-init
tech_stack:
  - layer: Install & hooks
    technology: "Bash (set -euo pipefail)"
  - layer: Config
    technology: "YAML, JSON"
  ...
```

**`config/workflow.yaml`** (new)
```yaml
defaults:
  - question: "Spec location"
    answer: ".xgh/specs/YYYY-MM-DD-<topic>-design.md"
  - question: "Test command"
    answer: "bash tests/test-config.sh"

phases:
  - name: Design
    model: opus
    effort: max
    steps: [...]

pitfalls:
  - title: "plugin.json has no skills array"
    body: "Skills are auto-discovered from filesystem — do not add to plugin.json"
```

**`config/agents.yaml`** (extend existing)

Add `model`, `color`, `tools` to each agent entry — mirrors lossless-claude's frontmatter schema. The generator reads these to produce the agents section of AGENTS.md, and also validates that each `agents/*.md` file has matching frontmatter.

**`config/team.yaml`** (new)
```yaml
conventions:
  - "All skills use assert_contains / assert_file_exists helpers"
  - "Commands are thin wrappers — logic lives in skills/"
  - "No context-mode references in xgh skill files"
pitfalls: [...]
```

### Generator script

```bash
# scripts/gen-agents-md.sh
# Reads config/*.yaml → produces AGENTS.md
# Uses python3 (already required for context tree search)
```

The script:
1. Reads `config/project.yaml` → project overview section
2. Reads `config/agents.yaml` → agent roster table + descriptions
3. Reads `config/workflow.yaml` → dev phases, defaults, test commands
4. Reads `config/team.yaml` → conventions and pitfalls
5. Reads `agents/*.md` frontmatter → validates against agents.yaml entries
6. Outputs `AGENTS.md`

### AGENTS.md structure (generated)

```markdown
<!-- AUTO-GENERATED. Run: bash scripts/gen-agents-md.sh -->

# AGENTS.md — xgh (eXtreme Go Horse)

## What is xgh?
{from project.yaml: description}

## Install
{from project.yaml: install}

## Tech Stack
{table from project.yaml: tech_stack}

## Repository Structure
{from project.yaml: structure — keep this hand-maintained in project.yaml, not inferred}

## Agent Roster
{table + descriptions from agents.yaml + agents/*.md frontmatter}

## Development Workflow
{phases from workflow.yaml}

## Defaults
{table from workflow.yaml: defaults}

## Test Commands
{from workflow.yaml: test_commands}

## Conventions
{from team.yaml: conventions}

## Common Pitfalls
{from team.yaml: pitfalls}
```

---

## What to borrow directly from lossless-claude

1. **WORKFLOW.md as a living doc** — extract the "phases + defaults + Copilot interaction" content from AGENTS.md into a separate `WORKFLOW.md`. Reference it from AGENTS.md with `@WORKFLOW.md`. Same contract: "update after every feature cycle."

2. **Agent frontmatter schema** — adopt lossless-claude's schema for `agents/*.md`:
   ```yaml
   model: haiku | sonnet | opus
   color: yellow | green | blue | ...
   tools: ["Read", "Grep", "Glob", ...]
   ```
   xgh agents already have `name` and `description` — add `model`, `color`, `tools`.

3. **Thin AGENTS.md** — ultimately AGENTS.md becomes:
   ```markdown
   <!-- AUTO-GENERATED -->
   @WORKFLOW.md
   @config/project.yaml (rendered)
   ```

---

## Incremental implementation path

**Step 1 (low risk):** Add `WORKFLOW.md` as a separate file. Extract the "phases, defaults, test commands, pitfalls" sections from AGENTS.md into it. Update AGENTS.md to `@WORKFLOW.md` include. No YAML needed yet.

**Step 2:** Add `model`, `color`, `tools` to all `agents/*.md` frontmatter. Mirrors lossless-claude's schema. Enables Codex/Claude to auto-read agent capabilities without parsing prose.

**Step 3:** Create `config/project.yaml` and `config/team.yaml`. Move static content out of AGENTS.md.

**Step 4:** Write `scripts/gen-agents-md.sh`. Add to CI to verify AGENTS.md stays in sync.

---

## Workflows and triggers: the missing layer

AGENTS.md currently has no concept of *when* things run. The YAML sources need to capture this so AGENTS.md can generate an accurate "automation map" section.

### What already exists

**`config/workflows/*.yaml`** — 4 multi-agent collaboration patterns already defined:

| File | Pattern |
|------|---------|
| `parallel-impl.yaml` | Coordinator splits → agents implement in parallel → coordinator merges |
| `plan-review.yaml` | Agent A plans → Agent B reviews → Agent A implements |
| `security-review.yaml` | Implementation → security audit → fix loop |
| `validation.yaml` | Multi-step validation with gating |

Each workflow has: `roles`, `steps`, `depends_on`, `parallel`, `completion`. This schema is already solid.

**`~/.xgh/triggers/*.yaml`** — IFTTT-style user-defined triggers that fire on inbox events. The trigger engine reads these to decide: _"when item X arrives, run skill Y."_ Currently no default triggers ship with xgh — users define their own.

### What's missing: a trigger registry in the repo

The disconnect: workflows define _how_ to run multi-agent tasks, but nothing in the repo declares _what triggers them_. This creates two gaps:

1. AGENTS.md can't describe "what fires when" because that information doesn't exist in a machine-readable form in the repo
2. `/xgh-init` can't seed useful default triggers because there's no trigger catalog to draw from

### Proposed: `config/triggers.yaml` — default trigger catalog

A catalog of triggers that ship with xgh and get installed to `~/.xgh/triggers/` on `/xgh-init`:

```yaml
triggers:
  - name: pr-opened
    description: "When a PR is opened in a tracked repo, run the pr-reviewer workflow"
    when:
      source: github
      event: pull_request.opened
    action:
      skill: xgh:pr-reviewer
      workflow: plan-review
      agent: pr-reviewer
    cooldown: 0

  - name: slack-mention
    description: "When someone mentions the team in Slack, run briefing"
    when:
      source: slack
      type: mention
    action:
      skill: xgh:brief
    cooldown: 300   # 5 min

  - name: jira-assigned
    description: "When a ticket is assigned to the team, run implement"
    when:
      source: jira
      event: issue_assigned
      project: "*"
    action:
      skill: xgh:implement
      workflow: plan-review
    cooldown: 0

  - name: digest-ready
    description: "When analyze produces a digest, seed context to all platforms"
    when:
      source: local
      path: "~/.xgh/inbox/digest.md"
      event: created
    action:
      skill: xgh:seed
    cooldown: 600   # 10 min
```

### Workflow ↔ trigger ↔ agent binding

The full "what triggers when" picture requires three YAML files to agree:

```
config/triggers.yaml     — event → skill/workflow binding
config/workflows/*.yaml  — workflow → roles → agents
config/agents.yaml       — agent → capabilities
```

The generator script reads all three to produce an "Automation Map" section in AGENTS.md:

```markdown
## Automation Map

| Trigger | Condition | Skill | Workflow | Agents |
|---------|-----------|-------|----------|--------|
| pr-opened | GitHub PR opened | xgh:pr-reviewer | plan-review | pr-reviewer (planner), code-reviewer (reviewer) |
| slack-mention | Slack @mention | xgh:brief | — | — |
| jira-assigned | Jira ticket assigned | xgh:implement | plan-review | claude-code (planner), codex (implementer) |
| digest-ready | Digest written locally | xgh:seed | — | — |
```

This table is currently impossible to write accurately by hand — it requires knowing the workflow's role→agent mapping. With YAML sources, it generates itself.

### Trigger schema additions

The existing trigger skill (`skills/trigger/trigger.md`) reads `~/.xgh/triggers/*.yaml` with a `when` schema that supports `source`, `path`, `type`, and pattern matching. The proposed `config/triggers.yaml` should use the same schema so triggers in the catalog can be installed verbatim to `~/.xgh/triggers/`.

Add one field: `installed_by` — marks catalog triggers so `/xgh-init` knows which ones to add/update vs. leave alone (user-defined triggers have no `installed_by`).

---

## What this enables beyond AGENTS.md

- **`/xgh-init` becomes accurate** — reads YAML sources, generates verified AGENTS.md + installs default triggers from catalog
- **Automation map is always current** — the trigger↔workflow↔agent binding is machine-derived, never stale
- **Multi-platform parity** — `gen-agents-md.sh` also generates `GEMINI.md`, `.github/copilot-instructions.md`, Codex `SKILL.md` from the same sources
- **Agent schema validation** — CI asserts every `agents/*.md` has required frontmatter (`model`, `color`, `tools`)
- **`/xgh-seed` uses the same sources** — context brief written to each platform's skill_dir is derived from YAML, not ad-hoc prose
