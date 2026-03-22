# Multi-Platform Dispatch Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenCode as a new dispatch target and introduce context injection (xgh-seed) so dispatched agents arrive with project memory — applying lessons from ByteRover's connector architecture.

**Architecture:** Extend `config/agents.yaml` with a per-platform property schema (skill_dir, rules_file, dir_flag, auto_detect) as a shared registry. Build OpenCode dispatch skill following the codex/gemini 5-step pattern. Add a new `xgh-seed` skill that writes a project context brief into each detected platform's skill directory.

**Tech Stack:** Bash, YAML, Markdown skill files, xgh plugin pattern (thin commands + frontmatter skills), lossless-claude MCP for context.

---

## ByteRover Learnings Applied

| ByteRover concept | xgh equivalent |
|---|---|
| Per-platform property table (skill_dir, rules_file, MCP config) | `agents.yaml` registry fields |
| 3 connector types (Skill / MCP / Rules) | dispatch exec / review + context injection |
| Auto-detection (`which opencode`) | `scripts/detect-agents.sh` |
| Context injection (writes SKILL.md to platform dir) | `/xgh-seed` writes `context.md` to platform dirs |
| Platform-specific rules files (GEMINI.md, AGENTS.md) | Seeded into each platform automatically |

## OpenCode Key Differences vs Codex/Gemini

| Property | Codex | Gemini CLI | OpenCode |
|---|---|---|---|
| exec command | `codex exec "<p>"` | `gemini -p "<p>"` | `opencode run "<p>"` |
| dir flag | `-C <dir>` | `cd <dir> &&` | `cd <dir> &&` |
| auto-approve | `--full-auto` | `--yolo` | non-interactive = auto (no flag needed) |
| review mode | `codex review` | `--approval-mode plan` | prompt-engineering only |
| output capture | `-o <file>` | `> <file>` | `> <file>` |
| reads .claude/skills | no | no | **yes** (native; verify: `opencode --help \| grep skill`) |
| model flag | `--model <name>` | `--model <name>` | `--model <provider>/<name>` |

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Modify | `config/agents.yaml` | Add `skill_dir`, `rules_file`, `dir_flag`, `output_flag`, `exec_approval`, `review_approval`, `auto_detect` to codex + gemini; add `opencode` entry |
| Create | `scripts/detect-agents.sh` | Check which CLI agents are installed; exit 0 with list to stdout |
| Create | `tests/test-detect-agents.sh` | Assert script exists, contains expected checks, outputs valid format |
| Create | `skills/opencode/opencode.md` | OpenCode dispatch skill (mirrors codex.md/gemini.md pattern) |
| Create | `commands/opencode.md` | Thin wrapper: `/xgh-opencode` → triggers opencode skill |
| Create | `tests/test-opencode-dispatch.sh` | Static file-content assertions for opencode skill |
| Create | `tests/skill-triggering/prompts/opencode.txt` | Natural language trigger prompt for opencode dispatch |
| Create | `skills/seed/seed.md` | Context injection skill: writes project brief to platform skill dirs |
| Create | `commands/seed.md` | Thin wrapper: `/xgh-seed` → triggers seed skill |
| Create | `tests/test-seed.sh` | Static assertions for seed skill and command |
| Modify | `commands/help.md` | Add `/xgh-opencode` and `/xgh-seed` entries |
| Modify | `plugin.json` | Register new skills: opencode, seed |

---

## Task 1: Extend agents.yaml platform registry schema

**Files:**
- Modify: `config/agents.yaml`
- Test: `tests/test-config.sh` (existing, add new assertions)

- [ ] **Step 1: Write failing assertions in test-config.sh**

Add to `tests/test-config.sh` after the existing codex/gemini block:

