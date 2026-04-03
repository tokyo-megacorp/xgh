# Project Preferences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize PR workflow preferences in `config/project.yaml` so skills read defaults instead of hardcoding or re-probing every invocation.

**Architecture:** Extend `lib/config-reader.sh` with `load_pr_pref` / `probe_pr_field` / `cache_pr_pref` functions. Add `preferences.pr` block to `project.yaml`. Update ship-prs, watch-prs, review-pr skills to consume it. Extract provider quirks to shared references. Delete copilot-pr-review (absorbed). Add validation skill.

**Tech Stack:** Bash, Python 3 (PyYAML), YAML, Markdown

**Spec:** `.xgh/specs/2026-03-25-project-preferences-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `lib/config-reader.sh` | Add `load_pr_pref`, `probe_pr_field`, `cache_pr_pref` |
| Modify | `config/project.yaml` | Add `preferences.pr` section |
| Modify | `skills/ship-prs/ship-prs.md` | Replace Step 0a/0c with `load_pr_pref`, remove copilot-pr-review integration section, replace inline provider profiles with shared refs |
| Modify | `skills/watch-prs/watch-prs.md` | Replace Step 0a/0c with `load_pr_pref`, replace inline provider profiles with shared refs |
| Modify | `skills/review-pr/review-pr.md` | Use `load_pr_pref repo` for repo detection |
| Modify | `agents/pr-poller.md` | Document that it receives pre-resolved values (no direct project.yaml reads) |
| Modify | `skills/_shared/references/project-preferences.md` | Add `pr` domain to preference table, add per-domain cascade note |
| Create | `skills/_shared/references/providers/github.md` | Copilot two-system distinction, never-approves, reviewer list cycle, [bot] rules |
| Create | `skills/_shared/references/providers/gitlab.md` | MR reviewers, approval rules |
| Create | `skills/_shared/references/providers/bitbucket.md` | PR reviewers, default reviewers |
| Create | `skills/_shared/references/providers/azure-devops.md` | Required reviewers, policies |
| Create | `skills/_shared/references/preference-capture.md` | Convention for persisting user preference statements to project.yaml |
| Create | `skills/validate-project-prefs/validate-project-prefs.md` | Validation skill — checks hardcoded values, missing project.yaml reads |
| Create | `commands/validate-project-prefs.md` | Thin command wrapper |
| Delete | `skills/copilot-pr-review/copilot-pr-review.md` | Absorbed into ship-prs + shared references |
| Delete | `commands/copilot-pr-review.md` | Command wrapper for deleted skill |
| Modify | `config/team.yaml` | Add project preferences pitfall |
| Modify | `tests/test-config.sh` | Remove copilot-pr-review assertions, add project.yaml `preferences.pr` assertions, add validate-project-prefs assertions |
| Modify | `tests/test-skills.sh` | Add validate-project-prefs skill assertions |
| Create | `tests/test-config-reader.sh` | Unit tests for `load_pr_pref` / `probe_pr_field` / `cache_pr_pref` |

---

## Task 1: Add `preferences.pr` to project.yaml + tests

**Files:**
- Modify: `config/project.yaml`
- Modify: `tests/test-config.sh`

- [ ] **Step 1: Write failing tests**

Add to `tests/test-config.sh` after the existing `preferences:` assertions (line ~94):

```bash
# --- preferences.pr section ---
assert_contains "config/project.yaml" "pr:"
assert_contains "config/project.yaml" "provider: github"
assert_contains "config/project.yaml" "repo: tokyo-megacorp/xgh"
assert_contains "config/project.yaml" "copilot-pull-request-reviewer\[bot\]"
assert_contains "config/project.yaml" "reviewer_comment_author: Copilot"
assert_contains "config/project.yaml" "merge_method: squash"
assert_contains "config/project.yaml" "review_on_push: true"
assert_contains "config/project.yaml" "auto_merge: true"
assert_contains "config/project.yaml" "branches:"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-config.sh`
Expected: FAIL on `pr:` and related assertions

- [ ] **Step 3: Add preferences.pr section to project.yaml**

Insert after the existing `preferences:` block (after `agents:` section, before `implementation_status:`):

```yaml
  pr:
    provider: github
    repo: tokyo-megacorp/xgh
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

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-config.sh`
Expected: All pass including new assertions

- [ ] **Step 5: Commit**

```bash
git add config/project.yaml tests/test-config.sh
git commit -m "feat: add preferences.pr section to project.yaml"
```

---

## Task 2: Extend config-reader.sh with PR preference helpers

**Files:**
- Modify: `lib/config-reader.sh`
- Create: `tests/test-config-reader.sh`

- [ ] **Step 1: Write failing tests**

Create `tests/test-config-reader.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_equals() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 missing '$2'"
    FAIL=$((FAIL + 1))
  fi
}

