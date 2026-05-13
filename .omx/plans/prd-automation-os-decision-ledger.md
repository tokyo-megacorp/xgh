# PRD — xgh Automation OS Decision Ledger

## Metadata

| Field | Value |
|---|---|
| Source spec | `.omx/specs/deep-interview-automation-self-referential-focus.md` |
| Context snapshots | `.omx/context/automation-self-referential-focus-20260513T131348Z.md`, `.omx/context/automation-self-referential-surface-inventory.md`, `.omx/context/automation-self-referential-expanded-inventory.md` |
| Ralplan mode | consensus |
| Architect verdict | APPROVE after one iteration |
| Critic verdict | APPROVE |
| Authorized work | Decision spike / audit / classification only |
| Not authorized | Cleanup implementation, archive, deletion, repo migration, irreversible public deprecation, public retirement announcement |

## RALPLAN-DR Summary

### Principles

1. **Decision first, cleanup later** — this plan authorizes a decision ledger, not implementation cleanup.
2. **Declarative convergence is the product boundary** — a surface belongs in xgh only if YAML/config declarations converge into concrete agent/platform behavior.
3. **Retirement must be evaluated honestly** — retirement is a real option, not a rhetorical foil.
4. **Irreversible actions require separate approval** — no archive, deletion, repo migration, public deprecation, or retirement announcement is authorized here.
5. **Evidence beats intuition** — every classification needs paths and evidence, not vibes.

### Decision Drivers

1. Does each surface help YAML/config declarations converge into concrete agent/platform behavior?
2. Does each surface help xgh operate, inspect, or improve xgh itself?
3. What is the relative cost/risk of refocus versus retirement?

### Viable Options

#### Option A — Refocus xgh as Automation OS

Pros:
- Preserves the strong declarative AI ops thesis.
- Keeps context tree, provider framework, generated instructions, hooks, and config surfaces if tied to convergence.
- Enables disciplined pruning of generic utility bloat later.

Cons:
- Requires public-surface narrowing.
- Some shipped surfaces may need hiding or deletion after approval.

#### Option B — Retire xgh

Pros:
- Avoids further investment in a bloated or pivot-heavy repo.
- Preserves useful concepts through archive/migration notes.

Cons:
- Migration gate is not passed.
- Retirement/archive is irreversible enough to require explicit approval.
- May discard still-valuable convergence architecture.

#### Option C — Defer with blocking evidence gaps

Pros:
- Appropriate if evidence gaps block a fair decision.
- Prevents premature refocus or retirement.

Cons:
- Delays strategic cleanup.
- Leaves public product identity ambiguous.

## Problem

xgh has accumulated public surfaces that may dilute its core identity. The intended direction is **Automation OS**: users declare automation behavior in YAML/config, and xgh converges supported agent/platform surfaces to match.

However, the strategic decision is unresolved: xgh may be worth refocusing, or it may be better retired/sunset if surface entropy and maintenance cost outweigh the value of repair.

## Goal

Produce an evidence-backed **decision ledger** that recommends exactly one path:

1. `refocus`
2. `retire`
3. `defer with blocking evidence gaps`

## Non-goals

This decision spike must not implement broad cleanup.

Out of scope unless directly tied to declarative convergence:

- Generic agent dispatch as a standalone product surface.
- Manual knowledge curation as a user-facing goal.
- Token/window utility surfaces.
- Broad architecture rewrite.
- Irreversible retirement/archive action.

## Decision Boundaries

This PRD authorizes **audit and classification only**.

No agent may perform the following without separate explicit user approval:

- Archive actions.
- File or surface deletions.
- Repo migration.
- Irreversible public deprecation.
- Public-facing retirement announcement.

`docs/MIGRATION_GATE.md` must be reviewed before any future migration path. Current gate status is **PENDING**, and the document states it does not authorize migration by itself.

## Required Decision Ledger Schema

Each audited surface must produce one ledger row with:

| Field | Requirement |
|---|---|
| `surface_id` | Stable identifier, e.g. `command:xgh-brief`, `skill:retrieve`, `doc:README`, `context:.xgh/context-tree/decisions/declarative-ai-ops.md` |
| `file_paths` | One or more concrete repo paths |
| `evidence_lines` | Exact quoted or summarized line references from inspected files |
| `declarative_convergence_justification` | How the surface does or does not help YAML/config declarations converge into agent/platform behavior |
| `self_referential_value` | Whether it helps xgh operate, evaluate, or improve xgh itself |
| `refocus_disposition` | Exactly one of `Keep`, `Deprecate-hide`, `Delete` |
| `retirement_disposition` | Exactly one of `Archive`, `Migrate concept`, `Abandon` |
| `estimated_effort_risk` | Small / Medium / Large plus risk note |
| `final_rationale` | Short rationale tying evidence to both axes |


The ledger artifact must be written as sectioned Markdown unless a later execution plan explicitly chooses a machine-readable companion. Recommended destination: `.omx/plans/automation-os-decision-ledger.md`. Each material claim must cite `path:start-end` line ranges; summaries are acceptable only when line ranges are still provided.

