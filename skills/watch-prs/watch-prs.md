---
name: xgh:watch-prs
description: "Use /xgh-watch-prs when you want to watch PRs / babysit PRs until they reach merge — waiting on CI, a reviewer hasn't responded, comments need fixes, or you want merge to happen automatically without manually polling GitHub. GitHub-first: uses gh CLI and GitHub REST/GraphQL APIs. Other provider profiles are present for future support but platform-specific CLI equivalents are not yet implemented."
---

> **Output format:** Start with `## 🐴🤖 xgh watch-prs`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. Keep per-poll output terse.

# /xgh-watch-prs — PR Merge Orchestrator

Watch a batch of PRs through review cycles until all are merged. **GitHub-first:** all implementation steps use `gh` CLI and GitHub REST/GraphQL APIs. Provider profiles for GitLab, Bitbucket, and Azure DevOps are included as a framework for future support, but platform-specific CLI equivalents are not yet implemented. Each poll cycle takes the next correct action: accept suggestion commits, dispatch fix agents, reply to comments, resolve outdated threads, re-request review, or merge.

## Usage

```
/xgh-watch-prs start <PR> [<PR>...] [--repo owner/repo] [--interval 3m] [--merge-method merge|squash|rebase] [--reviewer <login>] [--accept-suggestion-commits] [--require-resolved-threads] [--post-merge-hook '<command>']
/xgh-watch-prs poll-once <PR> [<PR>...]
/xgh-watch-prs status
/xgh-watch-prs stop
```

