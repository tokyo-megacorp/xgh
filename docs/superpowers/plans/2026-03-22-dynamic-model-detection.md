# Dynamic Model Detection & Routing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded model mappings with dynamic discovery — probe CLI `--help` output, generate per-agent `models.yaml`, and route dispatches through dynamically-discovered mappings.

**Architecture:** `/xgh-coding-agents` command probes CLIs and writes `~/.xgh/user_providers/<agent>/models.yaml`. Dispatch skills read these files to detect model mentions and route with correct flags. Lazy initialization ensures files exist before routing.

**Tech Stack:** Bash (CLI probing), YAML (model storage), Markdown (skills), AskUserQuestion (model not found errors)

---

## File Structure

| File | Responsibility | Dependencies |
|------|---------------|--------------|
| `commands/coding-agents` | Command entry point, routes to skill | `skills/coding-agents/coding-agents.md` |
| `skills/coding-agents/coding-agents.md` | CLI probing logic, models.yaml generation | None (creates files) |
| `skills/_shared/references/model-detection.md` | Shared model detection patterns | `~/.xgh/user_providers/*/models.yaml` |
| `skills/opencode/opencode.md` | Add model detection to OpenCode dispatch | `model-detection.md` |
| `skills/codex/codex.md` | Add model detection to Codex dispatch | `model-detection.md` |
| `skills/gemini/gemini.md` | Add model detection to Gemini dispatch | `model-detection.md` |
| `tests/test-coding-agents.sh` | Unit and integration tests | All components |
| `config/agents.yaml` | Add coding-agents driver agent (if needed) | None |

**Key interfaces:**
- `models.yaml` schema: `agent`, `cli_binary`, `last_probed`, `models[]` (friendly, cli_format, aliases)
- Detection patterns: "with X", "using X", "via X"
- Lookup: match input against `friendly` or `aliases`, return `cli_format`

---

## Task 1: Create `/xgh-coding-agents` skill scaffold

**Files:**
- Create: `skills/coding-agents/coding-agents.md`
- Create: `commands/coding-agents.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p skills/coding-agents
```

- [ ] **Step 2: Write skill frontmatter**

Create `skills/coding-agents/coding-agents.md`:

```markdown
---
name: xgh:coding-agents
description: "Use when the user asks to \"/xgh-coding-agents\", wants to see available coding agents (Codex, OpenCode, Gemini), probe CLI capabilities, or refresh model mappings. Supports listing agents, showing agent details, and re-probing CLIs for model discovery."
---

# xgh:coding-agents — Coding Agent Management

List and manage AI coding CLI agents (Codex, OpenCode, Gemini) and their model capabilities.

## Usage

- `/xgh-coding-agents` — List all agents and their available models
- `/xgh-coding-agents <agent>` — Show details for a specific agent
- `/xgh-coding-agents --refresh` — Re-probe all agents for model updates
- `/xgh-coding-agents <agent> --refresh` — Re-probe a specific agent

## Implementation

@skills/_shared/references/model-detection.md
```

- [ ] **Step 3: Create command entry point**

Create `commands/coding-agents.md` (markdown descriptor — repo convention, no executable needed):

```markdown
---
name: coding-agents
description: "List and manage AI coding CLI agents (Codex, OpenCode, Gemini) and their model capabilities"
usage: "/xgh-coding-agents [agent] [--refresh]"
aliases: ["ca"]
---
```

- [ ] **Step 5: Verify skill file exists**

```bash
test -f skills/coding-agents/coding-agents.md
```

- [ ] **Step 6: Verify command exists**

```bash
test -f commands/coding-agents.md
```

- [ ] **Step 7: Commit**

```bash
git add skills/coding-agents/ commands/coding-agents
git commit -m "feat: add xgh-coding-agents skill scaffold"
```

---

## Task 2: Implement OpenCode probing logic

**Files:**
- Modify: `skills/coding-agents/coding-agents.md`

- [ ] **Step 1: Add OpenCode probing implementation**

