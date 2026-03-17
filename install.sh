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
XGH_MODEL_PORT="${XGH_MODEL_PORT:-11434}"
XGH_BACKEND="${XGH_BACKEND:-}"
XGH_REMOTE_URL="${XGH_REMOTE_URL:-}"
XGH_SERVE_NETWORK="${XGH_SERVE_NETWORK:-0}"

# Determine inference backend: remote if explicitly set, vllm-mlx on Apple Silicon, Ollama everywhere else
if [ -n "$XGH_BACKEND" ] && [ "$XGH_BACKEND" = "remote" ]; then
  : # keep as remote — user explicitly set this
elif [[ "$(uname)" == "Darwin" ]] && [[ "$(uname -m)" == "arm64" ]]; then
  XGH_BACKEND="${XGH_BACKEND:-vllm-mlx}"
else
  XGH_BACKEND="${XGH_BACKEND:-ollama}"
fi

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

# ── 0. Backend / remote URL picker (interactive only) ────
# Skip picker if XGH_BACKEND was explicitly set by the caller
_XGH_BACKEND_WAS_SET="${XGH_BACKEND}"
if [ "$XGH_DRY_RUN" -eq 0 ] && [ -z "${_XGH_BACKEND_WAS_SET}" ]; then
  if [ -z "${_XGH_BACKEND_PICKED:-}" ]; then
    echo ""
    echo -e "  ${BOLD}Which inference backend?${NC}"
    echo ""
    if [ "$XGH_BACKEND" = "vllm-mlx" ]; then
      echo -e "    ${GREEN}1)${NC} Local — vllm-mlx (macOS Apple Silicon)     ${DIM}[auto-detected]${NC}"
    else
      echo "    1) Local — vllm-mlx (macOS Apple Silicon)"
    fi
    if [ "$XGH_BACKEND" = "ollama" ]; then
      echo -e "    ${GREEN}2)${NC} Local — Ollama (Linux / Intel Mac)          ${DIM}[auto-detected]${NC}"
    else
      echo "    2) Local — Ollama (Linux / Intel Mac)"
    fi
    echo "    3) Remote — connect to another machine's server"
    echo ""
    if [ "$XGH_BACKEND" = "vllm-mlx" ]; then
      _DEFAULT_BACKEND_NUM=1
    else
      _DEFAULT_BACKEND_NUM=2
    fi
    read -r -p "  🐴 Pick [${_DEFAULT_BACKEND_NUM}]: " _backend_choice
    _backend_choice="${_backend_choice:-${_DEFAULT_BACKEND_NUM}}"
    case "$_backend_choice" in
      1) XGH_BACKEND="vllm-mlx" ;;
      2) XGH_BACKEND="ollama" ;;
      3) XGH_BACKEND="remote" ;;
      *) : ;; # keep auto-detected
    esac
    _XGH_BACKEND_PICKED=1
  fi
fi

