#!/usr/bin/env bash
# hooks/post-tool-use-preferences.sh — PostToolUse drift detection
#
# Phase 2 Epic 2.2: Detect when config/project.yaml is edited mid-session.
# Report which preference fields changed with old → new values.
# Matcher: Write|Edit|MultiEdit
#
# Stdin: { tool_name, tool_input: { file_path, ... }, session_id }
# Output: hookSpecificOutput with additionalContext on change, silent otherwise.
set -euo pipefail

# ── Read stdin ──────────────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# ── Extract file path ──────────────────────────────────────────────────
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null) || exit 0
[ -n "$FILE_PATH" ] || exit 0

# ── Resolve repo root ─────────────────────────────────────────────────
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
PROJ_YAML="${REPO_ROOT}/config/project.yaml"

# ── Only care about project.yaml (absolute path match) ─────────────────
# Normalize both paths for comparison
REAL_PROJ=$(realpath "$PROJ_YAML" 2>/dev/null || echo "$PROJ_YAML")
REAL_FILE=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
[[ "$REAL_FILE" == "$REAL_PROJ" ]] || exit 0

# ── Resolve session ID for snapshot path ───────────────────────────────
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[[ -z "$SESSION_ID" ]] && SESSION_ID="$$-$(date +%s)"
mkdir -p "${REPO_ROOT}/.xgh/run" 2>/dev/null || true
SNAPSHOT="${REPO_ROOT}/.xgh/run/xgh-${SESSION_ID}-project-yaml.yaml"

# ── Output helper ──────────────────────────────────────────────────────
_emit_context() {
  local msg="$1"
  jq -n --arg msg "$msg" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $msg
    }
  }'
}

# ── No snapshot → initialize baseline ──────────────────────────────────
if [[ ! -f "$SNAPSHOT" ]]; then
  cp "$PROJ_YAML" "$SNAPSHOT" 2>/dev/null || true
  _emit_context "[xgh] project.yaml snapshot initialized — future edits will be tracked"
  exit 0
fi

# ── Diff: compare leaf values between snapshot and current ──────────────
CHANGES=""
if command -v yq >/dev/null 2>&1; then
  # Use yq to convert both to flat JSON, then diff keys
  OLD_JSON=$(yq -o=json '.' "$SNAPSHOT" 2>/dev/null || echo "{}")
  NEW_JSON=$(yq -o=json '.' "$PROJ_YAML" 2>/dev/null || echo "{}")
  CHANGES=$(python3 - "$OLD_JSON" "$NEW_JSON" << 'PYEOF'
import sys, json

def flatten(obj, prefix="", depth=0, max_depth=5):
    items = {}
    if depth >= max_depth or not isinstance(obj, dict):
        items[prefix] = obj
        return items
    for k, v in obj.items():
        new_key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict) and depth < max_depth - 1:
            items.update(flatten(v, new_key, depth + 1, max_depth))
        else:
            items[new_key] = v
    return items

old = flatten(json.loads(sys.argv[1]))
new = flatten(json.loads(sys.argv[2]))

changes = []
all_keys = set(old.keys()) | set(new.keys())
for k in sorted(all_keys):
    if not k.startswith("preferences"):
        continue
    old_v = old.get(k)
    new_v = new.get(k)
    if old_v != new_v:
        if k not in old:
            changes.append(f"{k} added: {new_v}")
        elif k not in new:
            changes.append(f"{k} removed (was: {old_v})")
        else:
            changes.append(f"{k}: {old_v} → {new_v}")

print(", ".join(changes) if changes else "")
PYEOF
  ) || CHANGES=""
elif python3 -c "import yaml" 2>/dev/null; then
  CHANGES=$(python3 - "$SNAPSHOT" "$PROJ_YAML" << 'PYEOF'
import sys, yaml, json

def flatten(obj, prefix="", depth=0, max_depth=5):
    items = {}
    if depth >= max_depth or not isinstance(obj, dict):
        items[prefix] = obj
        return items
    for k, v in obj.items():
        new_key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict) and depth < max_depth - 1:
            items.update(flatten(v, new_key, depth + 1, max_depth))
        else:
            items[new_key] = v
    return items

with open(sys.argv[1]) as f:
    old = flatten(yaml.safe_load(f) or {})
with open(sys.argv[2]) as f:
    new = flatten(yaml.safe_load(f) or {})

changes = []
all_keys = set(old.keys()) | set(new.keys())
for k in sorted(all_keys):
    if not k.startswith("preferences"):
        continue
    old_v = old.get(k)
    new_v = new.get(k)
    if old_v != new_v:
        if k not in old:
            changes.append(f"{k} added: {new_v}")
        elif k not in new:
            changes.append(f"{k} removed (was: {old_v})")
        else:
            changes.append(f"{k}: {old_v} → {new_v}")

print(", ".join(changes) if changes else "")
PYEOF
  ) || CHANGES=""
fi

# ── Update snapshot ────────────────────────────────────────────────────
cp "$PROJ_YAML" "$SNAPSHOT" 2>/dev/null || true

# ── Report changes ─────────────────────────────────────────────────────
if [[ -n "$CHANGES" ]]; then
  _emit_context "[xgh] config/project.yaml changed: ${CHANGES}"
fi

exit 0
