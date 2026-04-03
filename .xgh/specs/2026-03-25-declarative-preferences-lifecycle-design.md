# Declarative Preferences with Explicit Convergence

> project.yaml as desired state. Hooks as the lifecycle. Convergence always explicit.

**Date:** 2026-03-25
**Status:** Approved
**Scope:** Full preference lifecycle system for xgh

---

## 1. Core Architecture

### Mental Model

project.yaml is the single source of truth for project preferences. The system follows a **declare → observe → converge** cycle, where convergence is always explicit (user-initiated), never automatic.

### Three Layers

```
┌─────────────────────────────────────┐
│  config/project.yaml                │  ← Desired state (checked-in, user-owned)
├─────────────────────────────────────┤
│  lib/preferences.sh                 │  ← Read layer (domain loaders + shared utils)
├─────────────────────────────────────┤
│  hooks/*                            │  ← Lifecycle layer (inject, validate, observe, suggest)
└─────────────────────────────────────┘
```

| Layer | Responsibility | Does NOT do |
|-------|---------------|-------------|
| **project.yaml** | Declares preferences across all domains | Execute, enforce, or probe |
| **preferences.sh** | Reads YAML, resolves cascades, returns values | Write back, cache, or modify state |
| **hooks** | Inject context, validate actions, observe drift, suggest saves | Auto-write to project.yaml |

### Key Constraints

- **No hook ever writes to project.yaml.** The only write path is the explicit `/xgh-save-preferences` skill.
- **No session cache.** YAML parsing is ~3ms via yq. Direct reads on every call.
- **Permission inheritance.** `/xgh-save-preferences` uses the Edit tool, which inherits the session's permission mode (default/auto/bypass).

---

## 2. project.yaml Schema

### Structure

The file has two zones:

**Project metadata** (root level) — not preference domains:
- `name`, `tagline`, `emoji`, `description`, `install`
- `tech_stack`, `key_design_decisions`, `implementation_status`

**Preference domains** (under `preferences:`) — consumed by the lifecycle system:

### Preference Domains

| Domain | Purpose | Cascade |
|--------|---------|---------|
| `pr` | PR workflow (repo, provider, reviewer, merge method) | CLI > target_branch > default > local probe |
| `dispatch` | Agent routing (default agent, effort levels) | CLI > default |
| `superpowers` | Agent effort/model config | CLI > default |
| `design` | Design task settings | CLI > default |
| `agents` | Default model fallback | CLI > default |
| `pair_programming` | Pairing config | CLI > default |
| `vcs` | Commit format, branch naming, PR templates | CLI > branch > default |
| `scheduling` | Poll intervals, cron timing, quiet hours | CLI > default |
| `notifications` | Delivery channels, batching, suppression | CLI > default |
| `retrieval` | Depth, max age, context tree sync | CLI > default |
| `testing` | Timeouts, required suites, skip rules | CLI > branch > default |

### Cascade Definitions

Each domain has a **fixed cascade** — no runtime metadata, no self-declaration.

**4-level cascade** (pr only):
```
CLI flag → target branch override → project default → local probe
```

**3-level cascade** (vcs, testing):
```
CLI flag → branch override → project default
```

**2-level cascade** (all others):
```
CLI flag → project default
```

### Branch Overrides

Any field within a branch-aware domain can appear under `branches.<ref>`:

```yaml
preferences:
  pr:
    merge_method: squash          # project default
    branches:
      main:
        merge_method: merge       # override for main
        required_approvals: 1
      develop:
        merge_method: squash
```

**Branch resolution:** For PR operations, the caller provides the **target branch** (PR base), not the current checked-out branch. For non-PR operations (vcs, testing), the current branch is used.

### Cross-Domain Dependencies

Domains may read from other domains via their loader functions. Dependencies are documented in the function header:

```bash
load_dispatch_pref() {
  # Dependencies: pr.repo (for GitHub-aware agent routing)
  ...
}
```

The `validate-project-prefs` skill audits these dependencies.

### Local Probe