# ── Remote URL prompt and validation ─────────────────────
if [ "$XGH_BACKEND" = "remote" ] && [ "$XGH_DRY_RUN" -eq 0 ]; then
  if [ -z "$XGH_REMOTE_URL" ]; then
    echo ""
    read -r -p "  🐴 Remote server URL [http://192.168.1.x:11434]: " XGH_REMOTE_URL
    XGH_REMOTE_URL="${XGH_REMOTE_URL:-}"
    if [[ ! "$XGH_REMOTE_URL" =~ ^https?:// ]]; then
      echo -e "  ${RED}▸${NC} URL must start with http:// or https://" >&2
      exit 1
    fi
  fi
  if curl -sf --max-time 5 "${XGH_REMOTE_URL}/v1/models" >/dev/null 2>&1; then
    info "Remote server reachable ✓"
  else
    warn "Cannot reach ${XGH_REMOTE_URL} — continuing anyway (server may not be running yet)"
  fi
fi

# ── 1. Dependencies ──────────────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Saddling up dependencies 🏇"

  if ! command -v brew &>/dev/null; then
    info "Homebrew not found — installing"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Node.js and npm (required by Cipher MCP wrapper and helper scripts)
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

  # ── Backend-specific dependencies ───────────────────────
  if [ "$XGH_BACKEND" = "vllm-mlx" ]; then
    # ── Apple Silicon: vllm-mlx + Qdrant via Homebrew ────

    # Install uv (Python package installer) if not present
    if ! command -v uv &>/dev/null; then
      info "uv (Python installer)"
      brew install uv
    fi

    # Install vllm-mlx (local model server for Apple Silicon)
    if ! command -v vllm-mlx &>/dev/null; then
      info "vllm-mlx (local model server for Apple Silicon)"
      uv tool install "git+https://github.com/waybarrios/vllm-mlx.git"
    fi

    # Kill any Ollama process squatting on port 11434
    if pgrep -x ollama >/dev/null 2>&1 || pgrep -x "Ollama" >/dev/null 2>&1; then
      warn "Ollama is running and will conflict with vllm-mlx on port 11434 — stopping it"
      osascript -e 'quit app "Ollama"' 2>/dev/null || true
      pkill -f "[Oo]llama" 2>/dev/null || true
      sleep 1
    fi

    # Only install Qdrant for presets that need it
    if [ "$XGH_PRESET" != "local-light" ]; then
      if ! command -v qdrant &>/dev/null && ! [ -x "${HOME}/.qdrant/bin/qdrant" ]; then
        info "Installing Qdrant..."
        brew install qdrant 2>/dev/null || warn "Could not install Qdrant via brew — install manually or ensure ~/.qdrant/bin/qdrant exists"
      fi

      # Fix Qdrant LaunchAgent plist: add MALLOC_CONF and correct WorkingDirectory
      _QDRANT_BIN=$(command -v qdrant 2>/dev/null || echo "${HOME}/.qdrant/bin/qdrant")
      _QDRANT_PLIST="${HOME}/Library/LaunchAgents/com.qdrant.server.plist"
      _QDRANT_STORAGE="${HOME}/.qdrant/storage"
      mkdir -p "${_QDRANT_STORAGE}"
      if [ -f "$_QDRANT_PLIST" ]; then
        # Inject MALLOC_CONF if not already present
        if ! grep -q "MALLOC_CONF" "$_QDRANT_PLIST" 2>/dev/null; then
          python3 - "$_QDRANT_PLIST" <<'PYEOF'
import sys, re
path = sys.argv[1]
content = open(path).read()
if '<key>MALLOC_CONF</key>' not in content:
    inject = '''    <key>EnvironmentVariables</key>
    <dict>
        <key>MALLOC_CONF</key>
        <string>background_thread:false</string>
    </dict>
'''
    content = content.replace('</dict>\n</plist>', inject + '</dict>\n</plist>')
    open(path, 'w').write(content)
    print('Patched MALLOC_CONF into', path)
PYEOF
          info "Qdrant plist: injected MALLOC_CONF=background_thread:false"
        fi
      fi

      # Clear stale WAL locks before starting (harmless if clean)
      find "${_QDRANT_STORAGE}" -path "*/wal/open-*" -delete 2>/dev/null || true

      # Start Qdrant as a background service if not already running
      if ! curl -sf http://localhost:6333/healthz >/dev/null 2>&1; then
        info "Starting Qdrant background service..."
        if [ -f "$_QDRANT_PLIST" ]; then
          launchctl unload "$_QDRANT_PLIST" 2>/dev/null || true
          launchctl load "$_QDRANT_PLIST" 2>/dev/null \
            || warn "Could not load Qdrant plist — start manually: launchctl load ${_QDRANT_PLIST}"
        else
          brew services start qdrant 2>/dev/null || warn "Could not start Qdrant service — start manually: brew services start qdrant"
        fi
      else
        info "Qdrant is already running"
      fi
    fi

  elif [ "$XGH_BACKEND" = "ollama" ]; then
    # ── Linux / Intel Mac: Ollama + Qdrant binary ────────

    # Install Ollama if not present
    if ! command -v ollama &>/dev/null; then
      info "Installing Ollama..."
      curl -fsSL https://ollama.com/install.sh | sh
    fi

    # Guard: if ollama still not in PATH, abort
    if ! command -v ollama &>/dev/null; then
      warn "Ollama not found after install attempt — install manually: curl -fsSL https://ollama.com/install.sh | sh"
      exit 1
    fi
    info "Ollama: $(command -v ollama)"

    # Install Qdrant binary (arch-aware) for presets that need it
    if [ "$XGH_PRESET" != "local-light" ]; then
      if ! [ -x "${HOME}/.qdrant/bin/qdrant" ]; then
        info "Installing Qdrant binary..."
        mkdir -p "${HOME}/.qdrant/bin"
        ARCH=$(uname -m)
        QDRANT_VER=$(curl -sf "https://api.github.com/repos/qdrant/qdrant/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
        curl -fsSL "https://github.com/qdrant/qdrant/releases/download/${QDRANT_VER}/qdrant-${ARCH}-unknown-linux-gnu.tar.gz" \
          | tar -xz -C "${HOME}/.qdrant/bin/"
        chmod +x "${HOME}/.qdrant/bin/qdrant"
        info "Qdrant ${QDRANT_VER} → ${HOME}/.qdrant/bin/qdrant"
      else
        info "Qdrant already installed: ${HOME}/.qdrant/bin/qdrant"
      fi

      # Write systemd user service for Qdrant
      QDRANT_SVC_DIR="${HOME}/.config/systemd/user"
      mkdir -p "$QDRANT_SVC_DIR"
      mkdir -p "${HOME}/.xgh/logs" "${HOME}/.qdrant/storage"
      cat > "${QDRANT_SVC_DIR}/xgh-qdrant.service" <<QDRANTSVCEOF
[Unit]
Description=Qdrant vector database (xgh)
After=network.target

[Service]
ExecStart=%h/.qdrant/bin/qdrant
WorkingDirectory=%h/.qdrant/storage
Restart=always
RestartSec=5
Environment=HOME=%h
Environment=MALLOC_CONF=background_thread:false
StandardOutput=append:%h/.xgh/logs/qdrant.log
StandardError=append:%h/.xgh/logs/qdrant.log

[Install]
WantedBy=default.target
QDRANTSVCEOF
      loginctl enable-linger "$USER" 2>/dev/null || true
      systemctl --user daemon-reload 2>/dev/null || true
      systemctl --user enable --now xgh-qdrant.service 2>/dev/null \
        || warn "Could not enable xgh-qdrant.service — start manually: systemctl --user start xgh-qdrant"
    fi
  elif [ "$XGH_BACKEND" = "remote" ]; then
    # ── Remote: no local model server — install Qdrant locally for vector storage ──
    info "Remote backend — no local model server install needed"

    if [ "$XGH_PRESET" != "local-light" ]; then
      # Install Qdrant locally (arch-aware, same as Ollama path)
      if ! command -v qdrant &>/dev/null && ! [ -x "${HOME}/.qdrant/bin/qdrant" ]; then
        if [[ "$(uname)" == "Darwin" ]]; then
          info "Installing Qdrant via Homebrew..."
          brew install qdrant 2>/dev/null || warn "Could not install Qdrant via brew — install manually"
        else
          info "Installing Qdrant binary..."
          mkdir -p "${HOME}/.qdrant/bin"
          ARCH=$(uname -m)
          QDRANT_VER=$(curl -sf "https://api.github.com/repos/qdrant/qdrant/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
          curl -fsSL "https://github.com/qdrant/qdrant/releases/download/${QDRANT_VER}/qdrant-${ARCH}-unknown-linux-gnu.tar.gz" \
            | tar -xz -C "${HOME}/.qdrant/bin/"
          chmod +x "${HOME}/.qdrant/bin/qdrant"
          info "Qdrant ${QDRANT_VER} → ${HOME}/.qdrant/bin/qdrant"
        fi
      else
        info "Qdrant already installed"
      fi
    fi
  fi

  # ── 2. Model Selection ─────────────────────────────────
  lane "Picking brains 🧠"

  # Detect installed models in HuggingFace cache (vllm-mlx path)
  HF_CACHE="${HF_HOME:-${HOME}/.cache/huggingface}/hub"
  _model_cached() {
    local slug; slug="models--$(echo "$1" | sed 's|/|--|g')"
    [ -d "${HF_CACHE}/${slug}" ]
  }

  # vllm-mlx model lists (Apple Silicon)
  VLLM_LLM_MODELS=(
    "mlx-community/Llama-3.2-3B-Instruct-4bit|Llama 3.2 3B (default, fast, 2GB)"
    "mlx-community/Llama-3.2-1B-Instruct-4bit|Llama 3.2 1B (tiny, 0.7GB)"
    "mlx-community/Mistral-7B-Instruct-v0.3-4bit|Mistral 7B (powerful, 4GB)"
    "mlx-community/Qwen3-4B-4bit|Qwen3 4B (balanced, 2.5GB)"
    "mlx-community/Qwen3-8B-4bit|Qwen3 8B (strong reasoning, 5GB)"
  )
  VLLM_EMBED_MODELS=(
    "mlx-community/nomicai-modernbert-embed-base-8bit|ModernBERT Embed 8-bit (default, 768 dims, best quality)"
    "mlx-community/nomicai-modernbert-embed-base-4bit|ModernBERT Embed 4-bit (smaller, 768 dims)"
    "mlx-community/all-MiniLM-L6-v2-4bit|MiniLM L6 (fast, 384 dims)"
  )

  # Ollama model lists (Linux / Intel Mac)
  OLLAMA_LLM_MODELS=(
    "llama3.2:3b|Llama 3.2 3B (default, fast, 2GB)"
    "llama3.2:1b|Llama 3.2 1B (tiny, 0.7GB)"
    "mistral:7b|Mistral 7B (powerful, 4GB)"
    "qwen3:4b|Qwen3 4B (balanced, 2.5GB)"
    "qwen3:8b|Qwen3 8B (strong reasoning, 5.2GB)"
  )
  OLLAMA_EMBED_MODELS=(
    "nomic-embed-text|Nomic Embed Text (default, 768 dims, best quality)"
    "mxbai-embed-large|MXBai Embed Large (1024 dims — requires collection recreate)"
    "all-minilm:22m|MiniLM (384 dims — requires collection recreate)"
  )

  # Helper: fetch model IDs from a remote OpenAI-compat server
  _fetch_remote_models() {
    curl -sf "${XGH_REMOTE_URL}/v1/models" 2>/dev/null \
      | python3 -c "import json,sys; [print(m['id'] + '|' + m['id']) for m in json.load(sys.stdin).get('data',[])]" \
      2>/dev/null || true
  }

  # Select active arrays and availability helper based on backend
  if [ "$XGH_BACKEND" = "vllm-mlx" ]; then
    LLM_MODELS=("${VLLM_LLM_MODELS[@]}")
    EMBED_MODELS=("${VLLM_EMBED_MODELS[@]}")
    CUSTOM_LABEL="HuggingFace model ID"
    _model_available() { _model_cached "$1"; }
  elif [ "$XGH_BACKEND" = "remote" ]; then
    # Try to auto-populate from remote server
    CUSTOM_LABEL="Model ID (as reported by remote server)"
    _model_available() {
      curl -sf "${XGH_REMOTE_URL}/v1/models" 2>/dev/null \
        | python3 -c "
import json,sys
data=json.load(sys.stdin)
ids=[m['id'] for m in data.get('data',[])]
print('yes' if '${1}' in ids else 'no')
" 2>/dev/null | grep -q "^yes"
    }
    # Try to populate model lists from remote server
    _REMOTE_MODELS=""
    if [ -n "$XGH_REMOTE_URL" ] && curl -sf --max-time 5 "${XGH_REMOTE_URL}/v1/models" >/dev/null 2>&1; then
      _REMOTE_MODELS=$(_fetch_remote_models)
    fi
    if [ -n "$_REMOTE_MODELS" ]; then
      IFS=$'\n' read -r -d '' -a LLM_MODELS <<< "$_REMOTE_MODELS" || true
      IFS=$'\n' read -r -d '' -a EMBED_MODELS <<< "$_REMOTE_MODELS" || true
      info "Loaded $(echo "$_REMOTE_MODELS" | wc -l | tr -d ' ') model(s) from remote server"
    else
      # Fall back to vllm-mlx list as reference
      LLM_MODELS=("${VLLM_LLM_MODELS[@]}")
      EMBED_MODELS=("${VLLM_EMBED_MODELS[@]}")
      warn "Could not fetch models from remote server — showing vllm-mlx reference list"
    fi
  else
    LLM_MODELS=("${OLLAMA_LLM_MODELS[@]}")
    EMBED_MODELS=("${OLLAMA_EMBED_MODELS[@]}")
    CUSTOM_LABEL="Ollama model name (e.g. llama3.2:3b)"
    _model_available() { ollama list 2>/dev/null | grep -q "^${1}[[:space:]]"; }
  fi

  # Reorder model lists: installed models first, suggestions after
  _sort_installed_first() {
    local _installed=() _rest=()
    for _entry in "$@"; do
      IFS='|' read -r _mid _ <<< "$_entry"
      if _model_available "$_mid"; then
        _installed+=("$_entry")
      else
        _rest+=("$_entry")
      fi
    done
    printf '%s\n' "${_installed[@]+"${_installed[@]}"}" "${_rest[@]+"${_rest[@]}"}"
  }
  _sorted=()
  while IFS= read -r _e; do _sorted+=("$_e"); done < <(_sort_installed_first "${LLM_MODELS[@]}")
  LLM_MODELS=("${_sorted[@]}")
  _sorted=()
  while IFS= read -r _e; do _sorted+=("$_e"); done < <(_sort_installed_first "${EMBED_MODELS[@]}")
  EMBED_MODELS=("${_sorted[@]}")
  unset _sorted _e

  if [ "$XGH_BACKEND" = "vllm-mlx" ]; then
    ORIG_DEFAULT_LLM="mlx-community/Llama-3.2-3B-Instruct-4bit"
    ORIG_DEFAULT_EMBED="mlx-community/nomicai-modernbert-embed-base-8bit"
  elif [ "$XGH_BACKEND" = "remote" ]; then
    # Default to first item in the list
    IFS='|' read -r ORIG_DEFAULT_LLM _ <<< "${LLM_MODELS[0]}"
    IFS='|' read -r ORIG_DEFAULT_EMBED _ <<< "${EMBED_MODELS[0]}"
  else
    ORIG_DEFAULT_LLM="llama3.2:3b"
    ORIG_DEFAULT_EMBED="nomic-embed-text"
  fi

  # Read currently configured models from existing cipher.yml (if present)
  CURRENT_LLM=""
  CURRENT_EMBED=""
  if [ -f "${HOME}/.cipher/cipher.yml" ]; then
    CURRENT_LLM=$(awk '/^llm:$/{f=1;next} f && /^[^[:space:]]/{exit} f && /model:/{sub(/.*model:[[:space:]]*/,""); print; exit}' "${HOME}/.cipher/cipher.yml" 2>/dev/null || true)
    CURRENT_EMBED=$(awk '/^embedding:$/{f=1;next} f && /^[^[:space:]]/{exit} f && /model:/{sub(/.*model:[[:space:]]*/,""); print; exit}' "${HOME}/.cipher/cipher.yml" 2>/dev/null || true)
  fi

  # Prefer an already-installed model as the default (current config wins, then first installed)
  DEFAULT_LLM="${CURRENT_LLM:-$ORIG_DEFAULT_LLM}"
  for entry in "${LLM_MODELS[@]}"; do
    IFS='|' read -r mid _ <<< "$entry"
    if [ "$mid" = "$CURRENT_LLM" ]; then
      DEFAULT_LLM="$mid"
      break
    fi
  done
  if [ -z "$CURRENT_LLM" ]; then
    for entry in "${LLM_MODELS[@]}"; do
      IFS='|' read -r mid _ <<< "$entry"
      if _model_available "$mid"; then
        DEFAULT_LLM="$mid"
        break
      fi
    done
  fi

  DEFAULT_EMBED="${CURRENT_EMBED:-$ORIG_DEFAULT_EMBED}"
  if [ -z "$CURRENT_EMBED" ]; then
    for entry in "${EMBED_MODELS[@]}"; do
      IFS='|' read -r mid _ <<< "$entry"
      if _model_available "$mid"; then
        DEFAULT_EMBED="$mid"
        break
      fi
    done
  fi

  # Find the 1-based index of the default model in a list
  _default_index() {
    local default_id="$1"; shift
    local idx=1
    for entry in "$@"; do
      IFS='|' read -r mid _ <<< "$entry"
      if [ "$mid" = "$default_id" ]; then
        echo "$idx"
        return
      fi
      idx=$((idx + 1))
    done
    echo "1"
  }

  DEFAULT_LLM_IDX=$(_default_index "$DEFAULT_LLM" "${LLM_MODELS[@]}")
  DEFAULT_EMBED_IDX=$(_default_index "$DEFAULT_EMBED" "${EMBED_MODELS[@]}")

  # Interactive model picker (skip if env vars are set)
  if [ -z "$XGH_LLM_MODEL" ]; then
    echo ""
    echo -e "  ${BOLD}Pick an LLM${NC} ${DIM}(Cipher's reasoning brain)${NC}"
    echo ""
    for i in "${!LLM_MODELS[@]}"; do
      IFS='|' read -r model_id model_desc <<< "${LLM_MODELS[$i]}"
      local_tag=""
      if [ -n "$CURRENT_LLM" ] && [ "$model_id" = "$CURRENT_LLM" ]; then
        if _model_available "$model_id"; then
          local_tag=" ${CYAN}(current)${NC} ${GREEN}(installed)${NC}"
        else
          local_tag=" ${CYAN}(current)${NC}"
        fi
      elif _model_available "$model_id"; then
        local_tag=" ${GREEN}(installed)${NC}"
      fi
      if [ "$model_id" = "$DEFAULT_LLM" ]; then
        echo -e "    ${GREEN}$((i+1)))${NC} ${model_desc}${local_tag}"
      else
        echo -e "    $((i+1))) ${model_desc}${local_tag}"
      fi
    done
    echo "    c) Custom ${CUSTOM_LABEL}"
    echo ""
    read -r -p "  🐴 Pick [${DEFAULT_LLM_IDX}]: " llm_choice
    llm_choice="${llm_choice:-$DEFAULT_LLM_IDX}"

    if [ "$llm_choice" = "c" ] || [ "$llm_choice" = "C" ]; then
      read -r -p "  Enter ${CUSTOM_LABEL}: " XGH_LLM_MODEL
    elif [ "$llm_choice" -ge 1 ] 2>/dev/null && [ "$llm_choice" -le "${#LLM_MODELS[@]}" ]; then
      IFS='|' read -r XGH_LLM_MODEL _ <<< "${LLM_MODELS[$((llm_choice-1))]}"
    else
      XGH_LLM_MODEL="$DEFAULT_LLM"
    fi
  fi
  XGH_LLM_MODEL="${XGH_LLM_MODEL:-$DEFAULT_LLM}"

  if [ -z "$XGH_EMBED_MODEL" ]; then
    echo ""
    echo -e "  ${BOLD}Pick an embedding model${NC} ${DIM}(semantic search engine)${NC}"
    echo ""
    for i in "${!EMBED_MODELS[@]}"; do
      IFS='|' read -r model_id model_desc <<< "${EMBED_MODELS[$i]}"
      local_tag=""
      if [ -n "$CURRENT_EMBED" ] && [ "$model_id" = "$CURRENT_EMBED" ]; then
        if _model_available "$model_id"; then
          local_tag=" ${CYAN}(current)${NC} ${GREEN}(installed)${NC}"
        else
          local_tag=" ${CYAN}(current)${NC}"
        fi
      elif _model_available "$model_id"; then
        local_tag=" ${GREEN}(installed)${NC}"
      fi
      if [ "$model_id" = "$DEFAULT_EMBED" ]; then
        echo -e "    ${GREEN}$((i+1)))${NC} ${model_desc}${local_tag}"
      else
        echo -e "    $((i+1))) ${model_desc}${local_tag}"
      fi
    done
    echo "    c) Custom ${CUSTOM_LABEL}"
    echo ""
    read -r -p "  🐴 Pick [${DEFAULT_EMBED_IDX}]: " embed_choice
    embed_choice="${embed_choice:-$DEFAULT_EMBED_IDX}"

    if [ "$embed_choice" = "c" ] || [ "$embed_choice" = "C" ]; then
      read -r -p "  Enter ${CUSTOM_LABEL}: " XGH_EMBED_MODEL
    elif [ "$embed_choice" -ge 1 ] 2>/dev/null && [ "$embed_choice" -le "${#EMBED_MODELS[@]}" ]; then
      IFS='|' read -r XGH_EMBED_MODEL _ <<< "${EMBED_MODELS[$((embed_choice-1))]}"
    else
      XGH_EMBED_MODEL="$DEFAULT_EMBED"
    fi
  fi
  XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-$DEFAULT_EMBED}"

  # Warn if non-768-dim embed model selected on Ollama (existing collections are 768-dim)
  if [ "$XGH_BACKEND" = "ollama" ] && [[ "$XGH_EMBED_MODEL" != "nomic-embed-text" ]]; then
    warn "Non-768-dim embed model selected. Existing 768-dim Qdrant collections will be incompatible."
    warn "  Run with XGH_RESET_COLLECTION=1 if you want to recreate collections."
  fi

  info "LLM model:       ${XGH_LLM_MODEL}"
  info "Embedding model:  ${XGH_EMBED_MODEL}"

  # ── 3. Download/pull models ────────────────────────────
  if [ "$XGH_BACKEND" = "remote" ]; then
    info "Remote backend — skipping model download (models live on the remote server)"
  elif [ "$XGH_BACKEND" = "vllm-mlx" ]; then
    # vllm-mlx path: download from HuggingFace
    # _model_cached and HF_CACHE already defined in Model Selection above
    MODELS_TO_DOWNLOAD=()
    for m in "$XGH_LLM_MODEL" "$XGH_EMBED_MODEL"; do
      if _model_cached "$m"; then
        info "Model already cached: ${m}"
      else
        MODELS_TO_DOWNLOAD+=("$m")
      fi
    done

    if [ ${#MODELS_TO_DOWNLOAD[@]} -gt 0 ]; then
      lane "Downloading models (grab a coffee) ☕"
      uv run --with huggingface-hub python3 -c "
from huggingface_hub import snapshot_download
import sys
for model in sys.argv[1:]:
    print(f'  Downloading {model}...')
    try:
        snapshot_download(model)
        print(f'  ✓ {model}')
    except Exception as e:
        print(f'  ⚠ Could not download {model}: {e}')
" "${MODELS_TO_DOWNLOAD[@]}" || warn "Model pre-download failed — models will download on first use"
    else
      info "All models already cached — skipping download"
    fi
  else
    # Ollama path: pull models via ollama pull
    lane "Pulling Ollama models 🦙"
    for model in "$XGH_LLM_MODEL" "$XGH_EMBED_MODEL"; do
      if _model_available "$model"; then
        info "Already pulled: ${model}"
      else
        info "Pulling ${model}..."
        ollama pull "$model" || warn "Could not pull ${model} — pull manually: ollama pull ${model}"
      fi
    done
  fi

else
  info "Dry run — skipping the heavy lifting 🏋️"
  # Validate remote URL if set
  if [ "$XGH_BACKEND" = "remote" ] && [ -n "$XGH_REMOTE_URL" ]; then
    if [[ ! "$XGH_REMOTE_URL" =~ ^https?:// ]]; then
      error "XGH_REMOTE_URL must start with http:// or https://"
      exit 1
    fi
    info "Remote backend: ${XGH_REMOTE_URL}"
  fi
  if [ "$XGH_BACKEND" = "vllm-mlx" ]; then
    XGH_LLM_MODEL="${XGH_LLM_MODEL:-mlx-community/Llama-3.2-3B-Instruct-4bit}"
    XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-mlx-community/nomicai-modernbert-embed-base-8bit}"
  elif [ "$XGH_BACKEND" = "remote" ]; then
    XGH_LLM_MODEL="${XGH_LLM_MODEL:-mlx-community/Llama-3.2-3B-Instruct-4bit}"
    XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-mlx-community/nomicai-modernbert-embed-base-8bit}"
  else
    XGH_LLM_MODEL="${XGH_LLM_MODEL:-llama3.2:3b}"
    XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-nomic-embed-text}"
  fi
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

  lossless-claude install || warn "lossless-claude install failed — run manually: lossless-claude install"
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

# -- Cipher Pre/PostToolUse hooks (detect extraction failures, suggest direct storage) --
info "Adding cipher safety nets..."

cat > "${HOOKS_DIR}/cipher-pre-hook.sh" <<'PREHOOKEOF'
#!/bin/bash
# PreToolUse hook for cipher memory tools.
# Detects structured/complex content that cipher's 3B extraction model
# will likely reject, and suggests direct Qdrant storage instead.

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)

case "$tool_name" in
  mcp__cipher__cipher_extract_and_operate_memory|mcp__cipher__cipher_workspace_store)
    ;;
  *)
    exit 0
    ;;
esac

analysis=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    inp = data.get('tool_input', {})
    interaction = inp.get('interaction', '')
    if isinstance(interaction, list):
        interaction = ' '.join(interaction)

    reasons = []
    length = len(interaction)

    if length > 500:
        reasons.append(f'long ({length} chars)')
    if interaction.count('#') >= 2:
        reasons.append('markdown headers')
    if '|' in interaction and interaction.count('|') >= 6:
        reasons.append('tables')
    if '\`\`\`' in interaction:
        reasons.append('code blocks')
    if interaction.count(chr(10)) > 10:
        reasons.append(f'{interaction.count(chr(10))} lines')

    if reasons:
        print('COMPLEX:' + '; '.join(reasons))
    else:
        print('SIMPLE')
except:
    print('SIMPLE')
" 2>/dev/null)

if [[ "$analysis" == COMPLEX* ]]; then
    reason="${analysis#COMPLEX:}"
    read -r -d '' CONTEXT << MARKDOWN
Warning: **Cipher extraction warning**: Content is structured/complex ($reason). Cipher's 3B model will likely filter this (extracted:0).

**Recommended**: Use \`/store-memory\` skill or store directly via \`ctx_execute\` with:
\`\`\`javascript
const { storeWithDedup } = require(process.env.HOME + '/.local/lib/qdrant-store.js');
\`\`\`
MARKDOWN

    jq -n --arg ctx "$CONTEXT" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }'
fi
PREHOOKEOF
chmod +x "${HOOKS_DIR}/cipher-pre-hook.sh"

cat > "${HOOKS_DIR}/cipher-post-hook.sh" <<'POSTHOOKEOF'
#!/bin/bash
# PostToolUse hook for cipher memory tools.
# Detects two failure modes and instructs Claude on recovery:
#   1. extracted:0  — cipher's LLM filtered the content → retry via qdrant-store.js
#   2. dimension mismatch — embedding model dims don't match Qdrant collection → diagnose + fix

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)

case "$tool_name" in
  mcp__cipher__cipher_extract_and_operate_memory|mcp__cipher__cipher_workspace_store)
    ;;
  *)
    exit 0
    ;;
esac

result=$(echo "$input" | jq -r '.tool_result // empty' 2>/dev/null)

diagnosis=$(echo "$result" | python3 -c "
import sys, json, re

def decode(raw):
    raw = raw.strip()
    try:
        return json.loads(json.loads(raw))
    except (json.JSONDecodeError, TypeError):
        try:
            return json.loads(raw)
        except Exception:
            return {'_raw': raw}

raw = sys.stdin.read()
data = decode(raw)
raw_str = str(data)

# --- Check 1: dimension mismatch ---
dim_pattern = re.search(r'[Vv]ector dimension[^;]*expected\s*(?:dim:?\s*)?(\d+)[^;]*got\s*(\d+)', raw_str)
if not dim_pattern:
    dim_pattern = re.search(r'expected\s*dim[:\s]+(\d+)[,\s]+got\s*(\d+)', raw_str)
if dim_pattern:
    expected, got = dim_pattern.group(1), dim_pattern.group(2)
    print(f'DIM_MISMATCH:{expected}:{got}')
    sys.exit(0)

if 'dimension' in raw_str.lower() and ('error' in raw_str.lower() or 'wrong' in raw_str.lower()):
    print('DIM_MISMATCH:unknown:unknown')
    sys.exit(0)

# --- Check 2: extracted:0 ---
ext = data.get('extraction', {})
extracted = ext.get('extracted', -1)
skipped = ext.get('skipped', 0)

if extracted == -1:
    workspace = data.get('workspace', None)
    if isinstance(workspace, list) and len(workspace) == 0:
        extracted = 0
        skipped = max(skipped, 1)

if extracted == 0 and skipped > 0:
    print(f'EXTRACTED_ZERO:{skipped}')
    sys.exit(0)

print('OK')
" 2>/dev/null)

# ── Dimension mismatch ───────────────────────────────────────────────────────
if [[ "$diagnosis" == DIM_MISMATCH:* ]]; then
    IFS=':' read -r _ expected_dim got_dim <<< "$diagnosis"

    collection_dim=$(python3 -c "
import urllib.request, json
try:
    r = urllib.request.urlopen('http://localhost:6333/collections/knowledge_memory', timeout=3)
    d = json.load(r)
    print(d['result']['config']['params']['vectors']['size'])
except Exception:
    print('unknown')
" 2>/dev/null)

    model_dim=$(python3 -c "
import urllib.request, json, os
try:
    import yaml
    cfg = yaml.safe_load(open(os.path.expanduser('~/.cipher/cipher.yml')))
    model = cfg.get('embedding', {}).get('model', 'unknown')
    base = cfg.get('embedding', {}).get('baseURL', 'http://localhost:11434/v1')
    data = json.dumps({'input': 'test', 'model': model, 'encoding_format': 'float'}).encode()
    req = urllib.request.Request(base + '/embeddings', data=data,
        headers={'Content-Type': 'application/json'})
    resp = urllib.request.urlopen(req, timeout=5)
    result = json.load(resp)
    print(len(result['data'][0]['embedding']))
except Exception:
    print('unknown')
" 2>/dev/null)

    cipher_model=$(python3 -c "
import yaml, os
try:
    cfg = yaml.safe_load(open(os.path.expanduser('~/.cipher/cipher.yml')))
    print(cfg.get('embedding', {}).get('model', 'unknown'))
except Exception:
    print('unknown')
" 2>/dev/null)

    read -r -d '' CONTEXT << MARKDOWN
**Cipher vector dimension mismatch** — Qdrant rejected the embedding.

| | Value |
|---|---|
| Qdrant collection expects | **${collection_dim} dims** |
| Current embedding model outputs | **${model_dim} dims** (model: \`${cipher_model}\`) |

**Root cause:** The embedding model was changed after the collection was created with different dimensions. Qdrant collections have a fixed vector size.

**Fix options:**

**Option A — Recreate the collection** (data loss — all stored memories are deleted):
\`\`\`bash
curl -sf -X DELETE http://localhost:6333/collections/knowledge_memory
curl -sf -X PUT http://localhost:6333/collections/knowledge_memory \
  -H 'Content-Type: application/json' \
  -d '{"vectors":{"size":${model_dim},"distance":"Cosine"}}'
\`\`\`
Then retry the original store operation.

**Option B — Switch back to a compatible embedding model** (no data loss):
Edit \`~/.cipher/cipher.yml\` and set \`embedding.model\` to a model that outputs ${collection_dim} dims, then restart the cipher-mcp process.

**Do NOT retry the current operation until one of the above is resolved.** Ask the user which option they prefer.
MARKDOWN

    jq -n --arg ctx "$CONTEXT" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $ctx
        }
    }'
    exit 0
fi

# ── Extracted zero ───────────────────────────────────────────────────────────
if [[ "$diagnosis" == EXTRACTED_ZERO:* ]]; then
    skipped="${diagnosis#EXTRACTED_ZERO:}"
    read -r -d '' CONTEXT << MARKDOWN
**Cipher extraction failed** (extracted=0, skipped=${skipped}). The LLM filtered out the content.

**You MUST store this directly.** Use \`ctx_execute\` with JavaScript:
\`\`\`javascript
const { storeWithDedup } = require(process.env.HOME + '/.local/lib/qdrant-store.js');
const result = await storeWithDedup('knowledge_memory', TEXT, ['tag1'], { domain: 'iOS', projectId: 'acme-ios' });
console.log(JSON.stringify(result));
\`\`\`
Pass the ORIGINAL text that was meant to be stored. Do NOT ask the user — just retry automatically.
MARKDOWN

    jq -n --arg ctx "$CONTEXT" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $ctx
        }
    }'
fi
POSTHOOKEOF
chmod +x "${HOOKS_DIR}/cipher-post-hook.sh"

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
  # Merge: existing + hooks + permissions
  python3 -c "
import json, sys
base = json.load(open('${SETTINGS_FILE}'))
hooks_data = json.loads('''${RESOLVED_HOOKS}''')
perms_data = json.load(open('${PERMS_SETTINGS}'))
for overlay in [hooks_data, perms_data]:
    for k, v in overlay.items():
        if k in base and isinstance(base[k], dict) and isinstance(v, dict):
            base[k].update(v)
        else:
            base[k] = v
json.dump(base, open('${SETTINGS_FILE}', 'w'), indent=2)
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

# Add cipher Pre/PostToolUse hooks to settings
python3 -c "
import json
settings = json.load(open('${SETTINGS_FILE}'))
hooks = settings.setdefault('hooks', {})
cipher_matcher = 'mcp__cipher__cipher_extract_and_operate_memory|mcp__cipher__cipher_workspace_store'

# Add PreToolUse hook if not already present
if 'PreToolUse' not in hooks:
    hooks['PreToolUse'] = []
pre_exists = any(
    cipher_matcher in str(h.get('matcher', ''))
    for h in hooks.get('PreToolUse', [])
)
if not pre_exists:
    hooks['PreToolUse'].append({
        'matcher': cipher_matcher,
        'hooks': [{'type': 'command', 'command': 'bash ${HOOKS_CMD_PREFIX}/cipher-pre-hook.sh'}]
    })

# Add PostToolUse hook if not already present
if 'PostToolUse' not in hooks:
    hooks['PostToolUse'] = []
post_exists = any(
    cipher_matcher in str(h.get('matcher', ''))
    for h in hooks.get('PostToolUse', [])
)
if not post_exists:
    hooks['PostToolUse'].append({
        'matcher': cipher_matcher,
        'hooks': [{'type': 'command', 'command': 'bash ${HOOKS_CMD_PREFIX}/cipher-post-hook.sh'}]
    })

json.dump(settings, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null || warn "Could not add cipher hooks to settings — add them manually"

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

# -- store-memory skill (global, for direct Qdrant storage bypassing cipher extraction) --
info "Setting up store-memory skill"
STORE_MEMORY_DIR="${HOME}/.claude/skills/store-memory"
if [ ! -d "$STORE_MEMORY_DIR" ]; then
  mkdir -p "$STORE_MEMORY_DIR"
  cat > "${STORE_MEMORY_DIR}/SKILL.md" <<'SKILLEOF'
---
name: store-memory
description: Use when storing knowledge, documentation, specs, or structured content in vector memory, especially when cipher_extract_and_operate_memory returns extracted:0 or skipped content, or when ingesting files and documents into memory
---

# Store Memory

Direct vector memory storage that bypasses cipher's LLM extraction layer. Uses Claude as the extraction brain and the embedding model for vector generation.

## When to Use

- Cipher's `cipher_extract_and_operate_memory` returned `extracted: 0`
- Storing documentation, specs, architecture decisions
- Bulk document ingestion (files from `docs/`, specs, etc.)
- Structured content with markdown, tables, code blocks
- Content longer than ~500 characters

## When NOT to Use

- Short conversational facts — cipher handles these fine
- Content that cipher successfully extracted

## Workflow

1. **Analyze**: What's worth storing? Break into independently-searchable chunks (~200-500 chars each).
2. **Dedup**: For each chunk, search Qdrant (threshold 0.85). Skip if similar exists.
3. **Store**: Embed via vllm-mlx, write to Qdrant with cipher-compatible payload.
4. **Verify**: Search for a stored entry to confirm retrieval works.

## Code Pattern

Use `ctx_execute` with JavaScript, requiring the shared helper:

```javascript
const { storeWithDedup, search } = require(process.env.HOME + '/.local/lib/qdrant-store.js');
const result = await storeWithDedup('knowledge_memory', text, ['tag1', 'tag2'], {
  domain: 'iOS', projectId: 'acme-ios', source: 'docs/kb'
});
console.log(JSON.stringify(result));
```

## Payload Schema (cipher-compatible)

| Field | Type | Notes |
|-------|------|-------|
| text | string | **Required** — searchable content |
| tags | string[] | Searchable tags |
| timestamp | ISO string | Auto-set by helper |
| source | string | e.g. "docs/kb", "session-insight" |
| domain | string | e.g. "iOS", "devops" |
| confidence | float | 0.95 default |
| event | string | "ADD" |
| projectId | string | e.g. "acme-ios" |

## Collections

| Collection | Use for |
|------------|---------|
| knowledge_memory | Facts, patterns, decisions, specs |
| workspace_memory | Team progress, bugs, project context |
| reflection_memory | Reasoning traces (use cipher_store_reasoning_memory) |

## Chunking Guidelines

- Each chunk: independently searchable, ~200-500 chars
- Include key identifiers (class names, ticket numbers, file paths)
- Don't split tightly-related context across chunks

## Common Mistakes

- **Storing raw file contents** — summarize and extract key facts instead
- **One giant entry** — break into chunks for better search precision
- **Missing `encoding_format: 'float'`** — causes 192-dim zeros (the fix-openai-embeddings.js preload handles this for cipher, but direct HTTP calls need it explicit)
- **Not verifying** — always search after storing to confirm retrieval
SKILLEOF
  info "store-memory → ${STORE_MEMORY_DIR}"
else
  info "store-memory already in place"
fi

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
    info "No MCPs detected (besides Cipher)"
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

# Determine model host binding (server-side flag)
XGH_MODEL_HOST="${XGH_MODEL_HOST:-127.0.0.1}"
if [ "${XGH_SERVE_NETWORK:-0}" = "1" ]; then
  XGH_MODEL_HOST="0.0.0.0"
fi

cat > "$HOME/.xgh/models.env" <<MODELSEOF
# xgh model server configuration — generated by installer
XGH_LLM_MODEL="${XGH_LLM_MODEL}"
XGH_EMBED_MODEL="${XGH_EMBED_MODEL}"
XGH_MODEL_PORT="${XGH_MODEL_PORT}"
XGH_BACKEND="${XGH_BACKEND}"
XGH_REMOTE_URL="${XGH_REMOTE_URL}"
XGH_MODEL_HOST="${XGH_MODEL_HOST}"
MODELSEOF
# Note: model server runs as a launchd/systemd daemon (see ingest-schedule.sh)

# ── start-models.sh (remote backend connectivity check) ──
if [ "$XGH_BACKEND" = "remote" ]; then
  cat > "$HOME/.xgh/start-models.sh" <<STARTMODELSEOF
#!/usr/bin/env bash
# xgh model server — remote backend
# No local model server needed. Verifying remote server connectivity...
source "\$(dirname "\$0")/models.env"
if curl -sf "\${XGH_REMOTE_URL}/v1/models" >/dev/null 2>&1; then
  echo "✓ Remote inference server reachable: \${XGH_REMOTE_URL}"
else
  echo "✗ Cannot reach remote inference server: \${XGH_REMOTE_URL}"
  echo "  Check network connectivity and that the server is running."
  exit 1
fi
STARTMODELSEOF
  chmod +x "$HOME/.xgh/start-models.sh"
  info "start-models.sh → ~/.xgh/start-models.sh (remote connectivity check)"
fi

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

  # Copy scheduler templates
  cp "${PACK_DIR}/scripts/schedulers/com.xgh.retriever.plist" "$HOME/.xgh/schedulers/"
  cp "${PACK_DIR}/scripts/schedulers/com.xgh.analyzer.plist"  "$HOME/.xgh/schedulers/"
  # Copy models plist and substitute XGH_MODEL_HOST placeholder
  sed "s/127\.0\.0\.1/${XGH_MODEL_HOST}/g" \
    "${PACK_DIR}/scripts/schedulers/com.xgh.models.plist" \
    > "$HOME/.xgh/schedulers/com.xgh.models.plist"
  cp "${PACK_DIR}/scripts/ingest-schedule.sh" "$HOME/.xgh/lib/"
  chmod +x "$HOME/.xgh/lib/ingest-schedule.sh"

  # Auto-install the scheduler
  if [ "$XGH_DRY_RUN" -eq 0 ]; then
    bash "$HOME/.xgh/lib/ingest-schedule.sh" install || warn "Could not install scheduler — run ~/.xgh/lib/ingest-schedule.sh install manually"
  else
    info "Dry run — skipping scheduler install"
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
echo -e "  ${DIM}Backend${NC}      ${XGH_BACKEND}"
echo -e "  ${DIM}LLM${NC}          ${XGH_LLM_MODEL}"
echo -e "  ${DIM}Embeddings${NC}   ${XGH_EMBED_MODEL}"
if [ "$XGH_BACKEND" = "remote" ]; then
  echo -e "  ${DIM}Remote URL${NC}   ${XGH_REMOTE_URL}"
fi
echo -e "  ${DIM}Context tree${NC} ${XGH_CONTEXT_TREE}/"
echo -e "  ${DIM}Scope${NC}        ${XGH_HOOKS_SCOPE}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo ""
echo -e "  ${GREEN}1.${NC} Launch Claude    ${DIM}claude${NC}"
echo -e "  ${GREEN}2.${NC} Run briefing     ${DIM}/xgh-brief${NC}"
echo -e ""
if [ "$XGH_BACKEND" = "remote" ]; then
  echo -e "  ${DIM}Remote inference: no local model daemon needed.${NC}"
else
  echo -e "  ${DIM}Models run automatically as a daemon (launchd/systemd).${NC}"
fi
if [ "${XGH_SERVE_NETWORK:-0}" = "1" ] && [ "$XGH_BACKEND" = "vllm-mlx" ]; then
  _LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "<your-ip>")
  echo ""
  echo -e "  ${GREEN}✓ vllm-mlx bound to 0.0.0.0:${XGH_MODEL_PORT}${NC}"
  echo -e "  ${DIM}Other devices can connect via: http://${_LOCAL_IP}:${XGH_MODEL_PORT}${NC}"
  echo -e "  ${DIM}On other machines: XGH_BACKEND=remote XGH_REMOTE_URL=http://${_LOCAL_IP}:${XGH_MODEL_PORT} bash install.sh${NC}"
fi
echo ""
echo -e "  ${DIM}Your AI now remembers. Ship it. 🐴${NC}"
echo ""
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
