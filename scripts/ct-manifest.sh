#!/usr/bin/env bash
# ct-manifest.sh — Flat manifest (_manifest.json) and index (_index.md) management
# Sourceable library with flat entries[] schema (no nested domains).

_CT_MANIFEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_CT_MANIFEST_DIR}/ct-frontmatter.sh"

ct_manifest_init() {
  local root="${1:?root required}"
  local manifest="${root}/_manifest.json"

  if [[ -f "$manifest" ]]; then
    # Validate existing manifest without overwriting
    python3 -c "import json; json.load(open('${manifest}'))" 2>/dev/null && return 0
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local team="${XGH_TEAM:-my-team}"

  python3 << PYEOF
import json

manifest = {
    "version": "1.0.0",
    "team": "${team}",
    "created": "${now}",
    "lastRebuilt": "${now}",
    "entries": []
}

with open("${manifest}", "w") as f:
    json.dump(manifest, f, indent=2)
PYEOF
}

ct_manifest_add() {
  local root="${1:?root required}"
  local rel_path="${2:?rel-path required}"
  local manifest="${root}/_manifest.json"
  local file_path="${root}/${rel_path}"

  [[ -f "$manifest" ]] || ct_manifest_init "$root"

  local title maturity importance tags updatedAt
  title=$(ct_frontmatter_get "$file_path" "title" 2>/dev/null || echo "")
  maturity=$(ct_frontmatter_get "$file_path" "maturity" 2>/dev/null || echo "draft")
  importance=$(ct_frontmatter_get "$file_path" "importance" 2>/dev/null || echo "0")
  tags=$(ct_frontmatter_get "$file_path" "tags" 2>/dev/null || echo "[]")
  updatedAt=$(ct_frontmatter_get "$file_path" "updatedAt" 2>/dev/null || echo "")

  # Default title from filename if missing
  if [[ -z "$title" ]]; then
    title=$(basename "$rel_path" .md | sed 's/-/ /g; s/\b\(.\)/\u\1/g')
  fi

  python3 << PYEOF
import json, ast

manifest_path = "${manifest}"
rel_path = "${rel_path}"
title = "${title}"
maturity = "${maturity}"
importance_str = "${importance}"
tags_str = """${tags}"""
updated_at = "${updatedAt}"

with open(manifest_path, "r") as f:
    m = json.load(f)

try:
    importance = int(importance_str)
except ValueError:
    importance = 0

# Parse tags
try:
    if tags_str.startswith("["):
        tags = [t.strip().strip("'\"") for t in tags_str.strip("[]").split(",") if t.strip()]
    else:
        tags = [tags_str] if tags_str else []
except:
    tags = []

entry = {
    "path": rel_path,
    "title": title,
    "maturity": maturity,
    "importance": importance,
    "tags": tags,
    "updatedAt": updated_at
}

# Upsert: remove existing entry with same path, then append
m["entries"] = [e for e in m.get("entries", []) if e["path"] != rel_path]
m["entries"].append(entry)

with open(manifest_path, "w") as f:
    json.dump(m, f, indent=2)
PYEOF
}

ct_manifest_remove() {
  local root="${1:?root required}"
  local rel_path="${2:?rel-path required}"
  local manifest="${root}/_manifest.json"

  [[ -f "$manifest" ]] || return 1

  python3 << PYEOF
import json

manifest_path = "${manifest}"
rel_path = "${rel_path}"

with open(manifest_path, "r") as f:
    m = json.load(f)

m["entries"] = [e for e in m.get("entries", []) if e["path"] != rel_path]

with open(manifest_path, "w") as f:
    json.dump(m, f, indent=2)
PYEOF
}

ct_manifest_rebuild() {
  local root="${1:?root required}"
  local manifest="${root}/_manifest.json"

  # Preserve metadata from existing manifest
  local team version created
  team=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('team','${XGH_TEAM:-my-team}'))" 2>/dev/null || echo "${XGH_TEAM:-my-team}")
  version=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('version','1.0.0'))" 2>/dev/null || echo "1.0.0")
  created=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('created',''))" 2>/dev/null || echo "")

  python3 << PYEOF
import json, os, re, datetime
from pathlib import Path

ct_dir = Path("${root}")
entries = []