Only `pr.provider` has a local probe (git remote URL parse). All other probed values (repo, reviewer, reviewer_comment_author) are populated by `/xgh-init` or `/xgh-track`, not at runtime.

The probe sits at the bottom of the cascade — it only fires when no CLI flag, branch override, or project default is set.

---

## 3. lib/preferences.sh — The Read Layer

### Replaces

`lib/config-reader.sh`, which becomes a thin wrapper for backwards compatibility.

### Structure

```
lib/preferences.sh
├── Core utilities (shared by all domains)
│   ├── _pref_read_yaml()      — read a field from project.yaml via yq (Python fallback)
│   ├── _pref_read_branch()    — read a branch-override field
│   ├── _pref_resolve()        — walk a cascade, return first non-empty value
│   └── _pref_probe_local()    — run local-only probes (git remote parse)
│
├── Domain loaders (one per domain, fixed cascade)
│   ├── load_pr_pref()         — CLI > target_branch > default > local probe
│   ├── load_vcs_pref()        — CLI > branch > default
│   ├── load_testing_pref()    — CLI > branch > default
│   ├── load_dispatch_pref()   — CLI > default
│   ├── load_superpowers_pref()— CLI > default
│   ├── load_design_pref()     — CLI > default
│   ├── load_agents_pref()     — CLI > default
│   ├── load_pair_programming_pref()    — CLI > default
│   ├── load_scheduling_pref() — CLI > default
│   ├── load_notifications_pref() — CLI > default
│   └── load_retrieval_pref()  — CLI > default
│
└── Cross-domain convention
    # Any loader may call another domain's loader
    # Dependencies declared in function header comment
```

### Core: `_pref_resolve()`

```bash
_pref_resolve() {
  local domain="$1" field="$2" cli_override="$3" branch="${4:-}"

  # Level 1: CLI override (always wins)
  [[ -n "$cli_override" ]] && echo "$cli_override" && return

  # Level 2: Branch override (if branch provided)
  if [[ -n "$branch" ]]; then
    local branch_val
    branch_val=$(_pref_read_branch "$domain" "$branch" "$field")
    [[ -n "$branch_val" ]] && echo "$branch_val" && return
  fi

  # Level 3: Project default
  local default_val
  default_val=$(_pref_read_yaml "preferences.$domain.$field")
  [[ -n "$default_val" ]] && echo "$default_val" && return

  # Level 4: handled by caller (e.g., load_pr_pref calls _pref_probe_local)
  # _pref_resolve does NOT probe — the caller decides if/how to probe.
}
```

### Loader Templates

**Simple (CLI > default):**
```bash
load_scheduling_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "scheduling" "$field" "$cli_override"
}
```

**With branch (CLI > branch > default):**
```bash
load_vcs_pref() {
  local field="$1" cli_override="${2:-}" branch="${3:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")}"
  _pref_resolve "vcs" "$field" "$cli_override" "$branch"
}
```

**With probe (CLI > target_branch > default > probe):**

**Contract:** Callers MUST pass `target_branch` for PR operations. Omitting it silently skips branch overrides — the most common source of wrong merge methods. For convenience, skills can detect the target via `gh pr view --json baseRefName -q .baseRefName 2>/dev/null`.

```bash
load_pr_pref() {
  # Contract: branch arg is REQUIRED for PR operations (target branch, not current)
  local field="$1" cli_override="${2:-}" branch="${3:-}"
  local val
  val=$(_pref_resolve "pr" "$field" "$cli_override" "$branch")

  # Probe fallback (only for provider)
  if [[ -z "$val" && "$field" == "provider" ]]; then
    val=$(_pref_probe_local "provider")
  fi

  echo "$val"
}
```

### Cross-Domain Example

```bash
load_dispatch_pref() {
  # Dependencies: pr.repo (for GitHub-aware agent routing)
  local field="$1" cli_override="${2:-}"

  if [[ "$field" == "repo" ]]; then
    load_pr_pref "repo" "$cli_override"
    return
  fi

  _pref_resolve "dispatch" "$field" "$cli_override"
}
```

### YAML Reader