# --- Source the library ---
assert_contains "lib/config-reader.sh" "load_pr_pref"
assert_contains "lib/config-reader.sh" "probe_pr_field"
assert_contains "lib/config-reader.sh" "cache_pr_pref"

# --- Functional tests using real project.yaml ---
source lib/config-reader.sh

# CLI override wins
result=$(load_pr_pref "provider" "gitlab" "")
assert_equals "CLI override wins" "gitlab" "$result"

# Project default (no CLI override, no branch)
result=$(load_pr_pref "provider" "" "")
assert_equals "Project default: provider" "github" "$result"

result=$(load_pr_pref "repo" "" "")
assert_equals "Project default: repo" "tokyo-megacorp/xgh" "$result"

result=$(load_pr_pref "reviewer" "" "")
assert_equals "Project default: reviewer" "copilot-pull-request-reviewer[bot]" "$result"

result=$(load_pr_pref "reviewer_comment_author" "" "")
assert_equals "Project default: reviewer_comment_author" "Copilot" "$result"

result=$(load_pr_pref "merge_method" "" "")
assert_equals "Project default: merge_method" "squash" "$result"

# Branch-specific override
result=$(load_pr_pref "merge_method" "" "main")
assert_equals "Branch override: main merge_method" "merge" "$result"

result=$(load_pr_pref "merge_method" "" "develop")
assert_equals "Branch override: develop merge_method" "squash" "$result"

# CLI override beats branch override
result=$(load_pr_pref "merge_method" "rebase" "main")
assert_equals "CLI beats branch" "rebase" "$result"

# Branch override for non-merge_method field
result=$(load_pr_pref "required_approvals" "" "main")
assert_equals "Branch override: main required_approvals" "1" "$result"

# Boolean field (review_on_push)
result=$(load_pr_pref "review_on_push" "" "")
assert_equals "Boolean field: review_on_push" "true" "$result"

# Unset field returns empty (skills must provide their own fallback)
result=$(load_pr_pref "nonexistent_field" "" "")
assert_equals "Unset field returns empty" "" "$result"

echo ""
echo "Config reader test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-config-reader.sh`
Expected: FAIL on `load_pr_pref` (function not defined)

- [ ] **Step 3: Implement the functions**

Add to `lib/config-reader.sh` after the existing `xgh_config_get` function:

```bash
# --- Project-level PR preference helpers ---
# Read order: CLI flag > branch override > project default > auto-detect probe
# See spec: .xgh/specs/2026-03-25-project-preferences-design.md

_project_yaml() {
  echo "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/config/project.yaml"
}

load_pr_pref() {
  local field="$1" cli_override="${2:-}" branch="${3:-}"

  # 1. CLI flag wins
  [[ -n "$cli_override" ]] && echo "$cli_override" && return

  local proj_yaml
  proj_yaml=$(_project_yaml)
  [ -f "$proj_yaml" ] || { probe_pr_field "$field"; return; }
  if ! python3 -c "import yaml" 2>/dev/null; then probe_pr_field "$field"; return; fi

  # 2. Branch-specific override
  if [[ -n "$branch" ]]; then
    local val
    val=$(python3 -c "
import yaml, sys
field, branch = sys.argv[1], sys.argv[2]
with open(sys.argv[3]) as f: d = yaml.safe_load(f) or {}
v = (d.get('preferences',{}).get('pr',{}).get('branches',{}).get(branch,{}).get(field))
if v is not None: print(str(v).lower() if isinstance(v, bool) else v)
" "$field" "$branch" "$proj_yaml" 2>/dev/null)
    [[ -n "$val" ]] && echo "$val" && return
  fi

  # 3. Project default
  local val
  val=$(python3 -c "
import yaml, sys
field = sys.argv[1]
with open(sys.argv[2]) as f: d = yaml.safe_load(f) or {}
v = (d.get('preferences',{}).get('pr',{}).get(field))
if v is not None: print(str(v).lower() if isinstance(v, bool) else v)
" "$field" "$proj_yaml" 2>/dev/null)
  [[ -n "$val" ]] && echo "$val" && return

  # 4. Probe, cache, return
  val=$(probe_pr_field "$field")
  [[ -n "$val" ]] && cache_pr_pref "$field" "$val"
  echo "$val"
}

probe_pr_field() {
  # Dependency chain: provider → repo → reviewer → reviewer_comment_author
  # Each probe may call load_pr_pref for upstream fields. If an upstream probe
  # fails (e.g., no gh CLI), downstream probes silently return empty.
  local field="$1"
  case "$field" in
    provider)
      local url
      url=$(git remote get-url origin 2>/dev/null) || return
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
          local enabled
          enabled=$(gh api "repos/$repo/copilot/policies" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code_review_enabled', d.get('copilot_code_review',{}).get('enabled','false')))" 2>/dev/null)
          [[ "${enabled,,}" == "true" ]] && echo "copilot-pull-request-reviewer[bot]" ;;
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
  local proj_yaml
  proj_yaml=$(_project_yaml)
  [ -f "$proj_yaml" ] || return
  python3 -c "import yaml" 2>/dev/null || { echo "PyYAML not installed; preference write disabled" >&2; return; }
  python3 -c "
import yaml, sys
field, value = sys.argv[1], sys.argv[2]
with open(sys.argv[3]) as f: d = yaml.safe_load(f) or {}
d.setdefault('preferences',{}).setdefault('pr',{})[field] = value
with open(sys.argv[3],'w') as f: yaml.dump(d, f, default_flow_style=False, sort_keys=False)
" "$field" "$value" "$proj_yaml" 2>/dev/null
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-config-reader.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/config-reader.sh tests/test-config-reader.sh
git commit -m "feat: add load_pr_pref / probe_pr_field / cache_pr_pref to config-reader.sh"
```

---

## Task 3: Create shared provider references

**Files:**
- Create: `skills/_shared/references/providers/github.md`
- Create: `skills/_shared/references/providers/gitlab.md`
- Create: `skills/_shared/references/providers/bitbucket.md`
- Create: `skills/_shared/references/providers/azure-devops.md`
- Modify: `tests/test-config.sh`

- [ ] **Step 1: Write failing tests**

Add to `tests/test-config.sh`:

```bash
# --- Provider references ---
assert_file_exists "skills/_shared/references/providers/github.md"
assert_file_exists "skills/_shared/references/providers/gitlab.md"
assert_file_exists "skills/_shared/references/providers/bitbucket.md"
assert_file_exists "skills/_shared/references/providers/azure-devops.md"
assert_contains "skills/_shared/references/providers/github.md" "copilot-pull-request-reviewer"
assert_contains "skills/_shared/references/providers/github.md" "never approves"
assert_contains "skills/_shared/references/providers/github.md" "reviewer list cycle"
assert_contains "skills/_shared/references/providers/github.md" "SWE Delegation"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-config.sh`
Expected: FAIL on provider reference files

- [ ] **Step 3: Create github.md**

