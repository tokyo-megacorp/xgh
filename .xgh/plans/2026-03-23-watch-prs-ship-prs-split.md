# watch-prs / ship-prs Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `xgh:watch-prs` into two skills — a pure passive observer (`watch-prs`) and a full active orchestrator (`ship-prs`) — sharing a mode-aware `pr-poller` agent as their common polling engine.

**Architecture:** `pr-poller` gains a `mode: observe|ship` parameter; in `observe` mode it reads state and returns structured deltas without writing anything to GitHub. `watch-prs` uses observe mode and outputs human-readable change logs. `ship-prs` carries all current active behavior plus new commands (`pause`, `resume`, `hold`, `unhold`, `dry-run`, `log`) and two new safety features (per-PR fix iteration cap, branch protection pre-flight).

**Tech Stack:** Bash markdown skills, gh CLI, CronCreate/CronList/CronDelete, haiku/sonnet agents, `.xgh/` JSON state files.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `agents/pr-poller.md` | Modify | Add `mode: observe\|ship` param; gate active steps + paused/held checks behind `ship` mode |
| `skills/watch-prs/watch-prs.md` | Rewrite | Pure passive observer — CronCreate with observe mode, change-log output, no GitHub writes |
| `commands/watch-prs.md` | Verify/Modify | Remove any active-behavior references that become stale after watch-prs rewrite |
| `skills/ship-prs/ship-prs.md` | Create | Full orchestrator — extract from watch-prs, add pause/resume/hold/unhold/dry-run/log, safety features |
| `commands/ship-prs.md` | Create | Command stub for ship-prs |
| `tests/skill-triggering/prompts/ship-prs.txt` | Create | Natural-language trigger test |
| `tests/skill-triggering/prompts/ship-prs-2.txt` | Create | Variant trigger test |
| `tests/skill-triggering/prompts/ship-prs-3.txt` | Create | Variant trigger test |
| `tests/test-config.sh` | Modify | Add ship-prs file-exists + content assertions |
| `tests/test-multi-agent.sh` | Modify | Add pr-poller mode assertion |
| `.gitignore` | Verify/Modify | Confirm `watch-prs-state.json` present; add `ship-prs-state.json` |

---

## State File Schemas

