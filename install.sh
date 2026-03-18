#!/usr/bin/env bash
set -euo pipefail

XGH_VERSION="${XGH_VERSION:-latest}"
XGH_TEAM="${XGH_TEAM:-my-team}"
XGH_CONTEXT_TREE="${XGH_CONTEXT_TREE:-.xgh/context-tree}"
XGH_PRESET="${XGH_PRESET:-local}"
XGH_DRY_RUN="${XGH_DRY_RUN:-0}"
XGH_LOCAL_PACK="${XGH_LOCAL_PACK:-}"
XGH_REPO="https://github.com/ipedro/xgh"
XGH_LLM_MODEL="${XGH_LLM_MODEL:-}"
XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-}"
XGH_BACKEND="${XGH_BACKEND:-}"
XGH_REMOTE_URL="${XGH_REMOTE_URL:-}"

# ── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "  ${GREEN}▸${NC} $*"; }
warn()  { echo -e "  ${YELLOW}▸${NC} $*"; }
error() { echo -e "  ${RED}▸${NC} $*" >&2; }
lane()  { echo ""; echo -e "  ${CYAN}━━━${NC} ${BOLD}$*${NC}"; echo ""; }

echo ""
echo -e "  ${BOLD}🐴🤖 xgh${NC} ${DIM}(eXtreme Go Horse)${NC}"
echo -e "  ${DIM}Team: ${XGH_TEAM} · Preset: ${XGH_PRESET}${NC}"
echo ""

# ── 1. Dependencies ──────────────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Saddling up dependencies 🏇"

  if ! command -v brew &>/dev/null; then
    info "Homebrew not found — installing"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Node.js and npm (required by lossless-claude and helper scripts)
  if ! command -v node &>/dev/null; then
    info "Node.js not found — installing via Homebrew"
    brew install node || warn "Could not install Node.js — install manually: brew install node"
  fi

  # context-mode (required — session optimizer, 98% context savings)
  if command -v claude &>/dev/null; then
    info "Installing context-mode..."
    claude plugin marketplace add "mksglu/context-mode" &>/dev/null || true
    claude plugin install "context-mode@context-mode" &>/dev/null || \
      warn "Could not install context-mode — install manually: claude plugin install context-mode@context-mode"
  else
    warn "Claude CLI not found — install context-mode manually: claude plugin marketplace add mksglu/context-mode && claude plugin install context-mode@context-mode"
  fi

  # Python 3 (required for model downloads and settings merging)
  if ! command -v python3 &>/dev/null; then
    info "Python 3 not found — installing via Homebrew"
    brew install python@3 || warn "Could not install Python 3 — install manually: brew install python@3"
  fi

else
  info "Dry run — skipping the heavy lifting 🏋️"
fi

# ── 3b. lossless-claude ────────────────────────────────
lane "Wiring up the memory layer 🧬"

if [ "$XGH_DRY_RUN" -eq 0 ]; then
  if ! command -v lossless-claude &>/dev/null; then
    if command -v npm &>/dev/null; then
      info "Installing lossless-claude..."
      npm install -g github:ipedro/lossless-claude &>/dev/null || {
        warn "Could not install lossless-claude — install manually: npm install -g github:ipedro/lossless-claude"
      }
    else
      warn "npm not found — install Node.js first, then: npm install -g github:ipedro/lossless-claude"
    fi
  else
    info "lossless-claude already installed: $(command -v lossless-claude)"
  fi

  if command -v lossless-claude &>/dev/null; then
    lossless-claude install || warn "lossless-claude install failed — run manually: lossless-claude install"
  else
    warn "lossless-claude not found — run manually once installed: lossless-claude install"
  fi
fi

# ── 3. Fetch xgh pack ───────────────────────────────────
lane "Fetching the tech pack 📦"
if [ -n "$XGH_LOCAL_PACK" ]; then
  PACK_DIR="$XGH_LOCAL_PACK"
  info "Using local pack: ${PACK_DIR}"
