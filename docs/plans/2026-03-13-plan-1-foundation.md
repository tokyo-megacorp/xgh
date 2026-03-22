# xgh Foundation — Implementation Plan (Plan 1 of 6)

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the xgh project with a working tech pack manifest, BYOP provider config system, and one-liner install script — everything needed so that `mcs sync` or `curl | bash` produces a fully configured Claude Code environment with Cipher MCP.

**Architecture:** Shell-based install script + YAML config for BYOP providers + MCS tech pack manifest. No custom runtime code yet — this plan creates the skeleton that Plans 2-6 build on.

**Tech Stack:** Bash, YAML, JSON, MCS tech pack schema v1

**Design doc:** `docs/plans/2026-03-13-xgh-design.md`

---

## File Structure

```
xgh/
├── techpack.yaml                      # MCS tech pack manifest
├── install.sh                         # Standalone one-liner installer
├── uninstall.sh                       # Clean removal script
├── config/
│   ├── settings.json                  # Claude Code settings (merged by MCS)
│   ├── hooks-settings.json            # Hook event registrations
│   └── presets/                       # BYOP provider presets
│       ├── local.yaml                 # Default: vllm-mlx + Qdrant
│       ├── local-light.yaml           # vllm-mlx + in-memory vectors
│       ├── openai.yaml                # OpenAI GPT-4o-mini + Qdrant
│       ├── anthropic.yaml             # Claude Haiku + Qdrant
│       └── cloud.yaml                 # OpenRouter + Qdrant Cloud
├── hooks/
│   ├── session-start.sh               # Placeholder (Plan 3)
│   └── prompt-submit.sh               # Placeholder (Plan 3)
├── skills/                            # Placeholder dirs (Plans 3-6)
│   └── .gitkeep
├── commands/                          # Placeholder dirs (Plan 4)
│   └── .gitkeep
├── agents/                            # Placeholder dirs (Plan 5)
│   └── .gitkeep
├── templates/
│   └── instructions.md                # CLAUDE.local.md template
├── scripts/
│   └── configure.sh                   # Post-install project config
├── tests/
│   ├── test-install.sh                # Install script integration test
│   └── test-config.sh                 # Config/preset validation test
└── docs/
    └── plans/                         # Design + implementation plans
```

---

## Chunk 1: Project Scaffold & Config System

### Task 1: Initialize project structure

**Files:**
- Create: `techpack.yaml` (stub — full manifest in Task 6)
- Create: `config/presets/local.yaml`
- Create: `config/presets/local-light.yaml`
- Create: `config/presets/openai.yaml`
- Create: `config/presets/anthropic.yaml`
- Create: `config/presets/cloud.yaml`
- Create: `hooks/.gitkeep`
- Create: `skills/.gitkeep`
- Create: `commands/.gitkeep`
- Create: `agents/.gitkeep`

- [ ] **Step 1: Write test for preset validation**

```bash
# tests/test-config.sh
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then
    ((PASS++))
  else
    echo "FAIL: $1 does not exist"
    ((FAIL++))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    ((PASS++))
  else
    echo "FAIL: $1 does not contain '$2'"
    ((FAIL++))
  fi
}

# Test preset files exist
assert_file_exists "config/presets/local.yaml"
assert_file_exists "config/presets/local-light.yaml"
assert_file_exists "config/presets/openai.yaml"
assert_file_exists "config/presets/anthropic.yaml"
assert_file_exists "config/presets/cloud.yaml"

# Test presets have required fields
for preset in config/presets/*.yaml; do
  assert_contains "$preset" "provider:"
  assert_contains "$preset" "model:"
done

# Test local preset has correct defaults
assert_contains "config/presets/local.yaml" "provider: openai"
assert_contains "config/presets/local.yaml" "model: llama3.2:3b"
assert_contains "config/presets/local.yaml" "model: nomic-embed-text"
assert_contains "config/presets/local.yaml" "type: qdrant"

# Test cloud providers require API key placeholder
assert_contains "config/presets/openai.yaml" "OPENAI_API_KEY"
assert_contains "config/presets/anthropic.yaml" "ANTHROPIC_API_KEY"

# Test placeholder dirs exist
assert_file_exists "hooks/.gitkeep"
assert_file_exists "skills/.gitkeep"
assert_file_exists "commands/.gitkeep"
assert_file_exists "agents/.gitkeep"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-config.sh`
Expected: FAIL — no preset files exist yet

- [ ] **Step 3: Create preset files**

```yaml
# config/presets/local.yaml
# xgh BYOP preset: local (default)
# Free, fully offline, no API keys needed
# Requires vllm-mlx running: vllm-mlx --model <model>
llm:
  provider: openai
  model: llama3.2:3b
  baseUrl: http://localhost:11434/v1
  apiKey: placeholder
embeddings:
  provider: openai
  model: nomic-embed-text
  baseUrl: http://localhost:11434/v1
  apiKey: placeholder
vector_store:
  type: qdrant
  url: http://localhost:6333
```