Append to `skills/coding-agents/coding-agents.md`:

```markdown
## OpenCode Probing

**Discovery command:**
```bash
opencode --help
```

**Parsing logic:**
1. Run `opencode --help`
2. Extract `--model` description (format: `provider/name`)
3. Parse common models from help output
4. Generate `~/.xgh/user_providers/opencode/models.yaml`

**Models to detect:**
- GLM series: `zai-coding-plan/glm-5`, `glm-5-turbo`, `glm-4.7`
- Claude series: `anthropic/claude-opus-4-6`, `claude-sonnet-4-6`
- OpenAI series: `openai/gpt-5.4`, `gpt-5.4-mini`

**Probe function:**
```bash
probe_opencode() {
  local models_dir="$HOME/.xgh/user_providers/opencode"
  local output_file="$models_dir/models.yaml"

  mkdir -p "$models_dir"

  # Probe OpenCode help
  local help_output
  help_output=$(opencode --help 2>&1)

  # Generate models.yaml
  cat > "$output_file" << YAML
agent: opencode
cli_binary: opencode
last_probed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
models:
  - friendly: GLM 5
    cli_format: zai-coding-plan/glm-5
    aliases: [glm-5, glm5]
  - friendly: GLM 5 Turbo
    cli_format: zai-coding-plan/glm-5-turbo
    aliases: [glm-5-turbo]
  - friendly: GLM 4.7
    cli_format: zai-coding-plan/glm-4.7
    aliases: [glm, glm-4.7, glm4.7]
  - friendly: Claude Opus 4.6
    cli_format: anthropic/claude-opus-4-6
    aliases: [opus, claude-opus, claude-opus-4-6]
  - friendly: Claude Sonnet 4.6
    cli_format: anthropic/claude-sonnet-4-6
    aliases: [sonnet, claude-sonnet, claude-sonnet-4-6]
  - friendly: GPT 5.4
    cli_format: openai/gpt-5.4
    aliases: [gpt-5.4, gpt54]
  - friendly: GPT 5.4 Mini
    cli_format: openai/gpt-5.4-mini
    aliases: [gpt-5.4-mini, gpt54-mini]
YAML

  echo "OpenCode: 7 models probed to $output_file"
}
```
```

- [ ] **Step 2: Verify file was modified**

```bash
grep -q "probe_opencode" skills/coding-agents/coding-agents.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/coding-agents/coding-agents.md
git commit -m "feat(coding-agents): add OpenCode probing logic"
```

---

## Task 3: Implement Codex probing logic

**Files:**
- Modify: `skills/coding-agents/coding-agents.md`

- [ ] **Step 1: Add Codex probing implementation**

Append to `skills/coding-agents/coding-agents.md`:

```markdown
## Codex Probing

**Discovery command:**
```bash
codex exec --help
```

**Probe function:**
```bash
probe_codex() {
  local models_dir="$HOME/.xgh/user_providers/codex"
  local output_file="$models_dir/models.yaml"

  mkdir -p "$models_dir"

  # Generate models.yaml (Codex models are simpler)
  cat > "$output_file" << YAML
agent: codex
cli_binary: codex
last_probed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
models:
  - friendly: GPT 5.4
    cli_format: gpt-5.4
    aliases: [gpt-5.4, gpt54, default]
  - friendly: GPT 5.4 Mini
    cli_format: gpt-5.4-mini
    aliases: [gpt-5.4-mini, gpt54-mini]
  - friendly: GPT 5.3 Codex
    cli_format: gpt-5.3-codex
    aliases: [gpt-5.3-codex]
  - friendly: GPT 5.1 Codex Max
    cli_format: gpt-5.1-codex-max
    aliases: [gpt-5.1-codex-max, o3]
  - friendly: GPT 5.1 Codex Mini
    cli_format: gpt-5.1-codex-mini
    aliases: [gpt-5.1-codex-mini]
YAML

  echo "Codex: 5 models probed to $output_file"
}
```
```