**Defaults:**
- `--interval 3m`
- `--merge-method merge`
- `--reviewer` — auto-detected from provider profile (e.g., `copilot-pull-request-reviewer[bot]` on GitHub)
- `--accept-suggestion-commits` — off (opt-in to auto-accept inline suggestion commits)
- `--require-resolved-threads` — off (unresolved threads don't block merge by default)

---

## Step 0 — Bootstrap

### Step 0a — Detect repo

If `--repo` is provided, use it. Otherwise auto-detect:
```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
```

If auto-detect fails: `❌ Could not determine repo. Use --repo owner/repo`

### Step 0b — Detect provider

Parse the origin remote URL:
```bash
ORIGIN=$(git remote get-url origin 2>/dev/null)
```

| Pattern in URL | Provider |
|----------------|----------|
| `github.com` | `github` |
| `gitlab.com` or `gitlab.` | `gitlab` |
| `bitbucket.org` | `bitbucket` |
| `dev.azure.com` or `visualstudio.com` | `azure-devops` |
| anything else | `generic` |

### Step 0c — Load provider profile and probe reviewer

See **Provider Profiles** section for embedded profiles.

**GitHub:** Probe Copilot availability:
```bash
COPILOT_CODE_REVIEW_ENABLED="$(
  gh api "repos/$REPO/copilot/policies" 2>/dev/null \
    | jq -r '.code_review_enabled // false' \
    || echo false
)"
```
- If enabled and `--reviewer` not set: default reviewer = `copilot-pull-request-reviewer[bot]`
- If disabled or endpoint 404s: print `⚠️ Copilot code review is not enabled for $REPO. Reviews need manual assignment. Pass --reviewer <login> to specify one.`

**Other providers:** If `--reviewer` not set and profile has no `reviewer_bot`:
`⚠️ No AI reviewer configured for $PROVIDER. Pass --reviewer <login> or reviews will be skipped.`

---

## Commands

---

### `start <PR> [<PR>...]` — Begin watching

**Step 1 — Check for existing session:**

Read `.xgh/watch-prs-state.json`. If it exists and a watcher is alive with matching repo + PRs, print session details and exit. If watcher is dead, resume from stored state.

**Step 2 — Initialize baselines:**

For each PR, gather initial state using the reviewer login from the provider profile:
```bash
# PR state
gh pr view $PR --repo $REPO --json state,mergeable --jq '{state, mergeable}'

# Last reviewer's review
gh api repos/$REPO/pulls/$PR/reviews --paginate \
  --jq '[.[] | select(.user.login == "<REVIEWER>")] | if length == 0 then null else last | {state: .state, submitted_at: .submitted_at} end'

# Comment count from reviewer bot (use reviewer_comment_author from provider profile)
# Field values for Copilot:
#   reviewer: "copilot-pull-request-reviewer[bot]"  — used in reviewer list API calls
#             strip [bot] suffix when using `gh pr edit` (GraphQL)
#   reviewer_comment_author: "Copilot"  — the .user.login on PR review *comments* (capital C)
#             NOT "copilot-pull-request-reviewer" — use this value for select(.user.login == ...)
gh api repos/$REPO/pulls/$PR/comments --paginate \
  --jq '[.[] | select(.user.login == "<REVIEWER_COMMENT_AUTHOR>")] | length'
```

**Step 3 — Write state file:**

Save to `.xgh/watch-prs-state.json`:
```json
{
  "repo": "owner/repo",
  "provider": "github",
  "reviewer": "copilot-pull-request-reviewer[bot]",
  "reviewer_comment_author": "Copilot",
  "merge_method": "merge",
  "accept_suggestion_commits": false,
  "require_resolved_threads": false,
  "post_merge_hook": null,
  "created_at": "ISO8601",
  "cron_job_id": null,
  "cron": "*/3 * * * *",
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

Use `CronCreate` to schedule recurring polls. Convert `--interval` to a standard cron expression (`5m → "*/5 * * * *"`, `10m → "*/10 * * * *"`). To avoid :00/:30 load spikes, prefer an offset minute list (e.g. `1,11,21,31,41,51 * * * *` for a 10m cadence starting at :01) — optional.

The sentinel string `WATCH:<REPO>:<PR_NUMBERS>` in the prompt makes it findable via `CronList` for stop/status.

```
CronCreate({
  cron: "<interval-expression>",
  recurring: true,
  prompt: `WATCH:<REPO>:<PR_NUMBERS>
Dispatch the xgh:pr-poller agent with:
- repo: <REPO>
- provider: <PROVIDER>
- prs: [<PR_NUMBERS>]
- reviewer: <REVIEWER>
- reviewer_comment_author: <REVIEWER_COMMENT_AUTHOR>
- merge_method: <MERGE_METHOD>
- accept_suggestion_commits: <BOOL>
- require_resolved_threads: <BOOL>
If the agent returns status ALL_DONE, read .xgh/watch-prs-state.json, take cron_job_id, and call CronDelete(cron_job_id). Fallback: scan CronList for a job whose prompt contains "WATCH:<REPO>:<PR_NUMBERS>" and delete it.`
})
```

Save the returned job ID to state: `"cron_job_id": "<id>"`.

Report:
```
✅ Watching PRs [<numbers>] in <repo> every <interval>.
   Provider: <provider> | Reviewer: <reviewer>
   Cron job: <id> (auto-stops when all PRs merge).
```

The `poll-once` subcommand still works for manual one-shot checks outside the cron cycle.

**Step 5 — Poll cycle (per PR):**

For each PR where `status != merged`, execute the decision tree:

#### A — Check if already merged

```bash
gh pr view $PR --repo $REPO --json state --jq '.state'
```

If `MERGED`: set `status = merged`, `last_action = merge-succeeded`. Skip remaining steps.

#### B — Gather current review state

```bash
# Last review from reviewer
REVIEW=$(gh api repos/$REPO/pulls/$PR/reviews --paginate \
  --jq '[.[] | select(.user.login == "<REVIEWER>")] | if length == 0 then null else last | {state: .state, submitted_at: .submitted_at} end')

# Comment count from reviewer
COMMENTS=$(gh api repos/$REPO/pulls/$PR/comments --paginate \
  --jq '[.[] | select(.user.login == "<REVIEWER_COMMENT_AUTHOR>")] | length')

# Mergeability and CI
PR_DATA=$(gh pr view $PR --repo $REPO --json mergeable,statusCheckRollup,reviewDecision)
MERGEABLE=$(echo "$PR_DATA" | jq -r '.mergeable')

# Unresolved review threads — GitHub only (skip for other providers)
if [ "$PROVIDER" = "github" ]; then
  UNRESOLVED=$(gh api graphql -f query='
    query($owner:String!,$repo:String!,$pr:Int!) {
      repository(owner:$owner,name:$repo) {
        pullRequest(number:$pr) {
          reviewThreads(first:100) {
            nodes { isResolved isOutdated id }
          }
        }
      }
    }' -F owner="${REPO%%/*}" -F repo="${REPO##*/}" -F pr=$PR \
    --jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false and .isOutdated == false)) | length')
fi
```

Compare against baselines stored in state file.

#### B1 — Null REVIEW guard (no review yet)

If `REVIEW` is null (no review submitted yet):
- Skip checks C and D
- If `MERGEABLE == CONFLICTING`: dispatch conflict-resolution agent
- Otherwise: re-request review per section E (with cooldown)

This is the "pending first review" state.

#### C — New review with new comments

**Condition:** `review.submitted_at > baseline_review_at` AND `comment_count > baseline_comment_count`

**Note:** Thread metadata (like `isOutdated`) comes from the GraphQL `reviewThreads` query in section B, not REST comments. When classifying comments in step 2, match each REST comment to its thread node ID from that earlier query to detect outdated threads.

**Guard:** If `active_agent != null`, skip (agent still working).

**Action:**
1. Fetch new comments since baseline:
   ```bash
   BASELINE_COUNT=$(jq -r ".prs[\"$PR\"].baseline_comment_count" .xgh/watch-prs-state.json)
   gh api repos/$REPO/pulls/$PR/comments --paginate \
     --jq "[.[] | select(.user.login == \"<REVIEWER_COMMENT_AUTHOR>\")] | sort_by(.created_at) | .[$BASELINE_COUNT:] | .[] | {id, path, line, body, diff_hunk, pull_request_review_id}"
   ```

2. For each comment, classify and act:
   - **Outdated thread** (detected via GraphQL `reviewThreads` query where `isOutdated == true`): resolve thread via GraphQL mutation, no code change
   - **Suggestion commit** (body contains ` ```suggestion `) AND `accept_suggestion_commits == true`: dispatch haiku Agent to accept via API
   - **Simple fix** (rename, string, style nit): dispatch haiku Agent to fix and push
   - **Logic/architecture concern**: dispatch sonnet Agent to fix and push
   - **Informational only**: leave reply with reasoning, no code change

