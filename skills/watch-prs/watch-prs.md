---
name: xgh:watch-prs
description: "Use /xgh-watch-prs to passively monitor PRs — surfaces review changes, new comments, CI status, and merge-readiness without touching anything. Never merges, never fixes comments, never requests reviews. Pairs with /xgh-ship-prs for active orchestration."
---

> **Output format:** Start with `## 🐴🤖 xgh watch-prs`. Use markdown tables for state snapshots. Use ✅ ⚠️ ❌ for status. Show change-log between polls as bullet list. Keep per-poll output terse.

# /xgh-watch-prs — PR Observer

Passively watch a batch of PRs and surface changes between polls: new comments, review state changes, CI status updates, and merge-readiness. **Read-only:** never merges, never requests reviews, never dispatches agents. Use `/xgh-ship-prs` to actively drive PRs to merge.

## Usage

```
/xgh-watch-prs start <PR> [<PR>...] [--repo owner/repo] [--interval 3m] [--reviewer <login>]
/xgh-watch-prs poll-once <PR> [<PR>...]
/xgh-watch-prs status
/xgh-watch-prs stop
```

**Defaults:**
- `--interval 3m`
- `--reviewer` — auto-detected from provider profile (e.g., `copilot-pull-request-reviewer[bot]` on GitHub)

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
- If enabled and `--reviewer` not set: default `reviewer` to `copilot-pull-request-reviewer[bot]` for tracking review state, and derive `reviewer_comment_author=Copilot` only when filtering inline review comments.
- If disabled or endpoint 404s: print `⚠️ Copilot code review is not enabled for $REPO. Pass --reviewer <login> to specify one.`

**Other providers:** If `--reviewer` not set and profile has no `reviewer_bot`:
`⚠️ No AI reviewer configured for $PROVIDER. Pass --reviewer <login> or review changes will not be tracked.`

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
gh api repos/$REPO/pulls/$PR/comments --paginate \
  --jq '[.[] | select(.user.login == "<REVIEWER_COMMENT_AUTHOR>")] | length'

# CI status
gh pr view $PR --repo $REPO --json statusCheckRollup --jq '.statusCheckRollup | map(.conclusion) | unique | join(",")'
```

**Step 3 — Write state file:**

Save to `.xgh/watch-prs-state.json`:
```json
{
  "session_id": "uuid",
  "repo": "owner/repo",
  "provider": "github",
  "reviewer": "copilot-pull-request-reviewer[bot]",
  "reviewer_comment_author": "Copilot",
  "cron_job_id": null,
  "cron": "*/3 * * * *",
  "created_at": "ISO8601",
  "prs": {
    "101": {
      "status": "watching",
      "last_seen_comment_count": 12,
      "last_seen_review_at": "ISO8601 or null",
      "last_seen_review_state": "COMMENTED or null",
      "last_seen_mergeable": "MERGEABLE",
      "last_seen_ci": "SUCCESS"
    }
  }
}
```

**Step 4 — Start poll loop:**

Use `CronCreate` to schedule recurring polls. Convert `--interval` to a standard cron expression (`5m → "*/5 * * * *"`, `10m → "*/10 * * * *"`).

The sentinel string `WATCH:<REPO>:<PR_NUMBERS>` in the prompt makes it findable via `CronList` for stop/status.

```
CronCreate({
  cron: "<interval-expression>",
  recurring: true,
  prompt: `WATCH:<REPO>:<PR_NUMBERS>
Dispatch the xgh:pr-poller agent with:
- mode: observe
- repo: <REPO>
- provider: <PROVIDER>
- prs: [<PR_NUMBERS>]
- reviewer: <REVIEWER>
- reviewer_comment_author: <REVIEWER_COMMENT_AUTHOR>
Read .xgh/watch-prs-state.json for per-PR last_seen baselines. Compare DELTA against
baselines and print a change-log. Update state with new last_seen values.
If the agent returns ALL_DONE, read .xgh/watch-prs-state.json, take cron_job_id,
and call CronDelete(cron_job_id). Fallback: scan CronList for a job whose prompt contains
"WATCH:<REPO>:<PR_NUMBERS>" and delete it.`
})
```

Save the returned job ID to state: `"cron_job_id": "<id>"`.

Report:
```
✅ Watching PRs [<numbers>] in <repo> every <interval>.
   Provider: <provider> | Reviewer: <reviewer>
   Cron job: <id> (auto-stops when all PRs merge).
   ℹ️ Passive mode — no merges or fixes. Use /xgh-ship-prs start <PRs> to ship.