```bash
# --- agents.yaml: opencode entry ---
assert_contains "config/agents.yaml" "opencode:"
assert_contains "config/agents.yaml" "opencode run"
assert_contains "config/agents.yaml" "auto_detect: opencode"

# --- agents.yaml: registry fields on codex + gemini ---
assert_contains "config/agents.yaml" "skill_dir:"
assert_contains "config/agents.yaml" "rules_file:"
assert_contains "config/agents.yaml" "auto_detect:"
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bash tests/test-config.sh 2>&1 | grep -E "FAIL|PASS|opencode"
```

Expected: FAIL lines for opencode entry and registry fields.

- [ ] **Step 3: Update config/agents.yaml**

Add registry fields to existing `codex` entry (inside `invocation:`):

```yaml
      skill_dir: ".agents/skills/xgh/"
      rules_file: "AGENTS.md"
      auto_detect: "codex"
      dir_flag: "-C"
      output_flag: "-o"
      exec_approval: "--full-auto"
      review_approval: "-s read-only"
```

Add registry fields to existing `gemini` entry (inside `invocation:`):

```yaml
      skill_dir: ".gemini/skills/xgh/"
      rules_file: "GEMINI.md"
      auto_detect: "gemini"
      dir_flag: "cd"
      output_flag: ">"
      exec_approval: "--yolo"
      review_approval: "--approval-mode plan"
```

Add new `opencode` entry after `gemini:`:

```yaml
  opencode:
    type: secondary
    description: "OpenCode CLI agent — implementation and code review (all permissions auto-approved in non-interactive mode)"
    capabilities:
      - fast-implementation
      - code-review
      - test-generation
    integration: bash-invocation
    invocation:
      method: bash
      exec_cmd: "opencode run"
      exec: "cd <dir> && opencode run \"<prompt>\" [passthrough flags] > <output>"
      review: "cd <dir> && opencode run \"Code review: <prompt>. Do NOT modify any files.\" [passthrough flags]"
      notes: "Non-interactive mode auto-approves all permissions (no --full-auto equivalent needed). OpenCode natively reads .claude/skills. Working dir via cd, output via redirect. Model: --model <provider>/<name>. Requires: npm i -g opencode-ai"
      skill_dir: ".opencode/skills/xgh/"
      rules_file: "AGENTS.md"
      auto_detect: "opencode"
      dir_flag: "cd"
      output_flag: ">"
      exec_approval: null  # non-interactive mode auto-approves all permissions
      review_mode: "prompt-only"  # no dedicated read-only flag; enforced via prompt
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
bash tests/test-config.sh 2>&1 | tail -5
```

Expected: PASS count increases, no FAIL for opencode assertions.

- [ ] **Step 5: Commit**

```bash
git add config/agents.yaml tests/test-config.sh
git commit -m "feat(agents): add platform registry fields + opencode entry to agents.yaml"
```

---

## Task 2: Agent auto-detection script

**Files:**
- Create: `scripts/detect-agents.sh`
- Create: `tests/test-detect-agents.sh`

- [ ] **Step 1: Write the test file first**

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0

assert_file_exists() {
  [[ -f "$1" ]] && PASS=$((PASS+1)) || { echo "FAIL: missing $1"; FAIL=$((FAIL+1)); }
}
assert_contains() {
  grep -qi "$2" "$1" 2>/dev/null && PASS=$((PASS+1)) || { echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); }
}
assert_output_valid() {
  local out
  out=$(bash "$1")
  # Must print "none" or a space-separated list of known agent IDs
  if echo "$out" | grep -qE '^(none|[a-z]+([ ][a-z]+)*)$'; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 produced unexpected output: '$out'"
    FAIL=$((FAIL+1))
  fi
}

assert_file_exists "scripts/detect-agents.sh"
assert_contains "scripts/detect-agents.sh" "command -v codex"
assert_contains "scripts/detect-agents.sh" "command -v gemini"
assert_contains "scripts/detect-agents.sh" "command -v opencode"
assert_output_valid "scripts/detect-agents.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

Save to `tests/test-detect-agents.sh`.

- [ ] **Step 2: Run test to confirm it fails**

```bash
bash tests/test-detect-agents.sh
```