### `.xgh/watch-prs-state.json`
```json
{
  "session_id": "uuid",
  "repo": "owner/repo",
  "provider": "github",
  "reviewer_comment_author": "Copilot",
  "cron_job_id": "<id>",
  "cron": "*/3 * * * *",
  "created_at": "ISO8601",
  "prs": {
    "42": {
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

### `.xgh/ship-prs-state.json`
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
  "cron_job_id": "<id>",
  "cron": "*/3 * * * *",
  "created_at": "ISO8601",
  "action_log": [],
  "prs": {
    "42": {
      "status": "watching",
      "held": false,
      "fix_cycle_count": 0,
      "merging": false,
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

> **`fix_cycle_count` lifecycle:** Initialized to 0 at `start`. Incremented each time a fix agent is dispatched. Never reset — counts lifetime dispatches for the session. A fresh `stop` + `start` creates a new session with a new state file, resetting the count.

> **`merging` flag:** Set to `true` immediately before calling `gh pr merge`. Cleared to `false` (or the field removed) after merge succeeds or fails. If a poll tick sees `merging: true`, it skips the merge step for that PR. Prevents double-merge from concurrent cron ticks.

### `action_log` entry format
```json
{ "at": "ISO8601", "pr": 42, "action": "dispatched-fix-agent", "detail": "3 new comments" }
```

---

## pr-poller observe mode — delta output format

When `mode: observe`, the agent returns `DELTA:` with a JSON summary per PR:
```
DELTA: [
  {
    "pr": 42,
    "mergeable": "MERGEABLE",
    "review_state": "APPROVED",
    "comment_count": 15,
    "ci_status": "SUCCESS",
    "changes": [
      "comment_count: 12 → 15",
      "review_state: COMMENTED → APPROVED"
    ],
    "merge_ready": true
  }
]
```
In observe mode: `ALL_DONE` is returned when all PRs are merged/closed (watch-prs uses this to auto-stop the cron). `ACTED` is never returned — observe mode only reports state, never takes action.

---

## Task 1 — Update pr-poller to support `mode: observe|ship`

**Files:**
- Modify: `agents/pr-poller.md`
- Modify: `tests/test-multi-agent.sh`

- [ ] Read `agents/pr-poller.md` in full.

- [ ] Add `mode` to the input format block:
  ```
  mode: observe   # or: ship (default: ship)
  ```

- [ ] Add an observe-mode section before "Poll cycle":
  ```markdown
  ## Observe mode (mode: observe)

  Read-only. Run only steps 1 and 3 for each PR. Do NOT merge, do NOT re-request review,
  do NOT dispatch any agent, do NOT write to GitHub.

  Return `DELTA: [...]` with the structured delta object per PR (see schema above).
  If a PR is already merged/closed, include `"done": true` in its delta entry.
  If ALL PRs are done, return `ALL_DONE` (same as ship mode).
  ```

- [ ] Gate Steps 2 (merge criteria + merge) and 4 (re-request review) and the comment decision tree behind `if mode == ship`:
  - In Step 2: prepend `**Ship mode only.**`
  - In Step 4: prepend `**Ship mode only.**`
  - In comment decision tree: prepend `**Ship mode only.** In observe mode, record new comments in the delta output only — do not classify or dispatch agents.`

- [ ] Add paused/held guard in ship mode — before the decision tree in Step 2 and Step 4:
  ```
  **Paused/held guard (ship mode only):** Before any active step, read `.xgh/ship-prs-state.json`.
  If top-level `paused == true`: skip ALL active steps for ALL PRs this tick, return `SKIPPED: session paused`.
  If `prs["<PR>"].held == true`: skip all active steps for that PR, include `"skipped": "held"` in its delta entry.
  ```

- [ ] Update "Your job" return values to include the new return statuses:
  ```
  - `DELTA: [...]` — observe mode; structured state snapshot per PR, no actions taken
  - `SKIPPED: session paused` — ship mode, paused flag was set
  ```

- [ ] Update the agent description to reference both `xgh:watch-prs` (observe mode) and `xgh:ship-prs` (ship mode) as dispatchers.

- [ ] Add pr-poller mode assertion to `tests/test-multi-agent.sh`, after the existing pr-poller block:
  ```bash
  assert_contains "$PLUGIN_DIR/agents/pr-poller.md"  "mode: observe"   "pr-poller: documents observe mode"
  assert_contains "$PLUGIN_DIR/agents/pr-poller.md"  "Ship mode only"  "pr-poller: gates active steps behind ship mode"
  ```

- [ ] Run test: `bash tests/test-multi-agent.sh` — expect all passing.

- [ ] Commit:
  ```bash
  git add agents/pr-poller.md tests/test-multi-agent.sh
  git commit -m "feat(pr-poller): add mode: observe|ship — gate active steps and paused/held checks behind ship mode"
  ```

---

## Task 2 — Rewrite watch-prs as pure passive observer

**Files:**
- Modify: `skills/watch-prs/watch-prs.md`

- [ ] Read `skills/watch-prs/watch-prs.md` in full.

- [ ] Replace the `name` and `description` frontmatter:
  ```yaml
  name: xgh:watch-prs
  description: "Use /xgh-watch-prs to passively monitor PRs — surfaces review changes, new comments, CI status, and merge-readiness without touching anything. Never merges, never fixes comments, never requests reviews. Pairs with /xgh-ship-prs for active orchestration."
  ```

- [ ] Replace the output format directive:
  ```
  > **Output format:** Start with `## 🐴🤖 xgh watch-prs`. Use markdown tables for state snapshots. Use ✅ ⚠️ ❌ for status. Show change-log between polls as bullet list. Keep per-poll output terse.
  ```

- [ ] Replace the Usage block:
  ```
  /xgh-watch-prs start <PR> [<PR>...] [--repo owner/repo] [--interval 3m] [--reviewer <login>]
  /xgh-watch-prs poll-once <PR> [<PR>...]
  /xgh-watch-prs status
  /xgh-watch-prs stop
  ```
  Remove `--merge-method`, `--accept-suggestion-commits`, `--require-resolved-threads`, `--post-merge-hook` — these belong to ship-prs only.

- [ ] Rewrite Step 3 (write state file) to use the watch-prs schema (see above — simpler schema, no baseline/active-agent fields).

- [ ] Rewrite Step 4 (start poll loop) — cron prompt dispatches pr-poller in `mode: observe`:
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
  - reviewer_comment_author: <REVIEWER_COMMENT_AUTHOR>
  Read .xgh/watch-prs-state.json for per-PR last_seen baselines. Compare DELTA against
  baselines and print a change-log. Update state with new last_seen values.
  If the agent returns ALL_DONE, read .xgh/watch-prs-state.json, take cron_job_id,
  and call CronDelete(cron_job_id).`
  })
  ```

- [ ] Rewrite Step 5 (poll cycle) to be purely observational:
  - **A** — fetch current state per PR (mergeable, review, comments, CI) via pr-poller observe mode
  - **B** — compare against `last_seen_*` baselines in state file
  - **C** — print change-log:
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
  - **D** — update `last_seen_*` in state file. No GitHub writes.

- [ ] Rewrite `status` command to show last-seen snapshot from state file.

- [ ] Rewrite `stop` command — remove any reference to merge/fix/agent cleanup. Just delete cron + state file.

- [ ] Remove all sections that belong exclusively to ship-prs:
  - Decision tree sections C, D, E (new review with/without comments, re-request review)
  - Conflict resolution section
  - Agent dispatch guidelines
  - `active_agent` lifecycle
  - `post_merge_hook`, `accept_suggestion_commits`, `require_resolved_threads`
  - Integration with xgh:copilot-pr-review (ship-prs concern)

- [ ] Keep: Bootstrap (Step 0), provider detection, provider profiles (stripped to read-only fields only — remove `review_request_strategy`, `suggestion_commits`, thread mutation fields from watch-prs copy).

- [ ] Verify `commands/watch-prs.md` — read and remove any references to merging, fix agents, or active actions (e.g., update the description and usage to match the new passive-only commands). Update `--interval` default to `3m` if still showing `5m`.

- [ ] Verify `.gitignore` already contains `.xgh/watch-prs-state.json`. If not, add it.

- [ ] Run tests: `bash tests/test-config.sh` — expect all passing.

- [ ] Commit:
  ```bash
  git add skills/watch-prs/watch-prs.md commands/watch-prs.md
  git commit -m "feat(watch-prs): rewrite as pure passive observer — observe mode, change-log output"
  ```

---

## Task 3 — Create ship-prs skill

**Files:**
- Create: `skills/ship-prs/ship-prs.md`

- [ ] Create directory: `mkdir -p skills/ship-prs`

- [ ] Create `skills/ship-prs/ship-prs.md` with frontmatter:
  ```yaml
  ---
  name: xgh:ship-prs
  description: "Use /xgh-ship-prs when you want to ship PRs / drive PRs to merge automatically — fixes Copilot review comments, dispatches fix agents, resolves conflicts, auto-merges when approved. Use /xgh-watch-prs for passive monitoring without side effects."
  ---
  ```

- [ ] Add output format directive:
  ```
  > **Output format:** Start with `## 🐴🤖 xgh ship-prs`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. Keep per-poll output terse.
  ```

- [ ] Add Usage block with all commands including new ones:
  ```
  /xgh-ship-prs start <PR> [<PR>...] [--repo owner/repo] [--interval 3m] [--merge-method merge|squash|rebase] [--reviewer <login>] [--accept-suggestion-commits] [--require-resolved-threads] [--max-fix-cycles 3] [--post-merge-hook '<command>']
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