3. **Reply format:**
   - After fixing: `"Fixed in <commit_url>"`
   - When not fixing (out-of-scope, pre-existing artifact, etc.): `"Not addressing: <one-line reasoning>"`
   - **Tag human reviewers** in replies (`@username`)
   - **NEVER tag bot reviewers** — no `@copilot`, no `@<anything>[bot]`

4. **Resolve outdated threads** (GitHub): after fixes are pushed, resolve any threads where `isOutdated == true`:
   ```bash
   gh api graphql -f query='
     mutation($threadId:ID!) {
       resolveReviewThread(input:{threadId:$threadId}) {
         thread { isResolved }
       }
     }' -f threadId="<THREAD_NODE_ID>"
   ```

5. Update state: `last_action = dispatched-fix-agent`, `active_agent = { type: "fix", agent_id: "<id>", started_at: ISO8601 }`
6. Update baseline: `baseline_review_at = review.submitted_at`, `baseline_comment_count = comment_count`

**Escalation:** If the haiku agent fails or produces broken code (build fails after push), re-dispatch with **sonnet** model.

#### D — New review with NO new comments

**Condition:** `review.submitted_at > baseline_review_at` AND `comment_count == baseline_comment_count`

Reviewer re-reviewed and found nothing new. Evaluate merge criteria in order:

1. `mergeable == MERGEABLE` — if CONFLICTING: dispatch conflict-resolution agent, wait
2. All `statusCheckRollup` entries: `conclusion SUCCESS` or `SKIPPED` — if any FAILURE/CANCELLED: report, wait
3. No review with `state == CHANGES_REQUESTED` from any author — if any: treat as new feedback (back to C)
4. At least one review from `<reviewer>` with `state == APPROVED`
5. If `require_resolved_threads == true`: `UNRESOLVED == 0` — if any: resolve outdated threads, then wait

If ALL criteria met:
```bash
gh pr merge $PR --repo $REPO --<merge_method>
```

If merge succeeds: `status = merged`, `last_action = merge-succeeded`
If merge fails for non-conflict reason: `last_action = merge-attempted`, log error, retry next cycle

#### E — No new review since baseline

**Condition:** `review.submitted_at == baseline_review_at` (or no review at all)

**Action:** Re-request review, respecting cooldown. Only if `last_review_request_at` is null OR at least one poll interval has elapsed.

