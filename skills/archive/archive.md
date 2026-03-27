---
name: xgh:archive
description: "Use this skill when the user runs /xgh-archive or /xgh-archive --obituary. Archives a file or feature by moving it to .xgh/archived/ with a timestamp prefix. With --obituary, also creates a GitHub issue labeled kind:decommission documenting what it did, why it was removed, what metric it failed to move, and who removed it — then stores the decision in LCM."
---

# xgh:archive — Archive & Obituary Workflow

## Trigger patterns

- `/xgh-archive <file-or-feature>` — archive only (move + timestamp)
- `/xgh-archive --obituary <feature-name>` — archive + GitHub obituary issue + LCM entry

## Guard checks

**1. Argument validation** — At least one positional argument must be provided (the file path or feature name). If no argument is given, print usage and stop:
```
Usage:
  /xgh-archive <file-or-feature>             # archive only
  /xgh-archive --obituary <feature-name>     # archive + obituary issue + LCM
```

**2. Target exists (archive mode)** — If a file path is provided (not a bare feature name), verify it exists on disk. If missing, print `Error: file not found: <path>` and stop.

**3. GitHub CLI available (obituary mode)** — Run `gh auth status` to confirm `gh` is authenticated. If not, print `Error: gh CLI not authenticated — run 'gh auth login' first` and stop.

**4. Repo context (obituary mode)** — Determine the GitHub repo to create the issue against. Use `gh repo view --json nameWithOwner -q .nameWithOwner` in the current directory, or fall back to the repo containing the archived file. If no repo can be resolved, ask the user which repo to use.

---

## Mode A — Archive only

Invoked when `--obituary` flag is NOT present.

### Step 1 — Resolve target

If `<file-or-feature>` is a file path:
- Resolve to absolute path
- Extract the basename for the archive filename

If it is a bare feature name (no `/` or `.` suggesting a path):
- Treat it as a logical feature name only (no file to move)
- Print a warning: `Note: no file path provided — creating a record without a physical move`

### Step 2 — Create archive directory

```bash
mkdir -p .xgh/archived/
```

### Step 3 — Move file (if applicable)

If a file was resolved, move it with a timestamp prefix:
```bash
TIMESTAMP=$(date +%Y%m%d)
mv <resolved-path> .xgh/archived/${TIMESTAMP}-<basename>
```

Print: `Archived: <original-path> → .xgh/archived/${TIMESTAMP}-<basename>`

### Step 4 — Done

Print a summary:
```
✓ Archived <feature-name>
  Destination: .xgh/archived/<timestamped-filename>
  Tip: run /xgh-archive --obituary <feature-name> to create a full GitHub obituary issue.
```

---

## Mode B — Archive + Obituary

Invoked when `--obituary` flag IS present.

### Step 1 — Run Mode A steps 1–3

Execute all archive steps first (move file if applicable).

### Step 2 — Collect obituary metadata

Ask the user the following questions interactively (one at a time). If the session appears non-interactive (headless / automated), accept empty values and mark them as `[not provided]`.

1. **What did it do?**
   Prompt: `What did <feature-name> do? (1–3 sentences)`

2. **Why was it removed?**
   Prompt: `Why was it removed? Focus on data: what metric did it fail to move, or what goal did it block?`

3. **Who removed it?**
   Prompt: `Who removed it? (agent name, GitHub handle, or "automated")`
   Default: detect from `git config user.name` or `git config user.email`. Pre-fill and allow override.

### Step 3 — Compose GitHub issue

Build the issue using this template:

```
title: obituary: <feature-name> — removed YYYY-MM-DD
body:
## What it did
<answer from Step 2.1>

## Why removed
<answer from Step 2.2>

## Who removed it
<answer from Step 2.3>

## Archive location
`.xgh/archived/<timestamped-filename>` (or "no file — logical feature only")

## LCM entry
Stored with tags: `["obituary", "removed:<feature-name>", "sprint:<YYYY-MM-DD>"]`
```

Where `YYYY-MM-DD` is today's date.

### Step 4 — Create GitHub issue

```bash
gh issue create \
  --title "obituary: <feature-name> — removed <YYYY-MM-DD>" \
  --body "<composed body>" \
  --label "kind:decommission"
```

If the label `kind:decommission` does not exist in the repo, create it first:
```bash
gh label create "kind:decommission" --color "#b60205" --description "Tracks removed features and decommissioned components"
```

Capture the issue URL from the output.

### Step 5 — Store in LCM

Call `mcp__lcm__lcm_store` (or `mcp__plugin_lcm_lcm__lcm_store` if the first is unavailable) with:

```json
{
  "name": "obituary: <feature-name>",
  "description": "<What it did> — Removed: <Why removed>. Removed by: <who>.",
  "type": "decision",
  "tags": ["obituary", "removed:<feature-name>", "sprint:<YYYY-MM-DD>"],
  "source": "xgh:archive"
}
```

If LCM is not available, log a warning: `LCM not available — obituary stored in GitHub only (issue: <url>)`.

### Step 6 — Done

Print a full summary:
```
✓ Obituary complete for <feature-name>
  Archived:    .xgh/archived/<timestamped-filename>  (or "logical feature — no file moved")
  GitHub:      <issue-url>
  LCM:         obituary | removed:<feature-name> | sprint:<YYYY-MM-DD>
```

---

## Error handling

| Condition | Behavior |
|-----------|----------|
| File not found | Print error, stop — do not create partial state |
| `gh` not authenticated | Print error with fix command, stop |
| GitHub issue creation fails | Print raw error, skip LCM step, report partial completion |
| LCM unavailable | Log warning, continue — GitHub issue is the primary record |
| Label creation fails (already exists) | Ignore the error, proceed with issue creation |

---

## Examples

```
# Archive a hook file, no issue
/xgh-archive hooks/pre-push-lint.sh

# Archive a skill and create obituary issue
/xgh-archive --obituary xgh:daily-digest

# Archive a logical feature (no file) with full obituary
/xgh-archive --obituary "auto-PR-labeler"
```