```

**Step 5 — Poll cycle (per PR):**

For each PR where `status != merged`, execute the observe cycle:

#### A — Fetch current state (read-only)

Call pr-poller with `mode: observe`. The agent returns a `DELTA: [...]` object per PR with current state and detected changes.

#### B — Compare against last_seen baselines

Read `last_seen_*` fields from `.xgh/watch-prs-state.json` for each PR. The pr-poller already computes the diff; extract the `changes` array.

#### C — Print change-log

```
## 🐴🤖 xgh watch-prs — tick 2026-03-23T15:32:00Z

| PR | State | Mergeable | Review | Comments | CI |
|----|-------|-----------|--------|----------|----|
| #42 | OPEN | ✅ | ✅ APPROVED | 12 | ✅ |
| #43 | OPEN | ✅ | ⚠️ COMMENTED | 15 (+3) | ✅ |

Changes since last tick:
• #43: 3 new Copilot comments (15:31)
• #43: review state COMMENTED (was null)

ℹ️ #42 is merge-ready — run /xgh-ship-prs start 42 to ship it.
```

If no changes: `✅ No changes since last tick.`

#### D — Update state (no GitHub writes)

Update `last_seen_*` fields in `.xgh/watch-prs-state.json` with values from the DELTA. No calls to GitHub mutation endpoints. If a DELTA entry has `"done": true`, also set `prs["<PR>"].status = "merged"` in `.xgh/watch-prs-state.json`.

---

### `poll-once <PR> [<PR>...]` — Single observe cycle

Execute exactly one observe cycle (Step 5 above) without starting a background loop. Create or update state file. Print what changed. Exit.

---

### `status` — Show current session

Load `.xgh/watch-prs-state.json` and display last-seen snapshot:

```
## 🐴🤖 xgh watch-prs — status

Repo: ipedro/lossless-claude | Provider: github
Cron: <job-id> every 3m
Active since: 2026-03-22T03:00:00Z

| PR   | Status      | Last Seen Review  | Comments | Mergeable | CI |
|------|-------------|-------------------|----------|-----------|-----|
| #101 | ✅ merged   | APPROVED 03:42:40 | 20       | —         | —   |
| #59  | 👀 watching | COMMENTED 00:08Z  | 28       | ✅        | ✅  |
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

## Provider Profiles

Embedded profiles — the skill references these directly, no external lookup needed.

### GitHub

```yaml
provider: github
reviewer_bot: copilot-pull-request-reviewer[bot]
reviewer_comment_author: Copilot
threads_api: graphql
```

#### GitHub: Two Copilot Systems — Critical Distinction

| System | Trigger | Effect |
|--------|---------|--------|
| **Code Review** | Add `copilot-pull-request-reviewer[bot]` to reviewer list | Leaves inline review comments |
| **SWE Delegation Agent** | `@copilot <anything>` in a comment — including `@copilot review` | Opens a **NEW PR** with code changes |

**NEVER use `@copilot` in comments.** This is a read-only observer — it should never comment on PRs.

### GitLab

```yaml
provider: gitlab
reviewer_bot: null
reviewer_comment_author: null
threads_api: rest
```

### Bitbucket

```yaml
provider: bitbucket
reviewer_bot: null
reviewer_comment_author: null
threads_api: none
```

### Azure DevOps

```yaml
provider: azure-devops
reviewer_bot: null
reviewer_comment_author: null
threads_api: rest
```

### Generic

```yaml
provider: generic
reviewer_bot: null
reviewer_comment_author: null
threads_api: none
```

---

## State File

**Path:** `.xgh/watch-prs-state.json`

Runtime state only — add to `.gitignore`.

**Persistence rules:**
- `start` creates the file
- Every poll cycle updates `last_seen_*` fields atomically
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
| All PRs merged | `✅ All PRs merged! Session complete.` |