Expected: FAIL on missing `scripts/detect-agents.sh`.

- [ ] **Step 3: Write the script**

```bash
#!/usr/bin/env bash
# detect-agents.sh — detect which AI CLI agents are installed
# Usage: bash scripts/detect-agents.sh
# Output: space-separated list of detected agent IDs (e.g. "codex gemini opencode")
# Exit 0 always.

DETECTED=()

command -v codex   &>/dev/null && DETECTED+=(codex)
command -v gemini  &>/dev/null && DETECTED+=(gemini)
command -v opencode &>/dev/null && DETECTED+=(opencode)
command -v qwen    &>/dev/null && DETECTED+=(qwen)
command -v aider   &>/dev/null && DETECTED+=(aider)

if [[ ${#DETECTED[@]} -eq 0 ]]; then
  echo "none"
else
  echo "${DETECTED[*]}"
fi
```

- [ ] **Step 4: Make executable and run test to confirm it passes**

```bash
chmod +x scripts/detect-agents.sh
bash tests/test-detect-agents.sh
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/detect-agents.sh tests/test-detect-agents.sh
git commit -m "feat(scripts): add detect-agents.sh with tests for platform auto-detection"
```

---

## Task 3: OpenCode dispatch skill + test

**Files:**
- Create: `skills/opencode/opencode.md`
- Create: `tests/test-opencode-dispatch.sh`

- [ ] **Step 1: Write the test file first**

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0

assert_file_exists() {
  [[ -f "$1" ]] && PASS=$((PASS+1)) || { echo "FAIL: missing $1"; FAIL=$((FAIL+1)); }
}
assert_contains() {
  grep -qi "$2" "$1" 2>/dev/null && PASS=$((PASS+1)) || { echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); }
}

# File existence
assert_file_exists "skills/opencode/opencode.md"
assert_file_exists "commands/opencode.md"
assert_file_exists "tests/skill-triggering/prompts/opencode.txt"

# Skill: invocation pattern
assert_contains "skills/opencode/opencode.md" "opencode run"
assert_contains "skills/opencode/opencode.md" "Working directory"
assert_contains "skills/opencode/opencode.md" "non-interactive"

# Skill: dispatch types
assert_contains "skills/opencode/opencode.md" "exec"
assert_contains "skills/opencode/opencode.md" "review"

# Skill: isolation modes
assert_contains "skills/opencode/opencode.md" "worktree"
assert_contains "skills/opencode/opencode.md" "same-dir"

# Skill: output capture
assert_contains "skills/opencode/opencode.md" "output"
assert_contains "skills/opencode/opencode.md" "redirect"

# Skill: opencode reads .claude/skills
assert_contains "skills/opencode/opencode.md" ".claude/skills"

# Skill: model flag format
assert_contains "skills/opencode/opencode.md" "provider"

# Skill: background dispatch
assert_contains "skills/opencode/opencode.md" "run_in_background"

# agents.yaml
assert_contains "config/agents.yaml" "opencode run"
assert_contains "config/agents.yaml" "opencode"

# commands/help.md
assert_contains "commands/help.md" "xgh-opencode"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

Save to `tests/test-opencode-dispatch.sh`.

- [ ] **Step 2: Run test to confirm it fails**

```bash
bash tests/test-opencode-dispatch.sh
```

Expected: FAIL lines for missing skill/command/prompt files.

- [ ] **Step 3: Create skills/opencode/ directory and skill file**

```bash
mkdir -p skills/opencode
```

Create `skills/opencode/opencode.md`. Mirror the structure of `skills/codex/codex.md` exactly (same 5-step pattern, same flag parse table, same worktree lifecycle) with these differences:

**Frontmatter:**
```yaml
---
name: xgh:opencode
description: >
  Dispatch implementation or code-review tasks to OpenCode CLI. Use when the user says
  "use opencode", "dispatch to opencode", "run this with opencode", or asks to delegate
  a coding task to OpenCode. OpenCode is an open-source AI coding agent that auto-approves
  all tool use in non-interactive mode. It natively reads .claude/skills for project context.
type: flexible
---
```