Disposition values are recommendation labels only. `Delete`, `Archive`, and `Migrate concept` do not authorize deletion, archival, migration, public deprecation, or retirement action.

The final artifact must also include these non-row sections:

- `Coverage inventory` — generated live-path inventory plus named skip rationales.
- `Refocus product shape` — declaration locations, generated outputs, and surfaces that become secondary, hidden, or removed if refocus is chosen.
- `Retirement safety` — direct citations showing `docs/MIGRATION_GATE.md` is pending and non-authorizing.
- `Aggregate decision summary` — disposition counts, effort/risk comparison, and the threshold used to choose `refocus`, `retire`, or `defer with blocking evidence gaps`.

## Classification Rules

### Axis 1: `refocus_disposition`

- `Keep` — directly supports declarative convergence or self-referential Automation OS operation.
- `Deprecate-hide` — useful capability but not core public surface for declarative convergence.
- `Delete` — orphaned, unsupported, duplicative, or contrary to Automation OS.

Exactly one value per row.

### Axis 2: `retirement_disposition`

- `Archive` — preserve historical/project record only.
- `Migrate concept` — preserve reusable idea elsewhere without assuming repo migration.
- `Abandon` — no meaningful value if xgh retires.

Exactly one value per row.

## Required Audit Coverage

The ledger must cover live filesystem surfaces, not only precomputed inventories:

1. `README.md`, including marketing claims, slash-command examples, and public command lists.
2. `package.json` and plugin metadata under `.claude-plugin/*`.
3. `docs/`, especially `docs/MIGRATION_GATE.md`.
4. Commands: every `commands/*.md` wrapper, including `analyze`, `brief`, `briefing`, `calibrate`, `command-center`, `config`, `doctor`, `help`, `init-providers`, `init`, `retrieve`, `schedule`, `seed`, `status`, `token-window`, `track`, and `trigger`.
5. Skills: every top-level shipped skill directory under `skills/`, including the named command-aligned skills plus support files such as `skills/AGENTS.md`; support-only directories such as `skills/_shared/` must either receive ledger rows or named skip rationales.
6. Generated/config surfaces recursively under `.github/`, `agents/`, `config/`, `hooks/`, and `templates/`; scoped `AGENTS.md` files must be classified as generated instruction surfaces or explicitly skipped with rationale.
7. Tests under `tests/`.
8. All top-level `.xgh/` categories, including `.xgh/context-tree/`, `.xgh/specs/`, `.xgh/plans/`, `.xgh/analysis/`, `.xgh/ideas/`, `.xgh/proposals/`, `.xgh/reviews/`, `.xgh/schemas/`, `.xgh/xgh.md`, roadmap, issue specs, and issue context.
9. Any orphaned or duplicate public references discovered during audit.

### Live Inventory Requirements

Before filling ledger rows, the executor must capture a fresh filesystem inventory and reconcile it against the required coverage list. At minimum, the audit evidence must include command output or equivalent generated lists for:

- `find commands -maxdepth 1 -type f -name '*.md'`
- `find skills -maxdepth 2 -type f -name '*.md'`
- `find package.json .claude-plugin docs .github agents config hooks templates tests .xgh -maxdepth 3 -type f`
- orphan/duplicate searches for `/xgh-`, `xgh:`, command filenames, skill names, and public metadata references across `README.md`, `package.json`, `.claude-plugin/`, `docs/`, `commands/`, `skills/`, `tests/`, and `.xgh/`

If a path is absent, ignored by git, generated, or intentionally skipped, the final ledger must name the path/category and explain why it was skipped. Precomputed context snapshots may guide discovery, but they are not sufficient proof of coverage.

### Code-Quality Review Focus

The audit must classify surfaces by product fit and implementation quality. For each command, skill, hook, generated/config surface, and test cluster, reviewers should note:

- whether it is reachable from a documented user path or generated instruction surface;
- whether its behavior is covered by tests or only by documentation claims;
- whether it duplicates another command, skill, or hook;
- whether it depends on manual knowledge curation, generic dispatch, or token-window utility behavior that does not support Automation OS convergence;
- whether keeping it would require code cleanup after the decision, and whether that cleanup is small, medium, or large risk.

These observations belong in `estimated_effort_risk` and `final_rationale`; they must not trigger implementation cleanup in this decision spike.

## Acceptance Criteria

- Public-surface audit identifies every shipped command/skill/doc surface and classifies it against declarative convergence.
- No orphan/bloat command reference remains unaccounted for.
- Recommendation explains how central automation config becomes if xgh is refocused.
- Roadmap/issues/specs are assessed for self-referential value.
- Deprecated/removal candidates explicitly include generic dispatch, manual curation, and token/window utilities where applicable.
- Retirement option is evaluated honestly.
- Final output recommends exactly one: `refocus`, `retire`, or `defer with blocking evidence gaps`.

