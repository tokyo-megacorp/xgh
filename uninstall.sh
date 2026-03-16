#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info() { echo -e "  ${GREEN}▸${NC} $*"; }
warn() { echo -e "  ${YELLOW}▸${NC} $*"; }

echo ""
echo -e "  ${BOLD}🐴🤖 xgh${NC} ${DIM}uninstaller${NC}"
echo ""

CLAUDE_DIR="${PWD}/.claude"

deregister_plugin() {
  local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"
  local cache_dir="${HOME}/.claude/plugins/cache/ipedro/xgh"

  # Remove from installed_plugins.json
  if [ -f "$plugins_json" ]; then
    python3 - <<PYEOF
import json, os

plugins_file = "${plugins_json}"
try:
    with open(plugins_file) as f:
        data = json.load(f)
    data.get("plugins", {}).pop("xgh@ipedro", None)
    with open(plugins_file, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("Removed xgh@ipedro from installed_plugins.json")
except Exception as e:
    print(f"Could not update installed_plugins.json: {e}")
PYEOF
  fi

  # Remove all cached plugin versions
  if [ -d "$cache_dir" ]; then
    rm -rf "$cache_dir"
    echo "Removed plugin cache at ${cache_dir}"
  fi
}

# Deregister plugin
info "Deregistering plugin"
deregister_plugin

# Remove hooks
info "Removing hooks"
rm -f "${CLAUDE_DIR}/hooks/"xgh-*.sh

# Remove skills
info "Removing skills"
rm -rf "${CLAUDE_DIR}/skills/"xgh-*

# Remove commands
info "Removing commands"
rm -f "${CLAUDE_DIR}/commands/"xgh-*.md

# Remove agents
info "Removing agents"
rm -f "${CLAUDE_DIR}/agents/"xgh-*.md

# Remove MCP config
info "Removing Cipher MCP config"
GLOBAL_SETTINGS="${HOME}/.claude/settings.json"
if [ -f "$GLOBAL_SETTINGS" ] && jq -e '.mcpServers.cipher' "$GLOBAL_SETTINGS" &>/dev/null; then
  jq 'del(.mcpServers.cipher) | if .mcpServers == {} then del(.mcpServers) else . end' \
    "$GLOBAL_SETTINGS" > "${GLOBAL_SETTINGS}.tmp" \
    && mv "${GLOBAL_SETTINGS}.tmp" "$GLOBAL_SETTINGS"
  info "Cipher removed from ~/.claude/settings.json"
fi
# Also clean legacy project .mcp.json
rm -f "${PWD}/.mcp.json"

# Remove xgh section from CLAUDE.local.md
CLAUDE_MD="${PWD}/CLAUDE.local.md"
if [ -f "$CLAUDE_MD" ] && grep -q "mcs:begin xgh" "$CLAUDE_MD"; then
  info "Cleaning CLAUDE.local.md"
  sed '/<!-- mcs:begin xgh/,/<!-- mcs:end xgh/d' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp"
  mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
fi

# Remove hook events from project settings (leave other settings intact)
SETTINGS_FILE="${CLAUDE_DIR}/settings.local.json"
if [ -f "$SETTINGS_FILE" ] && grep -q "xgh-session-start" "$SETTINGS_FILE"; then
  info "Cleaning project hook registrations"
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
" 2>/dev/null || warn "Could not clean project settings — remove xgh hooks manually"
fi

# Remove hook events from global settings
if [ -f "$GLOBAL_SETTINGS" ] && grep -q "xgh-" "$GLOBAL_SETTINGS"; then
  info "Cleaning global hook registrations"
  python3 -c "
import json
s = json.load(open('${GLOBAL_SETTINGS}'))
if 'hooks' in s:
    for event in list(s['hooks'].keys()):
        s['hooks'][event] = [h for h in s['hooks'][event] if 'xgh-' not in json.dumps(h)]
        if not s['hooks'][event]:
            del s['hooks'][event]
    if not s['hooks']:
        del s['hooks']
json.dump(s, open('${GLOBAL_SETTINGS}', 'w'), indent=2)
" 2>/dev/null || warn "Could not clean global settings — remove xgh hooks manually"
fi
# Remove global hook scripts
rm -f "${HOME}/.claude/hooks/"xgh-*.sh

# Optional: offer to uninstall plugins
if command -v claude &>/dev/null; then
  echo ""
  info "These plugins work independently — uninstall only if you no longer want them:"
  echo -e "    ${DIM}claude plugin uninstall context-mode@context-mode${NC}"
  echo -e "    ${DIM}claude plugin uninstall superpowers@superpowers${NC}"
fi

echo ""
echo -e "  ${BOLD}🐴🤖 xgh uninstalled.${NC} ${DIM}The horse has left the building.${NC}"
echo ""
echo -e "  ${DIM}Context tree (.xgh/) and global pack (~/.xgh/) are preserved.${NC}"
echo -e "  ${DIM}To remove completely: rm -rf .xgh ~/.xgh${NC}"
echo ""
