# Phase 1: Foundation + Inject — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full preference read layer (`lib/preferences.sh`) with 11 domain loaders, migrate config-reader.sh, wire dead preference blocks, and complete the hook lifecycle (SessionStart + PostCompact).

**Architecture:** Three-layer system — project.yaml (desired state) -> lib/preferences.sh (read layer with domain loaders) -> hooks (lifecycle). No cache, no auto-write. Direct yq reads (~3ms).

**Tech Stack:** Bash (`set -euo pipefail`), yq (primary YAML reader), Python yaml.safe_load (fallback), jq (JSON output in hooks)

---

## Execution Waves

```
Wave 1 (parallel, no deps):     1.1 [Opus], 1.4 [Sonnet], 1.5 [Sonnet], 1.7 [Sonnet]
Wave 2 (depends on Wave 1):     1.2 [Opus], 1.3 [Sonnet]
Wave 3 (depends on Wave 2):     1.6 [Opus]
Wave 4 (depends on all):        1.8 [Sonnet]
```

---

### Task 1 (Epic 1.1): lib/preferences.sh — Core Utils + 11 Domain Loaders [Opus]

**Files:**
- Create: `lib/preferences.sh`
- Create: `tests/test-preferences.sh`
- Read: `lib/config-reader.sh` (reference for existing patterns)
- Read: `config/project.yaml` (test fixture)
- Read: `.xgh/specs/2026-03-25-declarative-preferences-lifecycle-design.md` (Section 3)

**Context:**
- The spec defines 4 core utilities: `_pref_read_yaml()`, `_pref_read_branch()`, `_pref_resolve()`, `_pref_probe_local()`
- 11 domain loaders, each with a fixed cascade (see spec Section 2)
- `_pref_read_yaml` uses yq primary, Python fallback (same pattern as `hooks/session-start-preferences.sh`)
- `load_pr_pref()` is the only loader with a probe fallback (provider only)
- Cross-domain: `load_dispatch_pref("repo")` delegates to `load_pr_pref("repo")`

- [ ] **Step 1: Write test scaffold**

Create `tests/test-preferences.sh` with assert helpers (match existing test pattern from `tests/test-config-reader.sh`). Write failing tests for:
- `_pref_read_yaml` reads a known field from project.yaml
- `_pref_read_branch` reads branch override for main merge_method
- `_pref_resolve` returns CLI override when provided
- `_pref_resolve` returns branch override when CLI empty
- `_pref_resolve` returns project default when both empty
- `load_pr_pref` full cascade (CLI > branch > default > probe)
- `load_pr_pref` provider probe returns "github" from git remote
- `load_vcs_pref` with branch override
- `load_dispatch_pref` simple 2-level cascade
- `load_dispatch_pref("repo")` delegates to pr domain
- All 11 loaders return empty string for missing fields (no errors)
- `load_scheduling_pref`, `load_notifications_pref`, `load_retrieval_pref`, `load_testing_pref` — 2-level cascade

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-preferences.sh`
Expected: All FAIL (lib/preferences.sh doesn't exist yet)

- [ ] **Step 3: Implement core utilities**

Create `lib/preferences.sh` with:

```bash
#!/usr/bin/env bash
# lib/preferences.sh — Preference read layer for all domains
# Usage: source lib/preferences.sh
#        load_pr_pref "merge_method" "$CLI_OVERRIDE" "$TARGET_BRANCH"
#        load_dispatch_pref "default_agent" "$CLI_OVERRIDE"
set -euo pipefail

_pref_project_yaml() {
  echo "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/config/project.yaml"
}

_pref_read_yaml() {
  local key="$1"
  local proj_yaml
  proj_yaml=$(_pref_project_yaml)
  [ -f "$proj_yaml" ] || return 0
  # Primary: yq
  if command -v yq >/dev/null 2>&1; then
    local val
    val=$(yq ".$key" "$proj_yaml" 2>/dev/null) || true
    if [[ -n "$val" && "$val" != "null" && "$val" != "~" ]]; then
      # Normalize booleans to lowercase
      case "$val" in true|True|TRUE) echo "true"; return;; false|False|FALSE) echo "false"; return;; esac
      echo "$val"
      return
    fi
  fi
  # Fallback: Python
  python3 -c "
