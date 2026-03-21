# Project-Scoped Retrieval & Briefing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scope retrieval and briefing to the current git project + its explicit dependencies, falling back to all-projects mode when outside any tracked project.

**Architecture:** A shared `detect-project.sh` script resolves `git rev-parse --show-toplevel` → project name in `ingest.yaml` by matching `github:` repo paths against the git remote. The session-start hook injects the detected project as `XGH_PROJECT` into CronCreate prompts. `retrieve-all.sh` filters `provider.yaml` sources by project. The briefing/retrieve skills read the same env var. When `XGH_PROJECT` is empty (cwd outside any tracked project), behavior is unchanged — all projects are fetched.

**Tech Stack:** Bash (detect-project.sh), Python (session-start hook), Markdown (skill edits), YAML (ingest.yaml schema)

---

## File Structure

### New files

```
scripts/detect-project.sh              # Resolves cwd → project name + dependencies
tests/test-detect-project.sh           # Validation tests
```

### Modified files

```
scripts/retrieve-all.sh                # Accept XGH_PROJECT, filter sources
hooks/session-start.sh                 # Detect project, pass to CronCreate prompts
skills/retrieve/retrieve.md            # Add project scope step at top
skills/briefing/briefing.md            # Add project scope step at top
```

### Schema change

```
~/.xgh/ingest.yaml                     # Add optional `dependencies:` per project
```

---

## ingest.yaml Schema Addition

Each project gains an optional `dependencies:` list. When retrieval/briefing runs scoped to project X, it also includes all projects listed in X's dependencies.

```yaml
projects:
  xgh:
    status: active
    dependencies:              # NEW — optional list of project keys
      - lossless-claude
      - context-mode
    github:
      - ipedro/xgh
    # ... rest unchanged
```

If `dependencies:` is absent or empty, only the current project is in scope.

---

## Task 1: `detect-project.sh` script + tests

**Files:**
- Create: `scripts/detect-project.sh`
- Create: `tests/test-detect-project.sh`

- [ ] **Step 1: Write the test**

```bash
# tests/test-detect-project.sh
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }
assert_executable() { if [ -x "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 not executable"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "scripts/detect-project.sh"
assert_executable "scripts/detect-project.sh"
assert_contains "scripts/detect-project.sh" "#!/usr/bin/env bash"
assert_contains "scripts/detect-project.sh" "set -euo pipefail"
assert_contains "scripts/detect-project.sh" "git rev-parse"
assert_contains "scripts/detect-project.sh" "git remote"
assert_contains "scripts/detect-project.sh" "ingest.yaml"
assert_contains "scripts/detect-project.sh" "dependencies"
assert_contains "scripts/detect-project.sh" "XGH_PROJECT"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-detect-project.sh`
Expected: FAIL — script doesn't exist yet

- [ ] **Step 3: Create `scripts/detect-project.sh`**

The script detects which tracked project the cwd belongs to. It outputs two env-style lines to stdout: `XGH_PROJECT=<name>` and `XGH_PROJECT_SCOPE=<comma-separated list of project+deps>`. If no match, both are empty.

```bash
#!/usr/bin/env bash
set -euo pipefail

# detect-project.sh — Resolve cwd to a tracked project in ingest.yaml
#
# Logic:
#   1. Get git remote origin URL from cwd's repo
#   2. Extract owner/repo from the URL
#   3. Match against all projects' github: lists in ingest.yaml
#   4. If matched, resolve dependencies
#   5. Output: XGH_PROJECT=<name> and XGH_PROJECT_SCOPE=<name,dep1,dep2>
#
# If cwd is not in a git repo, or the repo doesn't match any project,
# both values are empty (= all-projects mode).

INGEST="${XGH_INGEST:-$HOME/.xgh/ingest.yaml}"

# Step 1: Get git remote origin URL
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "XGH_PROJECT="; echo "XGH_PROJECT_SCOPE="; exit 0; }
REMOTE_URL=$(git -C "$GIT_ROOT" remote get-url origin 2>/dev/null) || { echo "XGH_PROJECT="; echo "XGH_PROJECT_SCOPE="; exit 0; }

# Step 2: Extract owner/repo from URL
# Handles: git@github.com:owner/repo.git, https://github.com/owner/repo.git, https://github.com/owner/repo
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#\.git$##')

if [ -z "$OWNER_REPO" ] || [ ! -f "$INGEST" ]; then
    echo "XGH_PROJECT="
    echo "XGH_PROJECT_SCOPE="
    exit 0
fi

# Step 3: Match against ingest.yaml projects
# Use python for safe YAML parsing
RESULT=$(python3 -c "
import yaml, sys

with open('$INGEST') as f:
    config = yaml.safe_load(f)

projects = config.get('projects', {})
target = '$OWNER_REPO'
matched = None

for name, proj in projects.items():
    if not isinstance(proj, dict):
        continue
    repos = proj.get('github', []) or []
    if isinstance(repos, str):
        repos = [repos]
    for repo in repos:
        if repo.lower() == target.lower():
            matched = name
            break
    if matched:
        break

if not matched:
    print('')
    print('')
    sys.exit(0)

# Step 4: Resolve dependencies
deps = projects[matched].get('dependencies', []) or []
scope = [matched] + [d for d in deps if d in projects]

print(matched)
print(','.join(scope))
" 2>/dev/null) || { echo "XGH_PROJECT="; echo "XGH_PROJECT_SCOPE="; exit 0; }

PROJECT=$(echo "$RESULT" | head -1)
SCOPE=$(echo "$RESULT" | tail -1)

echo "XGH_PROJECT=$PROJECT"
echo "XGH_PROJECT_SCOPE=$SCOPE"
```

