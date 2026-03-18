# Context-Mode Enforcement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure context-mode tools are used during xgh sessions via four reinforcement layers: reference doc, skill preambles, escalating PreToolUse hook, and session health nudge.

**Architecture:** Layered defense in depth. A shared routing doc (Layer 1) teaches the correct pattern. Skill preambles (Layer 2) reinforce it in-context. A stateful PreToolUse hook (Layer 3) escalates warnings based on unedited-read counts. A UserPromptSubmit nudge (Layer 4) provides periodic big-picture feedback. State is tracked in a worktree-safe `/tmp/` JSON file.

**Tech Stack:** Bash + embedded Python3, JSON state files, Claude Code hooks API

**Spec:** `.xgh/specs/2026-03-18-context-mode-enforcement.md`

**Implementation notes:**
- PostToolUse hooks (`post-edit.sh`, `post-ctx-call.sh`) are silent — they track state but
  produce no stdout. This is correct per Claude Code's hook contract (PostToolUse hooks are
  not required to emit output).
- Hook stdin format: PreToolUse hooks receive `{"tool_input": {"file_path": "..."}}` via stdin.
  The implementer should verify this by checking context-mode's `pretooluse.mjs` at
  `~/.claude/plugins/cache/context-mode/` if file tracking doesn't work.
- All hash computations use Python `hashlib.sha1` only. Do NOT use bash `echo | shasum`
  (echo adds a trailing newline, producing a different hash).

---

## File Structure

| File | Responsibility |
|------|---------------|
| `plugin/references/context-mode-routing.md` | Single source of truth for tool routing rules |
| `plugin/hooks/pre-read.sh` | PreToolUse on Read — escalating advisory based on unedited-read count |
| `plugin/hooks/post-edit.sh` | PostToolUse on Edit/Write — decrements unedited counter |
| `plugin/hooks/post-ctx-call.sh` | PostToolUse on ctx_* tools — tracks context-mode usage |
| `plugin/hooks/session-start.sh` | Edit: add decision table entry, ctx-mode check, state init |
| `plugin/hooks/prompt-submit.sh` | Edit: add session health nudge |
| `config/hooks-settings.json` | Edit: add PreToolUse + PostToolUse entries |
| `install.sh` | Edit: fix hook source path, add new hooks to copy loop |
| `tests/test-hooks.sh` | Edit: add tests for new hooks |
| 23 skill files (listed in Task 9) | Edit: add 4-line context-mode preamble |

---

### Task 1: Fix installer hook copy path

The installer copies hooks from `${PACK_DIR}/hooks/` but the files live at `${PACK_DIR}/plugin/hooks/`. This creates empty placeholder hooks instead of real ones.

**Files:**
- Modify: `install.sh:188`
- Test: `tests/test-hooks.sh`

- [ ] **Step 1: Run existing hook tests to establish baseline**

