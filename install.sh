#!/usr/bin/env bash
set -euo pipefail

XGH_VERSION="${XGH_VERSION:-latest}"
XGH_TEAM="${XGH_TEAM:-my-team}"
XGH_CONTEXT_PATH="${XGH_CONTEXT_PATH:-.xgh/context-tree}"
XGH_PRESET="${XGH_PRESET:-local}"
XGH_DRY_RUN="${XGH_DRY_RUN:-0}"
XGH_LOCAL_PACK="${XGH_LOCAL_PACK:-}"
XGH_REPO="https://github.com/xgh-dev/xgh"

# ── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}→${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

echo ""
echo "🐴🤖 xgh (extreme-go-horsebot) installer"
echo "   Team: ${XGH_TEAM} | Preset: ${XGH_PRESET}"
echo ""

# ── 1. Dependencies ──────────────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  info "Checking dependencies..."

  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if ! command -v ollama &>/dev/null; then
    info "Installing Ollama..."
    brew install ollama
  fi

  # Only install Qdrant for presets that need it
  if [ "$XGH_PRESET" != "local-light" ]; then
    if ! command -v qdrant &>/dev/null; then
      info "Installing Qdrant..."
      brew install qdrant
    fi
  fi

  # ── 2. Models ──────────────────────────────────────────
  info "Pulling Ollama models (this may take a few minutes on first run)..."
  ollama pull llama3.2:3b 2>/dev/null || warn "Could not pull llama3.2:3b — you may need to start Ollama first"
  ollama pull nomic-embed-text 2>/dev/null || warn "Could not pull nomic-embed-text"
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
echo "🐴🤖 xgh installed successfully!"
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