**Key behavioral differences to document in the skill body:**

1. Invocation (Step 2 — Dispatch):
```bash
# Exec worktree:
WORK_DIR="$(git rev-parse --show-toplevel)/.worktrees/$BRANCH"
OUTPUT_FILE="$WORK_DIR/opencode-output.md"
cd "$WORK_DIR" && opencode run "$PROMPT" $PASSTHROUGH_FLAGS > "$OUTPUT_FILE" 2>&1

# Exec same-dir:
OUTPUT_FILE="$(git rev-parse --show-toplevel)/opencode-output.md"
cd "$(git rev-parse --show-toplevel)" && opencode run "$PROMPT" $PASSTHROUGH_FLAGS > "$OUTPUT_FILE" 2>&1

# Review (always same-dir):
cd "$(git rev-parse --show-toplevel)" && opencode run "Code review: $PROMPT. Analyze the code and provide feedback. Do NOT modify any files." $PASSTHROUGH_FLAGS
```

2. Auto-approve note: Non-interactive mode auto-approves all permissions — no `--full-auto` flag equivalent. This is OpenCode's default behavior when a prompt is passed via `opencode run`.

3. Context note: OpenCode natively reads `.claude/skills/` and `~/.claude/CLAUDE.md`. If xgh-seed has been run, `.opencode/skills/xgh/context.md` provides additional project context.

4. Model flag format: `--model anthropic/claude-opus-4-6` (provider/model, not just model name).

5. Parameter table:

| Parameter | Default | User flag |
|-----------|---------|-----------|
| `type` | `exec` | first arg: `exec` or `review` |
| `isolation` | `worktree` (exec), `same-dir` (review) | `--worktree`, `--same-dir` |
| `prompt` | — | remaining text after type |
| `model` | CLI default | `--model <provider>/<name>` |

6. Known limitations (no effort/thinking flag for OpenCode — omit effort table entirely).

- [ ] **Step 4: Create commands/opencode.md**

```markdown
---
description: Dispatch a task to OpenCode CLI in a worktree or same-dir. Use when asked to run something with opencode, delegate to opencode, or use opencode for implementation/review.
---

Use the xgh:opencode skill.
```

- [ ] **Step 5: Create trigger prompt**

```
tests/skill-triggering/prompts/opencode.txt:
```
```
I want to dispatch this refactoring task to OpenCode in a worktree: extract the retry logic from scripts/retrieve-all.sh into a shared function
```

- [ ] **Step 6: Add /xgh-opencode to commands/help.md**

Find the section listing dispatch commands (near `/xgh-codex`, `/xgh-gemini`) and add:
```
- `/xgh-opencode` — Dispatch a task to OpenCode CLI
```

- [ ] **Step 7: Run test to confirm it passes**

```bash
bash tests/test-opencode-dispatch.sh
```

Expected: all PASS.

- [ ] **Step 8: Run full test suite**

```bash
bash tests/test-config.sh 2>&1 | tail -5
```

Expected: no new failures.

- [ ] **Step 9: Commit**

```bash
git add skills/opencode/ commands/opencode.md tests/test-opencode-dispatch.sh tests/skill-triggering/prompts/opencode.txt commands/help.md
git commit -m "feat(opencode): add OpenCode CLI dispatch skill"
```

---

## Task 4: xgh-seed context injection skill + test

**Files:**
- Create: `skills/seed/seed.md`
- Create: `commands/seed.md`
- Create: `tests/test-seed.sh`

**What xgh-seed does:** Reads the current project context (last briefing digest, context-tree decisions, key architecture notes) and writes a concise `context.md` file into each detected platform's skill directory. This ensures dispatched agents (Gemini CLI, OpenCode, Codex, etc.) start with project memory pre-loaded.

