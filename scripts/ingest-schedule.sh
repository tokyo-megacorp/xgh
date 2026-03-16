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

# Detect claude binary location
CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "/usr/local/bin/claude")

_render_plist() {
  local src="$1" dst="$2"
  # Escape & in paths to prevent sed backreference interpretation
  local safe_log_dir="${XGH_LOG_DIR//&/\\&}"
  local safe_home="${HOME//&/\\&}"
  local safe_xgh_home="${XGH_HOME//&/\\&}"
  local safe_claude="${CLAUDE_BIN//&/\\&}"
  sed -e "s|XGH_LOG_DIR|${safe_log_dir}|g" \
      -e "s|XGH_USER_HOME|${safe_home}|g" \
      -e "s|XGH_HOME|${safe_xgh_home}|g" \
      -e "s|XGH_CLAUDE_BIN|${safe_claude}|g" \
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
  echo "✓ launchd agents loaded (retriever: 5min, analyzer: 30min)"
}

install_linux() {
  mkdir -p "$XGH_LOG_DIR"
  local tmp
  tmp=$(mktemp)
  crontab -l 2>/dev/null | grep -v "xgh-retrieve\|xgh-analyze" > "$tmp" || true
  printf "*/5 * * * * %s -p '/xgh-retrieve' --allowedTools 'mcp__claude_ai_Slack__*,mcp__claude_ai_Atlassian__*,Bash,Read,Write,Glob' --max-turns 3 >> %s/retriever.log 2>&1\n" \
    "$CLAUDE_BIN" "$XGH_LOG_DIR" >> "$tmp"
  printf "*/30 * * * * %s -p '/xgh-analyze' --allowedTools 'mcp__cipher__*,Bash,Read,Write,Glob' --max-turns 10 >> %s/analyzer.log 2>&1\n" \
    "$CLAUDE_BIN" "$XGH_LOG_DIR" >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  echo "✓ cron entries installed"
}

uninstall_macos() {
  launchctl unload "${PLIST_DIR}/com.xgh.retriever.plist" 2>/dev/null || true
  launchctl unload "${PLIST_DIR}/com.xgh.analyzer.plist"  2>/dev/null || true
  rm -f "${PLIST_DIR}/com.xgh.retriever.plist" "${PLIST_DIR}/com.xgh.analyzer.plist"
  echo "✓ launchd agents unloaded"
}

uninstall_linux() {
  crontab -l 2>/dev/null | grep -v "xgh-retrieve\|xgh-analyze" | crontab - || true
  echo "✓ cron entries removed"
}

case "${1:-help}" in
  install)
    if [[ "$(uname)" == "Darwin" ]]; then install_macos; else install_linux; fi ;;
  uninstall)
    if [[ "$(uname)" == "Darwin" ]]; then uninstall_macos; else uninstall_linux; fi ;;
  status)
    if [[ "$(uname)" == "Darwin" ]]; then
      echo "launchd:"; launchctl list 2>/dev/null | grep "com.xgh" || echo "  (not loaded)"
    else
      echo "cron:"; crontab -l 2>/dev/null | grep "xgh" || echo "  (not installed)"
    fi ;;
  *) echo "Usage: $0 install|uninstall|status"; exit 1 ;;
esac