Run: `bash tests/test-hooks.sh`
Expected: PASS (current tests don't catch the path bug since they test source files directly)

- [ ] **Step 2: Fix the source path**

In `install.sh`, change line 188:

```bash
# Before:
  src="${PACK_DIR}/hooks/${hook}.sh"
# After:
  src="${PACK_DIR}/plugin/hooks/${hook}.sh"
```

- [ ] **Step 3: Verify the fix**

Run: `XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh`
Expected: No errors. Hooks section completes without falling back to placeholders.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "fix: correct hook source path in installer copy loop"
```

---

### Task 2: Create context-mode routing reference doc

**Files:**
- Create: `plugin/references/context-mode-routing.md`

- [ ] **Step 1: Create the references directory**

```bash
mkdir -p plugin/references
```

- [ ] **Step 2: Write the routing doc**

Create `plugin/references/context-mode-routing.md`:

```markdown
# Context-Mode Routing Rules

When context-mode is available, use it to keep raw output out of the context window.
Even a single call can save 40% of context and significant token cost.

## Routing Table

| Action | Tool | When |
|--------|------|------|
| Understand / analyze a file | `ctx_execute_file(path)` | Always, unless Edit follows within 1-2 tool calls |
| Read a file to Edit it | `Read` | Only when the next action is Edit on the same file |
| Run multiple commands / searches | `ctx_batch_execute(commands, queries)` | Any multi-command research |
| Run builds, tests, log processing | `ctx_execute(language, code)` | Output expected >20 lines |
| Quick git/mkdir/rm | `Bash` | Output expected <20 lines |

## The "Next Action Test"

Before using `Read`, ask: **"Will my next 1-2 actions be an Edit on this same file?"**

- **Yes** → Use `Read` (Edit requires file content in context)
- **No** → Use `ctx_execute_file` (keeps raw content in sandbox)

## Phase-Specific Guidance

### Investigation / Debugging (Phase 1-3)

All file reads are analysis reads. Use `ctx_execute_file` for everything.
Use `ctx_batch_execute` for parallel searches (grep, glob, multi-file analysis).
Switch to `Read` only when you've identified the exact file to edit and are ready.

### Implementation (Phase 4)

Use `Read` for files you're about to `Edit`.
Use `ctx_execute(language, code)` for running builds, tests, and log processing.
Use `ctx_batch_execute` for verification commands.

## Common Mistakes

| Mistake | Correct Pattern |
|---------|----------------|
| `Read` 5 files to "understand the codebase" | `ctx_batch_execute` with queries |
| `Read` a file, then decide not to edit it | Should have used `ctx_execute_file` |
| `Bash` for `git diff` with large output | `ctx_execute(language="shell", code="git diff ...")` |
| `Read` a file, edit it 10 tool calls later | `ctx_execute_file` first, `Read` when ready to edit |
```

- [ ] **Step 3: Commit**

```bash
git add plugin/references/context-mode-routing.md
git commit -m "docs: add context-mode routing reference doc"
```

---

### Task 3: Write hook tests (TDD — all new hooks)

Write failing tests for pre-read, post-edit, post-ctx-call, updated session-start, and updated prompt-submit. All tests will fail until the hooks are implemented in Tasks 4-8.

**Files:**
- Modify: `tests/test-hooks.sh`

- [ ] **Step 1: Add state file helper and pre-read tests**

Append to `tests/test-hooks.sh` (before the final summary `echo`):

```bash
# ── Context-mode enforcement hooks ────────────────────────

# Helper: create a state file with given values
create_ctx_state() {
  local reads="$1" edits="$2" ctx_calls="$3"
  local state_file="/tmp/xgh-ctx-health-test-hooks.json"
  python3 -c "
import json
json.dump({
    'reads': $reads,
    'edits': $edits,
    'ctx_calls': $ctx_calls,
    'files_read': []
}, open('$state_file', 'w'))
"
  echo "$state_file"
}

# Helper: run a hook and capture its JSON output (returns empty JSON if hook missing)
run_hook_with_state() {
  local hook_script="$1"
  local state_file="$2"
  if [[ ! -f "$hook_script" ]]; then
    echo '{}'
    return 1
  fi
  XGH_CTX_STATE_OVERRIDE="$state_file" bash "$hook_script" < /dev/null 2>/dev/null
}

# Helper: extract additionalContext from hook output
extract_context() {
  local output="$1"
  python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    # Handle both PreToolUse and UserPromptSubmit formats
    if 'hookSpecificOutput' in d:
        print(d['hookSpecificOutput'].get('additionalContext', ''))
    else:
        print(d.get('additionalContext', ''))
except:
    print('')
" "$output"
}

# ── pre-read.sh tests ────────────────────────────────────

assert_file_exists "plugin/hooks/pre-read.sh"

# Test: pre-read emits valid JSON with hookSpecificOutput
PRE_READ_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$(create_ctx_state 0 0 0)")
PRE_READ_VALID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    hso = d.get('hookSpecificOutput', {})
    if hso.get('hookEventName') == 'PreToolUse' and 'additionalContext' in hso:
        print('yes')
    else:
        print('no:' + json.dumps(d))
except Exception as e:
    print('no:' + str(e))
" "$PRE_READ_OUT")
assert_eq "pre-read emits hookSpecificOutput" "$PRE_READ_VALID" "yes"

# Test: pre-read increments reads counter
STATE_FILE=$(create_ctx_state 0 0 0)
run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE" > /dev/null
READS_AFTER=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['reads'])")
assert_eq "pre-read increments reads" "$READS_AFTER" "1"