import yaml, sys
key = sys.argv[1]
with open(sys.argv[2]) as f: d = yaml.safe_load(f) or {}
val = d
for k in key.split('.'):
    if isinstance(val, dict): val = val.get(k)
    else: val = None
    if val is None: break
if val is not None:
    if isinstance(val, bool): print(str(val).lower())
    else: print(val)
" "$key" "$proj_yaml" 2>/dev/null || true
}

_pref_read_branch() {
  local domain="$1" branch="$2" field="$3"
  _pref_read_yaml "preferences.$domain.branches.$branch.$field"
}

_pref_resolve() {
  local domain="$1" field="$2" cli_override="$3" branch="${4:-}"
  # Level 1: CLI override
  [[ -n "$cli_override" ]] && echo "$cli_override" && return
  # Level 2: Branch override
  if [[ -n "$branch" ]]; then
    local branch_val
    branch_val=$(_pref_read_branch "$domain" "$branch" "$field")
    [[ -n "$branch_val" ]] && echo "$branch_val" && return
  fi
  # Level 3: Project default
  local default_val
  default_val=$(_pref_read_yaml "preferences.$domain.$field")
  [[ -n "$default_val" ]] && echo "$default_val" && return
  # Level 4: caller handles (probe, etc.)
}

_pref_probe_local() {
  local field="$1"
  case "$field" in
    provider)
      local url
      url=$(git remote get-url origin 2>/dev/null) || return
      case "$url" in
        *github.com*)       echo "github" ;;
        *gitlab.com*|*gitlab.*) echo "gitlab" ;;
        *bitbucket.org*)    echo "bitbucket" ;;
        *dev.azure.com*|*visualstudio.com*) echo "azure-devops" ;;
        *)                  echo "generic" ;;
      esac ;;
  esac
}
```

- [ ] **Step 4: Implement all 11 domain loaders**

Add to `lib/preferences.sh`:

```bash
# --- Domain Loaders ---
# Each has a fixed cascade. See spec Section 2 for cascade definitions.

# PR: CLI > target_branch > default > local probe
# Contract: branch arg is target branch for PR operations, not current branch
load_pr_pref() {
  local field="$1" cli_override="${2:-}" branch="${3:-}"
  local val
  val=$(_pref_resolve "pr" "$field" "$cli_override" "$branch")
  # Probe fallback (provider only)
  if [[ -z "$val" && "$field" == "provider" ]]; then
    val=$(_pref_probe_local "provider")
  fi
  echo "$val"
}

# VCS: CLI > branch > default (uses current branch)
load_vcs_pref() {
  local field="$1" cli_override="${2:-}" branch="${3:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")}"
  _pref_resolve "vcs" "$field" "$cli_override" "$branch"
}

# Testing: CLI > branch > default (uses current branch)
load_testing_pref() {
  local field="$1" cli_override="${2:-}" branch="${3:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")}"
  _pref_resolve "testing" "$field" "$cli_override" "$branch"
}

# Dispatch: CLI > default
# Dependencies: pr.repo (for GitHub-aware agent routing)
load_dispatch_pref() {
  local field="$1" cli_override="${2:-}"
  if [[ "$field" == "repo" ]]; then
    load_pr_pref "repo" "$cli_override"
    return
  fi
  _pref_resolve "dispatch" "$field" "$cli_override"
}

# Superpowers: CLI > default
load_superpowers_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "superpowers" "$field" "$cli_override"
}

# Design: CLI > default
load_design_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "design" "$field" "$cli_override"
}

# Agents: CLI > default
load_agents_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "agents" "$field" "$cli_override"
}

