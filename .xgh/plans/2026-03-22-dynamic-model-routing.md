# Dynamic Model Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically select the best agent + model + effort for each dispatched task, learned from real per-repo usage data.

**Architecture:** Router skill (`/xgh-dispatch`) classifies tasks into archetypes, looks up `.xgh/model-profiles.yaml` for performance data, and invokes the appropriate dispatch skill (codex/gemini/opencode) with the best model+effort flags. Each dispatch skill's curate step records observations after every dispatch, feeding the learning loop.

**Tech Stack:** Markdown skills (prompt engineering), YAML observation store, bash test assertions.

**Spec:** `.xgh/specs/2026-03-22-dynamic-model-routing-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| `skills/dispatch/dispatch.md` | **New** — Router skill: classify, lookup, select, dispatch |
| `commands/dispatch.md` | **New** — Slash command entry point for `/xgh-dispatch` |
| `tests/test-dispatch-router.sh` | **New** — Router skill structure assertions |
| `tests/test-model-profiles.sh` | **New** — Profile store and gitignore assertions |
| `tests/skill-triggering/prompts/dispatch.txt` | **New** — Trigger test prompt for router skill |
| `skills/codex/codex.md` | **Edit** — Extend Step 5 curate with observation write |
| `skills/gemini/gemini.md` | **Edit** — Extend Step 5 curate with observation write |
| `skills/opencode/opencode.md` | **Edit** — Extend Step 5 curate with observation write |
| `.gitignore` | **Edit** — Add `.xgh/model-profiles.yaml` |
| `tests/test-skills.sh` | **Edit** — Add router skill assertions |
| `tests/test-codex-dispatch.sh` | **Edit** — Add curate observation assertions |
| `tests/test-gemini-dispatch.sh` | **Edit** — Add curate observation assertions |
| `commands/help.md` | **Edit** — Add `/xgh-dispatch` to Everyday Commands table |

---

### Task 1: Gitignore and Profile Store Foundation

**Files:**
- Modify: `.gitignore`
- Create: `tests/test-model-profiles.sh`

- [ ] **Step 1: Write the test file**

Create `tests/test-model-profiles.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
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

# --- Gitignore includes model-profiles ---
assert_contains ".gitignore" "model-profiles.yaml"

# --- Observation schema documented in router skill ---
assert_contains "skills/dispatch/dispatch.md" "agent"
assert_contains "skills/dispatch/dispatch.md" "model"
assert_contains "skills/dispatch/dispatch.md" "effort"
assert_contains "skills/dispatch/dispatch.md" "archetype"
assert_contains "skills/dispatch/dispatch.md" "accepted"
assert_contains "skills/dispatch/dispatch.md" "ts"

echo ""
echo "Model profiles test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-model-profiles.sh`
Expected: FAIL — `.gitignore` missing `model-profiles.yaml`, router skill doesn't exist yet.

- [ ] **Step 3: Add model-profiles.yaml to .gitignore**

Add this line to `.gitignore` after the `.xgh/local/` entry:

```
.xgh/model-profiles.yaml
```

- [ ] **Step 4: Run test — partial pass**

Run: `bash tests/test-model-profiles.sh`
Expected: gitignore assertion passes, router skill assertions still fail (expected — Task 2 creates it).

- [ ] **Step 5: Commit**

```bash
git add .gitignore tests/test-model-profiles.sh
git commit -m "test: add model profiles test, gitignore model-profiles.yaml"
```

---

### Task 2: Router Skill — `/xgh-dispatch`

**Files:**
- Create: `skills/dispatch/dispatch.md`
- Create: `commands/dispatch.md`
- Create: `tests/test-dispatch-router.sh`
- Create: `tests/skill-triggering/prompts/dispatch.txt`

- [ ] **Step 1: Write the test file**