# Test: tier 1 (0-2 unedited reads) — generic tip
STATE_FILE=$(create_ctx_state 1 0 0)
TIER1_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE")
TIER1_CTX=$(extract_context "$TIER1_OUT")
TIER1_OK=$(python3 -c "
import sys
ctx = sys.argv[1]
print('yes' if 'ctx_execute_file' in ctx and '🛑' not in ctx and '⚠️' not in ctx else 'no:' + ctx)
" "$TIER1_CTX")
assert_eq "pre-read tier 1 is gentle tip" "$TIER1_OK" "yes"

# Test: tier 2 (3-4 unedited reads) — recommendation with counts
STATE_FILE=$(create_ctx_state 3 0 0)
TIER2_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE")
TIER2_CTX=$(extract_context "$TIER2_OUT")
TIER2_OK=$(python3 -c "
import sys
ctx = sys.argv[1]
print('yes' if '⚠️' in ctx else 'no:' + ctx)
" "$TIER2_CTX")
assert_eq "pre-read tier 2 has warning emoji" "$TIER2_OK" "yes"

# Test: tier 3 (5+ unedited reads) — strong warning
STATE_FILE=$(create_ctx_state 5 0 0)
TIER3_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE")
TIER3_CTX=$(extract_context "$TIER3_OUT")
TIER3_OK=$(python3 -c "
import sys
ctx = sys.argv[1]
print('yes' if '🛑' in ctx and 'context-mode-routing' in ctx else 'no:' + ctx)
" "$TIER3_CTX")
assert_eq "pre-read tier 3 has stop emoji + routing ref" "$TIER3_OK" "yes"

# Test: suppressed when ctx_calls >= 2
STATE_FILE=$(create_ctx_state 5 0 2)
SUPPRESSED_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE")
SUPPRESSED_CTX=$(extract_context "$SUPPRESSED_OUT")
SUPPRESSED_OK=$(python3 -c "
import sys
ctx = sys.argv[1]
print('yes' if '🛑' not in ctx and '⚠️' not in ctx else 'no:' + ctx)
" "$SUPPRESSED_CTX")
assert_eq "pre-read suppressed when ctx_calls >= 2" "$SUPPRESSED_OK" "yes"

# Test: missing state file is handled gracefully
rm -f /tmp/xgh-ctx-health-test-missing.json
MISSING_OUT=$(XGH_CTX_STATE_OVERRIDE="/tmp/xgh-ctx-health-test-missing.json" bash plugin/hooks/pre-read.sh < /dev/null 2>/dev/null)
MISSING_VALID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print('yes' if 'hookSpecificOutput' in d else 'no')
except:
    print('no:invalid-json')
" "$MISSING_OUT")
assert_eq "pre-read handles missing state file" "$MISSING_VALID" "yes"

# ── post-edit.sh tests ───────────────────────────────────

assert_file_exists "plugin/hooks/post-edit.sh"

# Test: post-edit increments edits counter
STATE_FILE=$(create_ctx_state 3 0 0)
XGH_CTX_STATE_OVERRIDE="$STATE_FILE" bash plugin/hooks/post-edit.sh < /dev/null 2>/dev/null
EDITS_AFTER=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['edits'])")
assert_eq "post-edit increments edits" "$EDITS_AFTER" "1"

# ── post-ctx-call.sh tests ───────────────────────────────

assert_file_exists "plugin/hooks/post-ctx-call.sh"

# Test: post-ctx-call increments ctx_calls counter
STATE_FILE=$(create_ctx_state 0 0 0)
XGH_CTX_STATE_OVERRIDE="$STATE_FILE" bash plugin/hooks/post-ctx-call.sh < /dev/null 2>/dev/null
CTX_AFTER=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['ctx_calls'])")
assert_eq "post-ctx-call increments ctx_calls" "$CTX_AFTER" "1"

# ── session-start ctx-mode integration tests ──────────────

# Test: decision table includes ctx_execute_file guidance
SS_CTX_OUT=$(XGH_CONTEXT_TREE="$TMPDIR_CT" bash plugin/hooks/session-start.sh)
SS_CTX_DT=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
dt = d.get('decisionTable', [])
has_ctx = any('ctx_execute_file' in s for s in dt)
print('yes' if has_ctx else 'no')
" "$SS_CTX_OUT")
assert_eq "session-start decision table mentions ctx_execute_file" "$SS_CTX_DT" "yes"

# Test: ctxModeAvailable key is present
SS_CTX_KEY=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print('yes' if 'ctxModeAvailable' in d else 'no')
" "$SS_CTX_OUT")
assert_eq "session-start has ctxModeAvailable key" "$SS_CTX_KEY" "yes"

# Test: schedulerInstructions mentions deep-retrieve
SS_DEEP=$(XGH_CONTEXT_TREE="$TMPDIR_CT" XGH_SCHEDULER="on" bash plugin/hooks/session-start.sh)
SS_DEEP_OK=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
si = d.get('schedulerInstructions', '')
print('yes' if '/xgh-deep-retrieve' in si else 'no')
" "$SS_DEEP")
assert_eq "schedulerInstructions mentions deep-retrieve" "$SS_DEEP_OK" "yes"

# ── prompt-submit nudge tests ────────────────────────────

# Test: nudge fires when 3+ unedited reads and 0 ctx calls
STATE_FILE=$(create_ctx_state 4 1 0)
PS_NUDGE_OUT=$(XGH_CTX_STATE_OVERRIDE="$STATE_FILE" PROMPT="hello" bash plugin/hooks/prompt-submit.sh)
PS_NUDGE_CTX=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
print('yes' if 'Session health' in ctx or 'context-mode' in ctx.lower() else 'no')
" "$PS_NUDGE_OUT")
assert_eq "prompt-submit nudge fires on high unedited reads" "$PS_NUDGE_CTX" "yes"

# Test: nudge suppressed when ctx_calls >= 2
STATE_FILE=$(create_ctx_state 5 0 3)
PS_NO_NUDGE=$(XGH_CTX_STATE_OVERRIDE="$STATE_FILE" PROMPT="hello" bash plugin/hooks/prompt-submit.sh)
PS_NO_NUDGE_CTX=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
print('yes' if 'Session health' not in ctx else 'no')
" "$PS_NO_NUDGE")
assert_eq "prompt-submit nudge suppressed when ctx active" "$PS_NO_NUDGE_CTX" "yes"
```

- [ ] **Step 2: Run tests to verify they all fail**

Run: `bash tests/test-hooks.sh`
Expected: All new tests FAIL (hooks don't exist yet). Existing tests still PASS.

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/test-hooks.sh
git commit -m "test: add failing tests for context-mode enforcement hooks"
```

---

### Task 4: Create pre-read.sh hook

**Files:**
- Create: `plugin/hooks/pre-read.sh`

- [ ] **Step 1: Write the hook**

Create `plugin/hooks/pre-read.sh`:

```bash
#!/usr/bin/env bash
# xgh PreToolUse hook — Read
# Escalating advisory based on unedited-read count.
# Output: {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "..."}}
set -euo pipefail

# Capture any stdin (Claude Code may pass tool input JSON)
export XGH_HOOK_INPUT=$(cat 2>/dev/null || echo '{}')

python3 << 'PYEOF'
import json, os, hashlib, subprocess

# Determine state file path
override = os.environ.get("XGH_CTX_STATE_OVERRIDE", "")
if override:
    state_path = override
else:
    try:
        project_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
    except Exception:
        project_root = os.getcwd()
    hash_val = hashlib.sha1(project_root.encode()).hexdigest()[:8]
    state_path = f"/tmp/xgh-ctx-health-{hash_val}.json"

# Read or initialize state
try:
    with open(state_path) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {"reads": 0, "edits": 0, "ctx_calls": 0, "files_read": []}

# Try to extract file path from hook input
try:
    hook_input = json.loads(os.environ.get("XGH_HOOK_INPUT", "{}"))
    file_path = hook_input.get("tool_input", {}).get("file_path", "")
except (json.JSONDecodeError, TypeError, AttributeError):
    file_path = ""

# Update state
state["reads"] += 1
if file_path and file_path not in state["files_read"]:
    state["files_read"].append(file_path)

# Write state
with open(state_path, "w") as f:
    json.dump(state, f)

# Compute escalation
unedited = state["reads"] - state["edits"]
ctx = state["ctx_calls"]

# Suppress warnings if agent has demonstrated context-mode awareness
if ctx >= 2:
    msg = "Context-mode: use ctx_execute_file for analysis reads."
elif unedited >= 5:
    files_str = ", ".join(os.path.basename(f) for f in state["files_read"][-5:]) if state["files_read"] else ""
    parts = [
        f"\U0001f6d1 {state['reads']} reads, {state['edits']} edits, {ctx} ctx calls.",
        "You are wasting context. Switch to ctx_execute_file NOW.",
    ]
    if files_str:
        parts.append(f"Unedited: {files_str}.")
    parts.append("See plugin/references/context-mode-routing.md")
    msg = " ".join(parts)
elif unedited >= 3:
    files_str = ", ".join(os.path.basename(f) for f in state["files_read"][-3:]) if state["files_read"] else ""
    parts = [
        f"\u26a0\ufe0f You have read {state['reads']} files and edited {state['edits']}.",
        "Use ctx_execute_file for analysis.",
    ]
    if files_str:
        parts.append(f"Unedited: {files_str}")
    msg = " ".join(parts)
else:
    msg = "Context-mode: use ctx_execute_file for analysis reads."

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": msg
    }
}
print(json.dumps(output))
PYEOF
```

- [ ] **Step 2: Make executable**

```bash
chmod +x plugin/hooks/pre-read.sh
```

- [ ] **Step 3: Run pre-read tests**

Run: `bash tests/test-hooks.sh 2>&1 | grep -E "pre-read|tier|suppress|missing"`
Expected: All pre-read tests PASS

- [ ] **Step 4: Commit**

```bash
git add plugin/hooks/pre-read.sh
git commit -m "feat: add pre-read hook with escalating context-mode advisory"
```

---

### Task 5: Create post-edit.sh hook

**Files:**
- Create: `plugin/hooks/post-edit.sh`

- [ ] **Step 1: Write the hook**

Create `plugin/hooks/post-edit.sh`:

```bash
#!/usr/bin/env bash
# xgh PostToolUse hook — Edit / Write
# Decrements unedited-read counter, removes file from tracking list.
set -euo pipefail

# Consume stdin (PostToolUse may receive tool result)
export XGH_HOOK_INPUT=$(cat 2>/dev/null || echo '{}')

python3 << 'PYEOF'
import json, os, hashlib, subprocess

# Determine state file path
override = os.environ.get("XGH_CTX_STATE_OVERRIDE", "")
if override:
    state_path = override
else:
    try:
        project_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
    except Exception:
        project_root = os.getcwd()
    hash_val = hashlib.sha1(project_root.encode()).hexdigest()[:8]
    state_path = f"/tmp/xgh-ctx-health-{hash_val}.json"

# Read or initialize state
try:
    with open(state_path) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {"reads": 0, "edits": 0, "ctx_calls": 0, "files_read": []}

# Try to extract file path from hook input
try:
    hook_input = json.loads(os.environ.get("XGH_HOOK_INPUT", "{}"))
    file_path = hook_input.get("tool_input", {}).get("file_path", "")
except (json.JSONDecodeError, TypeError, AttributeError):
    file_path = ""

# Update state
state["edits"] += 1
if file_path and file_path in state["files_read"]:
    state["files_read"].remove(file_path)

# Write state
with open(state_path, "w") as f:
    json.dump(state, f)
PYEOF
```

- [ ] **Step 2: Make executable**

```bash
chmod +x plugin/hooks/post-edit.sh
```

- [ ] **Step 3: Run post-edit tests**

Run: `bash tests/test-hooks.sh 2>&1 | grep "post-edit"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add plugin/hooks/post-edit.sh
git commit -m "feat: add post-edit hook for context-mode state tracking"
```

---

### Task 6: Create post-ctx-call.sh hook

**Files:**
- Create: `plugin/hooks/post-ctx-call.sh`

- [ ] **Step 1: Write the hook**

Create `plugin/hooks/post-ctx-call.sh`:

```bash
#!/usr/bin/env bash
# xgh PostToolUse hook — ctx_execute / ctx_execute_file / ctx_batch_execute / ctx_search / ctx_fetch_and_index
# Increments ctx_calls counter to track context-mode usage.
set -euo pipefail

# Consume stdin
cat > /dev/null 2>&1 || true

python3 << 'PYEOF'
import json, os, hashlib, subprocess

# Determine state file path
override = os.environ.get("XGH_CTX_STATE_OVERRIDE", "")
if override:
    state_path = override
else:
    try:
        project_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
    except Exception:
        project_root = os.getcwd()
    hash_val = hashlib.sha1(project_root.encode()).hexdigest()[:8]
    state_path = f"/tmp/xgh-ctx-health-{hash_val}.json"

# Read or initialize state
try:
    with open(state_path) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {"reads": 0, "edits": 0, "ctx_calls": 0, "files_read": []}

# Update state
state["ctx_calls"] += 1

# Write state
with open(state_path, "w") as f:
    json.dump(state, f)
PYEOF
```

- [ ] **Step 2: Make executable**

```bash
chmod +x plugin/hooks/post-ctx-call.sh
```

- [ ] **Step 3: Run post-ctx-call tests**

Run: `bash tests/test-hooks.sh 2>&1 | grep "post-ctx-call"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add plugin/hooks/post-ctx-call.sh
git commit -m "feat: add post-ctx-call hook for context-mode usage tracking"
```

---

### Task 7: Update session-start.sh

Add context-mode availability check, decision table entry, and state file initialization.

**Files:**
- Modify: `plugin/hooks/session-start.sh`

- [ ] **Step 1: Add ctx-mode availability check after existing variables**

After line 9 (`XGH_SCHEDULER="${XGH_SCHEDULER:-off}"`), add:

```python
# In the python3 heredoc, after the scheduler_instructions block:

# Context-mode availability check
ctx_mode_available = Path.home().joinpath(
    ".claude", "plugins", "cache", "context-mode"
).exists()
```

- [ ] **Step 2: Add decision table entry**

Add to the `decision_table` list:

```python
"For file analysis: use ctx_execute_file, not Read. Read is only for files about to be Edited."
```

Only include this entry when `ctx_mode_available` is True.

- [ ] **Step 3: Add state file initialization**

After the decision table, when `ctx_mode_available` is True:

```python
# Initialize context-mode tracking state
if ctx_mode_available:
    import hashlib, subprocess as sp
    try:
        proj = sp.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=sp.DEVNULL
        ).decode().strip()
    except Exception:
        proj = os.getcwd()
    h = hashlib.sha1(proj.encode()).hexdigest()[:8]
    state_p = f"/tmp/xgh-ctx-health-{h}.json"
    json.dump(
        {"reads": 0, "edits": 0, "ctx_calls": 0, "files_read": []},
        open(state_p, "w")
    )
```

- [ ] **Step 4: Add ctxModeAvailable to output**

Add `"ctxModeAvailable": ctx_mode_available` to the output dict.

- [ ] **Step 5: Run session-start tests**

Run: `bash tests/test-hooks.sh 2>&1 | grep -E "ctx_execute_file|ctxModeAvailable|deep-retrieve"`
Expected: All three PASS

- [ ] **Step 6: Run full hook test suite to confirm no regressions**

Run: `bash tests/test-hooks.sh`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add plugin/hooks/session-start.sh
git commit -m "feat: add context-mode priming to session-start hook"
```

---

### Task 8: Update prompt-submit.sh with session health nudge

**Files:**
- Modify: `plugin/hooks/prompt-submit.sh`

- [ ] **Step 1: Add nudge logic after the existing intent detection**

Before the final `print(json.dumps(...))` line, add:

```python
# Session health nudge — context-mode enforcement (Layer 4)
nudge = ""
state_override = os.environ.get("XGH_CTX_STATE_OVERRIDE", "")
if state_override:
    ctx_state_path = state_override
else:
    import hashlib, subprocess as sp
    try:
        proj = sp.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=sp.DEVNULL
        ).decode().strip()
    except Exception:
        proj = os.getcwd()
    h = hashlib.sha1(proj.encode()).hexdigest()[:8]
    ctx_state_path = f"/tmp/xgh-ctx-health-{h}.json"

try:
    with open(ctx_state_path) as f:
        ctx_state = json.load(f)
    unedited = ctx_state.get("reads", 0) - ctx_state.get("edits", 0)
    ctx_calls = ctx_state.get("ctx_calls", 0)
    if ctx_calls < 2 and unedited >= 3:
        nudge = (
            f"\n\n---\n\n"
            f"**Session health:** {ctx_state['reads']} reads, "
            f"{ctx_state['edits']} edits, {ctx_calls} context-mode calls. "
            f"Switch to ctx_execute_file for analysis reads."
        )
except (FileNotFoundError, json.JSONDecodeError, KeyError):
    pass  # No state file = context-mode not active, skip silently

# Append nudge to context if present
if nudge:
    context += nudge
```

- [ ] **Step 2: Run prompt-submit tests**

Run: `bash tests/test-hooks.sh 2>&1 | grep "prompt-submit"`
Expected: All prompt-submit tests PASS (including new nudge tests)

- [ ] **Step 3: Commit**

```bash
git add plugin/hooks/prompt-submit.sh
git commit -m "feat: add session health nudge to prompt-submit hook"
```

---

### Task 9: Add skill preambles (Layer 2)

Add the 4-line context-mode preamble to all xgh skills.

**Files:**
- Modify: 23 skill files (listed below)

- [ ] **Step 1: Define the preamble text**

Standard preamble (insert after the frontmatter `---` closing and before the first heading):

```markdown
> **Context-mode:** Use `ctx_execute_file` for analysis reads; `Read` only for files you will
> Edit within 1-2 tool calls. Use `ctx_batch_execute` for multi-command research. Full routing
> rules: `plugin/references/context-mode-routing.md`
```

- [ ] **Step 2: Add preamble to all skills using a script**

```bash
python3 << 'PYEOF'
import os, re

preamble = (
    '\n> **Context-mode:** Use `ctx_execute_file` for analysis reads; `Read` only for files you will\n'
    '> Edit within 1-2 tool calls. Use `ctx_batch_execute` for multi-command research. Full routing\n'
    '> rules: `plugin/references/context-mode-routing.md`\n'
)

skills = [
    "plugin/skills/investigate/investigate.md",
    "plugin/skills/implement/implement.md",
    "plugin/skills/deep-retrieve/deep-retrieve.md",
    "plugin/skills/retrieve/retrieve.md",
    "plugin/skills/analyze/analyze.md",
    "plugin/skills/briefing/briefing.md",
    "plugin/skills/doctor/doctor.md",
    "plugin/skills/init/init.md",
    "plugin/skills/track/track.md",
    "plugin/skills/index/index.md",
    "plugin/skills/profile/profile.md",
    "plugin/skills/schedule/schedule.md",
    "plugin/skills/calibrate/calibrate.md",
    "plugin/skills/collab/collab.md",
    "plugin/skills/design/design.md",
    "plugin/skills/ask/ask.md",
    "plugin/skills/curate/curate.md",
    "plugin/skills/command-center/command-center.md",
    "plugin/skills/knowledge-handoff/knowledge-handoff.md",
    "plugin/skills/mcp-setup/mcp-setup.md",
    "plugin/skills/pr-context-bridge/pr-context-bridge.md",
    "plugin/skills/todo-killer/todo-killer.md",
    "plugin/skills/team/cross-team-pollinator/cross-team-pollinator.md",
    "plugin/skills/team/onboarding-accelerator/onboarding-accelerator.md",
    "plugin/skills/team/subagent-pair-programming/subagent-pair-programming.md",
]

for skill_path in skills:
    if not os.path.exists(skill_path):
        print(f"SKIP: {skill_path} (not found)")
        continue

    content = open(skill_path).read()

    # Skip if preamble already present
    if "context-mode-routing.md" in content:
        print(f"SKIP: {skill_path} (already has preamble)")
        continue

    # Insert after second --- (end of frontmatter)
    parts = content.split("---", 2)
    if len(parts) >= 3:
        parts[2] = preamble + parts[2]
        new_content = "---".join(parts)
    else:
        # No frontmatter, prepend
        new_content = preamble + "\n" + content

    open(skill_path, "w").write(new_content)
    print(f"OK: {skill_path}")

PYEOF
```

- [ ] **Step 2b: Add extended context-mode section to heavy skills**

For these 5 skills, add a full `## Context-mode routing` section (in addition to the preamble)
referencing the phase-specific guidance from `plugin/references/context-mode-routing.md`:

- `plugin/skills/investigate/investigate.md` — note: Phase 1-3 = ctx_execute_file, Phase 4 = Read
- `plugin/skills/implement/implement.md` — note: context gathering = ctx_batch_execute, editing = Read
- `plugin/skills/deep-retrieve/deep-retrieve.md` — note: already has context-mode section, verify preamble doesn't duplicate
- `plugin/skills/retrieve/retrieve.md` — note: already references ctx_execute, add preamble
- `plugin/skills/analyze/analyze.md` — note: add ctx_batch_execute for inbox processing

```markdown
## Context-mode routing

Follow these rules for this skill's file access patterns:

| Phase | File access | Tool |
|-------|-------------|------|
| Investigation / context gathering | Understanding files | `ctx_execute_file(path)` |
| Investigation / context gathering | Running commands, searching | `ctx_batch_execute(commands, queries)` |
| Implementation | Reading a file to Edit it next | `Read` |
| Implementation | Running builds, tests | `ctx_execute(language, code)` |

See `plugin/references/context-mode-routing.md` for full rules and examples.
```

- [ ] **Step 3: Spot-check 3 skills for correct placement**

```bash
head -20 plugin/skills/investigate/investigate.md
head -20 plugin/skills/doctor/doctor.md
head -20 plugin/skills/ask/ask.md
```

Expected: Each shows the preamble after the frontmatter `---` and before the first `#` heading.

- [ ] **Step 4: Commit**

```bash
git add plugin/skills/
git commit -m "feat: add context-mode routing preamble to all xgh skills"
```

---

### Task 10: Update hooks-settings.json and installer

Register the three new hooks and add them to the installer copy loop.

**Files:**
- Modify: `config/hooks-settings.json`
- Modify: `install.sh:187`

- [ ] **Step 1: Update hooks-settings.json**

Replace the full file content with:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-session-start.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-prompt-submit.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-pre-read.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-post-edit.sh"
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-post-edit.sh"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-post-ctx-call.sh"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute_file",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-post-ctx-call.sh"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_context-mode_context-mode__ctx_batch_execute",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-post-ctx-call.sh"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_context-mode_context-mode__ctx_search",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-post-ctx-call.sh"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_context-mode_context-mode__ctx_fetch_and_index",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/xgh-post-ctx-call.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Update installer copy loop**

In `install.sh`, change the hook copy loop (line 187):

```bash
# Before:
for hook in session-start prompt-submit; do
# After:
for hook in session-start prompt-submit pre-read post-edit post-ctx-call; do
```

- [ ] **Step 3: Run install dry-run**

Run: `XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh`
Expected: No errors. All 5 hooks copied. Settings merged with new PreToolUse/PostToolUse entries.

- [ ] **Step 4: Commit**

```bash
git add config/hooks-settings.json install.sh
git commit -m "feat: register context-mode hooks in installer and settings"
```

---

### Task 11: End-to-end verification

- [ ] **Step 1: Run full hook test suite**

Run: `bash tests/test-hooks.sh`
Expected: All tests PASS (both existing and new)

- [ ] **Step 2: Run install test**

Run: `bash tests/test-install.sh`
Expected: PASS

- [ ] **Step 3: Run config test**

Run: `bash tests/test-config.sh`
Expected: PASS

- [ ] **Step 4: Dry-run install and verify hooks are real (not placeholders)**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```

Verify the installed hooks are non-placeholder:

```bash
for f in pre-read post-edit post-ctx-call; do
  if grep -q "placeholder" ".claude/hooks/xgh-${f}.sh" 2>/dev/null; then
    echo "FAIL: xgh-${f}.sh is a placeholder"
  else
    echo "OK: xgh-${f}.sh is real"
  fi
done
```

- [ ] **Step 5: Spot-check context-mode routing doc exists**

```bash
test -f plugin/references/context-mode-routing.md && echo "OK" || echo "MISSING"
```

- [ ] **Step 6: Final commit (if any cleanup needed)**

```bash
git status
# Only commit if there are changes
```