**GitHub + Copilot reviewer — reviewer list cycle:**
```bash
gh pr edit $PR --repo $REPO --remove-reviewer copilot-pull-request-reviewer 2>/dev/null
gh pr edit $PR --repo $REPO --add-reviewer copilot-pull-request-reviewer
```

> **NEVER use `@copilot` in comments.** Even `@copilot review` triggers the SWE delegation agent which opens a NEW PR. The reviewer list cycle is the only safe re-request method.

**Non-GitHub or custom reviewer:**
```bash
gh api repos/$REPO/pulls/$PR/requested_reviewers \
  -X DELETE -f "reviewers[]=$REVIEWER" 2>/dev/null
gh api repos/$REPO/pulls/$PR/requested_reviewers \
  -X POST -f "reviewers[]=$REVIEWER"
```

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

Useful for manual one-shot checks or debugging the decision tree.

---

### `status` — Show current session

Load `.xgh/watch-prs-state.json` and display:

```
## 🐴🤖 xgh watch-prs — status

Repo: ipedro/lossless-claude | Provider: github | Reviewer: copilot-pull-request-reviewer[bot]
Merge: squash | Cron: <job-id> every 3m
Active since: 2026-03-22T03:00:00Z

| PR   | Status      | Last Action          | Review    | Comments | Agent |
|------|-------------|----------------------|-----------|----------|-------|
| #101 | ✅ merged   | merge-succeeded      | 03:42:40Z | 20       | —     |
| #59  | 👀 watching | re-requested-review  | 00:08:20Z | 28       | —     |
```

If no state file: `ℹ️ No active watch-prs session.`

---

### `stop` — Terminate session

1. Load state file
2. If no session: print info message, exit
3. If `cron_job_id` is set: call `CronDelete(cron_job_id)`. If not set, scan `CronList` for any job whose prompt contains `WATCH:<REPO>:` and delete matches.
4. Delete state file
5. Print confirmation:
   - If `cron_job_id` was set and deleted: `✅ watch-prs stopped. Cron job <id> deleted.`
   - If scan was used (0 found): `✅ watch-prs stopped. (No active cron job found.)`
   - If scan was used (1+ found): `✅ watch-prs stopped. Deleted <N> cron job(s): <id1> <id2> ...`

---

## Conflict Resolution

When a PR is MERGEABLE=CONFLICTING, dispatch a conflict-resolution agent:

**Agent inputs:**
- Repo, branch name, base branch, PR number
- Instructions: fetch, checkout branch, merge base, resolve conflicts, verify no markers remain:
  ```bash
  git diff --name-only --diff-filter=U
  grep -rn "^<<<<<<<" -- . | grep -v node_modules | grep -v .git
  ```
  commit, push
- **CRITICAL:** Do NOT force push. Do NOT use `@copilot` in any comment. Re-request review via reviewer list cycle after resolution.

**After resolution:** Set `last_action = dispatched-conflict-agent`. Next cycle detects MERGEABLE and re-requests review.

---

## Agent Dispatch Guidelines

| Scenario | Model | Isolation |
|----------|-------|-----------|
| Accept suggestion commits | haiku | direct |
| Fix comments (style, docs, renames) | haiku | worktree |
| Fix comments (logic, architecture) | sonnet | worktree |
| Resolve merge conflicts | haiku | direct |
| Haiku agent failed | sonnet | worktree |

All fix agents run in background. The `active_agent` field prevents double-dispatching.

### `active_agent` lifecycle

**Set:** When dispatching any agent, record ID and timestamp:
```json
"active_agent": { "type": "fix", "agent_id": "<id>", "started_at": "ISO8601" }
```

**Check (at START of each poll cycle, before decision tree):**
1. If `active_agent != null`: use `TaskGet(agent_id)` to query status, OR check `git log --oneline origin/<branch> --since="<started_at>"` for new commits
2. If completed (success or failure): clear `active_agent = null`, proceed with decision tree
3. If still running: skip PR this cycle

**Clear:** After confirming completion. If `TaskGet` unavailable and no commits appear within 2× poll interval, treat as failed and clear.

---

## Provider Profiles

Embedded profiles — the skill references these directly, no external lookup needed.

### GitHub

```yaml
provider: github
reviewer_bot: copilot-pull-request-reviewer[bot]
reviewer_comment_author: Copilot
review_request_strategy: reviewer-list  # gh pr edit --remove-reviewer / --add-reviewer (only safe method)
threads_api: graphql   # resolveReviewThread mutation available
suggestion_commits: true
```

