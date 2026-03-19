#!/usr/bin/env bash
set -euo pipefail

XGH_VERSION="${XGH_VERSION:-latest}"
XGH_TEAM="${XGH_TEAM:-my-team}"
XGH_CONTEXT_TREE="${XGH_CONTEXT_TREE:-.xgh/context-tree}"
XGH_PRESET="${XGH_PRESET:-local}"
XGH_DRY_RUN="${XGH_DRY_RUN:-0}"
XGH_LOCAL_PACK="${XGH_LOCAL_PACK:-}"
XGH_REPO="https://github.com/ipedro/xgh"

# ── RTK constants ─────────────────────────────────────────
RTK_MIN_VERSION="0.31.0"
RTK_REPO="rtk-ai/rtk"
RTK_INSTALL_DIR="${HOME}/.local/bin"

# Detect CPU arch, cross-checking for Rosetta on macOS
_rtk_arch() {
  local arch
  arch="$(uname -m)"
  if [ "$arch" = "x86_64" ] && [ "$(uname -s)" = "Darwin" ]; then
    if sysctl hw.optional.arm64 2>/dev/null | grep -q ': 1'; then
      arch="aarch64"
    fi
  elif [ "$arch" = "arm64" ]; then
    arch="aarch64"
  fi
  echo "$arch"
}

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


  # context-mode (required — session optimizer, 98% context savings)
  if command -v claude &>/dev/null; then
    info "Installing context-mode..."
    claude plugin marketplace add "mksglu/context-mode" &>/dev/null || true
    claude plugin install "context-mode@context-mode" &>/dev/null || \
      warn "Could not install context-mode — install manually: claude plugin install context-mode@context-mode"
  else
    warn "Claude CLI not found — install context-mode manually: claude plugin marketplace add mksglu/context-mode && claude plugin install context-mode@context-mode"
  fi

  # Python 3 (required for settings merging and plugin registration)
  if ! command -v python3 &>/dev/null; then
    warn "Python 3 not found — install manually: brew install python@3"
  fi

else
  info "Dry run — skipping the heavy lifting 🏋️"
fi

# ── 3b. lossless-claude ────────────────────────────────
lane "Wiring up the memory layer 🧬"

if [ "$XGH_DRY_RUN" -eq 0 ] && [ "${XGH_SKIP_LCM:-0}" -eq 0 ]; then
  if ! command -v lossless-claude &>/dev/null; then
    info "Installing lossless-claude..."
    _lcm_installer="$(mktemp /tmp/lossless-claude-install-XXXXXX.sh)"
    if curl -fsSL https://raw.githubusercontent.com/ipedro/lossless-claude/main/install.sh -o "$_lcm_installer"; then
      chmod +x "$_lcm_installer"
      bash "$_lcm_installer" || warn "Could not install lossless-claude — skipping (set XGH_SKIP_LCM=1 to suppress)"
    else
      warn "Could not download lossless-claude installer — skipping (set XGH_SKIP_LCM=1 to suppress)"
    fi
    rm -f "$_lcm_installer"
  else
    info "lossless-claude already installed: $(command -v lossless-claude)"
  fi

  if command -v lossless-claude &>/dev/null; then
    lossless-claude install || {
      warn "lossless-claude install had issues — running diagnostics..."
      lossless-claude doctor 2>/dev/null || warn "Some checks failed — run 'lossless-claude doctor' after fixing"
    }
  else
    info "Skipping lossless-claude setup — memory features unavailable until installed"
  fi
else
  [ "${XGH_SKIP_LCM:-0}" -eq 1 ] && info "Skipping lossless-claude (XGH_SKIP_LCM=1)"
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
for hook in session-start prompt-submit pre-read post-edit post-ctx-call; do
  src="${PACK_DIR}/plugin/hooks/${hook}.sh"
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

# ── 6b. RTK — output compression ─────────────────────────
lane "Installing RTK 🗜️"

