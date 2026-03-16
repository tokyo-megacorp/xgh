#!/usr/bin/env bash
# scripts/ingest-schedule.sh — Install/uninstall xgh ingest scheduler
# Usage: ./ingest-schedule.sh install|uninstall|status
set -euo pipefail

PLIST_DIR="${HOME}/Library/LaunchAgents"
XGH_HOME="${HOME}/.xgh"
XGH_LOG_DIR="${XGH_HOME}/logs"
SCHED_DIR="${XGH_HOME}/schedulers"
RETRIEVER_PLIST="${SCHED_DIR}/com.xgh.retriever.plist"
ANALYZER_PLIST="${SCHED_DIR}/com.xgh.analyzer.plist"
MODELS_PLIST="${SCHED_DIR}/com.xgh.models.plist"
MODELS_ENV="${XGH_HOME}/models.env"

# Detect claude binary location
CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "/usr/local/bin/claude")

# Detect vllm-mlx binary location
VLLM_BIN=$(command -v vllm-mlx 2>/dev/null || echo "/usr/local/bin/vllm-mlx")

# Load model config from models.env if available
XGH_LLM_MODEL="${XGH_LLM_MODEL:-}"
XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-}"
XGH_MODEL_PORT="${XGH_MODEL_PORT:-11434}"
XGH_MODEL_HOST="${XGH_MODEL_HOST:-127.0.0.1}"
XGH_BACKEND="${XGH_BACKEND:-}"
XGH_REMOTE_URL="${XGH_REMOTE_URL:-}"
if [ -f "$MODELS_ENV" ]; then
  # shellcheck disable=SC1090
  source "$MODELS_ENV"
fi

_render_plist() {
  local src="$1" dst="$2"
  # Escape & in paths to prevent sed backreference interpretation
  local safe_log_dir="${XGH_LOG_DIR//&/\\&}"
  local safe_home="${HOME//&/\\&}"
  local safe_xgh_home="${XGH_HOME//&/\\&}"
  local safe_claude="${CLAUDE_BIN//&/\\&}"
  local safe_vllm="${VLLM_BIN//&/\\&}"
  local safe_llm_model="${XGH_LLM_MODEL//&/\\&}"
  local safe_embed_model="${XGH_EMBED_MODEL//&/\\&}"
  local safe_model_port="${XGH_MODEL_PORT//&/\\&}"
  local safe_model_host="${XGH_MODEL_HOST//&/\\&}"
  sed -e "s|XGH_LOG_DIR|${safe_log_dir}|g" \
      -e "s|XGH_USER_HOME|${safe_home}|g" \
      -e "s|XGH_HOME|${safe_xgh_home}|g" \
      -e "s|XGH_CLAUDE_BIN|${safe_claude}|g" \
      -e "s|XGH_VLLM_BIN|${safe_vllm}|g" \
      -e "s|XGH_LLM_MODEL|${safe_llm_model}|g" \
      -e "s|XGH_EMBED_MODEL|${safe_embed_model}|g" \
      -e "s|XGH_MODEL_PORT|${safe_model_port}|g" \
      -e "s|XGH_MODEL_HOST_PLACEHOLDER|${safe_model_host}|g" \
      "$src" > "$dst"
}

install_macos() {
  mkdir -p "$PLIST_DIR" "$XGH_LOG_DIR"
  _render_plist "$RETRIEVER_PLIST" "${PLIST_DIR}/com.xgh.retriever.plist"
  _render_plist "$ANALYZER_PLIST"  "${PLIST_DIR}/com.xgh.analyzer.plist"
  launchctl unload "${PLIST_DIR}/com.xgh.retriever.plist" 2>/dev/null || true
  launchctl unload "${PLIST_DIR}/com.xgh.analyzer.plist"  2>/dev/null || true
  launchctl load   "${PLIST_DIR}/com.xgh.retriever.plist"
  launchctl load   "${PLIST_DIR}/com.xgh.analyzer.plist"
  # Install models daemon if plist template exists, models are configured, and not using remote backend
  if [ "$XGH_BACKEND" = "remote" ]; then
    echo "✓ launchd agents loaded (retriever: 5min, analyzer: 30min) [remote backend — no local model service]"
  elif [ -f "$MODELS_PLIST" ] && [ -n "$XGH_LLM_MODEL" ]; then
    _render_plist "$MODELS_PLIST" "${PLIST_DIR}/com.xgh.models.plist"
    launchctl unload "${PLIST_DIR}/com.xgh.models.plist" 2>/dev/null || true
    launchctl load   "${PLIST_DIR}/com.xgh.models.plist"
    echo "✓ launchd agents loaded (retriever: 5min, analyzer: 30min, models: daemon)"
  else
    echo "✓ launchd agents loaded (retriever: 5min, analyzer: 30min)"
  fi
}

