---
name: xgh:ship-prs
description: "Use /xgh-ship-prs when you want to ship PRs / drive PRs to merge automatically — fixes Copilot review comments, dispatches fix agents, resolves conflicts, auto-merges when approved. Use /xgh-watch-prs for passive monitoring without side effects."
---

> **Output format:** Start with `## 🐴🤖 xgh ship-prs`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. Keep per-poll output terse.

# /xgh-ship-prs — PR Merge Orchestrator

Actively drive a batch of PRs through review cycles until all are merged. **GitHub-first:** all implementation steps use `gh` CLI and GitHub REST/GraphQL APIs. Provider profiles for GitLab, Bitbucket, and Azure DevOps are included as a framework for future support, but platform-specific CLI equivalents are not yet implemented. Each poll cycle takes the next correct action: accept suggestion commits, dispatch fix agents, reply to comments, resolve outdated threads, re-request review, or merge.

## Usage

```
/xgh-ship-prs start <PR> [<PR>...] [--repo owner/repo] [--interval 1m] [--merge-method merge|squash|rebase] [--reviewer <login>] [--accept-suggestion-commits] [--require-resolved-threads] [--max-fix-cycles 3] [--post-merge-hook '<command>']
/xgh-ship-prs poll-once <PR> [<PR>...]
/xgh-ship-prs status
/xgh-ship-prs stop
/xgh-ship-prs pause
/xgh-ship-prs resume
/xgh-ship-prs hold <PR>
/xgh-ship-prs unhold <PR>
/xgh-ship-prs dry-run [<PR>]
/xgh-ship-prs log [<PR>]
```