```yaml
# config/presets/local-light.yaml
# xgh BYOP preset: local-light
# Free, fully offline, no persistence (vectors lost on restart)
# Requires vllm-mlx running: vllm-mlx --model <model>
llm:
  provider: openai
  model: llama3.2:3b
  baseUrl: http://localhost:11434/v1
  apiKey: placeholder
embeddings:
  provider: openai
  model: nomic-embed-text
  baseUrl: http://localhost:11434/v1
  apiKey: placeholder
vector_store:
  type: in-memory
```

```yaml
# config/presets/openai.yaml
# xgh BYOP preset: openai
# ~$0.01/session, requires OPENAI_API_KEY
llm:
  provider: openai
  model: gpt-4o-mini
  api_key: ${OPENAI_API_KEY}
embeddings:
  provider: openai
  model: text-embedding-3-small
  api_key: ${OPENAI_API_KEY}
vector_store:
  type: qdrant
  url: http://localhost:6333
```

```yaml
# config/presets/anthropic.yaml
# xgh BYOP preset: anthropic
# ~$0.01/session, requires ANTHROPIC_API_KEY
llm:
  provider: anthropic
  model: claude-haiku-4-5-20251001
  api_key: ${ANTHROPIC_API_KEY}
embeddings:
  provider: openai
  model: nomic-embed-text
  baseUrl: http://localhost:11434/v1
  apiKey: placeholder
vector_store:
  type: qdrant
  url: http://localhost:6333
```

```yaml
# config/presets/cloud.yaml
# xgh BYOP preset: cloud
# ~$0.02/session, requires OPENROUTER_API_KEY
llm:
  provider: openrouter
  model: auto
  api_key: ${OPENROUTER_API_KEY}
embeddings:
  provider: openai
  model: text-embedding-3-small
  api_key: ${OPENAI_API_KEY}
vector_store:
  type: qdrant
  url: ${QDRANT_CLOUD_URL}
  api_key: ${QDRANT_API_KEY}
```

- [ ] **Step 4: Create placeholder directories**

```bash
mkdir -p hooks skills commands agents
touch hooks/.gitkeep skills/.gitkeep commands/.gitkeep agents/.gitkeep
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-config.sh`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add config/ hooks/ skills/ commands/ agents/ tests/test-config.sh
git commit -m "feat: add BYOP provider presets and project scaffold"
```

---

### Task 2: Create Claude Code settings and hook registration

**Files:**
- Create: `config/settings.json`
- Create: `config/hooks-settings.json`

- [ ] **Step 1: Write test for settings validation**

Append to `tests/test-config.sh`:

```bash
# Test settings files
assert_file_exists "config/settings.json"
assert_file_exists "config/hooks-settings.json"

# Test settings.json is valid JSON
if python3 -c "import json; json.load(open('config/settings.json'))" 2>/dev/null; then
  ((PASS++))
else
  echo "FAIL: config/settings.json is not valid JSON"
  ((FAIL++))
fi

# Test hooks-settings.json registers hook events
assert_contains "config/hooks-settings.json" "SessionStart"
assert_contains "config/hooks-settings.json" "UserPromptSubmit"
assert_contains "config/hooks-settings.json" "xgh-session-start.sh"
assert_contains "config/hooks-settings.json" "xgh-prompt-submit.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-config.sh`
Expected: FAIL — settings files don't exist yet

- [ ] **Step 3: Create settings files**

```json
// config/settings.json
{
  "permissions": {
    "allow": [
      "mcp__cipher__cipher_memory_search",
      "mcp__cipher__cipher_extract_and_operate_memory",
      "mcp__cipher__cipher_store_reasoning_memory",
      "mcp__cipher__cipher_search_reasoning_patterns",
      "mcp__cipher__cipher_extract_reasoning_steps",
      "mcp__cipher__cipher_evaluate_reasoning",
      "mcp__cipher__cipher_bash"
    ]
  }
}
```

```json
// config/hooks-settings.json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": ".claude/hooks/xgh-session-start.sh"
      }
    ],
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": ".claude/hooks/xgh-prompt-submit.sh"
      }
    ]
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-config.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add config/settings.json config/hooks-settings.json tests/test-config.sh
git commit -m "feat: add Claude Code settings and hook event registration"
```

---

### Task 3: Create CLAUDE.local.md template

**Files:**
- Create: `templates/instructions.md`

- [ ] **Step 1: Write test**

Append to `tests/test-config.sh`:

```bash
# Test template
assert_file_exists "templates/instructions.md"
assert_contains "templates/instructions.md" "xgh"
assert_contains "templates/instructions.md" "cipher_memory_search"
assert_contains "templates/instructions.md" "cipher_extract_and_operate_memory"
assert_contains "templates/instructions.md" "__TEAM_NAME__"
assert_contains "templates/instructions.md" "__CONTEXT_TREE_PATH__"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-config.sh`
Expected: FAIL

- [ ] **Step 3: Create template**

```markdown
<!-- templates/instructions.md -->
# xgh (extreme-go-horsebot) — Self-Learning Memory

This project uses xgh for persistent team memory powered by Cipher.
Your hooks automatically query memory before coding and curate learnings after.

## Team: __TEAM_NAME__
## Context Tree: __CONTEXT_TREE_PATH__/

## Available Cipher MCP Tools

**Memory Operations:**
- `cipher_memory_search` — Search prior knowledge before writing code
- `cipher_extract_and_operate_memory` — Store new knowledge (ADD/UPDATE/DELETE)
- `cipher_store_reasoning_memory` — Preserve high-quality reasoning traces

**Reasoning:**
- `cipher_extract_reasoning_steps` — Extract structured reasoning from conversation
- `cipher_evaluate_reasoning` — Assess reasoning quality
- `cipher_search_reasoning_patterns` — Find similar past reasoning

**Team (if workspace enabled):**
- `cipher_workspace_search` — Search team-wide knowledge
- `cipher_workspace_store` — Share knowledge with the team

## Decision Table (enforced by hooks)

Before writing code → query memory for conventions and related work.
After writing code → curate learnings, decisions, and patterns.
Made a decision → store rationale and alternatives considered.
Fixed a bug → store root cause, fix, and trigger conditions.

## Context Tree

Human-readable knowledge in `__CONTEXT_TREE_PATH__/`:
- Organized by domain → topic → subtopic
- YAML frontmatter tracks importance and maturity
- Git-committed — shared via normal git workflows
- Core conventions auto-loaded on session start
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-config.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add templates/instructions.md tests/test-config.sh
git commit -m "feat: add CLAUDE.local.md template with xgh instructions"
```

---

## Chunk 2: Install Script

### Task 4: Create the standalone install script

**Files:**
- Create: `install.sh`
- Create: `tests/test-install.sh`

- [ ] **Step 1: Write install test (dry-run mode)**

```bash
# tests/test-install.sh
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then
    ((PASS++))
  else
    echo "FAIL: expected '$2', got '$1'"
    ((FAIL++))
  fi
}

assert_file_exists() {
  if [ -f "$1" ]; then ((PASS++)); else echo "FAIL: $1 missing"; ((FAIL++)); fi
}

assert_dir_exists() {
  if [ -d "$1" ]; then ((PASS++)); else echo "FAIL: dir $1 missing"; ((FAIL++)); fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then ((PASS++)); else echo "FAIL: $1 missing '$2'"; ((FAIL++)); fi
}

assert_executable() {
  if [ -x "$1" ]; then ((PASS++)); else echo "FAIL: $1 not executable"; ((FAIL++)); fi
}

# Setup temp project dir
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
cd "$TMPDIR"
git init --quiet

# Run install in dry-run mode (skips brew/vllm-mlx, uses local files)
export XGH_DRY_RUN=1
export XGH_TEAM="test-team"
export XGH_CONTEXT_PATH=".xgh/context-tree"
export XGH_LOCAL_PACK="$(cd - >/dev/null && pwd)"

bash "${XGH_LOCAL_PACK}/install.sh"

# Verify .claude directory structure
assert_dir_exists ".claude"
assert_dir_exists ".claude/hooks"
assert_dir_exists ".claude/skills"
assert_dir_exists ".claude/commands"
assert_dir_exists ".claude/agents"

# Verify MCP config
assert_file_exists ".claude/.mcp.json"
assert_contains ".claude/.mcp.json" "cipher"
assert_contains ".claude/.mcp.json" "@byterover/cipher"

# Verify hooks installed
assert_file_exists ".claude/hooks/xgh-session-start.sh"
assert_file_exists ".claude/hooks/xgh-prompt-submit.sh"
assert_executable ".claude/hooks/xgh-session-start.sh"
assert_executable ".claude/hooks/xgh-prompt-submit.sh"

# Verify settings
assert_file_exists ".claude/settings.local.json"
assert_contains ".claude/settings.local.json" "SessionStart"

# Verify context tree initialized
assert_dir_exists ".xgh/context-tree"
assert_file_exists ".xgh/context-tree/_manifest.json"
assert_contains ".xgh/context-tree/_manifest.json" "test-team"

# Verify CLAUDE.local.md
assert_file_exists "CLAUDE.local.md"
assert_contains "CLAUDE.local.md" "xgh"
assert_contains "CLAUDE.local.md" "test-team"

# Verify .gitignore updated
assert_file_exists ".gitignore"
assert_contains ".gitignore" ".xgh/local/"

echo ""
echo "Install test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-install.sh`
Expected: FAIL — install.sh doesn't exist

