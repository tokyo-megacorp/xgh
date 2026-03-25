# Project Preferences — Centralized Configuration for Skills

**Date:** 2026-03-25
**Status:** Draft
**Scope:** config/project.yaml integration, provider reference extraction, copilot-pr-review deprecation, preference capture convention

---

## Problem

PR workflow skills (`ship-prs`, `watch-prs`, `copilot-pr-review`, `review-pr`) independently auto-detect repo, probe Copilot policies, and hardcode reviewer defaults on every invocation. Provider-specific quirks documentation (GitHub, GitLab, Bitbucket, Azure DevOps) is duplicated across multiple PR skills. None read from `config/project.yaml`, even though its `preferences:` section was designed as the project's preference registry.

Users must pass `--repo`, `--reviewer`, `--merge-method` on every call, or rely on per-skill auto-detection that re-probes APIs each time.

## Solution

1. Add a provider-agnostic `preferences.pr` section to `config/project.yaml`
2. Skills read defaults from project.yaml with a cascading read order
3. First invocation probes missing values and caches them back to project.yaml
4. Provider-specific documentation moves to shared references
5. `copilot-pr-review` is deprecated — its logic is absorbed into `ship-prs` and shared references
6. A preference capture convention teaches Claude to persist user statements to project.yaml
7. A validation skill enforces the convention

---

## Schema

```yaml
# config/project.yaml — new section under preferences:
preferences:
  pr:
    provider: github                      # github | gitlab | bitbucket | azure-devops
    repo: extreme-go-horse/xgh
    reviewer: copilot-pull-request-reviewer[bot]
    reviewer_comment_author: Copilot
    review_on_push: true
    merge_method: squash
    auto_merge: true
    branches:
      main:
        merge_method: merge
        required_approvals: 1
      develop:
        merge_method: squash
```

### Read order

For any field: **CLI flag > `branches.<base_ref>.<field>` > `preferences.pr.<field>` > auto-detect probe**

> **Note:** This cascade is specific to `preferences.pr` fields. Other preference domains (e.g., `preferences.dispatch`) use their own cascade defined in `_shared/references/project-preferences.md`. The `model-profiles.yaml` layer from that reference is not applicable to PR workflow fields.

---

## Skill consumption pattern

### Extending `lib/config-reader.sh`

The existing `lib/config-reader.sh` provides `xgh_config_get` for user-level config (`~/.xgh/ingest.yaml`). We extend it with project-level PR preference helpers that apply the same Python/PyYAML approach to `config/project.yaml`. Rather than introducing a `yq` dependency, these helpers reuse Python for both reads and writes.

```bash
# lib/config-reader.sh — new functions added to existing file

load_pr_pref() {
  local field="$1" cli_override="$2" branch="$3"

  # 1. CLI flag wins
  [[ -n "$cli_override" ]] && echo "$cli_override" && return

  # 2. Branch-specific override (use bracket notation for branch names with slashes)
  if [[ -n "$branch" ]]; then
    val=$(python3 -c "
import yaml, sys
field, branch = sys.argv[1], sys.argv[2]
with open('config/project.yaml') as f: d = yaml.safe_load(f)
v = (d.get('preferences',{}).get('pr',{}).get('branches',{}).get(branch,{}).get(field))
if v is not None: print(v)
" "$field" "$branch" 2>/dev/null)
    [[ -n "$val" ]] && echo "$val" && return
  fi

  # 3. Project default
  val=$(python3 -c "
import yaml, sys
field = sys.argv[1]
with open('config/project.yaml') as f: d = yaml.safe_load(f)
v = (d.get('preferences',{}).get('pr',{}).get(field))
if v is not None: print(v)
" "$field" 2>/dev/null)
  [[ -n "$val" ]] && echo "$val" && return

  # 4. Probe, cache, return
  val=$(probe_pr_field "$field")
  [[ -n "$val" ]] && cache_pr_pref "$field" "$val"
  echo "$val"
}

probe_pr_field() {
  local field="$1"
  case "$field" in
    provider)
      url=$(git remote get-url origin 2>/dev/null)
      case "$url" in
        *github.com*)    echo "github" ;;
        *gitlab.com*)    echo "gitlab" ;;
        *bitbucket.org*) echo "bitbucket" ;;
        *dev.azure.com*) echo "azure-devops" ;;
      esac ;;
    repo)
      local provider
      provider=$(load_pr_pref provider "" "")
      case "$provider" in
        github) gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null ;;
        gitlab) glab project view -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['path_with_namespace'])" ;;
      esac ;;
    reviewer)
      local provider repo
      provider=$(load_pr_pref provider "" "")
      repo=$(load_pr_pref repo "" "")
      case "$provider" in
        github)
          enabled=$(gh api "repos/$repo/copilot/policies" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('copilot_code_review',{}).get('enabled','false'))" 2>/dev/null)
          [[ "$enabled" == "true" ]] && echo "copilot-pull-request-reviewer[bot]" ;;
      esac ;;
    reviewer_comment_author)
      local reviewer
      reviewer=$(load_pr_pref reviewer "" "")
      case "$reviewer" in
        copilot-pull-request-reviewer*) echo "Copilot" ;;
      esac ;;
  esac
}

cache_pr_pref() {
  local field="$1" value="$2"
  python3 -c "
import yaml, sys
field, value = sys.argv[1], sys.argv[2]
with open('config/project.yaml') as f: d = yaml.safe_load(f)
d.setdefault('preferences',{}).setdefault('pr',{})[field] = value
with open('config/project.yaml','w') as f: yaml.dump(d, f, default_flow_style=False, sort_keys=False)
" "$field" "$value" 2>/dev/null
}
```

