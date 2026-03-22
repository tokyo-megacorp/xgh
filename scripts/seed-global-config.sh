#!/usr/bin/env bash
# seed-global-config.sh — Idempotent marker-based section injection.
# Usage: bash scripts/seed-global-config.sh <target-file> <marker-name> <content-file>
#
# Rules:
#   - If target doesn't exist → create with markers
#   - If target exists, no markers → APPEND our section (preserve user content)
#   - If target has markers → replace ONLY our section (preserve everything else)
#
# Never overwrites content outside the marked section.

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <target-file> <marker-name> <content-file>" >&2
  exit 1
fi

TARGET="$1"
TARGET="${TARGET/#\~/$HOME}"
MARKER_NAME="$2"
CONTENT_FILE="$3"

START="<!-- xgh:begin ${MARKER_NAME} -->"
END="<!-- xgh:end ${MARKER_NAME} -->"

if [ ! -f "$CONTENT_FILE" ]; then
  echo "ERROR: content file not found: $CONTENT_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$TARGET")"

if [ ! -f "$TARGET" ]; then
  # File doesn't exist — create fresh
  printf '%s\n' "$START" > "$TARGET"
  cat "$CONTENT_FILE" >> "$TARGET"
  printf '%s\n' "$END" >> "$TARGET"
  echo "Created $TARGET with [$MARKER_NAME] section"
elif grep -qF "$START" "$TARGET" && ! grep -qF "$END" "$TARGET"; then
  echo "ERROR: corrupted markers in $TARGET — $START found but $END missing" >&2
  exit 2
elif grep -qF "$START" "$TARGET"; then
  # Markers exist — replace only our section
  python3 - "$TARGET" "$START" "$END" "$CONTENT_FILE" << 'PY'
import sys, re
target, start, end, content_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
content = open(content_file).read()
text = open(target).read()
pattern = re.escape(start) + r'.*?' + re.escape(end)
replacement = f"{start}\n{content}\n{end}"
updated = re.sub(pattern, replacement, text, flags=re.DOTALL)
open(target, 'w').write(updated)
print(f"Updated section in {target}")
PY
  echo "Updated [$MARKER_NAME] section in $TARGET (preserved existing content)"
else
  # File exists, no markers — append our section
  printf '\n%s\n' "$START" >> "$TARGET"
  cat "$CONTENT_FILE" >> "$TARGET"
  printf '%s\n' "$END" >> "$TARGET"
  echo "Appended [$MARKER_NAME] section to $TARGET (preserved existing content)"
fi