Primary: `yq` (single binary, ~2ms per key lookup, no interpreter startup).
Fallback: Python `yaml.safe_load()` (~50ms with interpreter startup).

Non-git contexts (no repo root): loaders return empty string. Callers handle the absence.

**Malformed YAML handling:** If project.yaml exists but is unparseable, `_pref_read_yaml` returns empty string and SessionStart injects a warning: `[xgh] WARNING: config/project.yaml has syntax errors — preferences disabled this session. Run 'yq . config/project.yaml' to diagnose.` This warning fires once per session.

---

## 4. Hook Lifecycle

### Lifecycle Diagram

```
Session Start ──→ User Prompt ──→ Tool Execution ──→ Turn End
     │                │              │        │          │
 [plan/inject]   [capture]    [validate] [observe]  [suggest]
     │                │              │        │          │
SessionStart  UserPromptSubmit  PreToolUse  PostToolUse  Stop
                              PermReq    PostToolUseFail

             ── Compaction ──
             │              │
         (dropped)     [re-inject]
                       PostCompact
```

### Hook Specifications

| Hook | Role | Input | Output | Matcher |
|------|------|-------|--------|---------|
| **SessionStart** | plan/inject | session_id | `additionalContext`: preference index (~50 tokens) | — |
| **PostCompact** | re-inject | compaction summary | `additionalContext`: preference index (re-resolved for current branch) | manual\|auto |
| **PreToolUse** | validate | tool_name, tool_input | `additionalContext` for warnings; `decision: block` for hard violations | Bash |
| **PermissionRequest** | policy | tool_name, tool_input | `permissionDecision`: allow/deny/ask | configurable |
| **PostToolUse** | observe | tool_name, tool_input, tool_response | `additionalContext` for drift warnings | Edit |
| **PostToolUseFailure** | diagnose | tool_name, tool_input, error | `additionalContext` with config diagnosis | Bash |
| **UserPromptSubmit** | capture | user message | `additionalContext` asking Claude to confirm preference intent | — |
| **Stop** | suggest | — | `systemMessage` with pending preferences reminder (one-shot per session) | — |
| **Notification** | route | notification type/content | filtered notification | configurable |

### Hook Ordering (Coexistence Contract)

Hooks are ordered by array position in settings.json. Convention:

- **SessionStart**: existing hooks first → preference injection LAST
- **PreToolUse**: preference validation FIRST → existing hooks after
- **PostToolUse**: existing hooks first → preference observation LAST
- **Stop**: existing hooks first → preference reminder LAST

The `validate-project-prefs` skill audits hook ordering as part of its compliance checks.

### SessionStart Injection Format

Compact preference index (~50-120 tokens depending on configured domains; only domains with non-default values are included):

```
[xgh preferences] branch=develop
pr: repo=tokyo-megacorp/xgh provider=github reviewer=copilot-pull-request-reviewer[bot] merge_method=squash
dispatch: default_agent=claude exec_effort=normal
vcs: commit_format=<type>: <description>
Pending preferences: 0
```

Skills read full values from YAML on demand via `lib/preferences.sh`. The index tells Claude which domains are configured.

### PostCompact Re-injection

Re-reads project.yaml and re-resolves for the **current branch** (via `git branch --show-current`). Does not reuse SessionStart's cached branch — the user may have switched branches mid-session.

### PreToolUse Validation

Scoped narrowly: matches `Bash` tool only. Checks:
- `gh pr merge` commands: merge method matches `load_pr_pref("merge_method", "", "$TARGET_BRANCH")`
- `git push --force` on protected branches: warn based on `pr.branches.<ref>.protected`

Warns via `additionalContext`. Blocks only on hard violations (configurable).

### PostToolUse Observation

Scoped narrowly: matches `Edit` tool only. Detects:
- Direct edits to `config/project.yaml` — injects a reminder that preferences changed and may need review.

No broader drift detection (avoids false positives on high-frequency tools).

### UserPromptSubmit Capture

**Fully silent.** The hook detects possible preference statements via lightweight pattern matching (non-authoritative hint only) and injects `additionalContext`:

```
[xgh] Possible preference detected: "use rebase on main"
→ If this is a project preference the user wants to persist,
  write it to .xgh/pending-preferences-<session-id>.yaml
  using the pending preferences schema.
→ If this is a one-time instruction, ignore this message.
```

The hook does NOT write to the staging area. Claude's reasoning layer decides whether to write. If Claude confirms the intent, it writes to the staging file using the **Write tool** on `.xgh/pending-preferences-<session-id>.yaml`. The user sees the write in the transcript (full transparency). No dedicated skill is needed — the Write tool + schema is sufficient.

### Stop Hook Reminder

If `.xgh/pending-preferences-<session-id>.yaml` has entries, injects a `systemMessage`:

```
[xgh] 2 pending preferences discovered this session:
  pr.branches.main.merge_method: squash → rebase
  vcs.commit_format: (unset) → conventional
Run /xgh-save-preferences to apply.
```

**One-shot per session** — gated by `/tmp/xgh-<session-id>/prompted-for-prefs` flag file. Fires once, not on every compact/clear/resume.

---

## 5. Pending Preferences & /xgh-save-preferences

### Staging Area

**File:** `.xgh/pending-preferences-<session-id>.yaml` (gitignored, session-scoped)

**Schema:**
```yaml
pending:
  - domain: pr
    field: merge_method
    value: rebase
    branch: main                          # optional — if branch-scoped
    timestamp: "2026-03-25T14:32:00Z"
    source: "user statement: 'use rebase on main'"

  - domain: vcs
    field: commit_format
    value: "conventional"
    timestamp: "2026-03-25T14:35:00Z"
    source: "user confirmed during /xgh-implement"
```

**Write path:** Only Claude writes here, after confirming user intent. Hooks inject `additionalContext` to prompt Claude, but never write directly.

### /xgh-save-preferences Skill

```
1. Scan all .xgh/pending-preferences-*.yaml files
2. Deduplicate (latest timestamp wins per domain.field.branch)
3. Show diff:

   pr.branches.main.merge_method: squash → rebase
   vcs.commit_format: (unset) → conventional

   Apply 2 preference changes? [Y/n]

4. On confirm: Edit config/project.yaml (inherits session permission mode)
5. On success: clean up applied pending files
6. On failure: preserve staging files (rollback safety)
7. Show: "2 preferences saved to config/project.yaml"
```