## Review Findings and Documentation Updates

This PRD was reviewed for downstream execution clarity. The main quality risk was that the required coverage list named broad categories but did not require a fresh inventory artifact or state how code-quality observations should be represented without turning the spike into cleanup. The added live-inventory and code-quality sections make the expected evidence explicit while preserving the audit-only boundary.

Downstream reviewers should treat these documentation additions as scope clarifications, not as authorization to modify commands, skills, hooks, tests, generated instructions, or public docs outside the ledger deliverable.

## Execution Quality Gates

The decision-ledger execution is complete only when the final artifact includes:

1. A generated inventory or coverage checklist tied to live repo paths.
2. One schema-complete ledger row for every covered surface or explicitly skipped category.
3. Explicit dispositions for generic dispatch, manual knowledge curation, and token/window utilities.
4. A retirement assessment that cites `docs/MIGRATION_GATE.md` as pending and non-authorizing.
5. Exactly one recommendation: `refocus`, `retire`, or `defer with blocking evidence gaps`.
6. A verification note showing document validation and relevant repo checks were run or explaining any unavailable check.

Failure to satisfy any gate should result in `defer with blocking evidence gaps` or a failed verification pass, not silent narrowing of the audit scope.


If no schema-validator script exists, verification must perform a manual checklist against every required ledger field, valid disposition enum, coverage category, non-goal enforcement item, migration-gate citation, and final single-recommendation rule. The checklist result must be included in the final verification note.

## ADR — Decision Ledger Before Refocus/Retirement

### Decision

Use a two-axis evidence ledger as the next deliverable before choosing refocus, retirement, or deferment.

### Drivers

- Existing deep-interview spec requires a bounded decision spike, not implementation cleanup.
- Architect feedback requires decision-ledger framing.
- Public and internal surfaces extend beyond commands/skills/config and include README, docs, tests, `.xgh/context-tree`, `.xgh/specs`, and roadmap/issue context.
- Migration and irreversible retirement actions are gated.

### Alternatives Considered

1. **Cleanup plan now** — rejected because it assumes refocus before the decision spike completes.
2. **Retirement plan now** — rejected because migration/archive gates and user approval are not satisfied.
3. **Narrow command/skill audit only** — rejected because product surface includes docs, tests, generated instructions, specs, context tree, and roadmap artifacts.

### Why Chosen

The ledger produces a reversible, evidence-grounded decision artifact. It supports both refocus and retirement paths without prematurely executing either.

### Consequences

- Execution must wait until the ledger recommends a path.
- Cleanup/deletion tasks become follow-up work only after approval.
- Retirement remains gated by `docs/MIGRATION_GATE.md` and separate user approval.

### Follow-ups

- If recommendation is `refocus`: create an implementation PRD/test spec for public-surface narrowing and Automation OS repositioning.
- If recommendation is `retire`: create a separate retirement/migration plan and seek explicit user approval before action.
- If recommendation is `defer`: list blocking evidence gaps and assign targeted audit tasks.

## Available Agent Types Roster

- `explore` — fast repo search, surface inventory, file/path mapping.
- `planner` — ledger schema ownership, synthesis, final recommendation.
- `architect` — strategic fork review and migration/retirement safety.
- `critic` — classification consistency and evidence sufficiency.
- `verifier` — coverage, schema, and safety validation.
- `writer` — final recommendation narrative and migration/refocus handoff notes.
- `git-master` — only after a later implementation plan authorizes changes.

## Staffing / Handoff Guidance

### Ralph path

Use `$ralph` after approval if one persistent owner should produce the ledger end-to-end.

Suggested lane:
- `planner`: maintain ledger schema and final recommendation.
- `explore`: gather line evidence.
- `verifier`: check coverage and safety constraints.

Suggested reasoning: medium for exploration and ledger filling; high for final recommendation and verification.

### Team path

Use `$team` if faster parallel audit is preferred.

Suggested split:
1. Docs/README/Migration Gate auditor.
2. Commands/skills/config auditor.
3. Tests/context-tree/specs/roadmap auditor.
4. Verifier for schema, coverage, and safety.

Team verification path:
- Merge all ledger rows.
- Run schema validation from the test spec.
- Reconcile live filesystem against expected coverage.
- Confirm final recommendation has exactly one outcome.

Suggested launch hint:

```text
$team .omx/plans/prd-automation-os-decision-ledger.md
```

### Goal-Mode Follow-up Suggestions

- `$ultragoal` — recommended default if the user wants durable sequential tracking for the decision-ledger work.
- `$autoresearch-goal` — use only if the work expands into external ecosystem research or comparable project-replacement research.
- `$performance-goal` — not applicable unless future work becomes benchmark/latency/throughput focused.

Recommended next lane:

```text
$ralph .omx/plans/prd-automation-os-decision-ledger.md
```

or, for parallel audit:

```text
$team .omx/plans/prd-automation-os-decision-ledger.md
```
