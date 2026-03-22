---
name: xgh:babysit-prs
description: "This skill should be used when the user runs /xgh-babysit-prs or says 'babysit PRs', 'watch these PRs', 'monitor PR reviews', or needs to shepherd multiple PRs through Copilot review to merge. Watches a batch of GitHub PRs through Copilot review cycles — polls review status, dispatches fix agents for new comments, merges when clean, re-requests when stale, resolves merge conflicts, and terminates when all PRs are merged."
---

> **Output format:** Start with `## 🐴🤖 xgh babysit-prs`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. Keep per-poll output terse.

# /xgh-babysit-prs — PR Review Orchestrator

Watch a batch of PRs through GitHub Copilot review cycles until all are merged. Each poll cycle checks every tracked PR and takes the next correct action: dispatch a fix agent, merge, re-request review, or resolve conflicts.

## Usage

```
/xgh-babysit-prs start <PR> [<PR>...] [--repo owner/repo] [--interval 5m] [--merge-method squash] [--post-merge-hook '<command>']
/xgh-babysit-prs poll-once <PR> [<PR>...]
/xgh-babysit-prs status
/xgh-babysit-prs stop
```

## Step 0 — Detect repo

If `--repo` is provided, use it. Otherwise auto-detect:
```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
```

If auto-detect fails: `❌ Could not determine repo. Use --repo owner/repo`

## Commands

---

### `start <PR> [<PR>...]` — Begin watching

**Step 1 — Check for existing session:**

Read `.xgh/babysit-prs-state.json`. If it exists and a watcher is alive with matching repo + PRs, print session details and exit. If watcher is dead, resume from stored state.

**Step 2 — Initialize baselines:**

For each PR, gather initial state:
```bash
# PR state
gh pr view $PR --repo $REPO --json state,mergeable --jq '{state, mergeable}'

# Last Copilot review
gh api repos/$REPO/pulls/$PR/reviews \
  --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | if length == 0 then null else last | {state: .state, submitted_at: .submitted_at} end'

# Comment count
gh api repos/$REPO/pulls/$PR/comments \
  --jq '[.[] | select(.user.login == "Copilot")] | length'
```

**Step 3 — Write state file:**

Save to `.xgh/babysit-prs-state.json`:
```json
{
  "repo": "owner/repo",
  "merge_method": "squash",
  "post_merge_hook": null,
  "created_at": "ISO8601",
  "prs": {
    "101": {
      "status": "watching",
      "baseline_review_at": "ISO8601 or null",
      "baseline_comment_count": 12,
      "last_action": "initialized",
      "last_action_at": "ISO8601",
      "last_review_request_at": null,
      "active_agent": null
    }
  }
}
```

**Step 4 — Start poll loop:**

Do NOT call CronCreate directly. Instead, print the `/loop` command for the user to run:

```
✅ Session initialized. Start polling with:

   /loop <interval> /xgh-babysit-prs poll-once <PR1> [<PR2>...]

Example:
   /loop 5m /xgh-babysit-prs poll-once 28 29

The loop skill handles the scheduler. Cancel anytime with CronDelete using the job ID it returns.
```

The `poll-once` subcommand is the single-cycle action that `/loop` invokes each tick. When all PRs are merged, `poll-once` will print a completion summary and exit cleanly — the loop will continue firing but subsequent runs will be instant no-ops.

**Step 5 — Poll cycle (per PR):**

For each PR where `status != merged`, execute the decision tree:

#### A — Check if already merged

```bash
gh pr view $PR --repo $REPO --json state --jq '.state'
```

If `MERGED`: set `status = merged`, `last_action = merge-succeeded`. Skip remaining steps.

#### B — Gather current Copilot state

```bash
# Last review
REVIEW=$(gh api repos/$REPO/pulls/$PR/reviews \
  --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | if length == 0 then null else last | {state: .state, submitted_at: .submitted_at} end')

# Comment count
COMMENTS=$(gh api repos/$REPO/pulls/$PR/comments \
  --jq '[.[] | select(.user.login == "Copilot")] | length')

# Mergeability
MERGEABLE=$(gh pr view $PR --repo $REPO --json mergeable --jq '.mergeable')
```

Compare against baselines stored in state file.

#### B1 — Null REVIEW guard (no Copilot review yet)

If `REVIEW` is null (Copilot has not yet submitted any review for this PR):
- Skip checks C and D (new-comments and stale-review checks — they require a prior review)
- Proceed directly to the merge-conflict check: if `MERGEABLE == CONFLICTING`, dispatch conflict-resolution agent
- Otherwise: re-request Copilot review per section E (with cooldown)