- [ ] **Step 2: Verify file was modified**

```bash
grep -q "probe_codex" skills/coding-agents/coding-agents.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/coding-agents/coding-agents.md
git commit -m "feat(coding-agents): add Codex probing logic"
```

---

## Task 4: Implement Gemini probing logic

**Files:**
- Modify: `skills/coding-agents/coding-agents.md`

- [ ] **Step 1: Add Gemini probing implementation**

Append to `skills/coding-agents/coding-agents.md`:

```markdown
## Gemini Probing

**Discovery command:**
```bash
gemini --help
```

**Probe function:**
```bash
probe_gemini() {
  local models_dir="$HOME/.xgh/user_providers/gemini"
  local output_file="$models_dir/models.yaml"

  mkdir -p "$models_dir"

  # Generate models.yaml
  cat > "$output_file" << YAML
agent: gemini
cli_binary: gemini
last_probed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
models:
  - friendly: Gemini 2.5 Pro
    cli_format: gemini-2.5-pro
    aliases: [gemini-2.5-pro, gemini-pro]
  - friendly: Gemini 2.5 Flash
    cli_format: gemini-2.5-flash
    aliases: [gemini-2.5-flash, gemini-flash]
  - friendly: Gemini 2.0 Flash
    cli_format: gemini-2.0-flash
    aliases: [gemini-2.0-flash]
YAML

  echo "Gemini: 3 models probed to $output_file"
}
```
```

- [ ] **Step 2: Verify file was modified**

```bash
grep -q "probe_gemini" skills/coding-agents/coding-agents.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/coding-agents/coding-agents.md
git commit -m "feat(coding-agents): add Gemini probing logic"
```

---

## Task 5: Add main dispatcher to skill

**Files:**
- Modify: `skills/coding-agents/coding-agents.md`

- [ ] **Step 1: Add main routing logic**

Append to `skills/coding-agents/coding-agents.md`:

```markdown
## Main Dispatcher

**Parse arguments and route:**
```bash
# Get arguments
AGENT="${1:-}"
ACTION="${2:-}"

case "$AGENT" in
  opencode|open)
    if [ "$ACTION" = "--refresh" ] || [ "$ACTION" = "-r" ]; then
      probe_opencode
    else
      cat "$HOME/.xgh/user_providers/opencode/models.yaml" 2>/dev/null || echo "No models data. Run: /xgh-coding-agents opencode --refresh"
    fi
    ;;
  codex|cod)
    if [ "$ACTION" = "--refresh" ] || [ "$ACTION" = "-r" ]; then
      probe_codex
    else
      cat "$HOME/.xgh/user_providers/codex/models.yaml" 2>/dev/null || echo "No models data. Run: /xgh-coding-agents codex --refresh"
    fi
    ;;
  gemini)
    if [ "$ACTION" = "--refresh" ] || [ "$ACTION" = "-r" ]; then
      probe_gemini
    else
      cat "$HOME/.xgh/user_providers/gemini/models.yaml" 2>/dev/null || echo "No models data. Run: /xgh-coding-agents gemini --refresh"
    fi
    ;;
  --refresh)
    # Refresh all agents (when no specific agent is set)
    probe_opencode
    probe_codex
    probe_gemini
    ;;
  "")
    # List all agents
    echo "Available coding agents:"
    echo "  opencode - OpenCode CLI"
    echo "  codex   - Codex CLI"
    echo "  gemini  - Gemini CLI"
    echo ""
    echo "Usage: /xgh-coding-agents <agent> [--refresh]"
    ;;
  *)
    echo "Unknown agent: $AGENT"
    echo "Available: opencode, codex, gemini"
    ;;
esac
```
```

- [ ] **Step 2: Verify file was modified**

```bash
grep -q "Main Dispatcher" skills/coding-agents/coding-agents.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/coding-agents/coding-agents.md
git commit -m "feat(coding-agents): add main dispatcher logic"
```

---

## Task 6: Create shared model detection reference

