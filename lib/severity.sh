#!/usr/bin/env bash
# lib/severity.sh — Severity resolution for preference checks
# Sourced by pre-tool-use-preferences.sh only.
# Requires: lib/preferences.sh must be sourced first (provides _pref_read_yaml).

# Strict mode guard — only when executed directly, not when sourced.
# (Matches convention used in other lib/ files.)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

# Hardcoded defaults (safety=block, convention=warn)
# Uses a case statement for Bash 3.2 compatibility (macOS ships Bash 3.2).
_severity_defaults() {
  local check_name="$1"
  case "$check_name" in
    merge_method|protected_branch|force_push) echo "block" ;;
    branch_naming|commit_format) echo "warn" ;;
    *) echo "warn" ;;
  esac
}

_severity_resolve() {
  local domain="$1" check_name="$2"
  local configured
  # _pref_read_yaml is provided by lib/preferences.sh (must be sourced first)
  configured=$(_pref_read_yaml "preferences.${domain}.checks.${check_name}.severity")
  if [[ "$configured" == "block" || "$configured" == "warn" ]]; then
    echo "$configured"
  else
    _severity_defaults "$check_name"
  fi
}