**Conflict resolution:** Pending always wins (user's latest intent is newer). The diff clearly shows old → new.

**Orphan cleanup:** Pending files older than 24h are deleted based solely on file age (mtime), without relying on a `/tmp/xgh-<session-id>/` marker or `trap ... EXIT` semantics. This keeps cleanup safe for short-lived hook processes while ensuring abandoned pending files are eventually pruned.

### The Git Staging Analogy

```
.xgh/pending-preferences-*.yaml  ≈  git index (staging area)
config/project.yaml               ≈  committed state
/xgh-save-preferences             ≈  git commit
```

---

## 6. Phased Epic Breakdown

### Phase 0: Quick Wins (~3 days)

Prove the architecture with immediate user-visible value. Uses existing `lib/config-reader.sh` directly (no dependency on Phase 1's `preferences.sh`). Phase 1 later refactors these to use the new read layer.

| Epic | Deliverable |
|------|-------------|
| 0.1 | SessionStart preference injection (~50 token index) via existing `load_pr_pref` + direct yq reads |
| 0.2 | `/xgh-config show` — display resolved preferences for current branch |
| 0.3 | PreToolUse merge-method guard for `gh pr merge` via existing `load_pr_pref` |

### Phase 1: Foundation + Inject (1-2 weeks)

Full read layer and lifecycle injection.

| Epic | Deliverable |
|------|-------------|
| 1.1 | `lib/preferences.sh` — shared utils + all 11 domain loaders |
| 1.2 | Migrate `lib/config-reader.sh` to thin wrapper |
| 1.3 | Wire 4 dead preference blocks (superpowers, design, agents, pair_programming) |
| 1.4 | Add new domain skeletons to project.yaml (vcs, scheduling, notifications, retrieval, testing) |
| 1.5 | Hook coexistence contract — ordering, position comments, validation |
| 1.6 | SessionStart + PostCompact hooks (full implementation) |
| 1.7 | Staging area schema + .gitignore entry |
| 1.8 | Update `validate-project-prefs` to audit all 11 domains + hook ordering |

### Phase 2: Validate + Observe (1 week)

Preferences become enforceable.

| Epic | Deliverable |
|------|-------------|
| 2.1 | PreToolUse full validation (merge method, branch protection) |
| 2.2 | PostToolUse drift detection (project.yaml direct edits only) |
| 2.3 | PostToolUseFailure diagnosis (map API errors to config fields) |
| 2.4 | PermissionRequest policy hook (config-driven auto-approve/deny) |

### Phase 3: Capture + Converge (future — after Phase 2 proves value)

The explicit convergence loop.

| Epic | Deliverable |
|------|-------------|
| 3.1 | UserPromptSubmit silent detection hook |
| 3.2 | Pending preferences write path from Claude |
| 3.3 | Stop hook reminder (one-shot, diff-aware) |
| 3.4 | `/xgh-save-preferences` skill |
| 3.5 | Orphan cleanup in SessionStart |

### Phase 4: Route + Extend (parallel after Phase 1)

| Epic | Deliverable |
|------|-------------|
| 4.1 | Notification routing hook |
| 4.2 | `/xgh-config refresh` — re-probe and update project.yaml |
| 4.3 | Cross-domain dependency documentation + validation |

### Dependency Graph

```
Phase 0 (Quick Wins)
    │
    └──→ Phase 1 (Foundation + Inject)
              │
              ├──→ Phase 2 (Validate + Observe)
              │         │
              │         └──→ Phase 3 (Capture + Converge) [future]
              │
              └──→ Phase 4 (Route + Extend) [parallel]
```

---

## 7. Design Decisions Log

| Decision | Chosen | Rejected | Rationale |
|----------|--------|----------|-----------|
| Config reader | Domain-specific loaders | Generic reconciler | GLM-4.7 challenge: reconciler over-abstracts for single-user CLI |
| Session cache | No cache (direct reads) | /tmp session cache | YAML is 3ms; cache adds 8ms overhead for 10ms savings |
| Apply mechanism | Explicit /xgh-save-preferences | Stop hook auto-write | Auto-write to checked-in file causes silent merge conflicts |
| Cascade metadata | Fixed per domain | Self-declaring depth | Self-declaration doesn't generalize; domain-specific is simpler |
| Probe timing | Init-time for network, read-time for local | All probes at read-time | Network probes add 300-1500ms latency, auth failures are silent |
| Branch resolution | Target branch (caller provides) | git branch --show-current | PR branch overrides must use PR base, not checked-out branch |
| Context injection | Preference index (~50 tokens) | Full preference dump | At-scale injection (11 domains) would balloon to 800-1200 tokens |
| UserPromptSubmit | Silent detection + Claude decides | Direct write to staging | Regex detection too unreliable; Claude reasoning layer handles ambiguity |
| PreCompact hook | Dropped | Preserve pending prefs | Pending prefs already on disk; hook would be a no-op |
| PostToolUse scope | project.yaml edits only | Broad drift detection | High-frequency tools cause false positive floods |
| PR override source | Environment / CI metadata | Extra config in project.yaml | PR metadata already exists in CI; a new config knob would duplicate it and add user burden |

---

## 8. References

### Analysis Files
- `.xgh/analysis/hooks/*.md` — individual hook capability analyses (10 files)
- `.xgh/analysis/design-challenge.md` — GLM-4.7 adversarial challenge
- `.xgh/analysis/for-agent-eval-*.md` — FOR agent evaluations
- `.xgh/analysis/against-agent-eval-*.md` — AGAINST agent evaluations

### Existing Implementation
- `config/project.yaml` — current config file
- `lib/config-reader.sh` — current PR-only reader
- `skills/_shared/references/project-preferences.md` — current preference reference
- `skills/validate-project-prefs/validate-project-prefs.md` — current compliance checker