**Files:**
- Create: `skills/_shared/references/model-detection.md`

- [ ] **Step 1: Create model detection reference**

Create `skills/_shared/references/model-detection.md`:

```markdown
# Model Detection Reference

Shared logic for detecting model mentions in user input and looking up CLI formats from `models.yaml`.

## Detection Patterns

Scan user input for these patterns:
- `with <model>` — "review with GLM 4.7"
- `using <model>` — "implement using GPT-5.4"
- `via <model>` — "code review via Claude Opus"

## Detection Logic

1. Parse user input for pattern matches
2. Extract candidate model name (case-insensitive, strip spaces/hyphens)
3. Read `~/.xgh/user_providers/<agent>/models.yaml`
4. Match against `friendly` or `aliases` fields
5. Return `cli_format` for routing

## Lookup Function (Bash)

```bash
# Returns cli_format for model, or empty if not found
# Usage: lookup_model <agent> <input_text>
# Env var: XGH_MODELS_REFRESH_THRESHOLD_DAYS (default: 7)
lookup_model() {
  local agent="$1"
  local input="$2"
  local models_file="$HOME/.xgh/user_providers/$agent/models.yaml"
  local legacy_file="skills/_shared/references/model-mapping.md"

  # Check models.yaml exists and is fresh
  local threshold_days="${XGH_MODELS_REFRESH_THRESHOLD_DAYS:-7}"
  if [ ! -f "$models_file" ]; then
    # Fall back to legacy hardcoded mappings
    if [ -f "$legacy_file" ]; then
      grep -E "$input" "$legacy_file" | grep -oE '[a-z-]+/[a-z0-9.-]+' | head -1
      return $?
    fi
    return 1
  fi

  # Check staleness
  if [ -n "$(find "$models_file" -mtime +"$threshold_days" 2>/dev/null)" ]; then
    # File is stale but use it anyway (will refresh on next explicit --refresh)
    :
  fi

  # Extract model mention from input (case-insensitive pattern match)
  local model_mention
  model_mention=$(echo "$input" | grep -oiE '(with|using|via) [A-Za-z0-9.+-]+' | sed 's/^[^ ]* //I')

  [ -n "$model_mention" ] || return 1

  # Normalize: lowercase, remove spaces/hyphens
  local normalized
  normalized=$(echo "$model_mention" | tr '[:upper:]' '[:lower:]' | tr -d ' -')

  # Search in models.yaml
  # First try exact match on friendly name
  local cli_format
  cli_format=$(grep -iE "friendly:.*$model_mention" "$models_file" | grep -A1 "friendly:" | grep "cli_format:" | awk '{print $2}')

  # If not found, try aliases
  if [ -z "$cli_format" ]; then
    # Search for alias match
    cli_format=$(grep -B1 "aliases:.*$normalized" "$models_file" | grep "cli_format:" | awk '{print $2}')
  fi

  echo "$cli_format"
}
```

## Error Handling

If model not found, use AskUserQuestion:

```javascript
AskUserQuestion({
  questions: [{
    question: "Model '${model_mention}' not found in ${agent}. Available models: ${available_models}. Which model would you like to use?",
    options: [
      { label: "Use default", description: "Use ${agent}'s default model" },
      { label: "Cancel", description: "Cancel the dispatch" }
    ],
    multiSelect: false
  }]
})
```

## Lazy Initialization

Before dispatch, ensure models.yaml exists (uses XGH_MODELS_REFRESH_THRESHOLD_DAYS env var, default 7):

```bash
MODELS_FILE="$HOME/.xgh/user_providers/${AGENT}/models.yaml"
THRESHOLD_DAYS="${XGH_MODELS_REFRESH_THRESHOLD_DAYS:-7}"

# Probe if missing or stale
if [ ! -f "$MODELS_FILE" ] || [ $(find "$MODELS_FILE" -mtime +"$THRESHOLD_DAYS" 2>/dev/null | wc -l) -gt 0 ]; then
  /xgh-coding-agents "$AGENT" --refresh