**Defaults** (read from `config/project.yaml` → `preferences.pr`, overridden by CLI flags):
- `--interval 1m`
- `--merge-method` — from `preferences.pr.merge_method` (falls back to `squash` if unset)
- `--reviewer` — loaded from project.yaml or auto-detected from provider profile
- `--accept-suggestion-commits` — off (opt-in to auto-accept inline suggestion commits)
- `--require-resolved-threads` — off (unresolved threads don't block merge by default)
- `--max-fix-cycles 3`

---

## Step 0 — Bootstrap

### Step 0a — Load preferences from project.yaml

Source `lib/config-reader.sh` for `load_pr_pref`. See `skills/_shared/references/project-preferences.md` for the full cascade.

```bash
REPO=$(load_pr_pref repo "$CLI_REPO" "")
PROVIDER=$(load_pr_pref provider "" "")
REVIEWER=$(load_pr_pref reviewer "$CLI_REVIEWER" "")
REVIEWER_COMMENT_AUTHOR=$(load_pr_pref reviewer_comment_author "" "")
MERGE_METHOD=$(load_pr_pref merge_method "$CLI_MERGE_METHOD" "$BASE_BRANCH")
MERGE_METHOD="${MERGE_METHOD:-squash}"  # fallback — merge_method is not probed
```

---

## Commands

---

### `start <PR> [<PR>...]` — Begin shipping

**Step 0d — Branch protection pre-flight:**

Before creating the cron, check branch protection:
```bash
# Check branch protection required approvals
base_ref_name="$(gh pr view "$PR" --repo "$REPO" --json baseRefName -q .baseRefName)"
base_ref_name_uri="$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "$base_ref_name")"
gh api "repos/$REPO/branches/$base_ref_name_uri/protection" \
  --jq '.required_pull_request_reviews.required_approving_review_count // 0' 2>/dev/null
```
If required approvals > 1 and `--reviewer` is a single bot: print warning:
`⚠️ Branch requires <N> approving reviews but only 1 reviewer configured. Auto-merge may loop. Pass additional --reviewer logins or merge manually.`

**Step 1 — Check for existing session:**

Read `.xgh/ship-prs-state.json`. If it exists and a watcher is alive with matching repo + PRs, print session details and exit. If watcher is dead, resume from stored state.

**Step 2 — Initialize baselines:**

For each PR, gather initial state using the reviewer login from the provider profile:
```bash
# PR state
gh pr view $PR --repo $REPO --json state,mergeable --jq '{state, mergeable}'

# Last reviewer's review — use --include to capture ETag header for future conditional polling
REVIEWS_RESPONSE=$(gh api repos/$REPO/pulls/$PR/reviews --paginate --include 2>&1)
REVIEW_ETAG=$(echo "$REVIEWS_RESPONSE" | grep -i '^etag:' | tail -1 | sed 's/^[Ee][Tt][Aa][Gg]: *//;s/\r//')
REVIEW=$(echo "$REVIEWS_RESPONSE" | sed '/^HTTP\//,/^\s*$/{/^{/,$!d}' | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = [r for r in data if r.get('user', {}).get('login') == '<REVIEWER>']
if not items: print('null')
else: last = items[-1]; print(json.dumps({'state': last['state'], 'submitted_at': last['submitted_at']}))")

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

Save to `.xgh/ship-prs-state.json`:
```json
{
  "session_id": "uuid",
  "repo": "owner/repo",
  "provider": "github",
  "reviewer": "copilot-pull-request-reviewer[bot]",
  "reviewer_comment_author": "Copilot",
  "merge_method": "merge",
  "accept_suggestion_commits": false,
  "require_resolved_threads": false,
  "max_fix_cycles": 3,
  "post_merge_hook": null,
  "paused": false,
  "cron_job_id": null,
  "cron": "*/1 * * * *",
  "created_at": "ISO8601",
  "action_log": [],
  "prs": {
    "101": {
      "status": "watching",
      "held": false,
      "fix_cycle_count": 0,
      "merging": false,
      "baseline_review_at": "ISO8601 or null",
      "baseline_comment_count": 12,
      "review_etag": "W/\"<hash>\" or null",
      "last_action": "initialized",
      "last_action_at": "ISO8601",
      "last_review_request_at": null,
      "active_agent": null,
      "copilot_negotiation": {
        "round": 0,
        "capped": false,
        "rounds_detail": [],
        "pr_body_watermark": ""
      }
    }
  }
}
```

**Step 4 — Start poll loop:**

Use `CronCreate` to schedule recurring polls. Convert `--interval` to a standard cron expression (`1m → "* * * * *"`, `5m → "*/5 * * * *"`, `10m → "*/10 * * * *"`). To avoid :00/:30 load spikes, prefer an offset minute list (e.g. `1,11,21,31,41,51 * * * *` for a 10m cadence starting at :01) — optional.

**Note on 1m default:** The default interval is 1m because ETag conditional requests (304 Not Modified) do NOT count toward GitHub's rate limit. Only 200 responses (new review data) consume quota. Polling at 1m is safe when the API is used correctly.

The sentinel string `SHIP:<REPO>:<PR_NUMBERS>` in the prompt makes it findable via `CronList` for stop/status.

```
CronCreate({
  cron: "<interval-expression>",
  recurring: true,
  prompt: `SHIP:<REPO>:<PR_NUMBERS>
Dispatch the xgh:pr-poller agent with:
- mode: ship
- repo: <REPO>
- provider: <PROVIDER>
- prs: [<PR_NUMBERS>]
- reviewer: <REVIEWER>
- reviewer_comment_author: <REVIEWER_COMMENT_AUTHOR>
- merge_method: <MERGE_METHOD>
- accept_suggestion_commits: <BOOL>
- require_resolved_threads: <BOOL>
Before dispatching: read .xgh/ship-prs-state.json — if paused == true, skip all actions this tick.
For each PR: check prs["<PR>"].held — if true, skip that PR.
If the agent returns status ALL_DONE, read .xgh/ship-prs-state.json, take cron_job_id, and call CronDelete(cron_job_id). Fallback: scan CronList for a job whose prompt contains "SHIP:<REPO>:<PR_NUMBERS>" and delete it.`
})
```

Save the returned job ID to state: `"cron_job_id": "<id>"`.

Report:
```
✅ Shipping PRs [<numbers>] in <repo> every <interval>.
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
# Read stored ETag for this PR from state file
STORED_ETAG=$(jq -r ".prs[\"$PR\"].review_etag // empty" .xgh/ship-prs-state.json)
REVIEW_UNCHANGED=false  # reset at top of each PR loop iteration

# Last review from reviewer — use ETag conditional request if available
if [ -n "$STORED_ETAG" ]; then
  # Conditional request: single request (no --paginate) so ETag contract is well-defined.
  # 304 = no change (free, not rate-limited), 200 = new data
  REVIEWS_RESPONSE=$(gh api repos/$REPO/pulls/$PR/reviews --include \
    -H "If-None-Match: $STORED_ETAG" 2>&1)
  REVIEWS_EXIT=$?
  HTTP_STATUS=$(echo "$REVIEWS_RESPONSE" | grep -m1 '^HTTP' | awk '{print $2}')

  if [ "$REVIEWS_EXIT" -eq 0 ] && [ "$HTTP_STATUS" = "304" ]; then
    # No new review data — skip review processing this cycle
    echo "ℹ️ PR #$PR: no new review (ETag cached, 304 Not Modified)"
    # Jump to mergeability check only — skip C/D review-based branches
    REVIEW_UNCHANGED=true
  elif [ "$REVIEWS_EXIT" -eq 0 ]; then
    # 200 OK — extract new ETag and process review data
    NEW_ETAG=$(echo "$REVIEWS_RESPONSE" | grep -i '^etag:' | tail -1 | sed 's/^[Ee][Tt][Aa][Gg]: *//;s/\r//')
    [ -n "$NEW_ETAG" ] && jq --arg pr "$PR" --arg etag "$NEW_ETAG" \
      '.prs[$pr].review_etag = $etag' .xgh/ship-prs-state.json > "/tmp/ship-prs-state-${PR}.tmp" && \
      mv "/tmp/ship-prs-state-${PR}.tmp" .xgh/ship-prs-state.json
  else
    # Non-zero exit (network error, auth failure, etc.) — log and proceed without ETag
    echo "⚠️ PR #$PR: reviews API error (exit $REVIEWS_EXIT) — proceeding without ETag cache"
    REVIEWS_RESPONSE=$(gh api repos/$REPO/pulls/$PR/reviews --paginate --include 2>&1) || true
  fi
else
  # No stored ETag — first full fetch (with paginate); capture ETag from final page for future polls
  REVIEWS_RESPONSE=$(gh api repos/$REPO/pulls/$PR/reviews --paginate --include 2>&1)
  NEW_ETAG=$(echo "$REVIEWS_RESPONSE" | grep -i '^etag:' | tail -1 | sed 's/^[Ee][Tt][Aa][Gg]: *//;s/\r//')
  [ -n "$NEW_ETAG" ] && jq --arg pr "$PR" --arg etag "$NEW_ETAG" \
    '.prs[$pr].review_etag = $etag' .xgh/ship-prs-state.json > "/tmp/ship-prs-state-${PR}.tmp" && \
    mv "/tmp/ship-prs-state-${PR}.tmp" .xgh/ship-prs-state.json
fi

# Parse REVIEW from response body (skip if 304)
if [ "${REVIEW_UNCHANGED}" = "false" ]; then
  REVIEW=$(echo "$REVIEWS_RESPONSE" | python3 -c "
import sys, json, re
text = sys.stdin.read()
# Strip HTTP headers — body starts after first blank line following the status line
body_match = re.search(r'\r?\n\r?\n([\[{].*)', text, re.DOTALL)
body = body_match.group(1) if body_match else text
try:
    data = json.loads(body)
    items = [r for r in data if r.get('user', {}).get('login') == '<REVIEWER>']
    if not items: print('null')
    else: last = items[-1]; print(json.dumps({'state': last['state'], 'submitted_at': last['submitted_at']}))
except: print('null')")
fi

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

**ETag shortcut:** If `REVIEW_UNCHANGED == true` (304 Not Modified), skip sections C and D entirely — no review data changed. Proceed to mergeability check only (Step D merge criteria, using last known review state from state file). This is the primary path during quiet periods between Copilot review cycles.

If `REVIEW` is null (no review submitted yet):
- Skip checks C and D
- If `MERGEABLE == CONFLICTING`: dispatch conflict-resolution agent
- Otherwise: re-request review per section E (with cooldown)

This is the "pending first review" state.

#### C — New review with new comments

**Condition:** `review.submitted_at > baseline_review_at` AND `comment_count > baseline_comment_count`

**Note:** Thread metadata (like `isOutdated`) comes from the GraphQL `reviewThreads` query in section B, not REST comments. When classifying comments in step 2, match each REST comment to its thread node ID from that earlier query to detect outdated threads.

**Guard:** If `active_agent != null`, skip (agent still working).

**Fix cycle cap:** If `fix_cycle_count >= max_fix_cycles` for this PR:
- Do NOT dispatch another fix agent
- Print: `⚠️ PR #<N>: fix cycle cap reached (<max> cycles). Manual intervention needed.`
- Set `last_action = fix-cap-reached`
- Skip to next PR

**Action:**
1. Fetch new comments since baseline:
   ```bash
   BASELINE_COUNT=$(jq -r ".prs[\"$PR\"].baseline_comment_count" .xgh/ship-prs-state.json)
   gh api repos/$REPO/pulls/$PR/comments --paginate \
     --jq "[.[] | select(.user.login == \"<REVIEWER_COMMENT_AUTHOR>\")] | sort_by(.created_at) | .[$BASELINE_COUNT:] | .[] | {id, path, line, body, diff_hunk, pull_request_review_id}"
   ```

2. **Route by reviewer type:**

   **When `reviewer_comment_author == "Copilot"`** → run the **Copilot Negotiation Sub-Loop** (§C1–C6 below) instead of the plain fix-cycle for all suggestion-block comments. Plain comments and outdated threads are still handled via the existing paths.

   **When `reviewer_comment_author != "Copilot"`** (human reviewer) → use the original fix-cycle only:
   - **Outdated thread** (detected via GraphQL `reviewThreads` query where `isOutdated == true`): resolve thread via GraphQL mutation, no code change
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
6. Increment `fix_cycle_count` by 1. Never reset mid-session.
7. Update baseline: `baseline_review_at = review.submitted_at`, `baseline_comment_count = comment_count`
8. Append to `action_log`: `{ "at": "ISO8601", "pr": 42, "action": "dispatched-fix-agent", "detail": "3 new comments" }`

**Escalation:** If the haiku agent fails or produces broken code (build fails after push), re-dispatch with **sonnet** model.

---

#### C1 — Copilot Negotiation: Classify Comments

**Activates only when `reviewer_comment_author == "Copilot"`.**

For each new Copilot comment from step C.1, classify into one of three types:

| Type | Detection | Next step |
|------|-----------|-----------|
| **Suggestion block** | Body contains ` ```suggestion` fenced block | → C2 (evaluate) |
| **Plain comment** | All other comments | → Existing fix-cycle (dispatch haiku/sonnet agent) |
| **Outdated thread** | `isOutdated == true` from GraphQL `reviewThreads` | → Resolve via GraphQL mutation (unchanged) |

Both suggestion-block and plain-comment paths can coexist in the same cycle. Process all comment types before writing state.

#### C2 — Copilot Negotiation: Evaluate Suggestion

**Cap check first:** Before evaluating, check `copilot_negotiation.round >= max_fix_cycles` (default 3). If capped, jump to C6.

For each suggestion-block comment:

1. Extract the suggested diff from the ` ```suggestion` fenced block in the comment body
2. Read the current file at `comment.path` lines around `comment.line` (use `comment.diff_hunk` for context)
3. **Sonnet evaluation** — reason through each criterion:

   **Accept conditions (any one sufficient):**
   - Fixes a real bug or corrects incorrect logic
   - Clear readability improvement with no semantic change
   - Removes unnecessary complexity

   **Reject conditions (any one sufficient):**
   - Removes intentional logic
   - Introduces a regression
   - Pure style preference with no correctness benefit
   - Conflicts with project conventions (check `config/project.yaml` `preferences.code_style`)

4. Check for staleness: compare `comment.diff_hunk` against current file content at `comment.path:comment.line`. If the surrounding lines no longer match the hunk, the suggestion is **stale** — skip C3/C4 and post:
   ```
   gh api repos/$REPO/pulls/comments/$COMMENT_ID/replies \
     -X POST -f "body=This suggestion is stale — the surrounding code has changed. Please re-review the updated file."
   ```

5. Route to C3 (accept) or C4 (reject).

#### C3 — Copilot Negotiation: Accept Path

```bash
# 1. Apply the suggestion as a patch to the file
#    Parse the ```suggestion block from comment.body
#    Apply it to comment.path starting at comment.line
#    Verify the file is valid (no syntax errors if detectable)

# 2. Optionally run tests if test_command is set in config/project.yaml
#    If tests fail, treat as implicit reject:
#    - Revert the file change
#    - Post reply: "Suggestion would break tests (<test output excerpt>). Rejecting."
#    - Route to C4 logic (no code change)

# 3. Commit
git add <comment.path>
git commit -m "fix: accept Copilot suggestion on <comment.path>:<comment.line> (PR #$PR round $ROUND)"

# 4. Push
git push origin <branch>

# 5. Reply to the comment — NO @copilot mention
gh api repos/$REPO/pulls/comments/$COMMENT_ID/replies \
  -X POST -f "body=Applied in <commit_url>. Thanks."
```

Record result in the current round's `accepted` counter.

#### C4 — Copilot Negotiation: Reject Path

```bash
# Post inline reply with one-sentence reason — NO @copilot mention
gh api repos/$REPO/pulls/comments/$COMMENT_ID/replies \
  -X POST -f "body=Not applying: <one-sentence reason>. Keeping current implementation because <rationale>."
```

No code change. No commit. Record result in the current round's `rejected` counter.

#### C5 — Copilot Negotiation: Round Bookkeeping

After processing all comments in this cycle (both suggestion and plain types):

1. **Increment round counter:**
   ```
   copilot_negotiation.round += 1
   ROUND = copilot_negotiation.round
   ```

2. **Append round detail:**
   ```json
   {
     "round": ROUND,
     "at": "ISO8601",
     "suggestions_total": N,
     "accepted": X,
     "rejected": Y,
     "plain_comments_fixed": Z
   }
   ```

3. **Write watermark to PR body:**
   ```bash
   BODY=$(gh pr view $PR --repo $REPO --json body -q .body)

   # Replace existing watermark, or append in HTML comment section
   NEW_BODY=$(echo "$BODY" | sed "s/\[COPILOT_ROUND: [0-9]*\]/[COPILOT_ROUND: $ROUND]/")
   if ! echo "$NEW_BODY" | grep -q "\[COPILOT_ROUND:"; then
     NEW_BODY="$BODY\n\n<!-- xgh -->\n[COPILOT_ROUND: $ROUND]"
   fi

   gh pr edit $PR --repo $REPO --body "$NEW_BODY"
   ```
   Save watermark string in `copilot_negotiation.pr_body_watermark` for idempotency.

4. **Re-request Copilot review** (reviewer list cycle — same as Step E):
   ```bash
   gh pr edit $PR --repo $REPO --remove-reviewer copilot-pull-request-reviewer 2>/dev/null
   gh pr edit $PR --repo $REPO --add-reviewer copilot-pull-request-reviewer
   ```

5. **Update state:** `last_action = copilot-negotiation-round-<N>`

6. **Append to `action_log`:**
   ```json
   { "at": "ISO8601", "pr": 42, "action": "copilot-negotiation-round-1", "detail": "3 suggestions (2 accepted, 1 rejected), 2 plain comments fixed" }
   ```

#### C6 — Copilot Negotiation: Cap Check

**Check at the start of C2 (before evaluating a new round).** Cap threshold = `max_fix_cycles` (default 3).

```
if copilot_negotiation.round >= max_fix_cycles:
```

If capped:
1. Set `copilot_negotiation.capped = true`
2. Replace PR body watermark with cap marker:
   ```bash
   BODY=$(gh pr view $PR --repo $REPO --json body -q .body)
   NEW_BODY=$(echo "$BODY" | sed "s/\[COPILOT_ROUND: [0-9]*\]/[NEGOTIATION_CAPPED: $ROUND rounds]/")
   gh pr edit $PR --repo $REPO --body "$NEW_BODY"
   ```
3. **Store LCM metric:**
   ```
   lcm_store(
     content: "PR #<N> in <repo>: Copilot negotiation capped at <ROUND> rounds. Accepted: X suggestions total, Rejected: Y suggestions total.",
     tags: ["copilot-negotiation", "pr:<N>", "capped", "budget:rnd"]
   )
   ```
4. Set `last_action = negotiation-capped`
5. Print: `⚠️ PR #<N>: Copilot negotiation cap reached (<ROUND> rounds). Shipping.`
6. Proceed directly to merge criteria (Step D) — remaining Copilot comments do not block merge.

**LCM metric also stored on merge (always, when negotiation was active):**
```
lcm_store(
  content: "PR #<N> in <repo>: merged after <ROUND> Copilot negotiation rounds. Accepted: X suggestions total, Rejected: Y suggestions total.",
  tags: ["copilot-negotiation", "pr:<N>", "merged", "rounds:<N>", "budget:rnd"]
)
```

Store this from the merge success path in Step A (when `state = MERGED` and `copilot_negotiation.round > 0`).

#### D — New review with NO new comments

**Condition:** `review.submitted_at > baseline_review_at` AND `comment_count == baseline_comment_count`

Reviewer re-reviewed and found nothing new. Evaluate merge criteria in order:

1. `mergeable == MERGEABLE` — if CONFLICTING: dispatch conflict-resolution agent, wait
2. All `statusCheckRollup` entries: `conclusion SUCCESS` or `SKIPPED` — if any FAILURE/CANCELLED: report, wait
3. No review with `state == CHANGES_REQUESTED` from any author — if any: treat as new feedback (back to C)
4. At least one review from `<reviewer>` exists (Copilot never approves — see @references/providers/github.md)
5. All inline comments from `<reviewer_comment_author>` have been replied to (accept with fix + commit URL, or reject with reasoning)
6. If `require_resolved_threads == true`: `UNRESOLVED == 0` — if any: resolve outdated threads, then wait

**Double-merge guard:** Before calling `gh pr merge`:
1. Re-read `.xgh/ship-prs-state.json` — if `prs["<PR>"].merging == true`, skip merge (another tick is already merging)
2. Set `prs["<PR>"].merging = true` and write state file atomically
3. Call `gh pr merge ...`
4. On success or failure: set `merging = false` and write state file

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

### `pause` — Pause all active actions

Set `"paused": true` in `.xgh/ship-prs-state.json`. The cron continues firing but the
poller skips all active actions (merges, fix agents, review requests) until resumed.
Print: `⏸️ ship-prs paused. Cron still runs but no actions will be taken. Use /xgh-ship-prs resume to continue.`

---

### `resume` — Resume after pause

Set `"paused": false`. Print: `▶️ ship-prs resumed.`

---

### `hold <PR>` — Hold a specific PR

Set `prs["<PR>"].held = true`. The cron skips this PR each tick.
Print: `⏸️ PR #<N> held. It will be skipped until you run /xgh-ship-prs unhold <N>.`

---

### `unhold <PR>` — Release a held PR

Set `prs["<PR>"].held = false`. Print: `▶️ PR #<N> released.`

---

### `dry-run [<PR>]` — Preview actions without executing

Run one observe-mode poll cycle (pr-poller mode: observe) for the specified PR(s),
or all watched PRs if no PR given. Then apply the decision tree logic WITHOUT executing
any actions — only print what would happen:
```
Would: re-request Copilot review on #42 (cooldown elapsed)
Would: dispatch haiku agent to fix 3 comments on #43
Would: merge #44 with squash (all criteria met)
```
Do NOT write any state changes. Do NOT call gh API mutation endpoints. This includes pr-poller observe mode — pass `no_state_write: true` so `last_seen_*` fields in `.xgh/watch-prs-state.json` are NOT updated.

---

### `log [<PR>]` — Show action log

Read `action_log` from `.xgh/ship-prs-state.json`. Display as a table:

| Time | PR | Action | Detail |
|------|----|--------|--------|

If `<PR>` given, filter to that PR only.
If no session active: `ℹ️ No active ship-prs session.`

---

### `status` — Show current session

Load `.xgh/ship-prs-state.json` and display:

```
## 🐴🤖 xgh ship-prs — status

Repo: ipedro/lossless-claude | Provider: github | Reviewer: copilot-pull-request-reviewer[bot]
Merge: squash | Cron: <job-id> every 1m | Max fix cycles: 3
Active since: 2026-03-22T03:00:00Z | Paused: false

| PR   | Status      | Last Action                     | Review    | Comments | Fixes | Copilot Rounds | Agent |
|------|-------------|---------------------------------|-----------|----------|-------|----------------|-------|
| #101 | ✅ merged   | merge-succeeded                 | 03:42:40Z | 20       | 1     | 2/3            | —     |
| #59  | 👀 watching | copilot-negotiation-round-1     | 00:08:20Z | 28       | 0     | 1/3            | —     |
```

**Copilot Rounds column:** Shows `<current_round>/<cap>` (e.g. `2/3`). Shows `—` when `copilot_negotiation.round == 0` or `reviewer_comment_author != "Copilot"`. Shows `CAPPED` when `copilot_negotiation.capped == true`.

If no state file: `ℹ️ No active ship-prs session.`

---

### `stop` — Terminate session

1. Load state file
2. If no session: print info message, exit
3. If `cron_job_id` is set: call `CronDelete(cron_job_id)`. If not set, scan `CronList` for any job whose prompt contains `SHIP:<REPO>:` and delete matches.
4. Delete state file
5. Print confirmation:
   - If `cron_job_id` was set and deleted: `✅ ship-prs stopped. Cron job <id> deleted.`
   - If scan was used (0 found): `✅ ship-prs stopped. (No active cron job found.)`
   - If scan was used (1+ found): `✅ ship-prs stopped. Deleted <N> cron job(s): <id1> <id2> ...`

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

Provider-specific quirks, reviewer behavior, and API patterns are documented in shared references:
- `@references/providers/github.md` — Copilot review behavior, never-approves rule, reviewer list cycle, [bot] suffix rules
- `@references/providers/gitlab.md` — MR reviewer assignment, thread resolution
- `@references/providers/bitbucket.md` — PR reviewer assignment
- `@references/providers/azure-devops.md` — Required reviewers, policies

---

## Known Pitfalls

| Pitfall | How ship-prs handles it |
|---------|--------------------------|
| `@copilot` in any comment triggers delegation (including `@copilot review`) | Agent prompts include "NEVER use @copilot in comments — reviewer list cycle only" |
| `[bot]` suffix required in REST API | Encodes suffix in REST calls; uses `gh pr edit` (GraphQL, no suffix) for reviewer list |
| Copilot ignores conflicting PRs | Detects CONFLICTING, resolves before re-requesting |
| COMMENTED reviews can't be dismissed | Never attempts dismiss — uses re-request cycle |
| Review latency varies | Cooldown prevents re-request spam |
| Outdated threads (with --require-resolved-threads) | Detects outdated threads, resolves via GraphQL before merge |
| Reviews on unrelated files | Agent prompts: "reply out-of-scope for pre-existing artifacts" |
| API pagination hides new reviews | All review/comment endpoints use `--paginate` |
| Fix agents loop without progress | fix_cycle_count cap (max_fix_cycles) stops infinite dispatch |
| Concurrent cron ticks double-merging | merging flag prevents double-merge across overlapping ticks |
| Branch requires N approvals but 1 reviewer | Pre-flight warning at start |
| Copilot suggestion accepted but breaks tests | C3: run test_command before committing; if tests fail, revert + treat as reject |
| API rate limit exhausted by blind review polling | ETag conditional requests: 304 Not Modified is free (no rate-limit cost). Stored in `review_etag` per PR; passed as `If-None-Match` on each poll. Only 200 responses (new data) consume quota. |
| ETag absent in response (rare GitHub behavior) | If `NEW_ETAG` is empty after a 200, skip the ETag save — next poll falls back to full fetch. No crash. |
| Suggestion targets code that has since changed | C2: compare diff_hunk against current file; if stale, skip + reply "stale, please re-review" |
| Multiple suggestions in one comment | C1: parse all fenced blocks per comment; evaluate and act on each independently |
| Negotiation loops without progress | C6: cap at max_fix_cycles (default 3); ship with [NEGOTIATION_CAPPED] watermark |
| PR body edit clobbers custom content | Watermark lives in `<!-- xgh -->` HTML comment section appended at end of body |
| Copilot posts plain comments alongside suggestion blocks | Both types processed in same cycle; C1 classifies all, routes to appropriate path each |

---

## State File

**Path:** `.xgh/ship-prs-state.json`

Runtime state only — add to `.gitignore`.

**Persistence rules:**
- `start` creates the file
- Every poll cycle rewrites atomically
- `status` reads only
- `stop` deletes it
- `poll-once` creates/updates but leaves no background process

**Per-PR ETag state** (added to each PR block on first reviews fetch):

| Field | Type | Description |
|-------|------|-------------|
| `review_etag` | string\|null | GitHub ETag from last successful `GET .../reviews` response. `null` on first cycle. Used as `If-None-Match` header on subsequent polls. 304 response means no new review data — skips C/D processing. |

**Per-PR negotiation state** (added to each PR block when `reviewer_comment_author == "Copilot"`):

| Field | Type | Description |
|-------|------|-------------|
| `copilot_negotiation.round` | int | Current round number (0 = not started) |
| `copilot_negotiation.capped` | bool | True once round >= max_fix_cycles |
| `copilot_negotiation.rounds_detail` | array | Per-round breakdown: total/accepted/rejected/plain_fixed |
| `copilot_negotiation.pr_body_watermark` | string | Last written watermark, for idempotency |

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