if [ "$XGH_DRY_RUN" -eq 0 ] && [ "${XGH_SKIP_RTK:-0}" -eq 0 ]; then
  _RTK_BIN=""

  # Check xgh-managed binary first to avoid PATH-shadowing by e.g. Homebrew installs
  _xgh_rtk="${RTK_INSTALL_DIR}/rtk"
  _check_bin=""
  if [ -x "$_xgh_rtk" ]; then
    _check_bin="$_xgh_rtk"
  elif command -v rtk &>/dev/null; then
    _check_bin="$(command -v rtk)"
  fi

  if [ -n "$_check_bin" ]; then
    _installed_ver="$("$_check_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -z "$_installed_ver" ]; then
      # Can't parse version — trust the binary rather than clobbering it
      warn "RTK: could not parse version from '$("$_check_bin" --version 2>/dev/null | head -1)' — skipping upgrade check"
      _RTK_BIN="$_check_bin"
    elif python3 -c "
v=tuple(int(x) for x in '${_installed_ver}'.split('.'))
m=tuple(int(x) for x in '${RTK_MIN_VERSION}'.split('.'))
exit(0 if v >= m else 1)
" 2>/dev/null; then
      info "RTK already installed: ${_check_bin} (${_installed_ver})"
      _RTK_BIN="$_check_bin"
    fi
    # Warn if a different rtk shadows the one we're using
    if [ -n "$_RTK_BIN" ] && command -v rtk &>/dev/null; then
      _path_rtk="$(command -v rtk)"
      if [ "$_path_rtk" != "$_RTK_BIN" ]; then
        warn "RTK: also found at ${_path_rtk} — it may shadow ${_RTK_BIN} in PATH"
      fi
    fi
  fi

  if [ -z "$_RTK_BIN" ]; then
    _arch="$(_rtk_arch)"
    _os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    case "${_arch}-${_os}" in
      aarch64-darwin) _asset="rtk-aarch64-apple-darwin.tar.gz" ;;
      x86_64-darwin)  _asset="rtk-x86_64-apple-darwin.tar.gz" ;;
      aarch64-linux)  _asset="rtk-aarch64-unknown-linux-gnu.tar.gz" ;;
      x86_64-linux)   _asset="rtk-x86_64-unknown-linux-musl.tar.gz" ;;
      *)
        warn "RTK: unsupported platform ${_arch}-${_os} — skipping"
        _asset=""
        ;;
    esac

    if [ -n "$_asset" ]; then
      _tag="$(curl -sf "https://api.github.com/repos/${RTK_REPO}/releases/latest" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name','v${RTK_MIN_VERSION}'))" \
        2>/dev/null || echo "v${RTK_MIN_VERSION}")"
      _tag="${_tag:-v${RTK_MIN_VERSION}}"

      _base_url="https://github.com/${RTK_REPO}/releases/download/${_tag}"
      _tmpdir="$(mktemp -d)"

      info "Downloading RTK ${_tag} (${_asset})..."
      if curl -sfL "${_base_url}/${_asset}" -o "${_tmpdir}/${_asset}"; then

        _checksum_asset="$(curl -sf "https://api.github.com/repos/${RTK_REPO}/releases/latest" \
          | python3 -c "
import json,sys
assets=[a['name'] for a in json.load(sys.stdin).get('assets',[])
        if 'checksum' in a['name'].lower() or a['name'].endswith('.sha256')]