install_linux() {
  mkdir -p "$XGH_LOG_DIR"
  local tmp
  tmp=$(mktemp)
  crontab -l 2>/dev/null | grep -v "xgh-retrieve\|xgh-analyze" > "$tmp" || true
  printf "*/5 * * * * %s -p '/xgh-retrieve' --allowedTools 'mcp__claude_ai_Slack__*,mcp__claude_ai_Atlassian__*,Bash,Read,Write,Glob' --dangerously-skip-permissions --max-turns 3 >> %s/retriever.log 2>&1\n" \
    "$CLAUDE_BIN" "$XGH_LOG_DIR" >> "$tmp"
  printf "*/30 * * * * %s -p '/xgh-analyze' --allowedTools 'mcp__cipher__*,Bash,Read,Write,Glob' --dangerously-skip-permissions --max-turns 10 >> %s/analyzer.log 2>&1\n" \
    "$CLAUDE_BIN" "$XGH_LOG_DIR" >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  echo "✓ cron entries installed"

  # Skip local model service setup for remote backend
  if [ "$XGH_BACKEND" = "remote" ]; then
    echo "  (remote backend — skipping local model service setup)"
  else
    # Ensure Ollama system service is running (installed by curl | sh)
    if systemctl is-active ollama.service >/dev/null 2>&1; then
      echo "✓ ollama.service already running"
    elif systemctl is-enabled ollama.service >/dev/null 2>&1; then
      sudo systemctl start ollama.service 2>/dev/null \
        || echo "⚠ Could not start ollama.service — run: sudo systemctl start ollama"
    else
      echo "⚠ ollama.service not found — run: curl -fsSL https://ollama.com/install.sh | sh"
    fi
  fi

  # Write and enable xgh-qdrant systemd user service
  loginctl enable-linger "$USER" 2>/dev/null || true
  local svc_dir="${HOME}/.config/systemd/user"
  mkdir -p "$svc_dir"
  mkdir -p "${XGH_LOG_DIR}" "${HOME}/.qdrant/storage"
  cat > "${svc_dir}/xgh-qdrant.service" <<QDRANTSVCEOF
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
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now xgh-qdrant.service 2>/dev/null || true
  echo "✓ xgh-qdrant.service installed and started"
}

uninstall_macos() {
  launchctl unload "${PLIST_DIR}/com.xgh.retriever.plist" 2>/dev/null || true
  launchctl unload "${PLIST_DIR}/com.xgh.analyzer.plist"  2>/dev/null || true
  launchctl unload "${PLIST_DIR}/com.xgh.models.plist"    2>/dev/null || true
  rm -f "${PLIST_DIR}/com.xgh.retriever.plist" "${PLIST_DIR}/com.xgh.analyzer.plist" "${PLIST_DIR}/com.xgh.models.plist"
  echo "✓ launchd agents unloaded"
}

uninstall_linux() {
  crontab -l 2>/dev/null | grep -v "xgh-retrieve\|xgh-analyze" | crontab - || true
  systemctl --user disable --now xgh-models.service 2>/dev/null || true
  rm -f "${HOME}/.config/systemd/user/xgh-models.service"
  systemctl --user disable --now xgh-qdrant.service 2>/dev/null || true
  rm -f "${HOME}/.config/systemd/user/xgh-qdrant.service"
  systemctl --user daemon-reload 2>/dev/null || true
  echo "✓ cron entries and systemd services removed"
  # Note: ollama.service is intentionally NOT stopped (other apps may use it)
}

case "${1:-help}" in
  install)
    if [[ "$(uname)" == "Darwin" ]]; then install_macos; else install_linux; fi ;;
  uninstall)
    if [[ "$(uname)" == "Darwin" ]]; then uninstall_macos; else uninstall_linux; fi ;;
  status)
    if [ "$XGH_BACKEND" = "remote" ]; then
      echo "backend: remote"
      echo "remote URL: ${XGH_REMOTE_URL:-<not set>}"
      if [ -n "$XGH_REMOTE_URL" ] && curl -sf --max-time 5 "${XGH_REMOTE_URL}/v1/models" >/dev/null 2>&1; then
        echo "connectivity: reachable ✓"
      else
        echo "connectivity: unreachable ✗"
      fi
    elif [[ "$(uname)" == "Darwin" ]]; then
      echo "launchd:"; launchctl list 2>/dev/null | grep "com.xgh" || echo "  (not loaded)"
    else
      echo "cron:"; crontab -l 2>/dev/null | grep "xgh" || echo "  (not installed)"
      echo "systemd:"; systemctl --user status xgh-models.service 2>/dev/null | head -5 || echo "  (not installed)"
    fi ;;
  *) echo "Usage: $0 install|uninstall|status"; exit 1 ;;
esac
