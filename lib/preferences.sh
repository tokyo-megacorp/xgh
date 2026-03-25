#!/usr/bin/env bash
# lib/preferences.sh — Declarative preference read layer
# Usage: source lib/preferences.sh
#        load_pr_pref "merge_method" "$CLI_OVERRIDE" "$BASE_BRANCH"
#        load_dispatch_pref "default_agent" "$CLI_OVERRIDE"
#
# Reads config/project.yaml via yq (primary) or Python yaml.safe_load (fallback).
# Never writes to project.yaml — the only write path is /xgh-save-preferences.
# See spec: .xgh/specs/2026-03-25-declarative-preferences-lifecycle-design.md

# Only set strict mode when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

# ============================================================
# Core utilities
# ============================================================

# Locate config/project.yaml via git rev-parse
_pref_project_yaml() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
  echo "$root/config/project.yaml"
}

# Read a dotted key from project.yaml (e.g. "preferences.pr.merge_method")
# Primary: yq (~2ms). Fallback: Python yaml.safe_load (~50ms).
# Returns empty string for missing keys. Booleans normalized to lowercase.
_pref_read_yaml() {
  local key="$1"
  local yaml_file
  yaml_file=$(_pref_project_yaml)
  [[ -f "$yaml_file" ]] || return 0

  local val=""

  if command -v yq >/dev/null 2>&1; then
    # yq uses dotted path with leading dot
    local yq_path=".${key}"
    # For non-scalar values (arrays/maps), output compact JSON for consistency
    local raw_type
    raw_type=$(yq -r "$yq_path | type // \"!!null\"" "$yaml_file" 2>/dev/null) || raw_type=""
    case "$raw_type" in
      "!!seq"|"!!map")
        val=$(yq -o=json -c "$yq_path" "$yaml_file" 2>/dev/null) || val=""
        ;;
      *)
        val=$(yq -r "$yq_path // \"\"" "$yaml_file" 2>/dev/null) || val=""
        [[ "$val" == "null" ]] && val=""
        ;;
    esac
  elif python3 -c "import yaml" 2>/dev/null; then
    val=$(python3 - "$yaml_file" "$key" << 'PYEOF'
import sys, yaml, json
yaml_file, key = sys.argv[1], sys.argv[2]
try:
    with open(yaml_file) as f:
        data = yaml.safe_load(f) or {}
    val = data
    for k in key.split('.'):
        if isinstance(val, dict):
            val = val.get(k)
        else:
            val = None
            break
    if val is None:
        print("")
    elif isinstance(val, bool):
        print(str(val).lower())
    elif isinstance(val, (list, dict)):
        print(json.dumps(val, separators=(',', ':')))
    else:
        print(val)
except Exception:
    print("")
PYEOF
    ) || val=""
  fi

  # Normalize booleans from yq output
  case "$val" in
    true|True|TRUE)   val="true" ;;
    false|False|FALSE) val="false" ;;
  esac

  echo "$val"
}

# Read a branch-override field: preferences.<domain>.branches.<branch>.<field>
# Read a branch-override field using bracket notation for safe branch names
# (handles dots, slashes, hyphens in branch names like release-1.0 or feature/foo)
_pref_read_branch() {
  local domain="$1" branch="$2" field="$3"
  local yaml_file
  yaml_file=$(_pref_project_yaml)
  [[ -f "$yaml_file" ]] || return 0

  local val=""

  if command -v yq >/dev/null 2>&1; then
    val=$(yq -r ".preferences.${domain}.branches[\"${branch}\"].${field} // \"\"" "$yaml_file" 2>/dev/null) || val=""
    [[ "$val" == "null" ]] && val=""
  elif python3 -c "import yaml" 2>/dev/null; then
    val=$(python3 - "$yaml_file" "$domain" "$branch" "$field" << 'PYEOF'
import sys, yaml
yaml_file, domain, branch, field = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(yaml_file) as f:
        data = yaml.safe_load(f) or {}
    val = data.get("preferences", {}).get(domain, {}).get("branches", {}).get(branch, {}).get(field)
    if val is None:
        print("")
    elif isinstance(val, bool):
        print(str(val).lower())
    else:
        print(val)
except Exception:
    print("")
PYEOF
    ) || val=""
  fi

  # Normalize booleans
  case "$val" in
    true|True|TRUE)   val="true" ;;
    false|False|FALSE) val="false" ;;
  esac

  echo "$val"
}