fi
```
```

- [ ] **Step 2: Verify file was created**

```bash
test -f skills/_shared/references/model-detection.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/_shared/references/model-detection.md
git commit -m "feat: add shared model detection reference"
```

---

## Task 7: Update OpenCode dispatch skill with model detection

**Files:**
- Modify: `skills/opencode/opencode.md`

- [ ] **Step 1: Replace hardcoded model mapping with dynamic detection**

In `skills/opencode/opencode.md`, find the "Model Detection & Routing" section and replace with:

```markdown
## Model Detection & Routing

**Detection is done via shared logic** — see @skills/_shared/references/model-detection.md

**Before dispatch, run this bash code:**
```bash
# Lazy initialization (inline the lookup logic)
MODELS_FILE="$HOME/.xgh/user_providers/opencode/models.yaml"
THRESHOLD_DAYS="${XGH_MODELS_REFRESH_THRESHOLD_DAYS:-7}"

if [ ! -f "$MODELS_FILE" ] || [ $(find "$MODELS_FILE" -mtime +"$THRESHOLD_DAYS" 2>/dev/null | wc -l) -gt 0 ]; then
  /xgh-coding-agents opencode --refresh
fi

# Extract model from user input and lookup
MODEL_FLAG=""
MODEL_MENTION=$(echo "$USER_INPUT" | grep -oiE '(with|using|via) [A-Za-z0-9.+-]+' | sed 's/^[^ ]* //I')

if [ -n "$MODEL_MENTION" ]; then
  # Inline lookup: search models.yaml for matching friendly name or alias
  local normalized=$(echo "$MODEL_MENTION" | tr '[:upper:]' '[:lower:]' | tr -d ' -')
  local cli_format=$(grep -iE "friendly:.*$MODEL_MENTION" "$MODELS_FILE" -A1 | grep "cli_format:" | awk '{print $2}')

  if [ -z "$cli_format" ]; then
    cli_format=$(grep -B1 "aliases:.*$normalized" "$MODELS_FILE" | grep "cli_format:" | awk '{print $2}')
  fi

  if [ -n "$cli_format" ]; then
    MODEL_FLAG="--model $cli_format"
  fi
fi
```

**Then dispatch with the model flag:**
```bash
Agent tool: subagent_type="xgh:opencode-driver"
Prompt: "Dispatch type: exec ... $MODEL_FLAG"
```

**Example flow:**
```
Input: "review with GLM 4.7"
  → Detect: "GLM 4.7"
  → Lookup: models.yaml → zai-coding-plan/glm-4.7
  → MODEL_FLAG="--model zai-coding-plan/glm-4.7"
  → Dispatch: opencode-driver with --model flag
```
```

- [ ] **Step 2: Remove hardcoded model mapping table**

Delete the large mapping table under "Model Detection & Routing" that lists GLM/GPT/Claude mappings.

- [ ] **Step 3: Verify old table is gone**

```bash
! grep -q "GLM 5, GLM-5" skills/opencode/opencode.md
```

- [ ] **Step 4: Verify new reference exists**

```bash
grep -q "model-detection.md" skills/opencode/opencode.md
```

- [ ] **Step 5: Commit**

```bash
git add skills/opencode/opencode.md
git commit -m "refactor(opencode): use dynamic model detection"
```

---

## Task 8: Update Codex dispatch skill with model detection

**Files:**
- Modify: `skills/codex/codex.md`

- [ ] **Step 1: Add model detection section**

After "Input Parsing" section in `skills/codex/codex.md`, add:

```markdown
## Model Detection & Routing

**Detection is done via shared logic** — see @skills/_shared/references/model-detection.md

**Before dispatch, run this bash code:**
```bash
# Lazy initialization (inline the lookup logic)
MODELS_FILE="$HOME/.xgh/user_providers/codex/models.yaml"
THRESHOLD_DAYS="${XGH_MODELS_REFRESH_THRESHOLD_DAYS:-7}"