Create `tests/test-dispatch-router.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
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

# --- File existence ---
assert_file_exists "skills/dispatch/dispatch.md"
assert_file_exists "commands/dispatch.md"
assert_file_exists "tests/skill-triggering/prompts/dispatch.txt"

# --- Skill: all 8 archetypes ---
assert_contains "skills/dispatch/dispatch.md" "brainstorming"
assert_contains "skills/dispatch/dispatch.md" "planning"
assert_contains "skills/dispatch/dispatch.md" "implementation"
assert_contains "skills/dispatch/dispatch.md" "code-review"
assert_contains "skills/dispatch/dispatch.md" "debugging"
assert_contains "skills/dispatch/dispatch.md" "refactoring"
assert_contains "skills/dispatch/dispatch.md" "documentation"
assert_contains "skills/dispatch/dispatch.md" "quick-task"

# --- Skill: profile lookup ---
assert_contains "skills/dispatch/dispatch.md" "model-profiles.yaml"

# --- Skill: override flags ---
assert_contains "skills/dispatch/dispatch.md" "--model"
assert_contains "skills/dispatch/dispatch.md" "--agent"

# --- Skill: cold start fallback ---
assert_contains "skills/dispatch/dispatch.md" "CLI default"

# --- Skill: agent-specific flag awareness ---
assert_contains "skills/dispatch/dispatch.md" "OpenCode has no effort flag"

# --- Skill: model prefix routing ---
assert_contains "skills/dispatch/dispatch.md" "gpt-"
assert_contains "skills/dispatch/dispatch.md" "gemini-"

# --- Skill: dispatches to known agents ---
assert_contains "skills/dispatch/dispatch.md" "xgh-codex"
assert_contains "skills/dispatch/dispatch.md" "xgh-gemini"
assert_contains "skills/dispatch/dispatch.md" "xgh-opencode"

# --- Skill: observation write ---
assert_contains "skills/dispatch/dispatch.md" "observation"
assert_contains "skills/dispatch/dispatch.md" "accepted"

# --- Command file ---
assert_contains "commands/dispatch.md" "xgh:dispatch"
assert_contains "commands/dispatch.md" "/xgh-dispatch"
assert_contains "commands/dispatch.md" "exec"
assert_contains "commands/dispatch.md" "--model"
assert_contains "commands/dispatch.md" "--agent"

echo ""
echo "Dispatch router test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-dispatch-router.sh`
Expected: FAIL — skill, command, and prompt files don't exist yet.

- [ ] **Step 3: Write the trigger test prompt**

Create `tests/skill-triggering/prompts/dispatch.txt`:

```
Dispatch this task to the best available agent.
```

- [ ] **Step 4: Write the router skill**

Create `skills/dispatch/dispatch.md`:

```markdown
---
name: xgh:dispatch
description: "This skill should be used when the user asks to \"dispatch\", \"route task\", \"auto dispatch\", \"pick the best model\", \"send to best agent\", or wants to automatically select the optimal agent, model, and effort level for a task based on learned performance profiles. Wraps /xgh-codex, /xgh-gemini, and /xgh-opencode with intelligent model routing."
trigger: "/xgh dispatch"
mcp_dependencies:
  required: []
  optional:
    - lossless-claude: "lossless-claude MCP — search past work, store outcomes"
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh dispatch`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# xgh:dispatch — Dynamic Model Router

Automatically select the best agent + model + effort for a task based on learned per-repo performance profiles. Wraps the dispatch skills (`/xgh-codex`, `/xgh-gemini`, `/xgh-opencode`) with intelligent routing.

## Preamble — Execution mode

This skill inherits the execution mode preamble from the target dispatch skill. The router itself always runs inline (classification is fast), then delegates to the selected dispatch skill which applies its own preamble.

## Input Parsing

Parse the user's request to determine:

**Router-specific flags** (consumed by the router, not forwarded):

| Flag | Purpose |
|------|---------|
| `--agent <name>` | Force a specific agent (codex, gemini, opencode) — skip agent selection |
| `--model <name>` | Force a specific model — skip model selection, infer agent from prefix |

**All other flags** are forwarded to the target dispatch skill as passthrough (e.g., `--effort`, `--worktree`, `--same-dir`, `exec`, `review`).

**Model prefix → agent inference** (used when `--model` is provided without `--agent`):