- [ ] **Step 4: Make executable**

```bash
chmod +x scripts/detect-project.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-detect-project.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/detect-project.sh tests/test-detect-project.sh
git commit -m "feat(providers): add detect-project.sh for cwd-based project scoping"
```

---

## Task 2: Update `retrieve-all.sh` to filter by project scope

**Files:**
- Modify: `scripts/retrieve-all.sh`
- Modify: `tests/test-retrieve-all.sh` (add assertion)

- [ ] **Step 1: Add test assertion**

Append to `tests/test-retrieve-all.sh` BEFORE the final results line:

```bash
assert_contains "scripts/retrieve-all.sh" "XGH_PROJECT_SCOPE"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-retrieve-all.sh`
Expected: FAIL — retrieve-all.sh doesn't contain XGH_PROJECT_SCOPE yet

- [ ] **Step 3: Modify `scripts/retrieve-all.sh`**

Add project scoping logic after the `mkdir -p` line (line 33) and before the discovery loop (line 35). The script should:

1. Read `XGH_PROJECT_SCOPE` env var (comma-separated project names, or empty for all)
2. If non-empty, build a filter: for each provider, check its `provider.yaml` `sources:` entries — only run the provider if at least one source's `project:` field is in the scope list
3. If empty, run all providers (current behavior)

Insert after line 33 (`mkdir -p "$INBOX_DIR" "$HOME/.xgh/logs"`):

```bash
# Project scoping: if XGH_PROJECT_SCOPE is set, only run providers
# whose sources include at least one project in scope
SCOPE="${XGH_PROJECT_SCOPE:-}"
in_scope() {
    local provider_yaml="$1"
    # No scope = all providers in scope
    [ -z "$SCOPE" ] && return 0
    # Check if any source project matches the scope
    python3 - "$SCOPE" "$provider_yaml" << 'PYSCOPE'
import yaml, sys
scope = set(sys.argv[1].split(','))
with open(sys.argv[2]) as f:
    cfg = yaml.safe_load(f)
for src in cfg.get('sources', []):
    if isinstance(src, dict) and src.get('project', '') in scope:
        sys.exit(0)
sys.exit(1)
PYSCOPE
}
```

Then add an `in_scope` check in the loop, after the mcp-mode skip and before the fetch.sh executable check:

```bash
    # Skip providers with no sources in current project scope
    if [ -f "$provider_dir/provider.yaml" ] && ! in_scope "$provider_dir/provider.yaml"; then
        continue
    fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-retrieve-all.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/retrieve-all.sh tests/test-retrieve-all.sh
git commit -m "feat(providers): scope retrieve-all.sh to current project via XGH_PROJECT_SCOPE"
```

---

## Task 3: Update session-start hook to detect and inject project scope

**Files:**
- Modify: `hooks/session-start.sh`
- Modify: `tests/test-session-start.sh` (add assertion)

- [ ] **Step 1: Add test assertion**

Append to `tests/test-session-start.sh` BEFORE the final results line:

```bash
assert_contains "$HOOK" "detect-project"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-session-start.sh`
Expected: FAIL

- [ ] **Step 3: Modify `hooks/session-start.sh`**

In the bash section (before the python block), add project detection:

```bash
# ── Project detection ──
XGH_PROJECT=""
XGH_PROJECT_SCOPE=""
DETECT_SCRIPT="${HOME}/.xgh/scripts/detect-project.sh"
if [ -x "$DETECT_SCRIPT" ]; then
    eval "$(bash "$DETECT_SCRIPT" 2>/dev/null)" || true
fi
export XGH_PROJECT XGH_PROJECT_SCOPE
```

