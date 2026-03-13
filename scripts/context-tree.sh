#!/usr/bin/env bash
set -euo pipefail

# context-tree.sh — CLI dispatcher over ct-* library functions
# Sources all libraries, parses subcommands, dispatches to library calls.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all ct-* libraries
source "${SCRIPT_DIR}/ct-frontmatter.sh"
source "${SCRIPT_DIR}/ct-scoring.sh"
source "${SCRIPT_DIR}/ct-manifest.sh"
source "${SCRIPT_DIR}/ct-archive.sh"
source "${SCRIPT_DIR}/ct-search.sh"
source "${SCRIPT_DIR}/ct-sync.sh"

CT_ROOT="${XGH_CONTEXT_TREE:-.xgh/context-tree}"

# --- Subcommand implementations ---

cmd_init() {
  mkdir -p "$CT_ROOT"
  ct_manifest_init "$CT_ROOT"
  ct_manifest_update_indexes "$CT_ROOT"
  echo "Initialized context tree at $CT_ROOT"
}

cmd_create() {
  local rel_path="${1:?Usage: context-tree.sh create <rel-path> <title> [content]}"
  local title="${2:?title required}"
  local content="${3:-}"

  local file_path="${CT_ROOT}/${rel_path}"

  if [[ -f "$file_path" ]]; then
    echo "Error: file already exists: ${file_path}" >&2
    return 1
  fi

  mkdir -p "$(dirname "$file_path")"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  {
    echo "---"
    echo "title: ${title}"
    echo "importance: 50"
    echo "recency: 1.0000"
    echo "maturity: draft"
    echo "accessCount: 0"
    echo "updateCount: 0"
    echo "createdAt: ${now}"
    echo "updatedAt: ${now}"
    echo "---"
    echo ""
    if [[ -n "$content" ]]; then
      echo "$content"
    fi
  } > "$file_path"

  ct_score_recalculate "$file_path"
  ct_manifest_add "$CT_ROOT" "$rel_path"

  echo "Created: ${rel_path}"
}

cmd_read() {
  local rel_path="${1:?Usage: context-tree.sh read <rel-path>}"
  local file_path="${CT_ROOT}/${rel_path}"

  if [[ ! -f "$file_path" ]]; then
    echo "Error: not found: ${file_path}" >&2
    return 1
  fi

  # Bump accessCount
  ct_frontmatter_increment_int "$file_path" "accessCount"

  # Bump importance via search-hit event (+3)
  ct_score_apply_event "$file_path" "search-hit"

  cat "$file_path"
}

cmd_update() {
  local rel_path="${1:?Usage: context-tree.sh update <rel-path> <content>}"
  local content="${2:?content required}"
  local file_path="${CT_ROOT}/${rel_path}"

  if [[ ! -f "$file_path" ]]; then
    echo "Error: not found: ${file_path}" >&2
    return 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Append update section
  {
    echo ""
    echo "## Update ${now}"
    echo "${content}"
  } >> "$file_path"

  # Bump importance via update event (+5)
  ct_score_apply_event "$file_path" "update"

  # Reset recency to 1.0
  ct_frontmatter_set "$file_path" "recency" "1.0000"

  # Update updatedAt
  ct_frontmatter_set "$file_path" "updatedAt" "$now"

  # Bump updateCount
  ct_frontmatter_increment_int "$file_path" "updateCount"

  echo "Updated: ${rel_path}"
}

cmd_delete() {
  local rel_path="${1:?Usage: context-tree.sh delete <rel-path>}"
  local file_path="${CT_ROOT}/${rel_path}"

  if [[ ! -f "$file_path" ]]; then
    echo "Error: not found: ${file_path}" >&2
    return 1
  fi

  rm "$file_path"

  # Check and remove _archived/ counterparts
  local rel_no_ext="${rel_path%.md}"
  rm -f "${CT_ROOT}/_archived/${rel_no_ext}.stub.md" 2>/dev/null || true
  rm -f "${CT_ROOT}/_archived/${rel_no_ext}.full.md" 2>/dev/null || true

  # Clean empty parent dirs up to CT_ROOT
  local parent_dir
  parent_dir=$(dirname "$file_path")
  while [[ "$parent_dir" != "$CT_ROOT" ]] && [[ -d "$parent_dir" ]]; do
    if [[ -z "$(ls -A "$parent_dir" 2>/dev/null)" ]]; then
      rmdir "$parent_dir"
      parent_dir=$(dirname "$parent_dir")
    else
      break
    fi
  done

  # Remove from manifest
  ct_manifest_remove "$CT_ROOT" "$rel_path"

  echo "Deleted: ${rel_path}"
}

