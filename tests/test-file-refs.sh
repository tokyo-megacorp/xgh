#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

# Validate that relative file references in markdown link syntax resolve to real files.
# Pattern: [text](../path/to/file) or [text](./path/to/file)

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

# Collect all relative refs: source_file|ref_path
for dir in skills commands agents; do
  [ -d "$dir" ] || continue
  find "$dir" -name '*.md' | while read -r mdfile; do
    sed -n 's/.*\[.*\](\(\.\.\{0,1\}\/[^)]*\)).*/\1/p' "$mdfile" | while read -r ref; do
      ref="${ref%%#*}"
      [ -z "$ref" ] && continue
      echo "$mdfile|$ref"
    done
  done
done > "$tmpfile"

# Check each ref
while IFS='|' read -r source_file ref_path; do
  source_dir="$(dirname "$source_file")"
  resolved="$source_dir/$ref_path"
  if [ -e "$resolved" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $source_file references '$ref_path' but $resolved does not exist"
    FAIL=$((FAIL+1))
  fi
done < "$tmpfile"

echo
echo "File reference test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