- [ ] Copy Bootstrap (Steps 0a–0c) from watch-prs verbatim — same provider detection logic.

- [ ] Copy Step 3 (write state file) from watch-prs but use the ship-prs schema (see above — includes `paused`, `held`, `fix_cycle_count`, `max_fix_cycles`, `action_log`).

- [ ] Add **branch protection pre-flight** to Step 1 (before CronCreate):
  ```bash
  # Check branch protection required approvals
  gh api repos/$REPO/branches/$(gh pr view $PR --repo $REPO --json baseRefName -q .baseRefName)/protection \
    --jq '.required_pull_request_reviews.required_approving_review_count // 0' 2>/dev/null
  ```
  If required approvals > 1 and `--reviewer` is a single bot: print warning:
  `⚠️ Branch requires <N> approving reviews but only 1 reviewer configured. Auto-merge may loop. Pass additional --reviewer logins or merge manually.`

- [ ] Copy Step 4 (CronCreate) from current watch-prs, updating state file path to `.xgh/ship-prs-state.json` and mode to `ship`:
  - Sentinel: `SHIP:<REPO>:<PR_NUMBERS>` (distinguishes from watch-prs crons)
  - Cron prompt dispatches pr-poller with `mode: ship`

- [ ] Copy Step 5 (poll cycle, decision tree, sections A–E) from current watch-prs.