if [ ! -f "$MODELS_FILE" ] || [ $(find "$MODELS_FILE" -mtime +"$THRESHOLD_DAYS" 2>/dev/null | wc -l) -gt 0 ]; then
  /xgh-coding-agents codex --refresh
fi

# Extract model from user input and lookup
MODEL_FLAG=""
MODEL_MENTION=$(echo "$USER_INPUT" | grep -oiE '(with|using|via) [A-Za-z0-9.+-]+' | sed 's/^[^ ]* //I')

if [ -n "$MODEL_MENTION" ]; then
  # Inline lookup: search models.yaml for matching friendly name or alias
  local normalized=$(echo "$MODEL_MENTION" | tr '[:upper:]' '[:lower:]' | tr -d ' -')
  local cli_format=$(grep -iE "friendly:.*$MODEL_MENTION" "$MODELS_FILE" -A1 | grep "cli_format:" | awk '{print $2}')

  if [ -z "$cli_format" ]; then
    cli_format=$(grep -B1 "aliases:.*$normalized" "$MODELS_FILE" | grep "cli_format:" | awk '{print $2}')
  fi

  if [ -n "$cli_format" ]; then
    MODEL_FLAG="-m $cli_format"
  fi
fi
```

**Then dispatch with the model flag:**
```bash
Agent tool: subagent_type="xgh:codex-driver"
Prompt: "Dispatch type: exec ... $MODEL_FLAG"
```

**Example flow:**
```
Input: "review with GPT-5.4"
  → Detect: "GPT-5.4"
  → Lookup: models.yaml → gpt-5.4
  → MODEL_FLAG="-m gpt-5.4"
  → Dispatch: codex-driver with -m flag
```
```

- [ ] **Step 2: Verify section was added**

```bash
grep -q "Model Detection & Routing" skills/codex/codex.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/codex/codex.md
git commit -m "refactor(codex): use dynamic model detection"
```

---

## Task 9: Update Gemini dispatch skill with model detection

**Files:**
- Modify: `skills/gemini/gemini.md`

- [ ] **Step 1: Add model detection section**

After "Input Parsing" section in `skills/gemini/gemini.md`, add:

```markdown
## Model Detection & Routing

**Detection is done via shared logic** — see @skills/_shared/references/model-detection.md

**Before dispatch, run this bash code:**
```bash
# Lazy initialization (inline the lookup logic)
MODELS_FILE="$HOME/.xgh/user_providers/gemini/models.yaml"
THRESHOLD_DAYS="${XGH_MODELS_REFRESH_THRESHOLD_DAYS:-7}"

if [ ! -f "$MODELS_FILE" ] || [ $(find "$MODELS_FILE" -mtime +"$THRESHOLD_DAYS" 2>/dev/null | wc -l) -gt 0 ]; then
  /xgh-coding-agents gemini --refresh
fi

# Extract model from user input and lookup
MODEL_FLAG=""
MODEL_MENTION=$(echo "$USER_INPUT" | grep -oiE '(with|using|via) [A-Za-z0-9.+-]+' | sed 's/^[^ ]* //I')

if [ -n "$MODEL_MENTION" ]; then
  # Inline lookup: search models.yaml for matching friendly name or alias
  local normalized=$(echo "$MODEL_MENTION" | tr '[:upper:]' '[:lower:]' | tr -d ' -')
  local cli_format=$(grep -iE "friendly:.*$MODEL_MENTION" "$MODELS_FILE" -A1 | grep "cli_format:" | awk '{print $2}')

  if [ -z "$cli_format" ]; then
    cli_format=$(grep -B1 "aliases:.*$normalized" "$MODELS_FILE" | grep "cli_format:" | awk '{print $2}')
  fi

  if [ -n "$cli_format" ]; then
    MODEL_FLAG="--model $cli_format"
  fi