- [ ] **Step 3: Create install.sh**

```bash
# install.sh
#!/usr/bin/env bash
set -euo pipefail

XGH_VERSION="${XGH_VERSION:-latest}"
XGH_TEAM="${XGH_TEAM:-my-team}"
XGH_CONTEXT_PATH="${XGH_CONTEXT_PATH:-.xgh/context-tree}"
XGH_PRESET="${XGH_PRESET:-local}"
XGH_DRY_RUN="${XGH_DRY_RUN:-0}"
XGH_LOCAL_PACK="${XGH_LOCAL_PACK:-}"
XGH_REPO="https://github.com/extreme-go-horse/xgh"

# ── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}→${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

echo ""
echo "🐴 xgh (extreme-go-horsebot) installer"
echo "   Team: ${XGH_TEAM} | Preset: ${XGH_PRESET}"
echo ""

# ── 1. Dependencies ──────────────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  info "Checking dependencies..."

  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if ! command -v vllm-mlx &>/dev/null; then
    info "Installing vllm-mlx..."
    brew install vllm-mlx
  fi

  # Only install Qdrant for presets that need it
  if [ "$XGH_PRESET" != "local-light" ]; then
    if ! command -v qdrant &>/dev/null; then
      info "Installing Qdrant..."
      brew install qdrant
    fi
  fi

  # ── 2. Models ──────────────────────────────────────────
  info "Models are served by vllm-mlx — ensure it is running with the required models"
else
  info "[DRY RUN] Skipping dependency installation"
fi

# ── 3. Fetch xgh pack ───────────────────────────────────
if [ -n "$XGH_LOCAL_PACK" ]; then
  PACK_DIR="$XGH_LOCAL_PACK"
  info "Using local pack: ${PACK_DIR}"
else
  PACK_DIR="${HOME}/.xgh/pack"
  info "Fetching xgh..."
  mkdir -p "$(dirname "$PACK_DIR")"

  if [ -d "$PACK_DIR" ]; then
    git -C "$PACK_DIR" pull --quiet 2>/dev/null || warn "Could not update pack"
  else
    git clone --quiet --depth 1 "$XGH_REPO" "$PACK_DIR"
  fi
fi

# ── 4. Cipher MCP Server ────────────────────────────────
info "Configuring Cipher MCP server..."
CLAUDE_DIR="${PWD}/.claude"
mkdir -p "${CLAUDE_DIR}"

# Read preset for env vars
PRESET_FILE="${PACK_DIR}/config/presets/${XGH_PRESET}.yaml"
if [ ! -f "$PRESET_FILE" ]; then
  error "Unknown preset: ${XGH_PRESET}"
  error "Available: local, local-light, openai, anthropic, cloud"
  exit 1
fi

# Extract vector store type and URL from preset (simple parsing)
VS_TYPE=$(grep 'type:' "$PRESET_FILE" | tail -1 | awk '{print $2}')
VS_URL=$(grep 'url:' "$PRESET_FILE" | tail -1 | awk '{print $2}' || echo "")

# Build env block for MCP config
MCP_ENV="{
        \"VECTOR_STORE_TYPE\": \"${VS_TYPE}\",
        \"CIPHER_LOG_LEVEL\": \"info\",
        \"SEARCH_MEMORY_TYPE\": \"both\",
        \"USE_WORKSPACE_MEMORY\": \"true\",
        \"XGH_TEAM\": \"${XGH_TEAM}\""

# Add vector store URL if present
if [ -n "$VS_URL" ] && [ "$VS_URL" != '${QDRANT_CLOUD_URL}' ]; then
  MCP_ENV="${MCP_ENV},
        \"VECTOR_STORE_URL\": \"${VS_URL}\""
fi

MCP_ENV="${MCP_ENV}
      }"

cat > "${CLAUDE_DIR}/.mcp.json" <<MCPEOF
{
  "mcpServers": {
    "cipher": {
      "command": "npx",
      "args": ["-y", "@byterover/cipher"],
      "env": ${MCP_ENV}
    }
  }
}
MCPEOF

# ── 5. Hooks ────────────────────────────────────────────
info "Installing hooks..."
mkdir -p "${CLAUDE_DIR}/hooks"

# Copy hook files (or create placeholders if not in pack yet)
for hook in session-start prompt-submit; do
  src="${PACK_DIR}/hooks/${hook}.sh"
  dst="${CLAUDE_DIR}/hooks/xgh-${hook}.sh"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
  else
    # Placeholder hook
    cat > "$dst" <<'HOOKEOF'
#!/usr/bin/env bash
# xgh placeholder hook — replaced by Plan 3
exit 0
HOOKEOF
  fi
  chmod +x "$dst"
done

# ── 6. Settings ─────────────────────────────────────────
info "Configuring Claude Code settings..."
SETTINGS_FILE="${CLAUDE_DIR}/settings.local.json"

# Start with hooks-settings as base, merge with existing if present
HOOKS_SETTINGS="${PACK_DIR}/config/hooks-settings.json"
PERMS_SETTINGS="${PACK_DIR}/config/settings.json"

if [ -f "$SETTINGS_FILE" ] && [ -s "$SETTINGS_FILE" ]; then
  # Merge: existing + hooks + permissions
  # Use python3 for reliable JSON merge (available on macOS)
  python3 -c "
import json, sys
base = json.load(open('${SETTINGS_FILE}'))
for f in sys.argv[1:]:
    with open(f) as fh:
        overlay = json.load(fh)
        for k, v in overlay.items():
            if k in base and isinstance(base[k], dict) and isinstance(v, dict):
                base[k].update(v)
            else:
                base[k] = v
json.dump(base, open('${SETTINGS_FILE}', 'w'), indent=2)
" "$HOOKS_SETTINGS" "$PERMS_SETTINGS" 2>/dev/null || {
    # Fallback: just use hooks settings
    cp "$HOOKS_SETTINGS" "$SETTINGS_FILE"
  }
else
  # No existing settings — merge hooks + permissions
  python3 -c "
import json
hooks = json.load(open('${HOOKS_SETTINGS}'))
perms = json.load(open('${PERMS_SETTINGS}'))
merged = {**hooks, **perms}
json.dump(merged, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null || cp "$HOOKS_SETTINGS" "$SETTINGS_FILE"
fi

# ── 7. Skills + Commands + Agents ────────────────────────
info "Installing skills, commands, and agents..."
mkdir -p "${CLAUDE_DIR}/skills" "${CLAUDE_DIR}/commands" "${CLAUDE_DIR}/agents"

for skill_dir in "${PACK_DIR}/skills/"*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  [ "$skill_name" = ".gitkeep" ] && continue
  cp -r "$skill_dir" "${CLAUDE_DIR}/skills/xgh-${skill_name}"
done

for cmd in "${PACK_DIR}/commands/"*.md; do
  [ -f "$cmd" ] || continue
  cp "$cmd" "${CLAUDE_DIR}/commands/xgh-$(basename "$cmd")"
done

for agent in "${PACK_DIR}/agents/"*.md; do
  [ -f "$agent" ] || continue
  cp "$agent" "${CLAUDE_DIR}/agents/xgh-$(basename "$agent")"
done

# ── 8. Context Tree ─────────────────────────────────────
info "Initializing context tree..."
mkdir -p "${PWD}/${XGH_CONTEXT_PATH}"

if [ ! -f "${PWD}/${XGH_CONTEXT_PATH}/_manifest.json" ]; then
  cat > "${PWD}/${XGH_CONTEXT_PATH}/_manifest.json" <<MANIFESTEOF
{
  "version": 1,
  "team": "${XGH_TEAM}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "domains": []
}
MANIFESTEOF
fi

# ── 9. Gitignore ─────────────────────────────────────────
info "Updating .gitignore..."
GITIGNORE="${PWD}/.gitignore"
touch "$GITIGNORE"
for pattern in ".xgh/local/" "data/cipher-sessions.db*" ".claude/settings.local.json"; do
  grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null || echo "$pattern" >> "$GITIGNORE"
done

# ── 10. CLAUDE.local.md ─────────────────────────────────
info "Adding xgh instructions to CLAUDE.local.md..."
CLAUDE_MD="${PWD}/CLAUDE.local.md"
if ! grep -q "mcs:begin xgh" "$CLAUDE_MD" 2>/dev/null; then
  TEMPLATE="${PACK_DIR}/templates/instructions.md"
  if [ -f "$TEMPLATE" ]; then
    {
      echo ""
      echo "<!-- mcs:begin xgh.instructions -->"
      sed "s/__TEAM_NAME__/${XGH_TEAM}/g; s|__CONTEXT_TREE_PATH__|${XGH_CONTEXT_PATH}|g" "$TEMPLATE"
      echo "<!-- mcs:end xgh.instructions -->"
    } >> "$CLAUDE_MD"
  else
    cat >> "$CLAUDE_MD" <<CLAUDEEOF

<!-- mcs:begin xgh.instructions -->
# xgh (extreme-go-horsebot) — Self-Learning Memory
Team: ${XGH_TEAM} | Context Tree: ${XGH_CONTEXT_PATH}/
<!-- mcs:end xgh.instructions -->
CLAUDEEOF
  fi
fi

# ── Done ─────────────────────────────────────────────────
echo ""
echo "🐴 xgh installed successfully!"
echo ""
echo "  Team:         ${XGH_TEAM}"
echo "  Preset:       ${XGH_PRESET}"
echo "  Context tree: ${XGH_CONTEXT_PATH}/"
echo "  Cipher MCP:   .claude/.mcp.json"
echo "  Hooks:        .claude/hooks/xgh-*.sh"
echo ""
echo "  Start Claude Code — your memory layer is active."
echo ""
echo "  Customize: XGH_TEAM=my-team XGH_PRESET=openai ./install.sh"
echo ""
```