for md_file in sorted(ct_dir.rglob("*.md")):
    name = md_file.name
    # Skip _index.md, _archived/, *.stub.md, and any _-prefixed files
    if name.startswith("_") or name.endswith(".stub.md"):
        continue

    rel = md_file.relative_to(ct_dir)
    parts = rel.parts

    # Skip root-level files and _archived
    if len(parts) < 2:
        continue
    if parts[0] == "_archived":
        continue

    fields = {}
    try:
        with open(md_file, "r") as f:
            lines = f.readlines()
        if lines and lines[0].strip() == "---":
            count = 0
            in_fm = False
            for line in lines:
                if line.strip() == "---":
                    count += 1
                    if count == 1:
                        in_fm = True
                        continue
                    else:
                        break
                if in_fm:
                    m = re.match(r"^(\w+):\s*(.*)", line.strip())
                    if m:
                        fields[m.group(1)] = m.group(2)
    except:
        pass

    title = fields.get("title", name.replace(".md", ""))
    maturity = fields.get("maturity", "draft")
    try:
        importance = int(fields.get("importance", "0"))
    except ValueError:
        importance = 0

    tags_str = fields.get("tags", "[]")
    try:
        if tags_str.startswith("["):
            tags = [t.strip().strip("'\"") for t in tags_str.strip("[]").split(",") if t.strip()]
        else:
            tags = [tags_str] if tags_str else []
    except:
        tags = []

    updated_at = fields.get("updatedAt", "")

    entries.append({
        "path": str(rel),
        "title": title,
        "maturity": maturity,
        "importance": importance,
        "tags": tags,
        "updatedAt": updated_at,
    })

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
created_val = "${created}" if "${created}" else now

manifest = {
    "version": "${version}",
    "team": "${team}",
    "created": created_val,
    "lastRebuilt": now,
    "entries": entries,
}

with open("${manifest}", "w") as f:
    json.dump(manifest, f, indent=2)
PYEOF
}

ct_manifest_list() {
  local root="${1:?root required}"
  local manifest="${root}/_manifest.json"

  [[ -f "$manifest" ]] || return 1

  python3 << PYEOF
import json

with open("${manifest}", "r") as f:
    m = json.load(f)

for entry in m.get("entries", []):
    print(entry["path"])
PYEOF
}

ct_manifest_update_indexes() {
  local root="${1:?root required}"

  for domain_dir in "${root}"/*/; do
    [ -d "$domain_dir" ] || continue
    local domain_name
    domain_name=$(basename "$domain_dir")
    [[ "$domain_name" == _* ]] && continue

    local index_file="${domain_dir}_index.md"
    local manifest="${root}/_manifest.json"

    python3 << PYEOF
import json
from pathlib import Path

manifest_path = "${manifest}"
domain_name = "${domain_name}"
index_file = "${index_file}"

with open(manifest_path, "r") as f:
    m = json.load(f)

# Filter entries for this domain
domain_entries = []
for e in m.get("entries", []):
    parts = Path(e["path"]).parts
    if parts and parts[0] == domain_name:
        domain_entries.append(e)

# Sort by importance descending
domain_entries.sort(key=lambda e: int(e.get("importance", 0)) if isinstance(e.get("importance"), (int, str)) else 0, reverse=True)

with open(index_file, "w") as f:
    f.write(f"# {domain_name}\n\n")
    f.write(f"> Auto-generated index. {len(domain_entries)} entries.\n\n")
    for e in domain_entries:
        importance = e.get("importance", 0)
        maturity = e.get("maturity", "draft")
        tags = e.get("tags", [])
        if isinstance(tags, str):
            tags_str = tags
        else:
            tags_str = ", ".join(tags)
        f.write(f'### {e["title"]}\n')
        f.write(f'- **Path:** {e["path"]}\n')
        f.write(f'- **Maturity:** {maturity} | **Importance:** {importance}\n')
        f.write(f'- **Tags:** {tags_str}\n')
        f.write("\n")
PYEOF
  done
}

# No-op when sourced; CLI dispatch when executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd=${1:-}
  case "$cmd" in
    init) ct_manifest_init "${2:?root required}" ;;
    add) ct_manifest_add "${2:?root required}" "${3:?rel-path required}" ;;
    remove) ct_manifest_remove "${2:?root required}" "${3:?rel-path required}" ;;
    rebuild) ct_manifest_rebuild "${2:?root required}" ;;
    list) ct_manifest_list "${2:?root required}" ;;
    update-indexes) ct_manifest_update_indexes "${2:?root required}" ;;
    *)
      echo "Usage: ct-manifest.sh {init|add|remove|rebuild|list|update-indexes} <root> [rel-path]" >&2
      exit 1
      ;;
  esac
fi