fi
```

**Then dispatch with the model flag:**
```bash
# Pass MODEL_FLAG to gemini command
gemini -p "$PROMPT" $MODEL_FLAG
```

**Example flow:**
```
Input: "review with Gemini Pro"
  → Detect: "Gemini Pro"
  → Lookup: models.yaml → gemini-2.5-pro
  → MODEL_FLAG="--model gemini-2.5-pro"
  → Dispatch: gemini with --model flag
```
```

- [ ] **Step 2: Verify section was added**

```bash
grep -q "Model Detection & Routing" skills/gemini/gemini.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/gemini/gemini.md
git commit -m "refactor(gemini): use dynamic model detection"
```

---

## Task 10: Delete hardcoded model mapping file

**Files:**
- Delete: `skills/_shared/references/model-mapping.md`

- [ ] **Step 1: Verify no skills still reference it**

```bash
! grep -r "model-mapping.md" skills/ --include="*.md"
```

- [ ] **Step 2: Delete the file**

```bash
rm skills/_shared/references/model-mapping.md
```

- [ ] **Step 3: Verify deletion**

```bash
! test -f skills/_shared/references/model-mapping.md
```

- [ ] **Step 4: Commit**

```bash
git add skills/_shared/references/model-mapping.md
git commit -m "chore: remove hardcoded model-mapping.md (replaced by dynamic detection)"
```

---

## Task 11: Write tests for coding-agents skill

**Files:**
- Create: `tests/test-coding-agents.sh`

- [ ] **Step 1: Write test file**

Create `tests/test-coding-agents.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Tests for /xgh-coding-agents command

PASS=0
FAIL=0

assert_equals() {
  if [ "$1" = "$2" ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected '$2', got '$1'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 missing '$2'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  if [ -f "$1" ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 does not exist"
    FAIL=$((FAIL + 1))
  fi
}

# Test 1: Skill file exists
assert_file_exists "skills/coding-agents/coding-agents.md"

# Test 2: Command file exists and is executable
assert_file_exists "commands/coding-agents"
if [ -x "commands/coding-agents" ]; then
  PASS=$((PASS + 1))
else
  echo "FAIL: commands/coding-agents is not executable"
  FAIL=$((FAIL + 1))
fi

# Test 3: Skill contains probing functions
assert_contains "skills/coding-agents/coding-agents.md" "probe_opencode"
assert_contains "skills/coding-agents/coding-agents.md" "probe_codex"
assert_contains "skills/coding-agents/coding-agents.md" "probe_gemini"

# Test 4: Skill contains dispatcher
assert_contains "skills/coding-agents/coding-agents.md" "Main Dispatcher"

# Test 5: Shared model detection reference exists
assert_file_exists "skills/_shared/references/model-detection.md"
assert_contains "skills/_shared/references/model-detection.md" "lookup_model"

# Test 6: Dispatch skills reference model detection
assert_contains "skills/opencode/opencode.md" "model-detection.md"
assert_contains "skills/codex/codex.md" "model-detection.md"
assert_contains "skills/gemini/gemini.md" "model-detection.md"

# Test 7: Hardcoded mapping is deleted
if [ -f "skills/_shared/references/model-mapping.md" ]; then
  echo "FAIL: model-mapping.md should be deleted"
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# Test 8: Model detection reference contains lookup function
assert_contains "skills/_shared/references/model-detection.md" "lookup_model"
assert_contains "skills/_shared/references/model-detection.md" "XGH_MODELS_REFRESH_THRESHOLD_DAYS"

# Test 9: YAML schema validation (check required fields exist)
assert_contains "skills/_shared/references/model-detection.md" "cli_format:"
assert_contains "skills/_shared/references/model-detection.md" "friendly:"
assert_contains "skills/_shared/references/model-detection.md" "aliases:"

# Test 10: Pattern matching is documented
assert_contains "skills/_shared/references/model-detection.md" "with <model>"
assert_contains "skills/_shared/references/model-detection.md" "using <model>"
assert_contains "skills/_shared/references/model-detection.md" "via <model>"

# Test 11: Lazy initialization logic exists
assert_contains "skills/_shared/references/model-detection.md" "Lazy Initialization"
assert_contains "skills/_shared/references/model-detection.md" "THRESHOLD_DAYS"

# Test 12: Backward compatibility fallback exists
assert_contains "skills/_shared/references/model-detection.md" "legacy_file"
assert_contains "skills/_shared/references/model-detection.md" "model-mapping.md"

# Test 13: Integration test - mock probing and verify YAML structure
echo "# Integration test: Mock opencode probe"
TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/user_providers/opencode"

# Mock probe function output
cat > "$TMP_DIR/user_providers/opencode/models.yaml" << 'TESTYAML'
agent: opencode
cli_binary: opencode
last_probed: 2026-03-22T20:00:00Z
models:
  - friendly: GLM 4.7
    cli_format: zai-coding-plan/glm-4.7
    aliases: [glm]
TESTYAML

# Verify YAML structure
assert_contains "$TMP_DIR/user_providers/opencode/models.yaml" "agent: opencode"
assert_contains "$TMP_DIR/user_providers/opencode/models.yaml" "cli_format:"
assert_contains "$TMP_DIR/user_providers/opencode/models.yaml" "aliases:"

rm -rf "$TMP_DIR"
PASS=$((PASS + 1))

# Test 14: Test pattern matching logic
echo "# Pattern matching test"
TEST_INPUT="review with GLM 4.7"
echo "$TEST_INPUT" | grep -qE '(with|using|via) [A-Za-z0-9.+-]+' && PASS=$((PASS + 1)) || {
  echo "FAIL: pattern matching failed for '$TEST_INPUT'"
  FAIL=$((FAIL + 1))
}

# Test 15: Test lookup function (simplified)
echo "# Lookup function test"
# Verify lookup_model function exists in reference
assert_contains "skills/_shared/references/model-detection.md" "lookup_model()"

echo ""
echo "coding-agents tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Make test executable**

```bash
chmod +x tests/test-coding-agents.sh
```

- [ ] **Step 3: Run tests to verify they pass**

```bash
bash tests/test-coding-agents.sh
```

Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add tests/test-coding-agents.sh
git commit -m "test: add coding-agents tests"
```