cmd_list() {
  find "$CT_ROOT" -name "*.md" \
    ! -name "_index.md" \
    ! -name "*.stub.md" \
    ! -name "context.md" \
    ! -path "*/_archived/*" \
    -type f 2>/dev/null | sort | while IFS= read -r f; do
    local rp="${f#${CT_ROOT}/}"
    local maturity importance
    maturity=$(ct_frontmatter_get "$f" "maturity" 2>/dev/null || echo "unknown")
    importance=$(ct_frontmatter_get "$f" "importance" 2>/dev/null || echo "0")
    maturity=${maturity:-unknown}
    importance=${importance:-0}
    printf "%-60s  [%s]  imp:%s\n" "$rp" "$maturity" "$importance"
  done
}

cmd_search() {
  local query="${1:?Usage: context-tree.sh search <query> [top]}"
  local top="${2:-10}"
  ct_search_run "$CT_ROOT" "$query" "$top"
}

cmd_score() {
  local rel_path="${1:?Usage: context-tree.sh score <rel-path> [event]}"
  local event="${2:-update}"
  ct_score_apply_event "${CT_ROOT}/${rel_path}" "$event"
}

cmd_archive() {
  ct_archive_run "$CT_ROOT"
}

cmd_restore() {
  local archived_full="${1:?Usage: context-tree.sh restore <archived-full>}"
  ct_archive_restore "$CT_ROOT" "$archived_full"
}

cmd_sync() {
  local sub="${1:?Usage: context-tree.sh sync <curate|query|refresh> [args...]}"
  shift

  case "$sub" in
    curate)  ct_sync_curate "$@" ;;
    query)   ct_sync_query "$CT_ROOT" "$@" ;;
    refresh) ct_sync_refresh "$CT_ROOT" ;;
    *)
      echo "Unknown sync subcommand: $sub" >&2
      echo "Usage: context-tree.sh sync {curate|query|refresh} [args...]" >&2
      return 1
      ;;
  esac
}

cmd_manifest() {
  local sub="${1:?Usage: context-tree.sh manifest <init|rebuild|update-indexes>}"
  shift

  case "$sub" in
    init)           ct_manifest_init "$CT_ROOT" ;;
    rebuild)        ct_manifest_rebuild "$CT_ROOT" ;;
    update-indexes) ct_manifest_update_indexes "$CT_ROOT" ;;
    *)
      echo "Unknown manifest subcommand: $sub" >&2
      echo "Usage: context-tree.sh manifest {init|rebuild|update-indexes}" >&2
      return 1
      ;;
  esac
}

# --- Main dispatch (only when executed directly) ---
main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: context-tree.sh <command> [args...]" >&2
    echo "Commands: init, create, read, update, delete, list, search, score, archive, restore, sync, manifest" >&2
    exit 1
  fi

  local cmd="$1"
  shift

  case "$cmd" in
    init)     cmd_init "$@" ;;
    create)   cmd_create "$@" ;;
    read)     cmd_read "$@" ;;
    update)   cmd_update "$@" ;;
    delete)   cmd_delete "$@" ;;
    list)     cmd_list "$@" ;;
    search)   cmd_search "$@" ;;
    score)    cmd_score "$@" ;;
    archive)  cmd_archive "$@" ;;
    restore)  cmd_restore "$@" ;;
    sync)     cmd_sync "$@" ;;
    manifest) cmd_manifest "$@" ;;
    *)
      echo "Unknown command: $cmd" >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
