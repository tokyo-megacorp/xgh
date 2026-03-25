---
name: xgh:review-pr
description: "Use when asked to review one or more PRs deeply — beyond Copilot's single-pass review. Triggers on: 'review PR', 'deep review', 'multi-persona review', 'thorough review'. Distinct from xgh:copilot-pr-review (bot delegation) — this runs 4 parallel Claude personas in 2 rounds."
---

# xgh:review-pr — Multi-Persona Code Review

Two-round parallel review: 4 personas run independently, then a second pass cross-pollinates findings.

> **Output format:** Follow the [xgh output style guide](../../templates/output-style.md). Start with `## 🐴🤖 xgh review-pr`.

## Input Parsing

```
xgh:review-pr 114 115          # review PRs #114 and #115
xgh:review-pr                  # auto-detect open PRs by current user
xgh:review-pr 114 --rounds 1   # single round only
```

Repo is read from `config/project.yaml` via `load_pr_pref repo` (see `skills/_shared/references/project-preferences.md`).

If no PR numbers given, fetch open PRs:
```bash
gh pr list --repo "$REPO" --author @me --state open --limit 30 --json number,title --jq '.[] | "#\(.number) \(.title)"'
```

## Personas

### 1. Product Owner
Are user-facing behaviors correct? Error messages clear and actionable? Does the change deliver what the issue promised? Edge cases users will hit?

### 2. Senior Engineer
Code quality, architecture fit, test coverage. Does it follow xgh conventions (skill frontmatter, `[SEARCH]`/`[STORE]` labels, hook patterns, `set -euo pipefail` in bash)? Dead code, unnecessary complexity, missing error handling?

### 3. Security Auditor
Attack surface, injection risks, path traversal, secrets in tracked files, TOCTOU gaps. Can any check be bypassed? Information leakage in error messages?

### 4. Documentation Specialist
Are new skills/agents/commands documented? Does `AGENTS.md` need updating? Are skill descriptions concise with trigger phrases front-loaded (e.g., "Use when...", "This skill should be used when...")? Do commands reference correct file paths?

## Steps

### Round 1 — Parallel review

**You MUST dispatch all 4 personas as parallel background agents using the Agent tool (`run_in_background: true`).** Do NOT review sequentially and do NOT simulate personas internally — internal simulation produces the same single-perspective blind spots as a plain review.

Each agent receives:
```
You are a [PERSONA] reviewing PR(s) [NUMBERS].
[PERSONA FOCUS from above]

For each PR:
1. Run: gh pr diff [NUMBER] --repo [REPO]
2. Read the changed files
3. Report findings with severity (Critical / High / Medium / Low) and file:line references
```

Wait for all 4 to complete, then compile into a single table:

| PR | Persona | Severity | Finding | File:Line |
|----|---------|----------|---------|-----------|

### Round 2 — Cross-pollination

Launch 4 new agents. Each receives the Round 1 table plus:

```
Round 1 found these issues:
[PASTE TABLE]

Your job:
1. Verify or challenge findings — real or false positives?
2. Look deeper at flagged areas
3. Find issues Round 1 missed

Round 2 focus by persona:
- PO: trace full user journey for every error path in flagged areas
- Eng: trace every code path, check for race conditions in flagged areas
- Security: construct concrete exploit scenarios for each finding
- Docs: verify every public API/skill change has correct documentation
```

Compile Round 2 findings. Deduplicate against Round 1.

### Final report

```
## 🐴🤖 xgh review-pr
Summary of multi-persona deep review findings across all requested PRs.

### Findings

| PR | Persona | Round | Severity | Finding | File:Line |
|----|---------|-------|----------|---------|-----------|

### Action items
- **Must fix before merge:** [Critical/High items]
- **Acceptable as-is:** [Low items with rationale]

### Verdict
| PR | Title | Verdict |
|----|-------|---------|
| #N | ...   | ✅ Ready to merge / ⚠️ Needs fixes / ❌ Needs redesign |
```

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Simulating personas internally | Use the Agent tool — 4 actual parallel agents, not internal reasoning |
| Single-pass review | Always dispatch 4 parallel agents — that's the whole point |
| Skipping Round 2 because Round 1 found nothing | Round 2 catches what Round 1 missed — always run both |
| Merging Round 1 and Round 2 into one agent | Keep rounds separate — Round 2 needs Round 1 as input |
| `--rounds 1` skips Round 2 | Only skip if user explicitly passes `--rounds 1` |