- [ ] **Step 4: Make install.sh executable**

```bash
chmod +x install.sh
```

- [ ] **Step 5: Run install test to verify it passes**

Run: `bash tests/test-install.sh`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/test-install.sh
git commit -m "feat: add one-liner install script with BYOP preset support"
```

---

### Task 5: Create the uninstall script

**Files:**
- Create: `uninstall.sh`

- [ ] **Step 1: Write test for uninstall**

```bash
# tests/test-uninstall.sh
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_not_exists() {
  if [ ! -e "$1" ]; then ((PASS++)); else echo "FAIL: $1 still exists"; ((FAIL++)); fi
}

assert_not_contains() {
  if ! grep -q "$2" "$1" 2>/dev/null; then ((PASS++)); else echo "FAIL: $1 still contains '$2'"; ((FAIL++)); fi
}

# Setup: install first, then uninstall
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
cd "$TMPDIR"
git init --quiet

export XGH_DRY_RUN=1
export XGH_TEAM="test-team"
export XGH_LOCAL_PACK="$(cd - >/dev/null && pwd)"

# Install
bash "${XGH_LOCAL_PACK}/install.sh" >/dev/null 2>&1

# Uninstall
bash "${XGH_LOCAL_PACK}/uninstall.sh"

# Verify removal
assert_not_exists ".claude/hooks/xgh-session-start.sh"
assert_not_exists ".claude/hooks/xgh-prompt-submit.sh"
assert_not_exists ".claude/.mcp.json"