Then in the python section, pass the project scope into CronCreate prompts. Modify the bash lane prompt (line ~77):

From:
```python
f"({job_num}) cron='*/5 * * * *', prompt='bash ~/.xgh/scripts/retrieve-all.sh || true', recurring=true  "
```

To:
```python
f"({job_num}) cron='*/5 * * * *', prompt='XGH_PROJECT_SCOPE={xgh_scope} bash ~/.xgh/scripts/retrieve-all.sh || true', recurring=true  "
```

Where `xgh_scope` is read from the environment at the top of the python block:

```python
xgh_project = os.environ.get("XGH_PROJECT", "")
xgh_scope = os.environ.get("XGH_PROJECT_SCOPE", "")
```

Similarly, for the MCP lane prompt, append a scoping instruction:

```python
"Only process sources for projects: {scope_list}. " if xgh_scope else ""
```

Also add `projectScope` to the JSON output so skills can read it:

```python
"projectScope": xgh_scope,
"projectName": xgh_project,
```

- [ ] **Step 4: Run tests to verify nothing broke**

Run: `bash tests/test-session-start.sh && bash tests/test-hooks.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start.sh tests/test-session-start.sh
git commit -m "feat(hooks): detect project context and inject scope into CronCreate prompts"
```

---

## Task 4: Update retrieve skill for project scoping

**Files:**
- Modify: `skills/retrieve/retrieve.md`

- [ ] **Step 1: Read the skill**

Read `skills/retrieve/retrieve.md` to understand the exact structure.

- [ ] **Step 2: Add project detection step**

Insert a new section between "Guard checks" and "Step 1 — Load config and cursors":

```markdown
## Step 0 — Detect project scope

Determine which projects to retrieve for:

1. Run `bash ~/.xgh/scripts/detect-project.sh` and read `XGH_PROJECT` and `XGH_PROJECT_SCOPE`
2. If `XGH_PROJECT` is non-empty:
   - Log: `Scoped to project: $XGH_PROJECT (+ dependencies: ...)`
   - In Step 1, filter `ingest.yaml` projects to only those in `XGH_PROJECT_SCOPE`
3. If `XGH_PROJECT` is empty:
   - Log: `All-projects mode (no git project detected)`
   - Proceed with all active projects (current behavior)

This scoping applies to all subsequent steps — Slack channels, link following, GitHub scans,
and inbox stashing are limited to the in-scope projects only.
```

- [ ] **Step 3: Update Step 1 to respect scope**

In "Step 1 — Load config and cursors", change:

From: `Read ~/.xgh/ingest.yaml. Collect all projects where status: active.`

To: `Read ~/.xgh/ingest.yaml. Collect projects where status: active. If XGH_PROJECT_SCOPE is set, filter to only projects in that scope.`

- [ ] **Step 4: Commit**

```bash
git add skills/retrieve/retrieve.md
git commit -m "feat(retrieve): scope interactive retrieval to current project"
```

---

## Task 5: Update briefing skill for project scoping

**Files:**
- Modify: `skills/briefing/briefing.md`

- [ ] **Step 1: Read the skill**

Read `skills/briefing/briefing.md` to understand the exact structure.

- [ ] **Step 2: Add project detection section**

Insert a new section between "MCP Detection" and "Data Gathering":

```markdown
## Project Scope

Determine which projects this briefing covers:

1. Run `bash ~/.xgh/scripts/detect-project.sh` and read `XGH_PROJECT` and `XGH_PROJECT_SCOPE`
2. If `XGH_PROJECT` is non-empty:
   - Show in header: `🐴🤖 **xgh briefing** — [date] [time] — project: **[name]** (+[N] deps)`
   - Scope ALL data gathering queries to projects in `XGH_PROJECT_SCOPE`:
     - Memory queries: add project name to search terms
     - Slack: only scan channels belonging to in-scope projects
     - Jira: filter JQL to in-scope project keys
     - GitHub: only check repos belonging to in-scope projects
     - Figma: only check files belonging to in-scope projects
   - Gmail and Calendar are NOT scoped (they're personal, not project-specific)
3. If `XGH_PROJECT` is empty:
   - Show in header: `🐴🤖 **xgh briefing** — [date] [time] — all projects`
   - Proceed with all active projects (current behavior — command center mode)

**Override:** `/xgh-briefing --all` forces all-projects mode regardless of cwd.
```

- [ ] **Step 3: Update Data Gathering sections**

For each numbered data gathering step (1-7), add a note that the queries should be filtered when `XGH_PROJECT_SCOPE` is set:

- **1. xgh Memory**: Add project name to search queries, e.g. `lcm_search("xgh last session")`
- **3. Jira**: Append `AND project IN (KEY1, KEY2)` to JQL when scoped
- **4. GitHub**: Only run `gh pr list` / `gh issue list` for repos in scope
- **6. Figma**: Only check file keys belonging to in-scope projects

- [ ] **Step 4: Commit**

```bash
git add skills/briefing/briefing.md
git commit -m "feat(briefing): scope briefing to current project context"
```

---

## Task 6: Update init/track to support `dependencies:` field

**Files:**
- Modify: `skills/track/track.md`

- [ ] **Step 1: Read current track skill**

Read `skills/track/track.md` to understand exact structure.

- [ ] **Step 2: Add dependencies question to Step 1**

After question 9 (default access level), add question 10:

```markdown
10. **Project dependencies** (optional) — other tracked projects that this project depends on.
    Show a list of existing project names from `ingest.yaml` and let the user pick.
    Example: "xgh depends on: lossless-claude, context-mode"
    Default: empty list.
```

- [ ] **Step 3: Update Step 3 (Write to ingest.yaml) to include dependencies**

Add `dependencies:` to the YAML template:

```yaml
    dependencies:            # from Q10
      - lossless-claude
      - context-mode
```

- [ ] **Step 4: Commit**

```bash
git add skills/track/track.md
git commit -m "feat(track): add dependencies question for project scoping"
```

---

## Task 7: Install `detect-project.sh` in init skill

**Files:**
- Modify: `skills/init/init.md`

- [ ] **Step 1: Read init skill**

Read `skills/init/init.md` to find Step 0f (install retrieve orchestrator).

- [ ] **Step 2: Add Step 0g after 0f**

```markdown
### 0g. Install project detector

```bash
DETECT_SCRIPT=$(find ~/.claude/plugins/cache -path "*/xgh/*/scripts/detect-project.sh" -print -quit 2>/dev/null)
if [ -n "$DETECT_SCRIPT" ]; then
    mkdir -p ~/.xgh/scripts
    cp "$DETECT_SCRIPT" ~/.xgh/scripts/detect-project.sh
    chmod +x ~/.xgh/scripts/detect-project.sh
    echo "Installed detect-project.sh"
fi
```
```

- [ ] **Step 3: Commit**

```bash
git add skills/init/init.md
git commit -m "feat(init): install detect-project.sh for project scoping"
```

---

## Task 8: Update doctor skill + run all tests

**Files:**
- Modify: `skills/doctor/doctor.md`

- [ ] **Step 1: Add project detection check to doctor**

In Check 7 (Providers), after the provider listing, add:

```markdown
### Project detection

Run `bash ~/.xgh/scripts/detect-project.sh` and report:
- If a project was detected: `✓ Project scope: <name> (+N dependencies)`
- If no match: `ℹ No project detected — all-projects mode`
- If script missing: `⚠ detect-project.sh not installed — run /xgh-init`
```

- [ ] **Step 2: Run all tests**

Run: `bash tests/test-config.sh && bash tests/test-providers.sh && bash tests/test-retrieve-all.sh && bash tests/test-session-start.sh && bash tests/test-detect-project.sh && bash tests/test-hooks.sh`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add skills/doctor/doctor.md
git commit -m "feat(doctor): add project detection health check"
```

---

## Verification Checklist

After all tasks are complete:

- [ ] `bash tests/test-detect-project.sh` — detect script exists and contains required keywords
- [ ] `bash tests/test-retrieve-all.sh` — orchestrator includes project scope filtering
- [ ] `bash tests/test-session-start.sh` — hook references detect-project
- [ ] `bash tests/test-hooks.sh` — all hook tests still pass
- [ ] `bash tests/test-config.sh` — existing tests still pass
- [ ] `scripts/detect-project.sh` is executable
- [ ] Manual test: run `bash scripts/detect-project.sh` from inside xgh repo — should output `XGH_PROJECT=xgh`
- [ ] Manual test: run `bash scripts/detect-project.sh` from `~/` — should output `XGH_PROJECT=`

---

## Behavioral Summary

| Context | XGH_PROJECT | Retrieval scope | Briefing scope |
|---------|-------------|-----------------|----------------|
| Inside `~/Developer/xgh` | `xgh` | xgh + its dependencies | xgh + its dependencies |
| Inside `~/Developer/rtk` | `rtk` | rtk only (no deps) | rtk only |
| Inside `~/` or non-git dir | (empty) | All projects | All projects |
| `/xgh-briefing --all` | (ignored) | N/A | All projects |
