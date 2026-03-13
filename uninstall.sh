#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}→${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

echo ""
echo "🐴🤖 Uninstalling xgh..."
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
echo "🐴🤖 xgh uninstalled."
echo ""
echo "  Note: Context tree (.xgh/) and global pack (~/.xgh/) are preserved."
echo "  To remove completely: rm -rf .xgh ~/.xgh"
echo ""
