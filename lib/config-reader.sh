#!/usr/bin/env bash
# lib/config-reader.sh — Read values from ~/.xgh/ingest.yaml and config/project.yaml
# Usage: source lib/config-reader.sh
#        xgh_config_get "budget.daily_token_cap" [default_value]
#        load_pr_pref "merge_method" "$CLI_OVERRIDE" "$BASE_BRANCH"
#
# Thin wrapper: delegates PR preferences to lib/preferences.sh when available,
# falls back to inline implementation for standalone use.

# --- Active profile ---
# Returns the name of the active profile, or empty string if none is set.
# Active profile stored at ~/.xgh/active-profile (plain text, just the name).
load_active_profile() {
  local profile_file="${HOME}/.xgh/active-profile"
  if [[ -f "$profile_file" ]]; then
    local name
    name=$(tr -d '[:space:]' < "$profile_file")
    echo "$name"
  else
    echo ""
  fi
}

xgh_config_get() {
  local key="$1"
  local default="${2:-}"
  local config="${HOME}/.xgh/ingest.yaml"
  [ -f "$config" ] || { echo "$default"; return 1; }
  if ! python3 -c "import yaml" 2>/dev/null; then echo "$default"; return 1; fi
  python3 - "$config" "$key" "$default" << 'PYEOF'
import sys, yaml
config_path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(config_path) as f:
        data = yaml.safe_load(f) or {}
    val = data
    for k in key.split('.'):
        val = val[k] if isinstance(val, dict) else None
        if val is None:
            break
    print(val if val is not None else default)
except Exception:
    print(default)
PYEOF
}

# --- Preference read layer delegation ---
# Source lib/preferences.sh if available; it provides load_pr_pref (and all
# other domain loaders) via the new cascade resolver.
_CONFIG_READER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_CONFIG_READER_DIR}/preferences.sh" ]]; then
  # shellcheck source=lib/preferences.sh
  source "${_CONFIG_READER_DIR}/preferences.sh"
fi

# --- Project-level PR preference helpers ---
# Read order: CLI flag > branch override > project default > auto-detect probe
# See spec: .xgh/specs/2026-03-25-project-preferences-design.md

# If preferences.sh provided load_pr_pref (check via _pref_resolve which is
# internal to preferences.sh), skip the inline fallback implementation.
if ! declare -F _pref_resolve >/dev/null 2>&1; then
  # --- Inline fallback (used when lib/preferences.sh is not available) ---

  _project_yaml() {
    echo "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/config/project.yaml"
  }

  load_pr_pref() {
    local field="$1" cli_override="${2:-}" branch="${3:-}"

    # 1. CLI flag wins
    [[ -n "$cli_override" ]] && echo "$cli_override" && return

    local proj_yaml
    proj_yaml=$(_project_yaml)
    [ -f "$proj_yaml" ] || { probe_pr_field "$field"; return; }
    if ! python3 -c "import yaml" 2>/dev/null; then probe_pr_field "$field"; return; fi

    # 2. Branch-specific override
    if [[ -n "$branch" ]]; then
      local val
      val=$(python3 -c "
import yaml, sys
field, branch = sys.argv[1], sys.argv[2]
with open(sys.argv[3]) as f: d = yaml.safe_load(f) or {}
v = (d.get('preferences',{}).get('pr',{}).get('branches',{}).get(branch,{}).get(field))
if v is not None: print(str(v).lower() if isinstance(v, bool) else v)
" "$field" "$branch" "$proj_yaml" 2>/dev/null)
      [[ -n "$val" ]] && echo "$val" && return
    fi

    # 3. Project default
    local val
    val=$(python3 -c "
import yaml, sys
field = sys.argv[1]
with open(sys.argv[2]) as f: d = yaml.safe_load(f) or {}
v = (d.get('preferences',{}).get('pr',{}).get(field))
if v is not None: print(str(v).lower() if isinstance(v, bool) else v)
" "$field" "$proj_yaml" 2>/dev/null)
    [[ -n "$val" ]] && echo "$val" && return

    # 4. Probe, cache, return
    val=$(probe_pr_field "$field")
    [[ -n "$val" ]] && cache_pr_pref "$field" "$val"
    echo "$val"
  }
fi

# --- Deprecated: probe_pr_field / cache_pr_pref ---
# Kept for backwards compatibility. New code should use lib/preferences.sh
# domain loaders directly. These functions are still used by some callers
# and by the fallback load_pr_pref above.

probe_pr_field() {
  # Dependency chain: provider → repo → reviewer → reviewer_comment_author
  # Each probe may call load_pr_pref for upstream fields. If an upstream probe
  # fails (e.g., no gh CLI), downstream probes silently return empty.
  local field="$1"
  case "$field" in
    provider)
      local url
      url=$(git remote get-url origin 2>/dev/null) || return
      case "$url" in
        *github.com*)       echo "github" ;;
        *gitlab.com*|*gitlab.*) echo "gitlab" ;;
        *bitbucket.org*)    echo "bitbucket" ;;
        *dev.azure.com*|*visualstudio.com*) echo "azure-devops" ;;
        *)                  echo "generic" ;;
      esac ;;
    repo)
      local provider
      provider=$(load_pr_pref provider "" "")
      case "$provider" in
        github)
          command -v gh >/dev/null 2>&1 || return
          gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true ;;
        gitlab)
          command -v glab >/dev/null 2>&1 || return
          glab project view -o json 2>/dev/null | python3 -c "
import sys,json
try: print(json.load(sys.stdin)['path_with_namespace'])
except: pass
" 2>/dev/null || true ;;
      esac ;;
    reviewer)
      local provider repo
      provider=$(load_pr_pref provider "" "")
      repo=$(load_pr_pref repo "" "")
      case "$provider" in
        github)
          command -v gh >/dev/null 2>&1 || return
          local enabled
          enabled=$(gh api "repos/$repo/copilot/policies" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('code_review_enabled', d.get('copilot_code_review',{}).get('enabled','false')))
except: print('false')
" 2>/dev/null || echo "false")
          [[ "${enabled,,}" == "true" ]] && echo "copilot-pull-request-reviewer[bot]" ;;
      esac ;;
    reviewer_comment_author)
      local reviewer
      reviewer=$(load_pr_pref reviewer "" "")
      case "$reviewer" in
        copilot-pull-request-reviewer*) echo "Copilot" ;;
      esac ;;
  esac
}

# DEPRECATED: cache_pr_pref — writes to project.yaml. New code should use
# /xgh-save-preferences instead. Retained for backwards compatibility.
cache_pr_pref() {
  local field="$1" value="$2"
  local proj_yaml
  proj_yaml=$(_project_yaml 2>/dev/null || _pref_project_yaml 2>/dev/null || echo "config/project.yaml")
  [ -f "$proj_yaml" ] || return
  python3 -c "import yaml" 2>/dev/null || { echo "PyYAML not installed; preference write disabled" >&2; return; }
  python3 -c "
import yaml, sys
field, value = sys.argv[1], sys.argv[2]
with open(sys.argv[3]) as f: d = yaml.safe_load(f) or {}
d.setdefault('preferences',{}).setdefault('pr',{})[field] = value
with open(sys.argv[3],'w') as f: yaml.dump(d, f, default_flow_style=False, sort_keys=False)
" "$field" "$value" "$proj_yaml" 2>/dev/null
}