print(assets[0] if assets else 'checksums.txt')
" 2>/dev/null || echo "checksums.txt")"

        curl -sfL "${_base_url}/${_checksum_asset}" -o "${_tmpdir}/checksums.txt" 2>/dev/null || true

        _verified=0
        if [ -s "${_tmpdir}/checksums.txt" ]; then
          _expected="$(grep "${_asset}" "${_tmpdir}/checksums.txt" | awk '{print $1}')"
          if [ -n "$_expected" ]; then
            if command -v sha256sum &>/dev/null; then
              _actual="$(sha256sum "${_tmpdir}/${_asset}" | awk '{print $1}')"
            else
              _actual="$(shasum -a 256 "${_tmpdir}/${_asset}" | awk '{print $1}')"
            fi
            if [ "$_actual" = "$_expected" ]; then
              _verified=1
            else
              warn "RTK: SHA256 mismatch — aborting install (expected ${_expected}, got ${_actual})"
              _asset=""
            fi
          else
            warn "RTK: no checksum entry found for ${_asset} — installing without verification"
            _verified=1
          fi
        else
          warn "RTK: could not fetch checksums — installing without verification"
          _verified=1
        fi

        if [ "$_verified" -eq 1 ] && [ -n "$_asset" ]; then
          mkdir -p "${RTK_INSTALL_DIR}"
          tar -xzf "${_tmpdir}/${_asset}" -C "${_tmpdir}" 2>/dev/null || true
          _extracted_bin="$(find "${_tmpdir}" -type f -name 'rtk' | head -1)"
          if [ -n "$_extracted_bin" ]; then
            mv "$_extracted_bin" "${RTK_INSTALL_DIR}/rtk"
            chmod +x "${RTK_INSTALL_DIR}/rtk"
            _RTK_BIN="${RTK_INSTALL_DIR}/rtk"
            info "RTK installed: ${_RTK_BIN}"
          else
            warn "RTK: binary not found in archive — skipping"
          fi
        fi
      else
        warn "RTK: download failed — skipping (set XGH_SKIP_RTK=1 to suppress)"
      fi
      rm -rf "$_tmpdir"
    fi
  fi

  if [ -n "$_RTK_BIN" ]; then
    "$_RTK_BIN" --version &>/dev/null || warn "RTK binary installed but --version failed"
    # Register hook via RTK's native init (idempotent, manages rtk-rewrite.sh + CLAUDE.md)
    "$_RTK_BIN" init -g --auto-patch 2>/dev/null \
      && info "RTK hook registered (rtk init -g --auto-patch)" \
      || warn "RTK: hook registration failed — run 'rtk init -g' manually"
  fi

else
  [ "${XGH_SKIP_RTK:-0}" -eq 1 ] && info "Skipping RTK (XGH_SKIP_RTK=1)"
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
for pattern in ".xgh/local/" "data/cipher-sessions.db*" ".claude/settings.local.json" ".mcp.json" ".lossless-claude/"; do
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

# ── xgh-ingest setup ──────────────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Setting up the ingest pipeline 📡"

  mkdir -p "$HOME/.xgh/inbox/processed"
  mkdir -p "$HOME/.xgh/logs"
  mkdir -p "$HOME/.xgh/digests"
  mkdir -p "$HOME/.xgh/calibration"
  mkdir -p "$HOME/.xgh/lib"

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

  # ── Migrate: clean up legacy artifacts ──────────────────────────────────────
  if [ -d "$HOME/.xgh/schedulers" ]; then
    rm -rf "$HOME/.xgh/schedulers"
    info "Removed orphaned ~/.xgh/schedulers/ (replaced by lossless-claude daemon)"
  fi
  if [ -f "$HOME/.xgh/models.env" ]; then
    rm -f "$HOME/.xgh/models.env"
    info "Removed legacy ~/.xgh/models.env (cipher.yml is source of truth)"
  fi

  # ── Migrate: unload any previously installed OS-level scheduler ──────────────
  if [ -f "$HOME/.xgh/lib/ingest-schedule.sh" ]; then
    info "Unloading legacy OS scheduler (replaced by Claude-internal CronCreate)..."
    bash "$HOME/.xgh/lib/ingest-schedule.sh" uninstall 2>/dev/null || true
    rm -f "$HOME/.xgh/lib/ingest-schedule.sh"
    info "Legacy scheduler removed. Enable session scheduling with XGH_SCHEDULER=on."
  fi
  info "Run /xgh-doctor to validate the pipeline"