else
  PACK_DIR="${HOME}/.xgh/pack"
  info "Pulling from the ranch..."
  mkdir -p "$(dirname "$PACK_DIR")"

  if [ -d "$PACK_DIR" ]; then
    git -C "$PACK_DIR" pull --quiet 2>/dev/null || warn "Could not update pack"
  else
    git clone --quiet --depth 1 "$XGH_REPO" "$PACK_DIR"
  fi
fi

# ── 4. Legacy MCP cleanup ──────────────────────────────
CLAUDE_DIR="${PWD}/.claude"
mkdir -p "${CLAUDE_DIR}"
PROJECT_CLAUDE_MCP="${CLAUDE_DIR}/.mcp.json"

# Clean up any legacy project-level cipher entries from .mcp.json
if [ -f "${PWD}/.mcp.json" ]; then
  LEGACY_KEYS=$(jq -r '.mcpServers | keys[]' "${PWD}/.mcp.json" 2>/dev/null || echo "")
  if [ "$LEGACY_KEYS" = "cipher" ]; then
    rm -f "${PWD}/.mcp.json"
    info "Removed legacy .mcp.json (cipher entry)"
  elif echo "$LEGACY_KEYS" | grep -q "cipher"; then
    jq 'del(.mcpServers.cipher)' "${PWD}/.mcp.json" > "${PWD}/.mcp.json.tmp" \
      && mv "${PWD}/.mcp.json.tmp" "${PWD}/.mcp.json"
    info "Removed stale cipher entry from project .mcp.json"
  fi
fi

# Clean up any legacy project-level cipher entries from .claude/.mcp.json
if [ -f "$PROJECT_CLAUDE_MCP" ]; then
  PROJECT_LEGACY_KEYS=$(jq -r '.mcpServers | keys[]' "$PROJECT_CLAUDE_MCP" 2>/dev/null || echo "")
  if [ "$PROJECT_LEGACY_KEYS" = "cipher" ]; then
    rm -f "$PROJECT_CLAUDE_MCP"
    info "Removed legacy .claude/.mcp.json (cipher entry)"
  elif echo "$PROJECT_LEGACY_KEYS" | grep -q "cipher"; then
    jq 'del(.mcpServers.cipher)' "$PROJECT_CLAUDE_MCP" > "${PROJECT_CLAUDE_MCP}.tmp" \
      && mv "${PROJECT_CLAUDE_MCP}.tmp" "$PROJECT_CLAUDE_MCP"
    info "Removed stale cipher entry from project .claude/.mcp.json"
  fi
fi

# Clean up any stale cipher entry from global ~/.claude/mcp.json
GLOBAL_MCP="${HOME}/.claude/mcp.json"
if [ -f "$GLOBAL_MCP" ] && jq -e '.mcpServers.cipher' "$GLOBAL_MCP" &>/dev/null; then
  jq 'del(.mcpServers.cipher)' "$GLOBAL_MCP" > "${GLOBAL_MCP}.tmp" \
    && mv "${GLOBAL_MCP}.tmp" "$GLOBAL_MCP"
  info "Removed stale cipher entry from ~/.claude/mcp.json"
fi

# ── 5. Hooks ────────────────────────────────────────────
XGH_HOOKS_SCOPE="${XGH_HOOKS_SCOPE:-}"

if [ -z "$XGH_HOOKS_SCOPE" ] && [ "$XGH_DRY_RUN" -eq 0 ]; then
  echo ""
  echo -e "  ${BOLD}Where should the horse roam?${NC}"
  echo ""
  echo -e "    1) ${GREEN}Global${NC} (~/.claude) — works in all projects ${DIM}(recommended)${NC}"
  echo "    2) Project (.claude) — only this project"
  echo ""
  read -r -p "  🐴 Pick [1]: " hooks_choice
  hooks_choice="${hooks_choice:-1}"
  if [ "$hooks_choice" = "2" ]; then
    XGH_HOOKS_SCOPE="project"
  else
    XGH_HOOKS_SCOPE="global"
  fi