- [ ] Add **fix cycle cap** to section C (new review with new comments), after the `active_agent` guard:
  ```
  **Fix cycle cap:** If `fix_cycle_count >= max_fix_cycles` for this PR:
  - Do NOT dispatch another fix agent
  - Print: `⚠️ PR #<N>: fix cycle cap reached (<max> cycles). Manual intervention needed.`
  - Set `last_action = fix-cap-reached`
  - Skip to next PR
  ```
  Increment `fix_cycle_count` each time a fix agent is dispatched for that PR. `fix_cycle_count` is never reset mid-session — it counts lifetime dispatches. A new `stop` + `start` resets it via a fresh state file.

- [ ] Add **double-merge guard** to section D (merge execution), immediately before `gh pr merge`:
  ```
  **Double-merge guard:** Before calling `gh pr merge`:
  1. Re-read `.xgh/ship-prs-state.json` — if `prs["<PR>"].merging == true`, skip merge (another tick is already merging)
  2. Set `prs["<PR>"].merging = true` and write state file atomically
  3. Call `gh pr merge ...`
  4. On success or failure: set `merging = false` and write state file
  ```

- [ ] Add the six new command definitions after `poll-once`:

  **`pause`:**
  ```
  Set `"paused": true` in `.xgh/ship-prs-state.json`. The cron continues firing but the
  poller skips all active actions (merges, fix agents, review requests) until resumed.
  Print: `⏸️ ship-prs paused. Cron still runs but no actions will be taken. Use /xgh-ship-prs resume to continue.`
  ```

  **`resume`:**
  ```
  Set `"paused": false`. Print: `▶️ ship-prs resumed.`
  ```

  **`hold <PR>`:**
  ```
  Set `prs["<PR>"].held = true`. The cron skips this PR each tick.
  Print: `⏸️ PR #<N> held. It will be skipped until you run /xgh-ship-prs unhold <N>.`
  ```

  **`unhold <PR>`:**
  ```
  Set `prs["<PR>"].held = false`. Print: `▶️ PR #<N> released.`
  ```

  **`dry-run [<PR>]`:**
  ```
  Run one observe-mode poll cycle (pr-poller mode: observe) for the specified PR(s),
  or all watched PRs if no PR given. Then apply the decision tree logic WITHOUT executing
  any actions — only print what would happen:
  "Would: re-request Copilot review on #42 (cooldown elapsed)"
  "Would: dispatch haiku agent to fix 3 comments on #43"
  "Would: merge #44 with squash (all criteria met)"
  Do NOT write any state changes. Do NOT call gh API mutation endpoints.
  ```

  **`log [<PR>]`:**
  ```
  Read `action_log` from `.xgh/ship-prs-state.json`. Display as a table:
  | Time | PR | Action | Detail |
  If <PR> given, filter to that PR only.
  If no session active: `ℹ️ No active ship-prs session.`
  ```

- [ ] Add to the cron prompt: check `paused` and `held` flags — skip actions if set.

- [ ] Copy full Provider Profiles section from current watch-prs (ship-prs needs all fields).

- [ ] Copy Integration with xgh:copilot-pr-review section.

- [ ] Copy Error Handling table.

- [ ] Update State File section to reference `.xgh/ship-prs-state.json`.

- [ ] Update all `watch-prs-state.json` references to `ship-prs-state.json`.

- [ ] Update all `BABYSIT:` / `WATCH:` sentinel references in cron prompt to `SHIP:`.

- [ ] Commit:
  ```bash
  git add skills/ship-prs/ship-prs.md
  git commit -m "feat(ship-prs): create active PR orchestrator skill — extracted from watch-prs, adds pause/resume/hold/unhold/dry-run/log + safety features"
  ```

---

## Task 4 — Create ship-prs command + trigger prompts

**Files:**
- Create: `commands/ship-prs.md`
- Create: `tests/skill-triggering/prompts/ship-prs.txt`
- Create: `tests/skill-triggering/prompts/ship-prs-2.txt`
- Create: `tests/skill-triggering/prompts/ship-prs-3.txt`

- [ ] Create `commands/ship-prs.md`:
  ```markdown
  ---
  name: xgh-ship-prs
  description: Ship a batch of PRs to merge automatically — fixes Copilot review comments, dispatches fix agents, auto-merges when approved
  usage: "/xgh-ship-prs <start|poll-once> <PR> [<PR>...] [--repo owner/repo] [--interval 3m] [--merge-method squash] [--post-merge-hook '<cmd>'] | /xgh-ship-prs <status|stop|pause|resume> | /xgh-ship-prs <hold|unhold|dry-run|log> [<PR>]"
  ---

  > **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh ship-prs`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. Keep per-poll output terse.

  # /xgh-ship-prs

  Run the `xgh:ship-prs` skill to shepherd multiple PRs through GitHub Copilot review cycles until all are merged.

  ## Usage

  ```
  /xgh-ship-prs start 28 29 [--interval 3m] [--merge-method squash] [--post-merge-hook 'make deploy']
  /xgh-ship-prs poll-once 28 29
  /xgh-ship-prs pause
  /xgh-ship-prs resume
  /xgh-ship-prs hold 28
  /xgh-ship-prs dry-run
  /xgh-ship-prs log
  /xgh-ship-prs status
  /xgh-ship-prs stop
  ```
  ```