| Prefix | Agent |
|--------|-------|
| `gpt-*`, `o1-*`, `o3-*`, `o4-*` | codex |
| `gemini-*` | gemini |
| `anthropic/*`, `openai/*`, `<provider>/<model>` (slash format) | opencode |

If the model name doesn't match any prefix pattern, require `--agent` and tell the user: "Can't infer agent from model name `<name>`. Pass `--agent codex\|gemini\|opencode`."

## Step 1: Classify Task

Read the task description and classify into one archetype:

| Archetype | Signals |
|-----------|---------|
| `brainstorming` | Creative exploration, specs, ideation, "design", "brainstorm", "explore options" |
| `planning` | Implementation plans, task breakdown, "plan", "break down", "outline steps" |
| `implementation` | Writing code, feature work, "implement", "build", "add", "create", "write" |
| `code-review` | Reviewing PRs, quality checks, "review", "check", "audit", "look at" |
| `debugging` | Investigation, root cause analysis, "debug", "fix", "investigate", "why is" |
| `refactoring` | Restructuring existing code, "refactor", "restructure", "clean up", "extract" |
| `documentation` | Writing docs, comments, "document", "write docs", "add comments", "README" |
| `quick-task` | Typo fixes, config changes, one-liners, "fix typo", "rename", "update version" |

Use the strongest signal. If ambiguous, default to `implementation` (most common archetype).

## Step 2: Lookup Profile

Read `.xgh/model-profiles.yaml` if it exists. This file is auto-generated by the curate step of dispatch skills.

**Profile file structure:**

```yaml
# Auto-generated by xgh dispatch curate step — do not edit
observations:
  - agent: codex
    model: gpt-5.4-mini
    effort: low
    archetype: quick-task
    accepted: true
    ts: 2026-03-22T14:00:00Z
```

**Lookup logic:**

1. Filter observations where `archetype` matches the classified archetype
2. Among entries where `accepted: true`, count observations per `{agent, model, effort}` tuple
3. Pick the tuple with the most `accepted: true` observations
4. If tied, prefer the most recently used (latest `ts`)
5. If no observations exist for this archetype → **cold start** (Step 3 handles this)

## Step 3: Select Agent + Model + Effort

**If profile data exists:** Use the `{agent, model, effort}` tuple from Step 2.

**If cold start (no data for this archetype):** Use CLI defaults — pick the first available agent from: codex, gemini, opencode (in install order via `bash scripts/detect-agents.sh`). Do NOT pass `-m` or `--effort` flags — let the CLI use its own default model and effort.

**If user provided overrides:**

| Override | Behavior |
|----------|----------|
| `--agent X` only | Use agent X, pick model+effort from profile (or CLI default) |
| `--model X` only | Infer agent from prefix, use model X, pick effort from profile (or CLI default). OpenCode has no effort flag — only model is passed. |
| `--agent X --model Y` | Use both as-is, no profile lookup |

Present the selection to the user before dispatching:

```
## 🐴🤖 xgh dispatch

| Field | Value |
|-------|-------|
| Task | <first 80 chars of prompt> |
| Archetype | <classified archetype> |
| Agent | <selected agent> |
| Model | <selected model or "default"> |
| Effort | <selected effort or "default"> |
| Source | profile (N observations) / cold start / user override |

Dispatching...
```

## Step 4: Dispatch

Invoke the target dispatch skill with the selected parameters. Build the invocation respecting each agent's supported flags:

**Codex** (supports model + effort):
```
/xgh-codex <type> -m <model> --effort <effort> "<prompt>" [passthrough flags]
```

**Gemini** (supports model + effort):
```
/xgh-gemini <type> -m <model> --effort <effort> "<prompt>" [passthrough flags]
```

**OpenCode** (supports model only — no effort flag):
```
/xgh-opencode <type> --model <provider>/<model> "<prompt>" [passthrough flags]
```

If model is "default", omit the `-m` / `--model` flag.
If effort is "default", omit the `--effort` flag.