elif [ -z "$XGH_HOOKS_SCOPE" ]; then
  XGH_HOOKS_SCOPE="global"
fi

lane "Hooking into Claude Code 🪝"
if [ "$XGH_HOOKS_SCOPE" = "global" ]; then
  HOOKS_DIR="${HOME}/.claude/hooks"
  SETTINGS_FILE="${HOME}/.claude/settings.json"
  HOOKS_CMD_PREFIX="~/.claude/hooks"
  info "Hooks → global (~/.claude/hooks)"
else
  HOOKS_DIR="${CLAUDE_DIR}/hooks"
  SETTINGS_FILE="${CLAUDE_DIR}/settings.local.json"
  HOOKS_CMD_PREFIX=".claude/hooks"
  info "Hooks → project (.claude/hooks)"
fi

mkdir -p "${HOOKS_DIR}"

# Copy hook files (or create placeholders if not in pack yet)
for hook in session-start prompt-submit; do
  src="${PACK_DIR}/hooks/${hook}.sh"
  dst="${HOOKS_DIR}/xgh-${hook}.sh"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
  else
    # Placeholder hook
    cat > "$dst" <<'HOOKEOF'
#!/usr/bin/env bash
# xgh placeholder hook
exit 0
HOOKEOF
  fi
  chmod +x "$dst"
done


# ── 6. Settings ─────────────────────────────────────────
lane "Tuning permissions ⚙️"
# SETTINGS_FILE was set in section 5 based on scope

HOOKS_SETTINGS="${PACK_DIR}/config/hooks-settings.json"
PERMS_SETTINGS="${PACK_DIR}/config/settings.json"

