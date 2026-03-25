#!/usr/bin/env bash
# hooks/post-compact-preferences.sh — PostCompact preference re-injection
# Re-reads project.yaml and re-resolves preferences for the current branch.
# The user may have switched branches mid-session, so we don't cache.
#
# PostCompact stdin: {"session_id": "...", "manual_or_auto": "...", "compaction_summary": "..."}
# We discard it — we only care about rebuilding the preference index.
#
# Coexistence contract: LAST in the PostCompact hook array.
# Output: JSON with `additionalContext` key containing the preference index.
set -euo pipefail

# Consume stdin (PostCompact sends JSON on stdin, we discard it)
cat >/dev/null 2>&1 || true

# Locate project root (walk up from cwd)
_find_project_root() {
  local dir
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -f "${dir}/config/project.yaml" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT=""
if ! PROJECT_ROOT=$(_find_project_root 2>/dev/null); then
  # No project.yaml found — skip injection silently
  exit 0
fi

PROJ_YAML="${PROJECT_ROOT}/config/project.yaml"

# --- Validate YAML before loading ---
# Returns 0=valid, 1=syntax error, 2=no validator available
_yaml_is_valid() {
  local yaml_file="$1"
  if command -v yq >/dev/null 2>&1; then
    yq '.' "$yaml_file" >/dev/null 2>&1 && return 0 || return 1
  elif python3 -c "import yaml" 2>/dev/null; then
    python3 -c "
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        yaml.safe_load(f)
except:
    sys.exit(1)
" "$yaml_file" 2>/dev/null && return 0 || return 1
  fi
  return 2
}

_yaml_is_valid "$PROJ_YAML"
yaml_status=$?
if [[ $yaml_status -eq 1 ]]; then
  warning="[xgh] WARNING: config/project.yaml has syntax errors — preferences disabled after compaction. Run 'yq . config/project.yaml' to diagnose."
  python3 -c "import json,sys; print(json.dumps({'additionalContext': sys.argv[1]}))" "$warning"
  exit 0
fi

# --- Build preference index via shared helper ---
# shellcheck source=_pref-index-builder.sh
BUILDER="${PROJECT_ROOT}/hooks/_pref-index-builder.sh"
if [[ ! -f "$BUILDER" ]]; then
  exit 0
fi
source "$BUILDER"

if _build_pref_index "$PROJECT_ROOT"; then
  python3 -c "import json,sys; print(json.dumps({'additionalContext': sys.argv[1]}))" "$PREF_INDEX_CONTEXT"
fi
