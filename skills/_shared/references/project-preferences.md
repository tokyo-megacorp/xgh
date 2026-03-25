# Project Preferences Reference

Skills can read `config/project.yaml` at dispatch time to pick up project-level defaults
without relying on AGENTS.md.

## Reading preferences (Python + PyYAML)

```python
import yaml, os
prefs = {}
if os.path.exists("config/project.yaml"):
    with open("config/project.yaml") as f:
        cfg = yaml.safe_load(f) or {}
    prefs = cfg.get("preferences", {})
```

## All preference domains

11 domains are defined. Skills source `lib/preferences.sh` and call the domain loader to
get a resolved value — the loader applies the correct cascade automatically.

```bash
source lib/preferences.sh
VALUE=$(load_<domain>_pref <field> [cli_override] [branch])
```

### Domain reference table

| Domain | Loader | Cascade | Keys |
|--------|--------|---------|------|
| `pr` | `load_pr_pref` | CLI > branch > default > probe | `provider`, `repo`, `reviewer`, `reviewer_comment_author`, `merge_method`, `review_on_push`, `auto_merge`, `branches` |
| `dispatch` | `load_dispatch_pref` | CLI > default | `default_agent`, `fallback_agent`, `exec_effort`, `review_effort` |
| `superpowers` | `load_superpowers_pref` | CLI > default | `implementation_model`, `review_model`, `effort` |
| `design` | `load_design_pref` | CLI > default | `model`, `effort` |
| `agents` | `load_agents_pref` | CLI > default | `default_model` |
| `pair_programming` | `load_pair_programming_pref` | CLI > default | `enabled`, `tool`, `effort`, `phases` |
| `vcs` | `load_vcs_pref` | CLI > branch > default | `commit_format`, `branch_naming`, `pr_template` |
| `testing` | `load_testing_pref` | CLI > branch > default | `timeout`, `required_suites`, `skip_rules` |
| `scheduling` | `load_scheduling_pref` | CLI > default | `retrieve_interval`, `analyze_interval`, `quiet_hours` |
| `notifications` | `load_notifications_pref` | CLI > default | `delivery`, `batching`, `suppress_below` |
| `retrieval` | `load_retrieval_pref` | CLI > default | `depth`, `max_age`, `context_tree_sync` |

### Field details by domain

**`dispatch`** — `/xgh-dispatch` cold-start defaults
- `default_agent`: agent identifier used when no explicit agent is passed (e.g. `xgh:dispatch`)
- `fallback_agent`: agent to use if dispatch can't determine best fit (e.g. `xgh:codex`)
- `exec_effort`: reasoning effort for implementation tasks (`low` | `normal` | `high` | `max`)
- `review_effort`: reasoning effort for review tasks (`low` | `normal` | `high` | `max`)

**`superpowers`** — superpowers dispatch (implementation + review steps)
- `implementation_model`: model shorthand for impl tasks (`sonnet` | `opus` | ...)
- `review_model`: model shorthand for review tasks (`sonnet` | `opus` | ...)
- `effort`: reasoning effort override (`low` | `normal` | `high` | `max`)

**`design`** — `/xgh-design`
- `model`: model shorthand (`sonnet` | `opus` | ...)
- `effort`: reasoning effort (`low` | `normal` | `high` | `max`)

**`agents`** — agent frontmatter resolution
- `default_model`: fallback model for any agent whose frontmatter declares `model: inherit`

**`pair_programming`** — pair-programming skills
- `enabled`: whether pairing is active (`true` | `false`)
- `tool`: agent to pair with (`xgh:dispatch` | `xgh:codex` | `xgh:gemini` | `xgh:opencode`)
- `effort`: reasoning effort for the pair agent
- `phases`: list of phases where pairing applies (`design` | `per_task` | both)

**`vcs`** — VCS workflow defaults (branch-aware)
- `commit_format`: conventional commit pattern or style hint (e.g. `<type>: <description>`)
- `branch_naming`: branch naming convention (e.g. `<type>/<description>`)
- `pr_template`: path to PR description template (e.g. `.github/pull_request_template.md`)