# Resolve hook command paths from template placeholder
RESOLVED_HOOKS=$(python3 -c "
import json
with open('${HOOKS_SETTINGS}') as f:
    data = json.load(f)
# Replace __HOOKS_DIR__ placeholder with actual path
raw = json.dumps(data)
raw = raw.replace('__HOOKS_DIR__', '${HOOKS_CMD_PREFIX}')
print(raw)
" 2>/dev/null)

if [ -f "$SETTINGS_FILE" ] && [ -s "$SETTINGS_FILE" ]; then
  # Merge: existing + hooks + permissions — deep-merge hooks.* arrays to preserve co-installed tool hooks
  python3 -c "
import json

def deep_merge(base, overlay):
    result = dict(base)
    for key, val in overlay.items():
        if key == 'hooks' and isinstance(result.get('hooks'), dict) and isinstance(val, dict):
            merged_hooks = dict(result['hooks'])
            for event, entries in val.items():
                existing = merged_hooks.get(event, [])
                existing_cmds = {h['command'] for e in existing for h in e.get('hooks', [])}
                new_entries = [e for e in entries if not any(h['command'] in existing_cmds for h in e.get('hooks', []))]
                merged_hooks[event] = existing + new_entries
            result['hooks'] = merged_hooks
        else:
            result[key] = val
    return result

base = json.load(open('${SETTINGS_FILE}'))
hooks_data = json.loads('''${RESOLVED_HOOKS}''')
perms_data = json.load(open('${PERMS_SETTINGS}'))
result = deep_merge(deep_merge(base, hooks_data), perms_data)
json.dump(result, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null || {
    warn "Could not merge settings — writing fresh"
    python3 -c "
import json
hooks_data = json.loads('''${RESOLVED_HOOKS}''')
perms_data = json.load(open('${PERMS_SETTINGS}'))
merged = {**hooks_data, **perms_data}
json.dump(merged, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null
  }
else
  # No existing settings — merge hooks + permissions
  python3 -c "
import json
hooks_data = json.loads('''${RESOLVED_HOOKS}''')
perms_data = json.load(open('${PERMS_SETTINGS}'))
merged = {**hooks_data, **perms_data}
json.dump(merged, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null
fi

# ── Plugin Registration ────────────────────────────────────
register_plugin() {
  local plugin_name="xgh"
  local registry="ipedro"
  local registry_key="${plugin_name}@${registry}"

  # Read version from gemini-extension.json
  local version
  version=$(python3 -c "
import json, sys
try:
    d = json.load(open('${PACK_DIR}/plugin/gemini-extension.json'))
    print(d['version'])
except Exception as e:
    print('1.0.0', file=sys.stderr)
    print('1.0.0')
" 2>/dev/null || echo "1.0.0")

  local cache_dir="${HOME}/.claude/plugins/cache/${registry}/${plugin_name}"
  local install_path="${cache_dir}/${version}"
  local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"

  local git_sha
  git_sha=$(git -C "${PACK_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown")

  local now
  now=$(python3 -c "
from datetime import datetime, timezone
print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))
")

  lane "Registering xgh plugin 🔌"
  info "Plugin version: ${version}"
  info "Cache path: ${install_path}"

  # Copy plugin/ contents to versioned cache directory (idempotent — overwrites on re-install)
  mkdir -p "${install_path}"
  cp -r "${PACK_DIR}/plugin/." "${install_path}/"

  # Write registration entry — preserves installedAt from previous install
  # Note: unquoted heredoc (<<PYEOF) intentionally uses shell variable expansion.
  # All interpolated values (paths, timestamps, sha) are safe: no quotes or newlines.
  local marketplace_dir="${HOME}/.claude/plugins/marketplaces/${registry}"
  local known_marketplaces="${HOME}/.claude/plugins/known_marketplaces.json"

  python3 - <<PYEOF
import json, os

plugins_file = "${plugins_json}"
registry_key = "${registry_key}"
install_path = "${install_path}"
version = "${version}"
git_sha = "${git_sha}"
now = "${now}"
marketplace_dir = "${marketplace_dir}"
known_marketplaces = "${known_marketplaces}"
registry = "${registry}"
plugin_name = "${plugin_name}"

# ── Register plugin in installed_plugins.json ──────────────
try:
    with open(plugins_file) as f:
        data = json.load(f)
except Exception:
    data = {"version": 2, "plugins": {}}

existing = data.get("plugins", {}).get(registry_key, [])
installed_at = existing[0].get("installedAt", now) if existing else now

data.setdefault("plugins", {})[registry_key] = [{
    "scope": "user",
    "installPath": install_path,
    "version": version,
    "installedAt": installed_at,
    "lastUpdated": now,
    "gitCommitSha": git_sha
}]

os.makedirs(os.path.dirname(plugins_file), exist_ok=True)
with open(plugins_file, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("Registered xgh@ipedro in installed_plugins.json")

# ── Register marketplace in known_marketplaces.json ────────
try:
    with open(known_marketplaces) as f:
        km = json.load(f)
except Exception:
    km = {}

if registry not in km:
    km[registry] = {
        "source": {
            "source": "github",
            "repo": "ipedro/xgh"
        },
        "installLocation": marketplace_dir,
        "lastUpdated": now
    }
    os.makedirs(os.path.dirname(known_marketplaces), exist_ok=True)
    with open(known_marketplaces, "w") as f:
        json.dump(km, f, indent=2)
        f.write("\n")
    print("Registered ipedro marketplace in known_marketplaces.json")

# ── Copy marketplace manifest to marketplace directory ─────
# Claude Code requires .claude-plugin/marketplace.json in the marketplace dir
# so it can look up plugins by name when loading installed_plugins.json.
src_marketplace_json = os.path.join(install_path, ".claude-plugin", "marketplace.json")
dst_marketplace_dir = os.path.join(marketplace_dir, ".claude-plugin")
dst_marketplace_json = os.path.join(dst_marketplace_dir, "marketplace.json")

if os.path.exists(src_marketplace_json):
    os.makedirs(dst_marketplace_dir, exist_ok=True)
    import shutil
    shutil.copy2(src_marketplace_json, dst_marketplace_json)
    print("Copied marketplace.json to marketplace directory")
else:
    print("Warning: .claude-plugin/marketplace.json not found in plugin cache — skipping marketplace manifest copy")
PYEOF

  # Detect old-style per-project skill copies and warn
  local old_found=false
  for d in "${HOME}/.claude/skills/xgh-"* ".claude/skills/xgh-"*; do
    [ -d "$d" ] && old_found=true && break
  done
  if $old_found; then
    info "Legacy per-project skill copies detected — /xgh-init will clean them up on next run"
  fi

  info "Plugin registered ✓"
}

# ── 7. Plugin Registration ──────────────────────────────────
register_plugin

# ── 8. Context Tree ─────────────────────────────────────
lane "Planting the knowledge tree 🌳"
mkdir -p "${PWD}/${XGH_CONTEXT_TREE}"

if [ ! -f "${PWD}/${XGH_CONTEXT_TREE}/_manifest.json" ]; then
  cat > "${PWD}/${XGH_CONTEXT_TREE}/_manifest.json" <<MANIFESTEOF
{
  "version": 1,
  "team": "${XGH_TEAM}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "entries": []
}
MANIFESTEOF
fi

# ── 9. Gitignore ─────────────────────────────────────────
info "Updating .gitignore"
GITIGNORE="${PWD}/.gitignore"
touch "$GITIGNORE"
for pattern in ".xgh/local/" "data/cipher-sessions.db*" ".claude/settings.local.json" ".mcp.json"; do
  grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null || echo "$pattern" >> "$GITIGNORE"
done

# ── 10. CLAUDE.local.md ─────────────────────────────────
info "Injecting xgh instructions into CLAUDE.local.md"
CLAUDE_MD="${PWD}/CLAUDE.local.md"
if ! grep -q "mcs:begin xgh" "$CLAUDE_MD" 2>/dev/null; then
  TEMPLATE="${PACK_DIR}/templates/instructions.md"
  if [ -f "$TEMPLATE" ]; then
    {
      echo ""
      echo "<!-- mcs:begin xgh.instructions -->"
      sed "s/__TEAM_NAME__/${XGH_TEAM}/g; s|__CONTEXT_TREE_PATH__|${XGH_CONTEXT_TREE}|g" "$TEMPLATE"
      echo "<!-- mcs:end xgh.instructions -->"
    } >> "$CLAUDE_MD"
  else
    cat >> "$CLAUDE_MD" <<CLAUDEEOF

<!-- mcs:begin xgh.instructions -->
# xgh (extreme-go-horsebot) — Self-Learning Memory
Team: ${XGH_TEAM} | Context Tree: ${XGH_CONTEXT_TREE}/
<!-- mcs:end xgh.instructions -->
CLAUDEEOF
  fi
fi

# ── 11. Optional Plugins ──────────────────────────────────
XGH_INSTALL_PLUGINS="${XGH_INSTALL_PLUGINS:-ask}"

install_plugin() {
  local marketplace="$1" plugin="$2" label="$3"
  if command -v claude &>/dev/null; then
    info "${label}"
    claude plugin marketplace add "$marketplace" &>/dev/null || true
    claude plugin install "${plugin}" &>/dev/null || {
      warn "Could not install ${label} — you can install it manually later"
      return 1
    }
    info "${label} ✓"
  else
    warn "Claude CLI not found — install ${label} manually:"
    echo "    claude plugin marketplace add ${marketplace}"
    echo "    claude plugin install ${plugin}"
  fi
}

if [ "$XGH_DRY_RUN" -eq 0 ] && [ "$XGH_INSTALL_PLUGINS" != "skip" ]; then
  lane "Superpowers 🦸"

  # ── superpowers ─────────────────────────────────────────
  INSTALL_SUPERPOWERS="n"
  if [ "$XGH_INSTALL_PLUGINS" = "all" ]; then
    INSTALL_SUPERPOWERS="y"
  elif [ "$XGH_INSTALL_PLUGINS" = "ask" ]; then
    echo ""
    echo -e "  ${BOLD}superpowers${NC} ${DIM}by obra${NC}"
    echo -e "  ${DIM}TDD, brainstorming, plan writing, subagent dev, code review${NC}"
    echo ""
    read -r -p "  🤖 Install? [y/N] " INSTALL_SUPERPOWERS
  fi
  if [[ "$(printf '%s' "$INSTALL_SUPERPOWERS" | tr '[:upper:]' '[:lower:]')" =~ ^y ]]; then
    install_plugin "obra/superpowers-marketplace" "superpowers@superpowers-marketplace" "superpowers"
  fi
fi

# ── 11b. Claude Code MCP Detection ────────────────────────
# Detect what MCPs are already connected in Claude Code (remote or local).
# Skills use this at runtime to know what's available vs. needs setup.

if command -v claude &>/dev/null && [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Detecting connected MCPs 🔌"

  # Parse `claude mcp list` for all connected servers
  CONNECTED_MCPS=""
  while IFS= read -r line; do
    if echo "$line" | grep -q "✓ Connected"; then
      name=$(echo "$line" | sed 's/:.*//' | xargs)
      CONNECTED_MCPS="${CONNECTED_MCPS}${name},"
      info "${name} ✓"
    fi
  done < <(claude mcp list 2>/dev/null)

  if [ -z "$CONNECTED_MCPS" ]; then
    info "No MCPs detected"
  fi

  # Save state for skills to read at runtime
  CONNECTOR_STATE="${PWD}/.xgh/connectors.json"
  mkdir -p "$(dirname "$CONNECTOR_STATE")"
  cat > "$CONNECTOR_STATE" <<CONNEOF
{
  "detected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "connected": [$(echo "$CONNECTED_MCPS" | sed 's/,$//' | sed 's/\([^,]*\)/"\1"/g' | sed 's/,/, /g')],
  "community_mcps": [
    {"name": "Slack", "package": "@anthropic/mcp-slack", "env": ["SLACK_BOT_TOKEN"]},
    {"name": "Linear", "package": "@anthropic/mcp-linear", "env": ["LINEAR_API_KEY"]},
    {"name": "Atlassian", "package": "@anthropic/mcp-atlassian", "env": ["ATLASSIAN_API_TOKEN", "ATLASSIAN_SITE_URL", "ATLASSIAN_EMAIL"]},
    {"name": "Figma", "package": "@anthropic/mcp-figma", "env": ["FIGMA_ACCESS_TOKEN"]},
    {"name": "Asana", "package": "@anthropic/mcp-asana", "env": ["ASANA_ACCESS_TOKEN"]},
    {"name": "Shortcut", "package": "@anthropic/mcp-shortcut", "env": ["SHORTCUT_API_TOKEN"]}
  ]
}
CONNEOF
  info "MCP state → ${CONNECTOR_STATE}"
else
  info "Skipping MCP detection (dry run or no claude CLI)"
fi

# ── 12. Model config ─────────────────────────────────────
info "Writing model configuration to ~/.xgh/models.env"
mkdir -p "$HOME/.xgh"

XGH_MODEL_HOST="${XGH_MODEL_HOST:-127.0.0.1}"

cat > "$HOME/.xgh/models.env" <<MODELSEOF
# xgh model server configuration — generated by installer
XGH_LLM_MODEL="${XGH_LLM_MODEL}"
XGH_EMBED_MODEL="${XGH_EMBED_MODEL}"
XGH_BACKEND="${XGH_BACKEND}"
XGH_REMOTE_URL="${XGH_REMOTE_URL}"
XGH_MODEL_HOST="${XGH_MODEL_HOST}"
MODELSEOF
# Note: model/backend setup is handled by lossless-claude install

# ── xgh-ingest setup ──────────────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Setting up the ingest pipeline 📡"

  mkdir -p "$HOME/.xgh/inbox/processed"
  mkdir -p "$HOME/.xgh/logs"
  mkdir -p "$HOME/.xgh/digests"
  mkdir -p "$HOME/.xgh/calibration"
  mkdir -p "$HOME/.xgh/lib"
  mkdir -p "$HOME/.xgh/schedulers"

  # Copy lib helpers
  cp "${PACK_DIR}/lib/workspace-write.js"  "$HOME/.xgh/lib/"
  cp "${PACK_DIR}/lib/config-reader.sh"    "$HOME/.xgh/lib/"
  cp "${PACK_DIR}/lib/usage-tracker.sh"    "$HOME/.xgh/lib/"
  chmod +x "$HOME/.xgh/lib/config-reader.sh" "$HOME/.xgh/lib/usage-tracker.sh"

  # Copy config template only if ~/.xgh/ingest.yaml doesn't exist yet
  if [ ! -f "$HOME/.xgh/ingest.yaml" ]; then
    cp "${PACK_DIR}/config/ingest-template.yaml" "$HOME/.xgh/ingest.yaml"
    info "Created ~/.xgh/ingest.yaml — edit your profile, then run /xgh-track to add projects"
  fi

  # Copy models plist and substitute XGH_MODEL_HOST placeholder
  sed "s/127\.0\.0\.1/${XGH_MODEL_HOST}/g" \
    "${PACK_DIR}/scripts/schedulers/com.xgh.models.plist" \
    > "$HOME/.xgh/schedulers/com.xgh.models.plist"

  # ── Migrate: unload any previously installed OS-level scheduler ──────────────
  if [ -f "$HOME/.xgh/lib/ingest-schedule.sh" ]; then
    info "Unloading legacy OS scheduler (replaced by Claude-internal CronCreate)..."
    bash "$HOME/.xgh/lib/ingest-schedule.sh" uninstall 2>/dev/null || true
    rm -f "$HOME/.xgh/lib/ingest-schedule.sh"
    info "Legacy scheduler removed. Enable session scheduling with XGH_SCHEDULER=on."
  fi
  info "Run /xgh-doctor to validate the pipeline"
fi

# ── Claude CLI auth check ────────────────────────────────
if command -v claude &>/dev/null; then
  if AUTH_JSON=$(claude auth status 2>/dev/null) && echo "$AUTH_JSON" | grep -q '"loggedIn": true'; then
    AUTH_EMAIL=$(echo "$AUTH_JSON" | grep '"email"' | sed 's/.*"email": *"//;s/".*//')
    info "Claude CLI authenticated${AUTH_EMAIL:+ as ${AUTH_EMAIL}}"
  else
    warn "Claude CLI found but not authenticated"
    warn "Run ${BOLD}claude${NC} to complete login before using xgh"
  fi
else
  warn "Claude CLI not found — install it, then run ${BOLD}claude${NC} to log in"
fi

# ── Done ─────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}🐴🤖 xgh is ready to ride!${NC}"
echo ""
echo -e "  ${DIM}Team${NC}         ${XGH_TEAM}"
echo -e "  ${DIM}Preset${NC}       ${XGH_PRESET}"
echo -e "  ${DIM}Context tree${NC} ${XGH_CONTEXT_TREE}/"
echo -e "  ${DIM}Scope${NC}        ${XGH_HOOKS_SCOPE}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo ""
echo -e "  ${GREEN}1.${NC} Launch Claude    ${DIM}claude${NC}"
echo -e "  ${GREEN}2.${NC} First-run init   ${DIM}/xgh-init${NC}"
echo -e "  ${GREEN}3.${NC} Run briefing     ${DIM}/xgh-brief${NC}"
echo -e ""
echo ""
echo -e "  ${DIM}Your AI now remembers. Ship it. 🐴${NC}"
echo ""
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