# Pair Programming: CLI > default
load_pair_programming_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "pair_programming" "$field" "$cli_override"
}

# Scheduling: CLI > default
load_scheduling_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "scheduling" "$field" "$cli_override"
}

# Notifications: CLI > default
load_notifications_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "notifications" "$field" "$cli_override"
}

# Retrieval: CLI > default
load_retrieval_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "retrieval" "$field" "$cli_override"
}
```

- [ ] **Step 5: Run tests and verify they pass**

Run: `bash tests/test-preferences.sh`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add lib/preferences.sh tests/test-preferences.sh
git commit -m "feat: add lib/preferences.sh — 11 domain loaders with cascade resolution"
```

---

### Task 2 (Epic 1.4): Add New Domain Skeletons to project.yaml [Sonnet]

**Files:**
- Modify: `config/project.yaml:61-99` (preferences section)

- [ ] **Step 1: Add 5 new domain skeletons**

Add after existing `pair_programming` block and before `branches:` in `pr`:

```yaml
  vcs:
    commit_format: "<type>: <description>"
    branch_naming: "<type>/<description>"
    pr_template: ""                       # path to .github/pull_request_template.md

  scheduling:
    retrieve_interval: "30m"
    analyze_interval: "1h"
    quiet_hours: ""                       # e.g. "22:00-08:00"

  notifications:
    delivery: "inline"                    # inline | telegram | slack
    batching: false
    suppress_below: ""                    # info | warn | error

  retrieval:
    depth: "normal"                       # shallow | normal | deep
    max_age: "7d"
    context_tree_sync: true

  testing:
    timeout: "120"                        # seconds
    required_suites: []                   # e.g. [unit, integration]
    skip_rules: []
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yq . config/project.yaml > /dev/null && echo OK`
Expected: OK

- [ ] **Step 3: Run existing tests**

Run: `bash tests/test-yaml-syntax.sh && bash tests/test-config-reader.sh`
Expected: All PASS (existing tests unaffected)

- [ ] **Step 4: Commit**

```bash
git add config/project.yaml
git commit -m "feat: add vcs, scheduling, notifications, retrieval, testing domain skeletons"
```

---

### Task 3 (Epic 1.5): Hook Coexistence Contract [Sonnet]

**Files:**
- Read: `.claude/settings.json` (existing hooks)
- Create: `tests/test-hook-ordering.sh`
- Read: `.xgh/specs/2026-03-25-declarative-preferences-lifecycle-design.md` (Section 4, Hook Ordering)

**Context:**
- SessionStart: existing hooks first, preference injection LAST
- PreToolUse: preference validation FIRST, existing hooks after
- PostToolUse: existing hooks first, preference observation LAST
- Stop: existing hooks first, preference reminder LAST
- The test should validate array positions in settings.json

- [ ] **Step 1: Write ordering validation test**

Create `tests/test-hook-ordering.sh` that:
- Reads `.claude/settings.json`
- For SessionStart: asserts `session-start-preferences.sh` is the LAST hook entry
- For PreToolUse: asserts `pre-tool-use-preferences.sh` is the FIRST hook entry with `Bash` matcher
- Uses jq to parse and validate positions

- [ ] **Step 2: Run test**

Run: `bash tests/test-hook-ordering.sh`
Expected: PASS (current ordering matches convention)

- [ ] **Step 3: Commit**

```bash
git add tests/test-hook-ordering.sh
git commit -m "feat: add hook ordering validation test (coexistence contract)"
```

---

### Task 4 (Epic 1.7): Staging Area Schema + .gitignore [Sonnet]

**Files:**
- Modify: `.gitignore`
- Create: `.xgh/schemas/pending-preferences.schema.yaml`

- [ ] **Step 1: Add gitignore entry**

Add to `.gitignore`:
```
# Preference staging area (session-scoped, never committed)
.xgh/pending-preferences-*.yaml
```