**No new dependency.** Python 3 + PyYAML are already required by the project (BM25 search, `gen-agents-md.sh`).

**Branch names with slashes** (e.g., `release/1.0`): Python's `dict.get()` handles arbitrary string keys naturally, unlike dot-notation in `yq`. This is why we use Python over `yq`.

**Concurrency:** `config/project.yaml` follows a single-writer constraint — only one skill invocation writes at a time. This is safe because Claude Code is single-threaded (skills run sequentially in the main session). Subagents receive pre-resolved values from the dispatching skill and never write to project.yaml directly.

### Skills that change

| Skill | Change |
|-------|--------|
| `ship-prs` | Replace Step 0a (detect repo), 0c (probe reviewer), merge-method defaults with `load_pr_pref` calls. Replace inline provider profiles with `@references/providers/<provider>.md`. Remove "Integration with xgh:copilot-pr-review" section (lines 593–611) — dead reference after deletion |
| `watch-prs` | Same Step 0a/0c replacement. Replace inline provider profiles with shared references |
| `copilot-pr-review` | **Delete.** Logic absorbed into ship-prs + shared provider references |
| `review-pr` | Use `load_pr_pref repo` instead of relying on `gh` auto-detection in dispatched agent prompts |
| `pr-poller` agent | Receives pre-resolved values from dispatching skill (no change — dispatching skill now reads from project.yaml) |

---

## Probe-and-cache flow

When `preferences.pr` is empty or missing fields, the first skill invocation auto-populates:

| Field | Probe method |
|-------|-------------|
| `provider` | `git remote get-url origin` → detect github.com / gitlab.com / bitbucket.org / dev.azure.com |
| `repo` | GitHub: `gh repo view --json nameWithOwner`; GitLab: `glab project view`; Bitbucket/Azure DevOps: requires manual configuration |
| `reviewer` | GitHub: `gh api repos/$REPO/copilot/policies` → if enabled, set copilot bot; GitLab: check project approval rules; Others: leave empty, warn user |
| `merge_method` | Leave empty (skill defaults to squash if unset) |

### Write-back rules

- After probing, write discovered values to `config/project.yaml` using the `cache_pr_pref` helper (Python `yaml.dump`)
- The file is tracked in git — user sees the change in `git diff` and can adjust before committing
- **Never overwrite:** If a field already has a value, probe skips it
- **CLI flags are ephemeral:** Override at runtime but don't write back
- **No TTL:** Values are stable (repo doesn't change, reviewer bot doesn't change). If the user switches providers, they edit project.yaml directly or delete the `pr:` block to re-probe

---

## Shared provider references

### New files

| File | Content |
|------|---------|
| `_shared/references/providers/github.md` | Copilot two-system distinction, reviewer list cycle, [bot] suffix rules, reviewer vs reviewer_comment_author mapping, review_on_push behavior, common errors |
| `_shared/references/providers/gitlab.md` | MR reviewers, approval rules, merge request API patterns |
| `_shared/references/providers/bitbucket.md` | PR reviewers, default reviewers, API patterns |
| `_shared/references/providers/azure-devops.md` | Required reviewers, policies, API patterns |

### Deleted files

