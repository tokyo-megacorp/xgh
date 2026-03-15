#!/usr/bin/env bash
# lib/usage-tracker.sh — Track Claude CLI session usage
# Usage: source lib/usage-tracker.sh
#        xgh_usage_log "retriever" 3 0
#        xgh_usage_check_cap || echo "Cap exceeded"

xgh_usage_log() {
  local run_name="${1//,/_}"
  local turns="${2//,/_}"
  local tokens_estimate="${3:-0}"
  tokens_estimate="${tokens_estimate//,/_}"
  local log_file="${HOME}/.xgh/logs/usage.csv"
  mkdir -p "$(dirname "$log_file")"
  [ -f "$log_file" ] || echo "timestamp,run_name,turns,tokens_estimate" > "$log_file"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),${run_name},${turns},${tokens_estimate}" >> "$log_file"
}

xgh_usage_check_cap() {
  local log_file="${HOME}/.xgh/logs/usage.csv"
  local lib_dir
  lib_dir="$(dirname "${BASH_SOURCE[0]}")"
  # shellcheck source=/dev/null
  [ -f "${lib_dir}/config-reader.sh" ] && source "${lib_dir}/config-reader.sh"
  local cap
  cap=$(xgh_config_get "budget.daily_token_cap" "2000000" 2>/dev/null || echo "2000000")
  local pause_on_cap
  pause_on_cap=$(xgh_config_get "budget.pause_on_cap" "true" 2>/dev/null || echo "true")
  [ "$pause_on_cap" = "true" ] || return 0
  [ -f "$log_file" ] || return 0
  local today daily_total
  today=$(date -u +%Y-%m-%d)
  daily_total=$(awk -F',' -v d="$today" 'NR>1 && substr($1,1,10)==d {sum+=$4} END {print int(sum+0)}' "$log_file")
  [ "$daily_total" -lt "$cap" ]
}
