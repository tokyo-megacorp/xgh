#!/usr/bin/env bash
set -euo pipefail

# Usage: update-cursor.sh <channel-id> <timestamp> [<project-slug>]
#
# Atomically updates the cursor for a channel in a per-project cursor file:
#   ~/.xgh/inbox/.cursors-<project-slug>.json
#
# Partitioned by project so parallel retrieve workers (one per project) each
# own their own file — no read-modify-write race condition between workers.
#
# Migration: on first run with a project slug, if the legacy shared file
# ~/.xgh/inbox/.cursors.json contains an entry for this channel, it is
# migrated into the project file and removed from the legacy file.
#
# Backward compat: if no project slug is given, falls back to the legacy
# ~/.xgh/inbox/.cursors.json (single-worker / all-projects mode).

CHANNEL="${1:?Usage: update-cursor.sh <channel-id> <timestamp> [project-slug]}"
TIMESTAMP="${2:?Usage: update-cursor.sh <channel-id> <timestamp> [project-slug]}"
PROJECT="${3:-}"

INBOX_DIR="${HOME}/.xgh/inbox"
mkdir -p "$INBOX_DIR"

if [ -n "$PROJECT" ]; then
    CURSORS_FILE="${INBOX_DIR}/.cursors-${PROJECT}.json"
else
    # Legacy fallback: all-projects mode (single worker, no race)
    CURSORS_FILE="${INBOX_DIR}/.cursors.json"
fi

# Migration: move channel entry from legacy file into project file (once)
LEGACY_FILE="${INBOX_DIR}/.cursors.json"
if [ -n "$PROJECT" ] && [ -f "$LEGACY_FILE" ] && [ "$CURSORS_FILE" != "$LEGACY_FILE" ]; then
    existing=$(jq -r --arg ch "$CHANNEL" '.[$ch] // empty' "$LEGACY_FILE" 2>/dev/null || true)
    if [ -n "$existing" ]; then
        # Copy entry to project file (will be overwritten below with fresher ts)
        [ -f "$CURSORS_FILE" ] || echo '{}' > "$CURSORS_FILE"
        TMP="$(mktemp)"
        jq --arg ch "$CHANNEL" --arg ts "$existing" '.[$ch] = $ts' "$CURSORS_FILE" > "$TMP"
        mv "$TMP" "$CURSORS_FILE"
        # Remove entry from legacy file
        TMP="$(mktemp)"
        jq --arg ch "$CHANNEL" 'del(.[$ch])' "$LEGACY_FILE" > "$TMP"
        mv "$TMP" "$LEGACY_FILE"
    fi
fi

# Ensure cursor file exists
[ -f "$CURSORS_FILE" ] || echo '{}' > "$CURSORS_FILE"

# Atomic update: write to temp, then move
TMP="$(mktemp)"
jq --arg ch "$CHANNEL" --arg ts "$TIMESTAMP" '.[$ch] = $ts' "$CURSORS_FILE" > "$TMP"
mv "$TMP" "$CURSORS_FILE"
