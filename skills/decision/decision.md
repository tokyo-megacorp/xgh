---
name: xgh:decision
description: "Use when the user runs /xgh-track decision or /xgh-decision, or asks to 'record a decision', 'capture a decision', 'log a decision', or 'track a decision'. Records a decision to LCM, creates a real GitHub Issue, and links it to the owner's GitHub Project — implementing the UNBREAKABLE_RULES §10 processo 100% cumprido pipeline. Supports --dry-run to preview without creating anything, and is idempotent (won't create duplicate issues for the same decision text)."
---

## Preamble — Execution mode

Follow the shared execution mode protocol in `skills/_shared/references/execution-mode-preamble.md`. Apply it to this skill's command name.

- `<SKILL_NAME>` = `decision`
- `<SKILL_LABEL>` = `Decision`

---

# xgh:decision — MAGI Decision → GitHub Issue Pipeline

Records a decision through the full UNBREAKABLE_RULES §10 pipeline:
`magi_store` → `gh issue create` → `gh project item-add`

## Usage

```
/xgh-track decision "<decision text>" [--owner <role>] [--sprint <sp>] [--repo <owner/repo>] [--project <N>] [--dry-run]
```

| Flag | Default | Description |
|------|---------|-------------|
| `decision text` | required | The decision to record (as a quoted string or prompted) |
| `--owner` | "Co-CEO" | Role or person responsible (e.g. "CTO", "Team Lead [xgh]", "Pedro") |
| `--sprint` | auto-detect or "sp-unknown" | Sprint or milestone label |
| `--repo` | detect from `git remote get-url origin` or prompt | Target GitHub repo for the issue |
| `--project` | auto-detect from `gh project list --owner <org>` | Project number to add the issue to |
| `--dry-run` | off | Show what would happen without creating anything |

## Step 1 — Collect inputs

If `decision text` was not provided in the invocation, prompt:
```
What is the decision? (be specific — this becomes a GitHub Issue title)
>
```

If `--owner` not set, prompt:
```
Who owns this decision? [Co-CEO / CTO / COO / Team Lead [repo] / Pedro, default: Co-CEO]
>
```

If `--sprint` not set, attempt auto-detection:
```bash
python3 -c "
import yaml, os
path = os.path.expanduser('~/.xgh/ingest.yaml')
try:
    d = yaml.safe_load(open(path))
    print('sp-current')
except Exception:
    print('sp-unknown')
"
```

If `--repo` not set, detect from git:
```bash
git remote get-url origin 2>/dev/null | sed 's|https://github.com/||;s|git@github.com:||;s|\.git$||'
```
If detection fails or output is empty, prompt: `Which GitHub repo? (owner/repo format)`

## Step 2 — Idempotency check

Before creating anything, search MAGI for a recent matching decision:

Use `magi_query` with query: the decision text (or key phrases from it).

If a match is found whose stored text closely resembles the current decision, report:
```
⚠️  Duplicate detected: this decision was already recorded.
   MAGI path: {magi_path}
   Issue: {issue_url}
   Stored: {date}

Re-create anyway? [y/N]
```
If user says N (or input is omitted), stop and print the existing links.

## Step 3 — Dry-run preview (if --dry-run)

Show what would be created without executing:

```
DRY RUN — nothing will be created

  MAGI entry:
    path: "decisions/{slug}.md"
    title: "Decision: {decision text}"
    body: "Decision: {decision text} | Owner: {owner} | Sprint: {sprint} | Repo: {repo}"
    tags: "category:decision,owner:{owner},sprint:{sprint}"

  GitHub Issue (to be created in {repo}):
    Title: Decision: {decision text}
    Body:
      ## Decision
      {decision text}
      ## Why
      Recorded via /xgh-track decision
      ## Owner
      {owner}
      ## Sprint
      {sprint}
      ## MAGI Reference
      (assigned after magi_store)

  Project item: would be added to project #{project} (if detected)
```

Stop after preview — do not execute any real operations.

## Step 4 — Execute pipeline

Execute in order. If any step fails, report the failure and stop.

### 4a — MAGI store

Call `magi_store` MCP tool with:
- `path`: `"decisions/{slug}.md"`
- `title`: `"Decision: {decision text}"`
- `body`: `"Decision: {decision text} | Owner: {owner} | Sprint: {sprint} | Repo: {repo}"`
- `tags`: `"category:decision,owner:{owner},sprint:{sprint}"`

Capture the returned path as `{magi_path}`.

### 4b — GitHub Issue create

```bash
gh issue create \
  --repo "{repo}" \
  --title "Decision: {decision text}" \
  --body "## Decision
{decision text}

## Why
Recorded via /xgh-track decision

## Owner
{owner}

## Sprint
{sprint}

## MAGI Reference
{magi_path}"
```

Attempt with `--label "decision"` first. If that fails (label doesn't exist in repo), retry without the label flag.

Capture the returned issue URL as `{issue_url}`.

### 4c — Project item add

Detect the project to link:
```bash
# Extract org from repo (first component before /)
ORG=$(echo "{repo}" | cut -d/ -f1)
# List projects for org
gh project list --owner "$ORG" --format json 2>/dev/null | python3 -c "
import json, sys
items = json.load(sys.stdin).get('projects', [])
if items:
    print(items[0]['number'])
else:
    print('')
"
```

If a project number is found:
```bash
gh project item-add {project} --owner {org} --url "{issue_url}"
```

If project detection fails or returns empty, skip and note: "⚠️ No project linked — run `gh project item-add` manually."

## Step 5 — Output

```
✅ Decision recorded

  Decision: {decision text}
  Owner:    {owner}
  Sprint:   {sprint}

  MAGI:   {magi_path}
  Issue:  {issue_url}
  Project: #{project} — item added ✓  (or: ⚠️ not linked)

To view: gh issue view {issue_number} --repo {repo}
```

## Common mistakes

### Missing label
If the "decision" label doesn't exist in the target repo, `gh issue create --label "decision"` will fail. Always retry without `--label` as fallback.

### Wrong org for project
`gh project item-add` requires `--owner` to be the org/user who owns the project, not necessarily the repo org.

### MAGI store before issue create
Always call `magi_store` first — the MAGI path is embedded in the issue body for auditability.

### Idempotency scope
Idempotency is checked only via MAGI search. If MAGI is unavailable, skip the check with a warning: "⚠️ MAGI unavailable — skipping duplicate check."