# CLAUDE.local.md should have xgh section removed
if [ -f "CLAUDE.local.md" ]; then
  assert_not_contains "CLAUDE.local.md" "mcs:begin xgh"
fi

echo ""
echo "Uninstall test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-uninstall.sh`
Expected: FAIL — uninstall.sh doesn't exist

- [ ] **Step 3: Create uninstall.sh**

```bash
# uninstall.sh
#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info() { echo -e "${GREEN}→${NC} $*"; }

echo ""
echo "🐴 Uninstalling xgh..."
echo ""

CLAUDE_DIR="${PWD}/.claude"

# Remove hooks
info "Removing hooks..."
rm -f "${CLAUDE_DIR}/hooks/"xgh-*.sh

# Remove skills
info "Removing skills..."
rm -rf "${CLAUDE_DIR}/skills/"xgh-*

# Remove commands
info "Removing commands..."
rm -f "${CLAUDE_DIR}/commands/"xgh-*.md

# Remove agents
info "Removing agents..."
rm -f "${CLAUDE_DIR}/agents/"xgh-*.md

# Remove MCP config
info "Removing Cipher MCP config..."
rm -f "${CLAUDE_DIR}/.mcp.json"

# Remove xgh section from CLAUDE.local.md
CLAUDE_MD="${PWD}/CLAUDE.local.md"
if [ -f "$CLAUDE_MD" ] && grep -q "mcs:begin xgh" "$CLAUDE_MD"; then
  info "Removing xgh section from CLAUDE.local.md..."
  sed '/<!-- mcs:begin xgh/,/<!-- mcs:end xgh/d' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp"
  mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
fi

# Remove hook events from settings (leave other settings intact)
SETTINGS_FILE="${CLAUDE_DIR}/settings.local.json"
if [ -f "$SETTINGS_FILE" ] && grep -q "xgh-session-start" "$SETTINGS_FILE"; then
  info "Removing hook registrations from settings..."
  python3 -c "
import json
s = json.load(open('${SETTINGS_FILE}'))
if 'hooks' in s:
    for event in list(s['hooks'].keys()):
        s['hooks'][event] = [h for h in s['hooks'][event] if 'xgh-' not in json.dumps(h)]
        if not s['hooks'][event]:
            del s['hooks'][event]
    if not s['hooks']:
        del s['hooks']
json.dump(s, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null || warn "Could not clean settings — remove xgh hooks manually"
fi

echo ""
echo "🐴 xgh uninstalled."
echo ""
echo "  Note: Context tree (.xgh/) and global pack (~/.xgh/) are preserved."
echo "  To remove completely: rm -rf .xgh ~/.xgh"
echo ""
```

- [ ] **Step 4: Make uninstall.sh executable**

