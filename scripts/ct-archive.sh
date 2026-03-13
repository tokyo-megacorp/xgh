#!/usr/bin/env bash
# ct-archive.sh — Archive low-importance drafts, restore archived files
# Sourceable library: defines ct_archive_run, ct_archive_restore.

_CT_ARCHIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_CT_ARCHIVE_DIR}/ct-frontmatter.sh"
source "${_CT_ARCHIVE_DIR}/ct-manifest.sh"

ct_archive_run() {
  local root="${1:?root required}"
  local count=0

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    local maturity importance
    maturity=$(ct_frontmatter_get "$file" "maturity" 2>/dev/null || echo "draft")
    importance=$(ct_frontmatter_get "$file" "importance" 2>/dev/null || echo "0")
    maturity=${maturity:-draft}
    importance=${importance:-0}

    if [[ "$maturity" == "draft" ]] && [[ "$importance" -lt 35 ]]; then
      # Compute rel_path (strip root/ prefix and .md suffix)
      local rel_path="${file#${root}/}"
      local rel_no_ext="${rel_path%.md}"

      # Create archive directory
      local archive_dir="${root}/_archived/$(dirname "$rel_no_ext")"
      mkdir -p "$archive_dir"

      local basename_no_ext
      basename_no_ext=$(basename "$rel_no_ext")

      # 1. Copy original to .full.md
      cp "$file" "${archive_dir}/${basename_no_ext}.full.md"

      # 2. Create .stub.md with metadata pointer
      local title
      title=$(ct_frontmatter_get "$file" "title" 2>/dev/null || echo "")
      local now
      now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

      cat > "${archive_dir}/${basename_no_ext}.stub.md" << STUBEOF
---
title: ${title}
originalPath: ${rel_path}
archivedAt: ${now}
archivePath: _archived/${rel_no_ext}.full.md
---

**ARCHIVED** — This entry was archived due to low importance.
STUBEOF

      # 3. Remove original file
      rm "$file"

      # 4. Remove from manifest
      ct_manifest_remove "$root" "$rel_path"

      # 5. Clean empty parent dirs up to root
      local parent_dir
      parent_dir=$(dirname "$file")
      while [[ "$parent_dir" != "$root" ]] && [[ -d "$parent_dir" ]]; do
        if [[ -z "$(ls -A "$parent_dir" 2>/dev/null)" ]]; then
          rmdir "$parent_dir"
          parent_dir=$(dirname "$parent_dir")
        else
          break
        fi
      done

      count=$((count+1))
      echo "Archived: ${rel_no_ext}"
    fi
  done < <(find "$root" -name "*.md" \
    ! -name "_index.md" \
    ! -name "*.stub.md" \
    ! -path "*/_archived/*" \
    -type f 2>/dev/null)

  echo "Archived ${count} entries"
}

ct_archive_restore() {
  local root="${1:?root required}"
  local archived_rel="${2:?archived-full path required}"

  # archived_rel is like "backend/auth/jwt-patterns.full.md"
  local full_path="${root}/_archived/${archived_rel}"

  if [[ ! -f "$full_path" ]]; then
    echo "Error: archive not found: ${full_path}" >&2
    return 1
  fi

  # Strip .full.md to get original rel path
  local rel_no_ext="${archived_rel%.full.md}"
  local original_rel="${rel_no_ext}.md"
  local target_file="${root}/${original_rel}"

  # 1. Copy .full.md back to original location
  mkdir -p "$(dirname "$target_file")"
  cp "$full_path" "$target_file"

  # 2. Re-register in manifest
  ct_manifest_add "$root" "$original_rel"

  # 3. Remove .full.md and .stub.md
  rm "$full_path"
  local stub_path="${root}/_archived/${rel_no_ext}.stub.md"
  [[ -f "$stub_path" ]] && rm "$stub_path"

  # 4. Clean empty parent dirs in _archived/
  local arch_dir
  arch_dir=$(dirname "$full_path")
  while [[ "$arch_dir" != "${root}/_archived" ]] && [[ -d "$arch_dir" ]]; do
    if [[ -z "$(ls -A "$arch_dir" 2>/dev/null)" ]]; then
      rmdir "$arch_dir"
      arch_dir=$(dirname "$arch_dir")
    else
      break
    fi
  done

  echo "Restored: ${rel_no_ext}"
}

# No-op when sourced; CLI dispatch when executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd=${1:-}
  case "$cmd" in
    run) ct_archive_run "${2:?root required}" ;;
    restore) ct_archive_restore "${2:?root required}" "${3:?archived-full required}" ;;
    *)
      echo "Usage: ct-archive.sh {run|restore} <root> [archived-full]" >&2
      exit 1
      ;;
  esac
fi