| File | Reason |
|------|--------|
| `skills/copilot-pr-review/copilot-pr-review.md` | Absorbed into ship-prs + shared references |
| `commands/copilot-pr-review.md` | Command wrapper for deleted skill |

### What moves where

| Content | From | To |
|---------|------|----|
| Copilot two-system table | Inline in ship-prs, watch-prs, copilot-pr-review | `providers/github.md` |
| Reviewer list cycle | Inline in ship-prs, watch-prs, copilot-pr-review, pr-poller | `providers/github.md` |
| `[bot]` suffix rules | Inline in copilot-pr-review | `providers/github.md` |
| Provider profile blocks (GitLab, Bitbucket, Azure DevOps) | Inline in ship-prs, watch-prs | Respective `providers/*.md` files |

---

## Preference capture convention

### Shared reference: `_shared/references/preference-capture.md`

Teaches Claude to recognize declarative user statements about project preferences and persist them to `config/project.yaml`.

### Trigger patterns

| User says | Field written |
|-----------|--------------|
| "copilot reviews PRs automatically" | `pr.review_on_push: true` |
| "we squash merge everything" | `pr.merge_method: squash` |
| "releases to main use merge commits" | `pr.branches.main.merge_method: merge` |
| "we need 2 approvals on main" | `pr.branches.main.required_approvals: 2` |
| "don't auto-merge, I want to review first" | `pr.auto_merge: false` |
| "use opus for code review" | `superpowers.review_model: opus` |

### Confirm-before-write flow

```
User: "we always squash to develop"
Claude: "I'll save that as your default merge method for develop."
→ writes preferences.pr.branches.develop.merge_method: squash
→ shows: "Updated config/project.yaml — pr.branches.develop.merge_method: squash"
```

### Where things go

| Type | Destination |
|------|------------|
| Runtime preferences (reviewer, merge method, models, effort) | `config/project.yaml` |
| Development process rules (TDD, branch strategy, test conventions) | `AGENTS.md` |
| Personal preferences (communication style, response length) | Memory system |

---

## Validation skill

Project-scoped skill at `skills/validate-project-prefs/validate-project-prefs.md`.

### Checks

| Check | Pattern | Location |
|-------|---------|----------|
| Hardcoded reviewer logins | `copilot-pull-request-reviewer` outside `_shared/references/providers/` | Fail |
| Hardcoded repo detection | `gh repo view --json nameWithOwner` outside `lib/config-reader.sh` | Fail |
| Inline provider profiles | `reviewer_bot:` / `reviewer_comment_author:` blocks outside `_shared/references/providers/` and `project.yaml` | Fail |
| Missing project.yaml read | Skill mentions `--repo`, `--reviewer`, or `--merge-method` but doesn't reference `load_pr_pref` or `project.yaml` | Warn |

### Output

Pass/fail table with file:line references.

---

## AGENTS.md update

New section under **Development Guidelines**:

```markdown
### Project preferences (`config/project.yaml`)

Skills MUST read runtime defaults from `config/project.yaml` under `preferences:`.
Never hardcode reviewer logins, repo names, merge methods, or provider-specific
values in skill files.

- **Read order:** CLI flag > branch override > project default > auto-detect probe
- **Probe-and-cache:** First invocation discovers missing values and writes them
  back to project.yaml. Subsequent runs read directly.
- **Provider quirks:** Live in `skills/_shared/references/providers/<provider>.md`,
  not inline in skills.
- **Preference capture:** When a user states a project preference, confirm and
  write to project.yaml. Show the diff. Don't silently assume.
- **Validation:** Run `xgh:validate-project-prefs` to check compliance.
```

---

## Summary of changes

| Action | Files |
|--------|-------|
| **Modify** | `config/project.yaml` (add `preferences.pr`), `skills/ship-prs/ship-prs.md`, `skills/watch-prs/watch-prs.md`, `skills/review-pr/review-pr.md`, `skills/_shared/references/project-preferences.md` (add `pr` block), `AGENTS.md` |
| **Create** | `skills/_shared/references/providers/github.md`, `skills/_shared/references/providers/gitlab.md`, `skills/_shared/references/providers/bitbucket.md`, `skills/_shared/references/providers/azure-devops.md`, `skills/_shared/references/preference-capture.md`, `skills/validate-project-prefs/validate-project-prefs.md` |
| **Extend** | `lib/config-reader.sh` (add `load_pr_pref`, `probe_pr_field`, `cache_pr_pref`) |
| **Delete** | `skills/copilot-pr-review/copilot-pr-review.md`, `commands/copilot-pr-review.md` |