```bash
chmod +x uninstall.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-uninstall.sh`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add uninstall.sh tests/test-uninstall.sh
git commit -m "feat: add uninstall script with clean removal"
```

---

## Chunk 3: MCS Tech Pack Manifest & Post-Install Script

### Task 6: Create the MCS tech pack manifest

**Files:**
- Create: `techpack.yaml`

- [ ] **Step 1: Write test for manifest validation**

```bash
# tests/test-techpack.sh
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then ((PASS++)); else echo "FAIL: $1 missing '$2'"; ((FAIL++)); fi
}

assert_file_exists() {
  if [ -f "$1" ]; then ((PASS++)); else echo "FAIL: $1 missing"; ((FAIL++)); fi
}

# Test manifest exists and has required fields
assert_file_exists "techpack.yaml"
assert_contains "techpack.yaml" "schemaVersion: 1"
assert_contains "techpack.yaml" "identifier: xgh"
assert_contains "techpack.yaml" "displayName:"
assert_contains "techpack.yaml" "description:"
assert_contains "techpack.yaml" "components:"

# Test required components are defined
assert_contains "techpack.yaml" "id: vllm-mlx"
assert_contains "techpack.yaml" "id: cipher"
assert_contains "techpack.yaml" "id: settings"
assert_contains "techpack.yaml" "id: gitignore"

# Test hooks are registered
assert_contains "techpack.yaml" "hookEvent: SessionStart"
assert_contains "techpack.yaml" "hookEvent: UserPromptSubmit"

# Test templates and prompts exist
assert_contains "techpack.yaml" "templates:"
assert_contains "techpack.yaml" "prompts:"
assert_contains "techpack.yaml" "TEAM_NAME"

# Test configureProject exists
assert_contains "techpack.yaml" "configureProject:"

# Test referenced files exist
assert_file_exists "scripts/configure.sh"

echo ""
echo "Techpack test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-techpack.sh`
Expected: FAIL

- [ ] **Step 3: Create techpack.yaml**

```yaml
# techpack.yaml
schemaVersion: 1
identifier: xgh
displayName: "xgh (extreme-go-horsebot)"
description: "Self-learning memory layer with team sharing — bring your own providers"
author: "xgh-dev"
minMCSVersion: "0.5.0"

components:
  # ── Infrastructure (plug-and-play) ─────────────────────
  - id: vllm-mlx
    description: "Local OpenAI-compatible proxy for MLX models (LLM + embeddings)"
    brew: vllm-mlx

  - id: qdrant
    description: "Vector store for semantic memory search"
    brew: qdrant

  - id: cipher
    description: "Cipher MCP memory server (by ByteRover)"
    dependencies: [qdrant]
    mcp:
      command: npx
      args: ["-y", "@byterover/cipher"]
      env:
        VECTOR_STORE_TYPE: qdrant
        VECTOR_STORE_URL: "http://localhost:6333"
        CIPHER_LOG_LEVEL: info
        SEARCH_MEMORY_TYPE: both
        USE_WORKSPACE_MEMORY: "true"
        XGH_TEAM: "__TEAM_NAME__"
      scope: project

  # ── Hooks ──────────────────────────────────────────────
  - id: session-start-hook
    description: "Load context tree and team knowledge on session start"
    hookEvent: SessionStart
    hook:
      source: hooks/session-start.sh
      destination: xgh-session-start.sh

  - id: prompt-submit-hook
    description: "Decision table: auto-query before coding, auto-curate after"
    hookEvent: UserPromptSubmit
    hook:
      source: hooks/prompt-submit.sh
      destination: xgh-prompt-submit.sh

  # ── Settings ───────────────────────────────────────────
  - id: settings
    description: "Claude Code settings with Cipher tool permissions"
    isRequired: true
    settingsFile: config/settings.json

  # ── Gitignore ──────────────────────────────────────────
  - id: gitignore
    description: "Ignore local xgh data and Cipher databases"
    isRequired: true
    gitignore:
      - .xgh/local/
      - data/cipher-sessions.db*
      - .claude/settings.local.json

templates:
  - sectionIdentifier: instructions
    contentFile: templates/instructions.md
    placeholders:
      - __TEAM_NAME__
      - __CONTEXT_TREE_PATH__

prompts:
  - key: TEAM_NAME
    type: input
    label: "Team name (used for workspace memory and context tree)"
    default: "my-team"

  - key: CONTEXT_TREE_PATH
    type: input
    label: "Context tree path (where git-committed knowledge lives)"
    default: ".xgh/context-tree"

configureProject:
  script: scripts/configure.sh

supplementaryDoctorChecks:
  - type: shellScript
    name: "Qdrant running"
    section: "xgh Infrastructure"
    command: "curl -sf http://localhost:6333/healthz >/dev/null 2>&1"
    fixCommand: "brew services start qdrant"
    isOptional: false
  - type: shellScript
    name: "vllm-mlx running"
    section: "xgh Infrastructure"
    command: "curl -sf http://localhost:11434/v1/models >/dev/null 2>&1"
    fixCommand: "vllm-mlx --model <embedding-model> &"
    isOptional: false
  - type: directoryExists
    name: "Context tree initialized"
    section: "xgh Memory"
    path: "__CONTEXT_TREE_PATH__"
    isOptional: false
```