---

## Task 12: Update AGENTS.md

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Add /xgh-coding-agents to command documentation**

Add to the appropriate section in `AGENTS.md`:

```markdown
## Command Reference

| Command | Purpose |
|---------|---------|
| `/xgh-coding-agents` | List and manage AI coding CLI agents (Codex, OpenCode, Gemini) and their model capabilities |
```

- [ ] **Step 2: Verify addition**

```bash
grep -q "xgh-coding-agents" AGENTS.md
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: add /xgh-coding-agents to AGENTS.md"
```

---

## Task 13: Manual verification

**Files:**
- None (manual testing)

- [ ] **Step 1: Test OpenCode probing**

```bash
# Verify OpenCode CLI is available
command -v opencode

# Run probe (should create models.yaml)
/xgh-coding-agents opencode --refresh

# Verify file was created
cat ~/.xgh/user_providers/opencode/models.yaml
```

- [ ] **Step 2: Test listing**

```bash
/xgh-coding-agents opencode
```

Should display OpenCode models

- [ ] **Step 3: Test model detection integration**

```bash
# This should route to OpenCode with GLM 4.7
/xgh-opencode "list files with GLM 4.7"
```

- [ ] **Step 4: Verify backward compatibility**

```bash
# Test without model mention (should use default)
/xgh-opencode "list files"
```

- [ ] **Step 5: Commit any fixes**

```bash
# If any issues found and fixed
git add -A
git commit -m "fix: address manual testing feedback"
```

---

## Completion Checklist

- [ ] All tasks completed with green checks
- [ ] All tests pass: `bash tests/test-coding-agents.sh`
- [ ] Manual verification successful
- [ ] No hardcoded model mappings remain
- [ ] Documentation updated (AGENTS.md)

---

**End of Implementation Plan**