**`testing`** — test runner defaults (branch-aware)
- `timeout`: maximum time allowed for test runs in seconds (e.g. `120`)
- `required_suites`: list of test suites that must be executed (e.g. `[unit, integration]`)
- `skip_rules`: patterns or identifiers for tests/suites to skip

**`scheduling`** — task scheduling preferences
- `retrieve_interval`: how often to retrieve context (e.g. `30m`, `1h`)
- `analyze_interval`: how often to analyze inbox (e.g. `1h`)
- `quiet_hours`: time window when tasks should not run (e.g. `22:00-08:00`)

**`notifications`** — notification routing
- `delivery`: notification delivery channel (`inline` | `telegram` | `slack`)
- `batching`: whether to batch notifications (`true` | `false`)
- `suppress_below`: minimum severity level to send (e.g. `info` | `warn` | `error`)

**`retrieval`** — context retrieval defaults
- `depth`: how deep to retrieve context (`shallow` | `normal` | `deep`)
- `max_age`: maximum age for retrieved entries (e.g. `7d`, `24h`)
- `context_tree_sync`: keep local context tree in sync (`true` | `false`)

**`pr`** — PR creation, review, and merge (`/xgh-ship-prs`, `/xgh-watch-prs`, `/xgh-review-pr`)
- `provider`: VCS provider (`github`)
- `repo`: `owner/repo` slug
- `reviewer`: reviewer to request (e.g. `copilot-pull-request-reviewer[bot]`)
- `reviewer_comment_author`: display name used in review comments (e.g. `Copilot`)
- `merge_method`: default merge strategy (`squash` | `merge` | `rebase`)
- `review_on_push`: auto-request review on push (`true` | `false`)
- `auto_merge`: enable auto-merge when checks pass (`true` | `false`)
- `branches.<ref>.*`: per-branch overrides for any field above

## Priority order

Each preference domain defines its own priority order.

**Default (CLI > default):** User override at call time → **project preferences** → empty (caller provides fallback)

**Branch-aware (CLI > branch > default):** User override at call time → `branches.<ref>.<field>` override → **project preferences** → empty (caller provides fallback)

**PR domain (CLI > branch > default > probe):** CLI flag → `branches.<base_ref>.<field>` → `preferences.pr.<field>` → auto-detect probe (provider only)

Skills MUST respect these orders. Never let project preferences override an explicit user flag.

## Using loaders in skills

Skills are Claude instruction files, not shell scripts. Reference the loaders conceptually
to describe what values skills should read. When a skill dispatches to a shell helper or
invokes a bash step, that step sources `lib/preferences.sh`:

```bash
source lib/preferences.sh

# Simple domain (CLI > default)
MODEL=$(load_superpowers_pref implementation_model "$CLI_MODEL")
EFFORT=$(load_design_pref effort "$CLI_EFFORT")

# Branch-aware domain (CLI > branch > default)
COMMIT_FMT=$(load_vcs_pref commit_format "$CLI_FMT")

# PR domain (CLI > branch > default > probe)
# branch arg = target branch for PR operations; empty skips branch overrides
REPO=$(load_pr_pref repo "$CLI_REPO" "$BASE_BRANCH")
MERGE_METHOD=$(load_pr_pref merge_method "$CLI_MERGE_METHOD" "$BASE_BRANCH")
MERGE_METHOD="${MERGE_METHOD:-squash}"  # fallback — merge_method is not probed
```

## PR preferences helper (legacy alias)

PR skills previously sourced `lib/config-reader.sh`. That source is still valid but
`lib/preferences.sh` is the canonical location going forward:

```bash
source lib/preferences.sh   # preferred
# source lib/config-reader.sh  # legacy — still works
REPO=$(load_pr_pref repo "$CLI_REPO" "")
MERGE_METHOD=$(load_pr_pref merge_method "$CLI_MERGE_METHOD" "$BASE_BRANCH")
MERGE_METHOD="${MERGE_METHOD:-squash}"
```