# Walk cascade: CLI > branch override > project default
# Level 4 (probe) is NOT handled here — callers decide if/how to probe.
_pref_resolve() {
  local domain="$1" field="$2" cli_override="$3" branch="${4:-}"

  # Level 1: CLI override (always wins)
  [[ -n "$cli_override" ]] && echo "$cli_override" && return

  # Level 2: Branch override (if branch provided)
  if [[ -n "$branch" ]]; then
    local branch_val
    branch_val=$(_pref_read_branch "$domain" "$branch" "$field")
    [[ -n "$branch_val" ]] && echo "$branch_val" && return
  fi

  # Level 3: Project default
  local default_val
  default_val=$(_pref_read_yaml "preferences.${domain}.${field}")
  [[ -n "$default_val" ]] && echo "$default_val" && return

  # Return empty for missing fields (never error)
  echo ""
}

# Local-only probes. Only "provider" is probed (via git remote URL parse).
# All other probed values are populated by /xgh-init or /xgh-track, not at runtime.
_pref_probe_local() {
  local field="$1"
  case "$field" in
    provider)
      local url
      url=$(git remote get-url origin 2>/dev/null) || { echo ""; return; }
      case "$url" in
        *github.com*)                              echo "github" ;;
        *gitlab.com*|*gitlab.*)                    echo "gitlab" ;;
        *bitbucket.org*)                           echo "bitbucket" ;;
        *dev.azure.com*|*visualstudio.com*)        echo "azure-devops" ;;
        *)                                         echo "generic" ;;
      esac
      ;;
    *)
      echo ""
      ;;
  esac
}

# ============================================================
# Domain loaders
# ============================================================

# --- pr: CLI > target_branch > default > local probe ---
# Contract: branch arg is REQUIRED for PR operations (target branch, not current).
# Omitting it silently skips branch overrides.
load_pr_pref() {
  local field="$1" cli_override="${2:-}" branch="${3:-}"
  local val
  val=$(_pref_resolve "pr" "$field" "$cli_override" "$branch")

  # Probe fallback (only for provider)
  if [[ -z "$val" && "$field" == "provider" ]]; then
    val=$(_pref_probe_local "provider")
  fi

  echo "$val"
}

# --- vcs: CLI > branch > default ---
# Branch defaults to current branch via git rev-parse.
load_vcs_pref() {
  local field="$1" cli_override="${2:-}" branch="${3:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")}"
  _pref_resolve "vcs" "$field" "$cli_override" "$branch"
}

# --- testing: CLI > branch > default ---
# Branch defaults to current branch via git rev-parse.
load_testing_pref() {
  local field="$1" cli_override="${2:-}" branch="${3:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")}"
  _pref_resolve "testing" "$field" "$cli_override" "$branch"
}

# --- dispatch: CLI > default ---
# Dependencies: pr.repo (for GitHub-aware agent routing)
load_dispatch_pref() {
  local field="$1" cli_override="${2:-}"

  # "repo" delegates to load_pr_pref
  if [[ "$field" == "repo" ]]; then
    load_pr_pref "repo" "$cli_override"
    return
  fi

  _pref_resolve "dispatch" "$field" "$cli_override"
}

# --- superpowers: CLI > default ---
load_superpowers_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "superpowers" "$field" "$cli_override"
}

# --- design: CLI > default ---
load_design_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "design" "$field" "$cli_override"
}

# --- agents: CLI > default ---
load_agents_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "agents" "$field" "$cli_override"
}

# --- pair_programming: CLI > default ---
load_pair_programming_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "pair_programming" "$field" "$cli_override"
}

# --- scheduling: CLI > default ---
load_scheduling_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "scheduling" "$field" "$cli_override"
}

# --- notifications: CLI > default ---
load_notifications_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "notifications" "$field" "$cli_override"
}

# --- retrieval: CLI > default ---
load_retrieval_pref() {
  local field="$1" cli_override="${2:-}"
  _pref_resolve "retrieval" "$field" "$cli_override"
}