The dispatch skill handles everything from here: workspace setup, execution, results collection, integration, and curate (which writes the observation back to the profile — see Task 3-5).

## Anti-Patterns

- **Over-routing.** If the user explicitly invokes `/xgh-codex`, `/xgh-gemini`, or `/xgh-opencode`, do NOT intercept. Those are direct dispatch — bypass the router.
- **Ignoring overrides.** If the user passes `--model` or `--agent`, respect it absolutely. The router's opinion is secondary to the user's.
- **Prompting for model selection.** Never ask the user "which model?" — the whole point is automatic selection. If you can't decide, use CLI defaults.
- **Stale profiles.** The profile file can grow large over time. Only read the last 100 observations for lookup. Older data is less relevant.
```

- [ ] **Step 5: Write the command file**

Create `commands/dispatch.md`:

```markdown
---
name: dispatch
description: "Auto-route tasks to the best agent + model + effort based on learned performance"
usage: "/xgh-dispatch [exec|review] [--agent <name>] [--model <name>] <prompt>"
aliases: ["route"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh dispatch`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-dispatch

Run the `xgh:dispatch` skill to automatically select the optimal agent, model, and effort level for a task.

## Usage

```
/xgh-dispatch "Add unit tests for the auth module"
/xgh-dispatch exec "Refactor connection pooling"
/xgh-dispatch review --base main
/xgh-dispatch --agent codex "Fix the flaky test"
/xgh-dispatch --model gpt-5.4-mini "Rename the variable"
/xgh-dispatch --agent gemini --model gemini-2.5-flash "Quick docs update"
```
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test-dispatch-router.sh`
Expected: ALL PASS

Run: `bash tests/test-model-profiles.sh`
Expected: ALL PASS (gitignore + observation schema assertions)

- [ ] **Step 7: Commit**

```bash
git add skills/dispatch/dispatch.md commands/dispatch.md tests/test-dispatch-router.sh tests/skill-triggering/prompts/dispatch.txt
git commit -m "feat: add /xgh-dispatch router skill with dynamic model routing"
```

---

### Task 3: Extend Codex Curate Step with Observation Write

**Files:**
- Modify: `skills/codex/codex.md` — Step 5 section
- Modify: `tests/test-codex-dispatch.sh` — add curate observation assertions

- [ ] **Step 1: Write the test assertions**

Append to `tests/test-codex-dispatch.sh` (before the final `echo` and `exit` lines):

```bash
# --- Skill: curate observation write ---
assert_contains "skills/codex/codex.md" "model-profiles.yaml"
assert_contains "skills/codex/codex.md" "observation"
assert_contains "skills/codex/codex.md" "archetype"
assert_contains "skills/codex/codex.md" "accepted"
```

- [ ] **Step 2: Run test to verify new assertions fail**

Run: `bash tests/test-codex-dispatch.sh`
Expected: New assertions FAIL, existing assertions still pass.

- [ ] **Step 3: Edit the curate step in codex.md**

Replace the existing Step 5 section in `skills/codex/codex.md`:

```markdown
## Step 5: Curate (if lossless-claude available)

Store the dispatch outcome for future reference:

```
lcm_store("Codex dispatch: <type> | model: <model> | isolation: <mode> | <outcome summary>", ["session", "codex"])
```

**Write observation to model profiles** (always, regardless of lossless-claude):

After the dispatch completes, append one observation to `.xgh/model-profiles.yaml`. Create the file if it doesn't exist.

```yaml
# Append to .xgh/model-profiles.yaml
- agent: codex
  model: <the -m flag value, or "default" if none was passed>
  effort: <the --effort value, or "default" if none was passed>
  archetype: <set by router if dispatched via /xgh-dispatch, otherwise "unknown">
  accepted: <true if worktree merged or user continued; false if re-dispatched or discarded>
  ts: <ISO 8601 timestamp>
```

Write this observation using a python one-liner:

```bash
python3 -c "
import yaml, os, datetime
path = '.xgh/model-profiles.yaml'
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    data = yaml.safe_load(open(path)) or {}
except FileNotFoundError:
    data = {}
data.setdefault('observations', [])
data['observations'].append({
    'agent': 'codex',
    'model': '<MODEL>',
    'effort': '<EFFORT>',
    'archetype': '<ARCHETYPE>',
    'accepted': True,  # or False based on outcome
    'ts': datetime.datetime.now(datetime.timezone.utc).isoformat()
})
yaml.dump(data, open(path, 'w'), default_flow_style=False, sort_keys=False)
"
```

Replace `<MODEL>`, `<EFFORT>`, `<ARCHETYPE>` with the actual values from the dispatch. Determine `accepted` from:
- Worktree merged → `true`
- User continued to next task → `true`
- User re-dispatched same task → `false`
- User discarded worktree → `false`
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-codex-dispatch.sh`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add skills/codex/codex.md tests/test-codex-dispatch.sh
git commit -m "feat(codex): extend curate step with model profile observation write"
```

---

### Task 4: Extend Gemini Curate Step with Observation Write

**Files:**
- Modify: `skills/gemini/gemini.md` — Step 5 section
- Modify: `tests/test-gemini-dispatch.sh` — add curate observation assertions

- [ ] **Step 1: Write the test assertions**

Append to `tests/test-gemini-dispatch.sh` (before the final `echo` and `exit` lines):

```bash
# --- Skill: curate observation write ---
assert_contains "skills/gemini/gemini.md" "model-profiles.yaml"
assert_contains "skills/gemini/gemini.md" "observation"
assert_contains "skills/gemini/gemini.md" "archetype"
assert_contains "skills/gemini/gemini.md" "accepted"
```

- [ ] **Step 2: Run test to verify new assertions fail**

Run: `bash tests/test-gemini-dispatch.sh`
Expected: New assertions FAIL, existing assertions still pass.

- [ ] **Step 3: Edit the curate step in gemini.md**

Replace the existing Step 5 section in `skills/gemini/gemini.md` with the same pattern as Task 3, but with `agent: gemini`:

```markdown
## Step 5: Curate (if lossless-claude available)

Store the dispatch outcome for future reference:

```
lcm_store("Gemini dispatch: <type> | model: <model> | isolation: <mode> | <outcome summary>", ["session", "gemini"])
```

**Write observation to model profiles** (always, regardless of lossless-claude):

After the dispatch completes, append one observation to `.xgh/model-profiles.yaml`. Create the file if it doesn't exist.

```yaml
# Append to .xgh/model-profiles.yaml
- agent: gemini
  model: <the -m flag value, or "default" if none was passed>
  effort: <the --effort value, or "default" if none was passed>
  archetype: <set by router if dispatched via /xgh-dispatch, otherwise "unknown">
  accepted: <true if worktree merged or user continued; false if re-dispatched or discarded>
  ts: <ISO 8601 timestamp>
```

Write using the same python one-liner pattern from the codex skill, with `'agent': 'gemini'`.

Determine `accepted` from:
- Worktree merged → `true`
- User continued to next task → `true`
- User re-dispatched same task → `false`
- User discarded worktree → `false`
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-gemini-dispatch.sh`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add skills/gemini/gemini.md tests/test-gemini-dispatch.sh
git commit -m "feat(gemini): extend curate step with model profile observation write"
```

---

### Task 5: Extend OpenCode Curate Step with Observation Write

**Files:**
- Modify: `skills/opencode/opencode.md` — Step 5 section

Note: No dedicated `test-opencode-dispatch.sh` modifications — opencode curate assertions are covered by `test-skills.sh` (Task 6).

- [ ] **Step 1: Edit the curate step in opencode.md**

Replace the existing Step 5 section in `skills/opencode/opencode.md` with the same pattern, but with `agent: opencode` and no effort field default (OpenCode doesn't support effort):

```markdown
## Step 5: Curate (if lossless-claude available)

Store the dispatch outcome for future reference:

```
lcm_store("OpenCode dispatch: <type> | model: <model> | isolation: <mode> | <outcome summary>", ["session", "opencode"])
```

**Write observation to model profiles** (always, regardless of lossless-claude):

After the dispatch completes, append one observation to `.xgh/model-profiles.yaml`. Create the file if it doesn't exist.

```yaml
# Append to .xgh/model-profiles.yaml
- agent: opencode
  model: <the --model flag value, or "default" if none was passed>
  effort: default
  archetype: <set by router if dispatched via /xgh-dispatch, otherwise "unknown">
  accepted: <true if worktree merged or user continued; false if re-dispatched or discarded>
  ts: <ISO 8601 timestamp>
```

Note: OpenCode has no effort flag. Always record `effort: default`.

Write using the same python one-liner pattern from the codex skill, with `'agent': 'opencode'` and `'effort': 'default'`.

Determine `accepted` from:
- Worktree merged → `true`
- User continued to next task → `true`
- User re-dispatched same task → `false`
- User discarded worktree → `false`
```

- [ ] **Step 2: Run existing tests to verify no regression**

Run: `bash tests/test-skills.sh`
Expected: ALL PASS (opencode skill assertions still hold)

- [ ] **Step 3: Commit**

```bash
git add skills/opencode/opencode.md
git commit -m "feat(opencode): extend curate step with model profile observation write"
```

---

### Task 6: Update test-skills.sh with Router Assertions

**Files:**
- Modify: `tests/test-skills.sh`

- [ ] **Step 1: Add router skill assertions**

Append to `tests/test-skills.sh` (before the final `echo` and `exit` lines):

```bash
# --- Dispatch router skill ---
assert_file_exists "skills/dispatch/dispatch.md"
assert_contains "skills/dispatch/dispatch.md" "xgh:dispatch"
assert_contains "skills/dispatch/dispatch.md" "model-profiles"
assert_contains "skills/dispatch/dispatch.md" "archetype"

# --- All dispatch skills have observation write ---
assert_contains "skills/codex/codex.md" "model-profiles.yaml"
assert_contains "skills/gemini/gemini.md" "model-profiles.yaml"
assert_contains "skills/opencode/opencode.md" "model-profiles.yaml"
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/test-skills.sh`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add tests/test-skills.sh
git commit -m "test: add dispatch router and observation write assertions to test-skills"
```

---

### Task 7: Update Help Command

**Files:**
- Modify: `commands/help.md`

- [ ] **Step 1: Add `/xgh-dispatch` to the Everyday Commands table**

In `commands/help.md`, add this row to the "Everyday Commands" table, after the `/xgh-opencode` row:

```markdown
| `/xgh-dispatch` | Auto-route tasks to the best agent + model + effort |
```

- [ ] **Step 2: Run all tests**

Run: `bash tests/test-config.sh`
Expected: ALL PASS across all test files.

- [ ] **Step 3: Commit**

```bash
git add commands/help.md
git commit -m "docs: add /xgh-dispatch to help command"
```

---

### Task 8: Full Test Suite Verification

- [ ] **Step 1: Run the complete test suite**

Run: `bash tests/test-config.sh`
Expected: ALL tests pass across all test files.

- [ ] **Step 2: Verify file structure**

Confirm these files exist:
- `skills/dispatch/dispatch.md`
- `commands/dispatch.md`
- `tests/test-dispatch-router.sh`
- `tests/test-model-profiles.sh`
- `tests/skill-triggering/prompts/dispatch.txt`

Confirm `.gitignore` contains `.xgh/model-profiles.yaml`.

- [ ] **Step 3: Final commit if any fixups needed**

If any tests failed and were fixed, commit the fixes:
```bash
git add -A
git commit -m "fix: test suite fixups for dynamic model routing"
```

---

### Task 9: Push for Review

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/modular-tui-engine
```

- [ ] **Step 2: Create PR for copilot review**

Create a PR targeting `main` with:
- Title: `feat: add dynamic model routing for agent dispatch`
- Body summarizing: router skill, curate extension, observation store, test coverage
- Tag for copilot review

- [ ] **Step 3: Address review feedback**

Fix any issues flagged by copilot review and push.
