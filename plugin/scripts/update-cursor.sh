#!/usr/bin/env bash
set -euo pipefail

# Usage: update-cursor.sh <channel-id> <timestamp>
# Atomically updates the cursor for a channel in ~/.xgh/inbox/.cursors.json

CURSORS_FILE="${HOME}/.xgh/inbox/.cursors.json"
CHANNEL="${1:?Usage: update-cursor.sh <channel-id> <timestamp>}"
TIMESTAMP="${2:?Usage: update-cursor.sh <channel-id> <timestamp>}"

# Ensure directory and file exist
mkdir -p "$(dirname "$CURSORS_FILE")"
[ -f "$CURSORS_FILE" ] || echo '{}' > "$CURSORS_FILE"

# Atomic update: write to temp, then move
TMP="$(mktemp)"
jq --arg ch "$CHANNEL" --arg ts "$TIMESTAMP" '.[$ch] = $ts' "$CURSORS_FILE" > "$TMP"
mv "$TMP" "$CURSORS_FILE"