- [ ] **Step 2: Create schema documentation**

Create `.xgh/schemas/pending-preferences.schema.yaml`:
```yaml
# Schema for .xgh/pending-preferences-<session-id>.yaml
# These files are gitignored and session-scoped.
# Written by Claude when it confirms a preference intent.
# Read by /xgh-save-preferences to apply changes.
#
# Example:
#   pending:
#     - domain: pr
#       field: merge_method
#       value: rebase
#       branch: main
#       timestamp: "2026-03-25T14:32:00Z"
#       source: "user statement: 'use rebase on main'"

type: object
required: [pending]
properties:
  pending:
    type: array
    items:
      type: object
      required: [domain, field, value, timestamp, source]
      properties:
        domain:
          type: string
          enum: [pr, dispatch, superpowers, design, agents, pair_programming, vcs, scheduling, notifications, retrieval, testing]
        field:
          type: string
        value:
          type: [string, number, boolean]
        branch:
          type: string
          description: "Optional — only for branch-scoped preferences"
        timestamp:
          type: string
          format: date-time
        source:
          type: string
          description: "Human-readable origin (user statement, skill detection, etc.)"
```

- [ ] **Step 3: Verify gitignore works**

Run: `touch .xgh/pending-preferences-test123.yaml && git status --porcelain .xgh/pending-preferences-test123.yaml && rm .xgh/pending-preferences-test123.yaml`
Expected: No output (file is ignored)

- [ ] **Step 4: Commit**

```bash
git add .gitignore .xgh/schemas/pending-preferences.schema.yaml
git commit -m "feat: add staging area schema and gitignore entry for pending preferences"
```

---

### Task 5 (Epic 1.2): Migrate config-reader.sh to Thin Wrapper [Opus]

**Files:**
- Modify: `lib/config-reader.sh`
- Read: `lib/preferences.sh` (must exist from Task 1)
- Test: `tests/test-config-reader.sh` (existing — must still pass)

**Context:**
- `config-reader.sh` currently has `load_pr_pref()`, `probe_pr_field()`, `cache_pr_pref()`, and `xgh_config_get()`
- After migration: `load_pr_pref` delegates to `preferences.sh`, probe/cache functions preserved for backwards compat
- `xgh_config_get()` stays (reads ingest.yaml, different file)
- The key risk: existing callers (hooks, skills) must not break

- [ ] **Step 1: Run existing tests as baseline**

Run: `bash tests/test-config-reader.sh`
Expected: All PASS

- [ ] **Step 2: Refactor config-reader.sh**

Replace the body of `load_pr_pref()` with a delegation to preferences.sh, keeping probe_pr_field and cache_pr_pref for backwards compatibility:

```bash
# Source the new preference read layer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/preferences.sh" 2>/dev/null || true

# load_pr_pref now delegates to preferences.sh
# Signature preserved: load_pr_pref "field" "cli_override" "branch"
# If preferences.sh isn't available (standalone use), fall back to inline implementation
if ! declare -F _pref_resolve >/dev/null 2>&1; then
  # ... keep existing inline implementation as fallback
fi
```

- [ ] **Step 3: Run existing tests**

Run: `bash tests/test-config-reader.sh`
Expected: All PASS (behavior preserved)

- [ ] **Step 4: Run preferences tests too**

Run: `bash tests/test-preferences.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/config-reader.sh
git commit -m "refactor: migrate config-reader.sh to thin wrapper over preferences.sh"
```

---

### Task 6 (Epic 1.3): Wire 4 Dead Preference Blocks [Sonnet]

**Files:**
- Modify: Skills that reference superpowers, design, agents, or pair_programming preferences
- Read: `config/project.yaml` (current preference values)
- Read: `lib/preferences.sh` (loader signatures)

**Context:**
- These 4 domains exist in project.yaml but no skill reads them via a loader
- Search for skills that could benefit: dispatch skill, implement skill, design skill, etc.
- The wiring is documentation + reference updates, not deep code changes
- Skills are markdown files that instruct Claude — wiring means adding "read from project.yaml" instructions