- [ ] Create `tests/skill-triggering/prompts/ship-prs.txt`:
  ```
  ship PR 45 and 46 to main
  ```

- [ ] Create `tests/skill-triggering/prompts/ship-prs-2.txt`:
  ```
  /xgh-ship-prs start 45 46
  ```

- [ ] Create `tests/skill-triggering/prompts/ship-prs-3.txt`:
  ```
  auto-merge these PRs once Copilot approves them: 45, 46, 47
  ```

- [ ] Commit:
  ```bash
  git add commands/ship-prs.md tests/skill-triggering/prompts/ship-prs*.txt
  git commit -m "feat(ship-prs): add command stub and trigger prompt test variants"
  ```

---

## Task 5 — Update tests and .gitignore

**Files:**
- Modify: `tests/test-config.sh`
- Modify: `.gitignore`

- [ ] Read `tests/test-config.sh` lines 36–65.

- [ ] Add ship-prs block after the watch-prs block in `test-config.sh`:
  ```bash
  # --- ship-prs: command + skill registration ---
  assert_file_exists "commands/ship-prs.md"
  assert_file_exists "skills/ship-prs/ship-prs.md"
  assert_contains "commands/ship-prs.md" "ship-prs"
  assert_contains "skills/ship-prs/ship-prs.md" "^name: xgh:ship-prs"
  assert_contains "skills/ship-prs/ship-prs.md" "pause"
  assert_contains "skills/ship-prs/ship-prs.md" "dry-run"
  assert_contains "skills/ship-prs/ship-prs.md" "fix_cycle_count"
  ```

- [ ] Add ship-prs prompt coverage assertions:
  ```bash
  assert_file_exists "tests/skill-triggering/prompts/ship-prs.txt"
  assert_file_exists "tests/skill-triggering/prompts/ship-prs-2.txt"
  assert_file_exists "tests/skill-triggering/prompts/ship-prs-3.txt"
  ```

- [ ] Read `.gitignore` — confirm `.xgh/watch-prs-state.json` is already present. Add `.xgh/ship-prs-state.json`.

- [ ] Run `bash tests/test-config.sh` — expect all passing.

- [ ] Commit:
  ```bash
  git add tests/test-config.sh .gitignore
  git commit -m "test: add ship-prs config and prompt assertions"
  ```

---

## Task 6 — Final verification

- [ ] Run full test suite:
  ```bash
  bash tests/test-config.sh && bash tests/test-multi-agent.sh
  ```
  Expected: all tests pass, 0 failures. (Do not hardcode expected counts — just verify 0 failures.)

- [ ] Smoke-check the split makes sense — read both skill files and verify:
  - `watch-prs` contains no `gh pr merge`, no `dispatch.*agent`, no `re-request` action logic
  - `ship-prs` contains no `last_seen_*` fields (those are watch-prs only)
  - `pr-poller` clearly gates steps 2 and 4 behind `mode == ship`

- [ ] Open PR against `develop` with title:
  `feat: split watch-prs into watch-prs (passive) + ship-prs (active orchestrator)`