ByteRover equivalent: `brv connectors install "Gemini CLI"` which drops `SKILL.md` + `WORKFLOWS.md` into `.gemini/skills/byterover/`.

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0

assert_file_exists() {
  [[ -f "$1" ]] && PASS=$((PASS+1)) || { echo "FAIL: missing $1"; FAIL=$((FAIL+1)); }
}
assert_contains() {
  grep -qi "$2" "$1" 2>/dev/null && PASS=$((PASS+1)) || { echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); }
}

assert_file_exists "skills/seed/seed.md"
assert_file_exists "commands/seed.md"

# Seed skill: reads context sources
assert_contains "skills/seed/seed.md" "context-tree"
assert_contains "skills/seed/seed.md" "detect-agents"
assert_contains "skills/seed/seed.md" "skill_dir"

# Seed skill: writes per-platform
assert_contains "skills/seed/seed.md" ".gemini/skills/xgh"
assert_contains "skills/seed/seed.md" ".agents/skills/xgh"
assert_contains "skills/seed/seed.md" ".opencode/skills/xgh"

# Seed skill: context content
assert_contains "skills/seed/seed.md" "context.md"
assert_contains "skills/seed/seed.md" "lossless-claude"

# commands/help.md
assert_contains "commands/help.md" "xgh-seed"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

Save to `tests/test-seed.sh`.

- [ ] **Step 2: Run test to confirm it fails**

```bash
bash tests/test-seed.sh
```

Expected: FAIL lines for missing files.

- [ ] **Step 3: Create skills/seed/seed.md**

```bash
mkdir -p skills/seed
```

**Frontmatter:**
```yaml
---
name: xgh:seed
description: >
  Inject xgh project context into other AI CLI tools' skill directories. Use when the user
  says "seed context", "inject xgh into gemini", "prep opencode with project context",
  "set up context for dispatch", or before dispatching to another agent. Writes a
  project-context brief into .gemini/skills/xgh/, .agents/skills/xgh/, .opencode/skills/xgh/
  so dispatched agents have project memory pre-loaded.
type: flexible
---
```

**Skill body — 4 steps:**

**Step 1: Detect installed agents**
Run `bash scripts/detect-agents.sh` to get the list of installed platforms.

**Step 2: Build context brief**
Read from these sources (in order, skip if missing):
1. `~/.xgh/inbox/digest.md` — last analyze digest (most recent project summary)
2. `.xgh/context-tree/decisions/` — all `.md` files (truncate each to 50 lines)
3. `.xgh/context-tree/architecture/` — all `.md` files (truncate each to 100 lines)
4. `.xgh/context-tree/conventions/` — all `.md` files (truncate each to 30 lines)
5. lossless-claude: `lcm_search("project briefing digest", { tags: ["session"], limit: 3 })` then `lcm_search("architecture decisions patterns", { limit: 3 })` — top memories

Compose a `context.md` with this structure:
```markdown
# xgh Project Context
_Auto-generated by /xgh-seed. Do not edit manually._

## Project Summary
[2-3 sentences from digest.md intro]

## Key Decisions
[Bullet list from context-tree/decisions/]

## Architecture
[Key points from context-tree/architecture/]

## Recent Activity
[Last 5 digest bullets]
```

Target: under 200 lines.

**Step 3: Write context.md to each detected platform's skill dir**

Platform → skill directory mapping (from agents.yaml `skill_dir` field):
- `codex` → `.agents/skills/xgh/`
- `gemini` → `.gemini/skills/xgh/`
- `opencode` → `.opencode/skills/xgh/`

For each detected platform:
```
mkdir -p <skill_dir>
# Write context.md to <skill_dir>/context.md
```

Also write a minimal `SKILL.md` to each dir:
```markdown
# xgh Context
This directory contains project context from xgh.
Run `/xgh-brief` in Claude Code to get a fresh briefing.
Run `/xgh-seed` to refresh this context.
```

