# Shared Dispatch Template

<!-- This file is the single source of truth for the shared dispatch workflow.
     It is referenced by: codex, gemini, opencode.
     CLI-specific content (binary, flags, models, commands) lives in each skill file.
     When updating shared workflow logic, update only this file. -->

This template defines the shared dispatch workflow for all CLI dispatch skills.
Each skill references this file and provides its own CLI-specific content inline.

## Step 1: Setup Workspace

### Worktree mode

Create an isolated git worktree for the CLI to work in (replace `<CLI>` with the skill's binary name):

```bash
SLUG=$(echo "<prompt-summary>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-30)
TIMESTAMP=$(date +%s)
BRANCH="<CLI>/${SLUG}-${TIMESTAMP}"
WORKTREE=".worktrees/<CLI>-${TIMESTAMP}"
mkdir -p .worktrees
git worktree add "$WORKTREE" -b "$BRANCH"
```

Set `WORK_DIR="$WORKTREE"`.

If `git worktree add` fails (branch exists, dirty state), report the error and suggest the skill's same-dir fallback flag.

### Same-dir mode

Set `WORK_DIR` to the current working directory. No worktree setup needed.

**Warning:** Do not use same-dir mode while Claude Code is also writing files. File conflicts will occur.

---

## Step 3: Collect Results

Read the output file (or agent result) to surface the outcome. For worktree mode, also summarize what the CLI changed:

```bash
git -C "$WORK_DIR" log --oneline "$BRANCH" --not main
git -C "$WORK_DIR" diff --stat main..."$BRANCH"
```

Present a structured summary to the user:

```
## <CLI_LABEL> Dispatch Results

| Field | Value |
|-------|-------|
| Type | exec / review |
| Model | <model if specified> |
| Isolation | worktree ($BRANCH) / same-dir |
| Files changed | N |
| Duration | Xs |

### <CLI_LABEL> Output
<summary or full content of output file>

### Changes (worktree mode)
<git log + diff stat>
```

If the output file is large (>200 lines), summarize the key points rather than including the full content.

---

## Step 4: Integration (worktree mode only)

Ask the user how to integrate the CLI's changes:

| Option | Command |
|--------|---------|
| **Merge** | `git merge $BRANCH` then cleanup |
| **Cherry-pick** | `git cherry-pick <commit-range>` then cleanup |
| **Keep for review** | Leave worktree at `$WORKTREE` for manual inspection |
| **Discard** | `git worktree remove "$WORKTREE" --force && git branch -D "$BRANCH"` |

Cleanup after merge:
```bash
git worktree remove "$WORKTREE"
git branch -d "$BRANCH"
```

Cleanup after cherry-pick (branch is not considered "merged" by Git — use `-D`):
```bash
git worktree remove "$WORKTREE"
git branch -D "$BRANCH"
```

---

## Step 5: Curate (if lossless-claude available)

Store the dispatch outcome for future reference. Replace all placeholders: `<CLI_LABEL>` (display name, e.g. "OpenCode"), `<cli>` (tag slug, e.g. `"opencode"`):

```
lcm_store("<CLI_LABEL> dispatch: <type> | model: <model> | isolation: <mode> | <outcome summary>", ["session", "<cli>"])
```

---

## Shared Anti-Patterns

These apply to all dispatch skills:

- **Vague prompts.** "Fix all the bugs" produces poor results. Specific file references and success criteria are required.
- **No verification step.** Always include a test command in the prompt. The CLI won't self-verify unless told to.
- **No scope constraints.** Without "modify only X", the CLI will touch whatever seems related.
- **Same-dir during parallel work.** Do not use same-dir mode while Claude Code is also editing files. Use worktree mode.
- **Skipping results review.** Always read and verify output before merging.
- **Large monolithic dispatches.** Split into focused subtasks, one CLI invocation each.