Create `skills/_shared/references/providers/github.md` with content from the spec's "GitHub Copilot review behavior" section. Include:
- Copilot never-approves behavior
- Every comment must be addressed (accept with commit URL or reject with reasoning)
- Merge-ready criteria (review exists + all comments replied + no CHANGES_REQUESTED)
- Two Copilot systems table (Code Review vs SWE Delegation)
- Reviewer list cycle (the only safe re-request method)
- `[bot]` suffix rules (REST needs it, GraphQL/`gh pr edit` doesn't)
- `reviewer` vs `reviewer_comment_author` mapping
- `review_on_push` behavior

- [ ] **Step 4: Create gitlab.md, bitbucket.md, azure-devops.md**

Minimal stubs with provider name, reviewer assignment patterns, and API notes. These are frameworks for future support per the spec.

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-config.sh`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add skills/_shared/references/providers/ tests/test-config.sh
git commit -m "feat: add shared provider references (github, gitlab, bitbucket, azure-devops)"
```

---

## Task 4: Create preference-capture reference

**Files:**
- Create: `skills/_shared/references/preference-capture.md`
- Modify: `skills/_shared/references/project-preferences.md`

- [ ] **Step 1: Write failing test**

Add to `tests/test-config.sh`:

```bash
assert_file_exists "skills/_shared/references/preference-capture.md"
assert_contains "skills/_shared/references/preference-capture.md" "config/project.yaml"
assert_contains "skills/_shared/references/preference-capture.md" "confirm"
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Create preference-capture.md**

Content per spec: trigger patterns table, confirm-before-write flow, "where things go" routing table (runtime prefs → project.yaml, process rules → AGENTS.md, personal prefs → memory).

- [ ] **Step 4: Update project-preferences.md**

Add `pr` domain to the preference blocks table:

```markdown
| `pr` | `provider`, `repo`, `reviewer`, `reviewer_comment_author`, `merge_method`, `review_on_push`, `auto_merge`, `branches` | `/xgh-ship-prs`, `/xgh-watch-prs`, `/xgh-review-pr` |
```

Add per-domain cascade note: "Each preference domain defines its own priority order. The `pr` domain uses: CLI flag > `branches.<base_ref>.<field>` > `preferences.pr.<field>` > auto-detect probe."

- [ ] **Step 5: Run test to verify it passes**

- [ ] **Step 6: Commit**

```bash
git add skills/_shared/references/preference-capture.md skills/_shared/references/project-preferences.md tests/test-config.sh
git commit -m "feat: add preference-capture convention and update project-preferences reference"
```

---

## Task 5: Update ship-prs to read from project.yaml

**Files:**
- Modify: `skills/ship-prs/ship-prs.md`

- [ ] **Step 1: Write failing test**

Add to `tests/test-skills.sh`:

```bash
# --- ship-prs reads project.yaml ---
assert_contains "skills/ship-prs/ship-prs.md" "load_pr_pref"
assert_contains "skills/ship-prs/ship-prs.md" "project.yaml"
assert_contains "skills/ship-prs/ship-prs.md" "providers/github.md"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-skills.sh`

- [ ] **Step 3: Update ship-prs.md**

Replace **Step 0a** (detect repo) with:
```
### Step 0a — Load preferences from project.yaml

Source `lib/config-reader.sh` for `load_pr_pref`.

```bash
REPO=$(load_pr_pref repo "$CLI_REPO" "")
PROVIDER=$(load_pr_pref provider "" "")
REVIEWER=$(load_pr_pref reviewer "$CLI_REVIEWER" "")
REVIEWER_COMMENT_AUTHOR=$(load_pr_pref reviewer_comment_author "" "")
MERGE_METHOD=$(load_pr_pref merge_method "$CLI_MERGE_METHOD" "$BASE_BRANCH")
MERGE_METHOD="${MERGE_METHOD:-squash}"  # fallback — merge_method is not probed
```

Replace **Step 0b/0c** (detect provider, probe reviewer) — the cascade in `load_pr_pref` handles this.

Replace inline **Provider Profiles** section with reference:
```
See `@references/providers/github.md` for GitHub Copilot quirks, reviewer list cycle, and [bot] suffix rules.
```

Remove **"Integration with xgh:copilot-pr-review"** section (lines 593–611) — dead reference after deletion.

Replace **Section D** merge criteria line 4 (`state == APPROVED`) with the Copilot-never-approves rule:
```
4. At least one review from `<reviewer>` exists (Copilot never approves — see @references/providers/github.md)
5. All inline comments from `<reviewer_comment_author>` have been replied to
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-skills.sh`

- [ ] **Step 5: Commit**

```bash
git add skills/ship-prs/ship-prs.md tests/test-skills.sh
git commit -m "feat: ship-prs reads PR preferences from project.yaml"
```

---

## Task 6: Update watch-prs to read from project.yaml

**Files:**
- Modify: `skills/watch-prs/watch-prs.md`

- [ ] **Step 1: Write failing test**

Add to `tests/test-skills.sh`:

```bash
# --- watch-prs reads project.yaml ---
assert_contains "skills/watch-prs/watch-prs.md" "load_pr_pref"
assert_contains "skills/watch-prs/watch-prs.md" "project.yaml"
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Update watch-prs.md**

Same pattern as ship-prs: replace Step 0a/0b/0c with `load_pr_pref` calls. Replace inline provider profiles with shared references.

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add skills/watch-prs/watch-prs.md tests/test-skills.sh
git commit -m "feat: watch-prs reads PR preferences from project.yaml"
```

---

## Task 7: Update review-pr to use load_pr_pref

**Files:**
- Modify: `skills/review-pr/review-pr.md`

- [ ] **Step 1: Write failing test**

Add to `tests/test-skills.sh`:

```bash
assert_contains "skills/review-pr/review-pr.md" "project.yaml"
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Update review-pr.md**

Replace any inline `gh repo view --json nameWithOwner` with `load_pr_pref repo`. Add note that repo is read from project.yaml via `load_pr_pref`.

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add skills/review-pr/review-pr.md tests/test-skills.sh
git commit -m "feat: review-pr reads repo from project.yaml"
```

---

## Task 8: Delete copilot-pr-review skill + command

**Files:**
- Delete: `skills/copilot-pr-review/copilot-pr-review.md`
- Delete: `commands/copilot-pr-review.md`
- Modify: `tests/test-config.sh` (remove copilot-pr-review assertions, lines 31-34 and 66-68)

- [ ] **Step 1: Update tests to remove copilot-pr-review assertions**

Remove from `tests/test-config.sh`:
```bash
# --- copilot-pr-review: command + skill registration ---
assert_file_exists "commands/copilot-pr-review.md"
assert_file_exists "skills/copilot-pr-review/copilot-pr-review.md"
assert_contains "commands/copilot-pr-review.md" "copilot-pr-review"
```

And remove the skill-triggering prompt assertions:
```bash
assert_file_exists "tests/skill-triggering/prompts/copilot-pr-review.txt"
assert_file_exists "tests/skill-triggering/prompts/copilot-pr-review-2.txt"
assert_file_exists "tests/skill-triggering/prompts/copilot-pr-review-3.txt"
```

- [ ] **Step 2: Run test to verify old assertions are gone**

Run: `bash tests/test-config.sh`
Expected: pass (assertions removed, files still exist)

- [ ] **Step 3: Delete the files**

```bash
git rm skills/copilot-pr-review/copilot-pr-review.md
git rm commands/copilot-pr-review.md
git rm tests/skill-triggering/prompts/copilot-pr-review.txt
git rm tests/skill-triggering/prompts/copilot-pr-review-2.txt
git rm tests/skill-triggering/prompts/copilot-pr-review-3.txt
```

- [ ] **Step 4: Run full test suite**

Run: `bash tests/test-config.sh && bash tests/test-skills.sh && bash tests/test-multi-agent.sh && bash tests/test-file-refs.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add tests/test-config.sh
git commit -m "feat: delete copilot-pr-review — absorbed into ship-prs + shared provider references"
```

---

## Task 9: Create validate-project-prefs skill + command

**Files:**
- Create: `skills/validate-project-prefs/validate-project-prefs.md`
- Create: `commands/validate-project-prefs.md`
- Modify: `tests/test-config.sh`
- Modify: `tests/test-skills.sh`

- [ ] **Step 1: Write failing tests**

Add to `tests/test-config.sh`:

```bash
# --- validate-project-prefs ---
assert_file_exists "commands/validate-project-prefs.md"
assert_file_exists "skills/validate-project-prefs/validate-project-prefs.md"
assert_contains "commands/validate-project-prefs.md" "validate-project-prefs"
```

Add to `tests/test-skills.sh`:

```bash
assert_file_exists "skills/validate-project-prefs/validate-project-prefs.md"
assert_contains "skills/validate-project-prefs/validate-project-prefs.md" "xgh:validate-project-prefs"
assert_contains "skills/validate-project-prefs/validate-project-prefs.md" "project.yaml"
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Create the skill**

`skills/validate-project-prefs/validate-project-prefs.md` — full content:

```markdown
---
name: xgh:validate-project-prefs
description: "Use when checking that skills read PR workflow values from config/project.yaml instead of hardcoding reviewer logins, repo names, or merge methods."
---

# xgh:validate-project-prefs — Preference Compliance Checker

Scan skill files for hardcoded PR workflow values that should be read from `config/project.yaml`.

## Checks

Run these grep patterns against `skills/` (excluding `_shared/references/providers/` and this skill):

### 1. Hardcoded reviewer logins

```bash
grep -rn "copilot-pull-request-reviewer" skills/ --include="*.md" \
  | grep -v "_shared/references/providers/" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches. **Fail:** list file:line for each match.

### 2. Hardcoded repo detection

```bash
grep -rn "gh repo view --json nameWithOwner" skills/ --include="*.md" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches (should use `load_pr_pref repo`). **Fail:** list file:line.

### 3. Inline provider profiles

```bash
grep -rn "reviewer_bot:" skills/ --include="*.md" \
  | grep -v "_shared/references/providers/" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches. **Fail:** list file:line.

### 4. Missing project.yaml read (warning only)

For skills that mention `--repo`, `--reviewer`, or `--merge-method` in their usage:
```bash
for skill in skills/ship-prs/ship-prs.md skills/watch-prs/watch-prs.md skills/review-pr/review-pr.md; do
  if ! grep -q "load_pr_pref\|project\.yaml" "$skill"; then
    echo "WARN: $skill mentions PR flags but does not reference load_pr_pref or project.yaml"
  fi
done
```

## Output format

| Check | Status | Details |
|-------|--------|---------|
| Hardcoded reviewer logins | ✅ / ❌ | file:line matches |
| Hardcoded repo detection | ✅ / ❌ | file:line matches |
| Inline provider profiles | ✅ / ❌ | file:line matches |
| Missing project.yaml read | ✅ / ⚠️ | skill files without reference |
```

- [ ] **Step 4: Create the command wrapper**

`commands/validate-project-prefs.md`:
```markdown
---
name: validate-project-prefs
description: "Validate that skills read from config/project.yaml instead of hardcoding PR workflow values"
usage: "/xgh-validate-project-prefs"
---

# /xgh-validate-project-prefs

Run the `xgh:validate-project-prefs` skill.
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-config.sh && bash tests/test-skills.sh`

- [ ] **Step 6: Commit**

```bash
git add skills/validate-project-prefs/ commands/validate-project-prefs.md tests/test-config.sh tests/test-skills.sh
git commit -m "feat: add validate-project-prefs skill and command"
```

---

## Task 10: Update AGENTS.md and team.yaml

**Files:**
- Modify: `config/team.yaml`

- [ ] **Step 1: Write failing test**

Add to `tests/test-config.sh`:

```bash
assert_contains "config/team.yaml" "project.yaml"
assert_contains "config/team.yaml" "preferences"
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Update team.yaml**

Add to `conventions.skills`:
```yaml
    - "Skills MUST read runtime defaults from `config/project.yaml` under `preferences:`. Never hardcode reviewer logins, repo names, merge methods, or provider-specific values in skill files."
```

Add to `pitfalls`:
```yaml
  - title: "Hardcoded PR workflow values in skills"
    body: "Skills must use `load_pr_pref` from `lib/config-reader.sh` to read reviewer, repo, merge method from `config/project.yaml`. Never hardcode `copilot-pull-request-reviewer` or repo slugs in skill markdown."
```

- [ ] **Step 4: Regenerate AGENTS.md**

```bash
bash scripts/gen-agents-md.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-config.sh`

- [ ] **Step 6: Commit**

```bash
git add config/team.yaml AGENTS.md
git commit -m "docs: add project preferences convention to team.yaml and regenerate AGENTS.md"
```

---

## Task 11: Final verification

- [ ] **Step 1: Run all 5 test suites**

```bash
bash tests/test-config.sh
bash tests/test-skills.sh
bash tests/test-multi-agent.sh
bash tests/test-file-refs.sh
bash tests/test-config-reader.sh
```

All must pass.

**CI integration:** Check if `.github/workflows/` has a CI config that lists test files explicitly. If so, add `bash tests/test-config-reader.sh` to it. If CI auto-discovers `tests/test-*.sh`, no change needed.

- [ ] **Step 2: Verify no hardcoded values remain**

```bash
# Should only match providers/github.md and project.yaml, not skill files
grep -r "copilot-pull-request-reviewer" skills/ --include="*.md" \
  | grep -v "_shared/references/providers/" \
  | grep -v "validate-project-prefs"
```

Expected: no matches (ship-prs/watch-prs now reference shared refs, not hardcoded values)

- [ ] **Step 3: Update spec status**

Change spec status from `Draft` to `Implemented` in `.xgh/specs/2026-03-25-project-preferences-design.md`.

- [ ] **Step 4: Commit**

```bash
git add .xgh/specs/2026-03-25-project-preferences-design.md
git commit -m "docs: mark project-preferences spec as implemented"
```
