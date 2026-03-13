#!/usr/bin/env bash
# xgh post-install configure script
# Called by MCS after tech pack installation to set up project-specific state.
set -euo pipefail

PROJECT_PATH="${MCS_PROJECT_PATH:-.}"
TEAM_NAME="${MCS_RESOLVED_TEAM_NAME:-my-team}"
CONTEXT_TREE_PATH="${MCS_RESOLVED_CONTEXT_TREE_PATH:-.xgh/context-tree}"

# Resolve context tree to absolute path within the project
CONTEXT_TREE_DIR="${PROJECT_PATH}/${CONTEXT_TREE_PATH}"

echo "xgh configure: setting up project at ${PROJECT_PATH}"
echo "  team:         ${TEAM_NAME}"
echo "  context tree: ${CONTEXT_TREE_DIR}"

# Create context tree directory
mkdir -p "${CONTEXT_TREE_DIR}"

# Initialize _manifest.json if it doesn't exist
MANIFEST="${CONTEXT_TREE_DIR}/_manifest.json"
if [ ! -f "${MANIFEST}" ]; then
  CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "${MANIFEST}" <<EOF
{
  "version": "1.0.0",
  "team": "${TEAM_NAME}",
  "created": "${CREATED_AT}",
  "entries": []
}
EOF
  echo "  created:      ${MANIFEST}"
else
  # Migrate domains[] to flat entries[] if needed
  if python3 -c "
import json, sys
m = json.load(open('${MANIFEST}'))
if 'domains' in m and 'entries' not in m:
    flat = []
    for d in m['domains']:
        domain = d.get('name', '')
        for t in d.get('topics', []):
            t['domain'] = domain
            flat.append(t)
    m['entries'] = flat
    del m['domains']
    json.dump(m, open('${MANIFEST}', 'w'), indent=2)
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    echo "  migrated:     ${MANIFEST} (domains[] -> entries[])"
  else
    echo "  exists:       ${MANIFEST} (unchanged)"
  fi
fi

echo "xgh configure: done"