- [ ] **Step 1: Audit which skills should use each domain**

Search skills/ for references to model selection, effort levels, pairing config that could be driven by preferences.

- [ ] **Step 2: Update skills/_shared/references/project-preferences.md**

Add reference entries for all 11 domains with loader signatures and example usage.

- [ ] **Step 3: Verify no test regressions**

Run: `bash tests/test-skills.sh`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add skills/
git commit -m "feat: wire superpowers, design, agents, pair_programming preference loaders into skills"
```

---

### Task 7 (Epic 1.6): Refactor SessionStart + Add PostCompact Hook [Opus]

**Files:**
- Modify: `hooks/session-start-preferences.sh`
- Create: `hooks/post-compact-preferences.sh`
- Modify: `.claude/settings.json` (add PostCompact hook)
- Create: `tests/test-post-compact-preferences.sh`
- Read: `lib/preferences.sh` (use loaders instead of inline reads)

**Context:**
- Current session-start-preferences.sh has inline yq/Python YAML reading
- Refactor to source lib/preferences.sh and use domain loaders
- PostCompact hook re-resolves preferences for current branch (user may have switched)
- PostCompact output format same as SessionStart (additionalContext with preference index)
- PostCompact matcher: "manual|auto"
- Position: LAST in PostCompact array (coexistence contract)

- [ ] **Step 1: Write PostCompact test**

Create `tests/test-post-compact-preferences.sh` with tests matching session-start pattern.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-post-compact-preferences.sh`
Expected: FAIL (hook doesn't exist)

- [ ] **Step 3: Create PostCompact hook**

Create `hooks/post-compact-preferences.sh` — similar to session-start but:
- Re-reads project.yaml fresh (no cache)
- Re-detects current branch
- Same output format (additionalContext)

- [ ] **Step 4: Refactor SessionStart to use preferences.sh**

Simplify `hooks/session-start-preferences.sh` to share code with PostCompact via a shared builder function, or at minimum use `_pref_read_yaml` instead of inline Python.

- [ ] **Step 5: Register PostCompact hook in settings.json**

Add to `.claude/settings.json`:
```json
"PostCompact": [{
  "matcher": "manual|auto",
  "hooks": [{
    "type": "command",
    "command": "bash /path/to/hooks/post-compact-preferences.sh"
  }]
}]
```

- [ ] **Step 6: Run all preference tests**

Run: `bash tests/test-session-start-preferences.sh && bash tests/test-post-compact-preferences.sh`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add hooks/session-start-preferences.sh hooks/post-compact-preferences.sh .claude/settings.json tests/test-post-compact-preferences.sh
git commit -m "feat: refactor SessionStart + add PostCompact preference re-injection hook"
```

---

### Task 8 (Epic 1.8): Update validate-project-prefs [Sonnet]

**Files:**
- Modify: `skills/validate-project-prefs/validate-project-prefs.md`
- Read: `lib/preferences.sh` (all loader names)
- Read: `.claude/settings.json` (hook ordering to validate)

**Context:**
- Current skill only checks PR domain (4 grep patterns)
- Expand to audit all 11 domains: check that skills use loaders, not hardcoded values
- Add hook ordering validation: check SessionStart LAST, PreToolUse FIRST, etc.
- Add cross-domain dependency check

- [ ] **Step 1: Expand checks to all 11 domains**

Add grep patterns for each domain's common hardcoded values.

- [ ] **Step 2: Add hook ordering audit**

Check settings.json for correct hook positions per coexistence contract.

- [ ] **Step 3: Verify skill runs**

Run the skill manually and check output format.

- [ ] **Step 4: Commit**

```bash
git add skills/validate-project-prefs/validate-project-prefs.md
git commit -m "feat: expand validate-project-prefs to audit all 11 domains + hook ordering"
```