This is the "pending first review" state.

#### C — New review with new comments

**Condition:** `review.submitted_at > baseline_review_at` AND `comment_count > baseline_comment_count`

**Guard:** If `active_agent != null`, skip (agent still working).

**Action:**
1. Fetch new comments (comments added since baseline):
   ```bash
   BASELINE_COUNT=$(jq -r ".prs[\"$PR\"].baseline_comment_count" .xgh/babysit-prs-state.json)
   gh api repos/$REPO/pulls/$PR/comments \
     --jq "[.[] | select(.user.login == \"Copilot\")] | sort_by(.created_at) | .[$BASELINE_COUNT:] | .[] | {id, path, line, body: .body[0:250]}"
   ```
   `$BASELINE_COUNT` is the comment count stored at last baseline update; slicing from that index returns only the newly added comments.
2. Dispatch a **haiku** Agent (worktree isolation) to fix the comments. Include:
   - Branch name, base branch, repo
   - The new Copilot comments (id, path, line, body)
   - Instructions to fix code issues, reply to out-of-scope comments, push, and re-request review
   - **CRITICAL:** Never tag `@copilot` — it opens new PRs
3. Update state: `last_action = dispatched-fix-agent`, `active_agent = { type: "fix", agent_id: "<id>", started_at: ISO8601 }`
4. Update baseline: `baseline_review_at = review.submitted_at`, `baseline_comment_count = comment_count`

**Escalation:** If the haiku agent fails or produces broken code (build fails after push), re-dispatch with **sonnet** model.

#### D — New review with NO new comments

**Condition:** `review.submitted_at > baseline_review_at` AND `comment_count == baseline_comment_count`

This means Copilot re-reviewed and found nothing new. **Merge.**

**Action:**
1. Check mergeability first:
   ```bash
   gh pr view $PR --repo $REPO --json mergeable --jq '.mergeable'
   ```
2. If `CONFLICTING`: dispatch conflict-resolution agent (see section below), set `last_action = dispatched-conflict-agent`
3. If `MERGEABLE`:
   ```bash
   gh pr merge $PR --repo $REPO --squash  # or --merge per config
   ```
4. If merge succeeds: `status = merged`, `last_action = merge-succeeded`
5. If merge fails for non-conflict reason: `last_action = merge-attempted`, log error, retry next cycle

#### E — No new review since baseline

**Condition:** `review.submitted_at == baseline_review_at` (or no review at all)

**Action:** Re-request Copilot review, respecting cooldown.

**Cooldown:** Only re-request if `last_review_request_at` is null OR at least one full poll interval has elapsed since the last request.

```bash
gh pr edit $PR --repo $REPO --remove-reviewer copilot-pull-request-reviewer 2>/dev/null
gh pr edit $PR --repo $REPO --add-reviewer copilot-pull-request-reviewer
```

> **Note on `[bot]` suffix:** The jq filters and REST API responses use the full login `copilot-pull-request-reviewer[bot]`. The `gh pr edit` command uses the GraphQL mutation `requestReviews`, which resolves reviewer slugs without the `[bot]` suffix — so `copilot-pull-request-reviewer` (no suffix) is correct here. This is documented behavior, not an inconsistency.

Update: `last_action = re-requested-review`, `last_review_request_at = now`

#### Post-cycle — Check completion

If ALL PRs have `status = merged`:
1. Run `--post-merge-hook` if configured
2. Delete state file
3. Print completion summary
4. Terminate

---

### `poll-once <PR> [<PR>...]` — Single poll cycle

Execute exactly one poll cycle (Step 5 above) without starting a background loop. Create or update state file. Print what changed. Exit.

Useful for cron-driven orchestration or manual one-shot checks.

---

### `status` — Show current session

Load `.xgh/babysit-prs-state.json` and display:

```
## 🐴🤖 xgh babysit-prs — status

Repo: ipedro/lossless-claude
Merge: squash | Loop: /loop 5m /xgh-babysit-prs poll-once 101 59
Active since: 2026-03-22T03:00:00Z

| PR   | Status   | Last Action         | Review    | Comments | Agent |
|------|----------|---------------------|-----------|----------|-------|
| #101 | ✅ merged | merge-succeeded     | 03:42:40Z | 20       | —     |
| #59  | 👀 watching | re-requested-review | 00:08:20Z | 28       | —     |
```

If no state file: `ℹ️ No active babysit-prs session.`

---

### `stop` — Terminate session