#### GitHub: Two Copilot Systems — Critical Distinction

| System | Trigger | Effect |
|--------|---------|--------|
| **Code Review** | Add `copilot-pull-request-reviewer[bot]` to reviewer list | Leaves inline review comments |
| **SWE Delegation Agent** | `@copilot <anything>` in a comment — including `@copilot review` | Opens a **NEW PR** with code changes |

**NEVER use `@copilot` in comments.** Even `@copilot review` triggers the SWE delegation agent. The reviewer list cycle is the only safe way to request a review.

Copilot does NOT read replies on its review comments. It is a one-way reviewer. Re-requesting via reviewer list is the only way to get another pass.

#### GitHub: Triggering Copilot Review

One safe method — reviewer list cycle only:

| Method | Command | Notes |
|--------|---------|-------|
| Reviewer list cycle | `gh pr edit --remove-reviewer copilot-pull-request-reviewer && --add-reviewer copilot-pull-request-reviewer` | Uses GraphQL, no `[bot]` suffix needed; only safe method |

`review_on_push: true` (repo setting) makes Copilot auto-review on every push — when enabled, manual re-requests after pushing fixes are redundant. Check with `status` before re-requesting.

### GitLab

```yaml
provider: gitlab
reviewer_bot: null
reviewer_comment_author: null
review_request_strategy: reviewer-list  # GitLab MR reviewer assignment
threads_api: rest   # PUT /discussions/:id/notes/:id with resolved:true
suggestion_commits: true
```

Pass `--reviewer <login>` for human or bot reviewer on GitLab.

### Bitbucket

```yaml
provider: bitbucket
reviewer_bot: null
reviewer_comment_author: null
review_request_strategy: reviewer-list
threads_api: none
suggestion_commits: false
```

### Azure DevOps

```yaml
provider: azure-devops
reviewer_bot: null
reviewer_comment_author: null
review_request_strategy: reviewer-list
threads_api: rest
suggestion_commits: false
```

### Generic

```yaml
provider: generic
reviewer_bot: null
reviewer_comment_author: null
review_request_strategy: reviewer-list
threads_api: none
suggestion_commits: false
```

---

## Integration with xgh:copilot-pr-review

This skill builds on `xgh:copilot-pr-review` for GitHub-specific API calls. Key mappings:

| watch-prs action | copilot-pr-review equivalent |
|--------------------|------------------------------|
| Initialize baseline | `status <PR>` |
| Re-request review | `re-review <PR>` |
| Fetch comments | `comments <PR>` |
| Reply to comment | `reply <PR> <id> "<msg>"` |

---

## Known Pitfalls

| Pitfall | How watch-prs handles it |
|---------|--------------------------|
| `@copilot` in any comment triggers delegation (including `@copilot review`) | Agent prompts include "NEVER use @copilot in comments — reviewer list cycle only" |
| `[bot]` suffix required in REST API | Encodes suffix in REST calls; uses `gh pr edit` (GraphQL, no suffix) for reviewer list |
| Copilot ignores conflicting PRs | Detects CONFLICTING, resolves before re-requesting |
| COMMENTED reviews can't be dismissed | Never attempts dismiss — uses re-request cycle |
| Review latency varies | Cooldown prevents re-request spam |
| Outdated threads (with --require-resolved-threads) | Detects outdated threads, resolves via GraphQL before merge |
| Reviews on unrelated files | Agent prompts: "reply out-of-scope for pre-existing artifacts" |
| API pagination hides new reviews | All review/comment endpoints use `--paginate` |

---

## State File

**Path:** `.xgh/watch-prs-state.json`

Runtime state only — add to `.gitignore`.

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
| Provider detection fails | `⚠️ Could not detect provider from remote URL. Defaulting to generic.` |
| Copilot not enabled (GitHub) | `⚠️ Copilot code review not enabled for $REPO. Pass --reviewer <login>` |
| State file corrupt | `❌ Invalid state file. Run stop then start again.` |
| Agent dispatch fails | `⚠️ Agent dispatch failed for PR #$PR. Will retry next cycle.` |
| Merge fails (non-conflict) | `⚠️ Merge failed for PR #$PR: $REASON. Will retry.` |
| All PRs merged | `✅ All PRs merged! Session complete.` |