**Step 4: Confirm and report**
List which platforms were seeded and where. Store a brief memory:
```
lcm_store("xgh-seed: seeded context into [platforms] on [date]", ["session"])
```

- [ ] **Step 4: Create commands/seed.md**

```markdown
---
description: Inject xgh project context into other AI CLI tools' skill directories (Gemini CLI, Codex, OpenCode). Use when asked to seed context, prep for dispatch, or inject project memory into another agent.
---

Use the xgh:seed skill.
```

- [ ] **Step 5: Add /xgh-seed to commands/help.md**

```
- `/xgh-seed` — Inject xgh project context into other CLI agents' skill directories
```

- [ ] **Step 6: Run test to confirm it passes**

```bash
bash tests/test-seed.sh
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add skills/seed/ commands/seed.md tests/test-seed.sh commands/help.md
git commit -m "feat(seed): add xgh-seed context injection skill for multi-platform dispatch"
```

---

## Task 5: plugin.json registration

**Files:**
- Modify: `plugin.json`

- [ ] **Step 1: Check current skills list in plugin.json**

```bash
grep -c "skills" plugin.json
```

- [ ] **Step 2: Add opencode and seed to skills + commands arrays**

Find the `"skills"` array in `plugin.json` and add:
```json
"skills/opencode/opencode.md",
"skills/seed/seed.md"
```

Find the `"commands"` array in `plugin.json` and add:
```json
"commands/opencode.md",
"commands/seed.md"
```

- [ ] **Step 3: Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('plugin.json')); print('valid')"
```

Expected: `valid`

- [ ] **Step 4: Run full test suite**

```bash
bash tests/test-config.sh 2>&1 | tail -5
```

Expected: no new failures.

- [ ] **Step 5: Commit**

```bash
git add plugin.json
git commit -m "feat(plugin): register opencode and seed skills in plugin.json"
```

---

## Task 6: Final integration smoke test

- [ ] **Step 1: Run all dispatch tests**

```bash
bash tests/test-codex-dispatch.sh && echo "codex: OK"
bash tests/test-gemini-dispatch.sh && echo "gemini: OK"
bash tests/test-opencode-dispatch.sh && echo "opencode: OK"
bash tests/test-seed.sh && echo "seed: OK"
```

Expected: all 4 print OK.

- [ ] **Step 2: Run full suite**

```bash
bash tests/test-config.sh 2>&1 | tail -10
bash tests/test-detect-agents.sh && echo "detect-agents: OK"
```

Expected: total PASS count increases from baseline, zero FAIL.

- [ ] **Step 3: Verify agent detection**

```bash
bash scripts/detect-agents.sh
```

Expected: lists any installed agents (or `none`).

- [ ] **Step 4: Update file map in plan**

Add `tests/test-detect-agents.sh` to the File Map table at the top of this document if not already present.

---

## Future Platforms (follow same pattern)

Once Task 1-5 are done, adding Qwen Code, Warp, or Augment follows the same recipe:
1. Add entry to `agents.yaml` with correct `exec_cmd`, `skill_dir`, `rules_file`, `auto_detect`
2. Copy `skills/opencode/opencode.md` → `skills/<platform>/`, update invocation details
3. Copy `commands/opencode.md` → `commands/<platform>.md`, update description
4. Copy `tests/test-opencode-dispatch.sh` → `tests/test-<platform>-dispatch.sh`, update assertions
5. Add prompt to `tests/skill-triggering/prompts/<platform>.txt`
6. Register in `plugin.json`
7. Run full test suite

> ⚠️ **Provisional** — verify invocation commands at implementation time; CLIs below may not have stable public releases.

| Platform | exec_cmd (provisional) | auto_detect | notes |
|---|---|---|---|
| Qwen Code | `qwen run` | `qwen` | MCP-first; rules via `QWEN.md` |
| Warp | `warp-agent` | `warp-agent` | Terminal-native; skill dir `.warp/skills/xgh/` |
| Augment | `augment` | `augment` | Rules via `.augment/rules/agent-context.md` |