fi

# ── Post-install validation ──────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Post-install validation 🔍"

  _V_PASS=0
  _V_FAIL=0
  _V_WARN=0

  _check_pass() { _V_PASS=$((_V_PASS + 1)); info "✅ $1"; }
  _check_warn() { _V_WARN=$((_V_WARN + 1)); warn "⚠️  $1"; }
  _check_fail() { _V_FAIL=$((_V_FAIL + 1)); error "❌ $1"; }

  # 1. Memory stack
  if command -v lossless-claude &>/dev/null; then
    if lossless-claude doctor &>/dev/null; then
      _check_pass "Memory stack (lossless-claude doctor)"
    else
      _check_fail "Memory stack — run: lossless-claude doctor"
    fi
  else
    _check_warn "lossless-claude not installed — memory features unavailable"
  fi

  # 2. Plugin registration
  PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"
  if [ -f "$PLUGINS_JSON" ] && python3 -c "
import json, sys
d = json.load(open('${PLUGINS_JSON}'))
sys.exit(0 if 'xgh@ipedro' in d.get('plugins', {}) else 1)
" 2>/dev/null; then
    _check_pass "Plugin: xgh@ipedro registered"
  else
    _check_fail "Plugin not registered — re-run installer"
  fi

  # 3. Skills in cache
  SKILL_COUNT=$(find "${HOME}/.claude/plugins/cache/ipedro/xgh/" -name "*.md" -path "*/skills/*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$SKILL_COUNT" -gt 0 ]; then
    _check_pass "Skills: ${SKILL_COUNT} skills in cache"
  else
    _check_fail "Skills missing from cache — re-run installer"
  fi

  # 4. Hooks in settings
  if [ -f "$SETTINGS_FILE" ] && python3 -c "
import json, sys
d = json.load(open('${SETTINGS_FILE}'))
hooks = d.get('hooks', {})
has_xgh = any('xgh-' in str(h) for event in hooks.values() for h in (event if isinstance(event, list) else []))
sys.exit(0 if has_xgh else 1)
" 2>/dev/null; then
    _check_pass "Hooks: xgh hooks registered"
  else
    _check_warn "xgh hooks may be missing — check settings.json"
  fi

  # 5. Context tree
  if [ -f "${PWD}/${XGH_CONTEXT_TREE}/_manifest.json" ]; then
    _check_pass "Context tree: ${XGH_CONTEXT_TREE}/_manifest.json"
  else
    _check_fail "Context tree missing"
  fi

  # 6. .gitignore
  GITIGNORE="${PWD}/.gitignore"
  if grep -q ".lossless-claude/" "$GITIGNORE" 2>/dev/null; then
    _check_pass "Gitignore: .lossless-claude/ ✓"
  else
    echo ".lossless-claude/" >> "$GITIGNORE"
    _check_warn "Added .lossless-claude/ to .gitignore (was missing)"
  fi

  # 7. Ingest config
  if [ -f "$HOME/.xgh/ingest.yaml" ]; then
    _check_pass "Ingest config: ~/.xgh/ingest.yaml"
  else
    _check_warn "No ingest.yaml — run /xgh-track to configure"
  fi

  # 8. Claude CLI
  if command -v claude &>/dev/null; then
    if AUTH_JSON=$(claude auth status 2>/dev/null) && echo "$AUTH_JSON" | grep -q '"loggedIn": true'; then
      AUTH_EMAIL=$(echo "$AUTH_JSON" | grep '"email"' | sed 's/.*"email": *"//;s/".*//')
      _check_pass "Claude CLI: authenticated${AUTH_EMAIL:+ as ${AUTH_EMAIL}}"
    else
      _check_warn "Claude CLI: not authenticated — run: claude"
    fi
  else
    _check_warn "Claude CLI: not found — install it, then run: claude"
  fi

  echo ""
  info "${_V_PASS} passed, ${_V_FAIL} failed, ${_V_WARN} warnings"
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