- [ ] **Step 4: Create post-install configure script**

```bash
# scripts/configure.sh
#!/usr/bin/env bash
set -euo pipefail

# Called by MCS after sync. Receives:
# - MCS_PROJECT_PATH: project root
# - MCS_RESOLVED_TEAM_NAME: resolved team name
# - MCS_RESOLVED_CONTEXT_TREE_PATH: resolved context tree path

TEAM="${MCS_RESOLVED_TEAM_NAME:-my-team}"
CTX_PATH="${MCS_RESOLVED_CONTEXT_TREE_PATH:-.xgh/context-tree}"
PROJECT="${MCS_PROJECT_PATH:-.}"

echo "🐴 Configuring xgh for project: $(basename "$PROJECT")"

# Initialize context tree if needed
mkdir -p "${PROJECT}/${CTX_PATH}"
if [ ! -f "${PROJECT}/${CTX_PATH}/_manifest.json" ]; then
  cat > "${PROJECT}/${CTX_PATH}/_manifest.json" <<EOF
{
  "version": 1,
  "team": "${TEAM}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "domains": []
}
EOF
  echo "  ✓ Context tree initialized at ${CTX_PATH}/"
else
  echo "  ✓ Context tree already exists at ${CTX_PATH}/"
fi

echo "  ✓ Configuration complete"
```

- [ ] **Step 5: Make configure script executable**

```bash
chmod +x scripts/configure.sh
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test-techpack.sh`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add techpack.yaml scripts/configure.sh tests/test-techpack.sh
git commit -m "feat: add MCS tech pack manifest with configureProject script"
```

---

### Task 7: Create placeholder hooks for Plan 3

**Files:**
- Create: `hooks/session-start.sh`
- Create: `hooks/prompt-submit.sh`

- [ ] **Step 1: Create placeholder hooks**

```bash
# hooks/session-start.sh
#!/usr/bin/env bash
# xgh session-start hook — placeholder for Plan 3
# Will: load context tree, inject core conventions, show status
echo '{"result": "xgh: session-start hook ready (not yet implemented)"}'
exit 0
```

```bash
# hooks/prompt-submit.sh
#!/usr/bin/env bash
# xgh prompt-submit hook — placeholder for Plan 3
# Will: inject decision table (auto-query before code, auto-curate after)
exit 0
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x hooks/session-start.sh hooks/prompt-submit.sh
git add hooks/
git commit -m "feat: add placeholder hooks for session-start and prompt-submit"
```

---

### Task 8: Run full test suite and final commit

- [ ] **Step 1: Run all tests**

```bash
bash tests/test-config.sh && bash tests/test-techpack.sh && bash tests/test-install.sh && bash tests/test-uninstall.sh
```

Expected: All tests PASS

- [ ] **Step 2: Verify install script works end-to-end**

```bash
# In a temp directory, test the full install flow
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init
XGH_DRY_RUN=1 XGH_TEAM=demo XGH_LOCAL_PACK=/Users/pedro/Developer/tr-xgh bash /Users/pedro/Developer/tr-xgh/install.sh
# Verify output shows success
cat .claude/.mcp.json
cat .xgh/context-tree/_manifest.json
cat CLAUDE.local.md
cd -
rm -rf "$TMPDIR"
```

- [ ] **Step 3: Final commit with all remaining files**

```bash
git add -A
git status  # Verify no secrets or large files
git commit -m "feat: complete xgh foundation — scaffold, BYOP, install, tech pack"
```

---

## Summary

After completing this plan, xgh has:

| Artifact | Status |
|----------|--------|
| BYOP provider presets (5 presets) | ✅ Working |
| `install.sh` (standalone one-liner) | ✅ Working, tested |
| `uninstall.sh` (clean removal) | ✅ Working, tested |
| `techpack.yaml` (MCS manifest) | ✅ Valid schema |
| `config/settings.json` (permissions) | ✅ Cipher tools allowed |
| `config/hooks-settings.json` (hook events) | ✅ SessionStart + UserPromptSubmit |
| `templates/instructions.md` (CLAUDE.local.md) | ✅ With placeholders |
| `scripts/configure.sh` (post-install) | ✅ Context tree init |
| Placeholder hooks | ✅ Ready for Plan 3 |
| Placeholder dirs (skills/commands/agents) | ✅ Ready for Plans 3-6 |
| Test suite (4 test files) | ✅ All passing |

**Next:** Plan 2 — Context Tree Engine (the custom markdown knowledge system with scoring and maturity).