1. Load state file
2. If no session: print info message, exit
3. Delete state file
4. Print confirmation:
   ```
   ✅ babysit-prs session cleared.
   ⚠️  Remember to cancel your /loop job if still running (CronDelete <job-id>).
   ```

The state file is the only persistent resource managed by this skill. The `/loop` job is managed externally — the user is responsible for cancelling it via `CronDelete` using the ID that `/loop` printed when they started it.

---

## Conflict Resolution

When a PR is MERGEABLE=CONFLICTING, dispatch a conflict-resolution agent:

**Agent inputs:**
- Repo, branch name, base branch
- PR number
- Instructions: fetch, checkout branch, merge base, resolve conflicts, verify no conflict markers across all tracked files:
  ```bash
  git diff --name-only --diff-filter=U
  # or equivalently:
  grep -rn "^<<<<<<<" -- . | grep -v node_modules | grep -v .git
  ```
  commit, push
- **CRITICAL:** Do NOT force push. Do NOT tag `@copilot`.

**After resolution:** Set `last_action = dispatched-conflict-agent`. Next cycle will detect the PR is now mergeable and re-request Copilot review.

---

## Agent Dispatch Guidelines

| Scenario | Model | Isolation |
|----------|-------|-----------|
| Fix Copilot comments (style, docs, renames) | haiku | worktree |
| Fix Copilot comments (logic, architecture) | sonnet | worktree |
| Resolve merge conflicts | haiku | direct (same repo) |
| Haiku agent failed | sonnet | worktree |

All agents run in background. The `active_agent` field in state prevents dispatching a second agent for the same PR.

### `active_agent` lifecycle

**Set:** When dispatching any agent (fix or conflict), record the agent ID and timestamp:
```json
"active_agent": { "type": "fix", "agent_id": "<id>", "started_at": "ISO8601" }
```

**Check (at START of each poll cycle, before decision tree):**
1. If `active_agent != null`, check whether the agent has completed:
   - Use `TaskGet(agent_id)` to query agent status, OR
   - Run `git log --oneline origin/<branch> --since="<started_at>"` to detect new commits pushed after dispatch
2. If the agent has **completed** (success or failure): clear `active_agent = null` and proceed with the normal decision tree for this PR
3. If the agent is **still running**: skip this PR in the current cycle (do not re-dispatch)

**Clear:** Set `active_agent = null` after confirming completion (step 2 above). Never leave `active_agent` set indefinitely — if `TaskGet` is unavailable and no commits appeared within 2× poll interval, treat as failed and clear.

---

## Integration with xgh:copilot-pr-review

This skill builds on `xgh:copilot-pr-review` for the underlying API calls (requires `xgh:copilot-pr-review` (PR #28 — merge that first)). Key mappings:

| babysit-prs action | copilot-pr-review equivalent |
|--------------------|------------------------------|
| Initialize baseline | `status <PR>` |
| Re-request review | `re-review <PR>` |
| Fetch comments | `comments <PR>` |
| Reply to comment | `reply <PR> <id> "<msg>"` |

---

## Known Pitfalls (inherited from copilot-pr-review)

| Pitfall | How babysit-prs handles it |
|---------|--------------------------|
| `@copilot` = delegation | All agent prompts include "NEVER tag @copilot" |
| `[bot]` suffix required | Uses `gh pr edit` which works without suffix |
| Copilot ignores conflicting PRs | Detects CONFLICTING state, resolves before re-requesting |
| COMMENTED can't be dismissed | Never attempts dismiss — uses DELETE+POST re-request cycle |
| Review latency varies | Cooldown prevents re-request spam |
| Reviews on unrelated files | Agent prompts include "reply out-of-scope for pre-existing artifacts" |

---

## State File

**Path:** `.xgh/babysit-prs-state.json`

This is runtime state, not source. Add to `.gitignore`.

**Persistence rules:**
- `start` creates the file
- Every poll cycle rewrites atomically
- `status` reads only
- `stop` deletes it
- `poll-once` creates/updates but leaves no background process

---

## Error Handling

| Error | Message |
|-------|---------|
| PR not found | `❌ PR #$PR not found in $REPO` |
| Repo auto-detect fails | `❌ Could not determine repo. Use --repo owner/repo` |
| State file corrupt | `❌ Invalid state file. Run stop then start again.` |
| Agent dispatch fails | `⚠️ Agent dispatch failed for PR #$PR. Will retry next cycle.` |
| Merge fails (non-conflict) | `⚠️ Merge failed for PR #$PR: $REASON. Will retry.` |
| All PRs merged | `✅ All PRs merged! Session complete.` |
