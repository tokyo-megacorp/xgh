#!/usr/bin/env bash
# hooks/_pref-index-builder.sh — Builds preference index for context injection
# Sourced by session-start-preferences.sh and post-compact-preferences.sh
# Outputs: sets PREF_INDEX_CONTEXT variable with the formatted index
#
# Coexistence contract: this file is a helper, not a hook itself.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

# _build_pref_index <project_root>
# Returns 0 with PREF_INDEX_CONTEXT set, or 1 if no domains have values.
_build_pref_index() {
  local project_root="${1:-.}"

  # Source preference loaders
  # shellcheck source=../lib/preferences.sh
  source "${project_root}/lib/preferences.sh" 2>/dev/null || return 1

  # Detect current branch
  local branch
  branch=$(git -C "$project_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  # Build domain lines
  local lines=()

  # PR domain
  local pr_repo pr_provider pr_reviewer pr_merge
  pr_repo=$(load_pr_pref "repo" "" "$branch")
  pr_provider=$(load_pr_pref "provider" "" "$branch")
  pr_reviewer=$(load_pr_pref "reviewer" "" "$branch")
  pr_merge=$(load_pr_pref "merge_method" "" "$branch")
  local pr_parts=""
  [[ -n "$pr_repo" ]] && pr_parts+="repo=$pr_repo "
  [[ -n "$pr_provider" ]] && pr_parts+="provider=$pr_provider "
  [[ -n "$pr_reviewer" ]] && pr_parts+="reviewer=$pr_reviewer "
  [[ -n "$pr_merge" ]] && pr_parts+="merge_method=$pr_merge "
  [[ -n "$pr_parts" ]] && lines+=("pr: ${pr_parts% }")

  # Dispatch domain
  local dispatch_agent dispatch_effort
  dispatch_agent=$(load_dispatch_pref "default_agent" "")
  dispatch_effort=$(load_dispatch_pref "exec_effort" "")
  local dispatch_parts=""
  [[ -n "$dispatch_agent" ]] && dispatch_parts+="default_agent=$dispatch_agent "
  [[ -n "$dispatch_effort" ]] && dispatch_parts+="exec_effort=$dispatch_effort "
  [[ -n "$dispatch_parts" ]] && lines+=("dispatch: ${dispatch_parts% }")

  # Superpowers domain
  local sp_impl sp_review sp_effort
  sp_impl=$(load_superpowers_pref "implementation_model" "")
  sp_review=$(load_superpowers_pref "review_model" "")
  sp_effort=$(load_superpowers_pref "effort" "")
  local sp_parts=""
  [[ -n "$sp_impl" ]] && sp_parts+="implementation_model=$sp_impl "
  [[ -n "$sp_review" ]] && sp_parts+="review_model=$sp_review "
  [[ -n "$sp_effort" ]] && sp_parts+="effort=$sp_effort "
  [[ -n "$sp_parts" ]] && lines+=("superpowers: ${sp_parts% }")

  # VCS domain
  local vcs_fmt vcs_branch_naming
  vcs_fmt=$(load_vcs_pref "commit_format" "" "$branch")
  vcs_branch_naming=$(load_vcs_pref "branch_naming" "" "$branch")
  local vcs_parts=""
  [[ -n "$vcs_fmt" ]] && vcs_parts+="commit_format=$vcs_fmt "
  [[ -n "$vcs_branch_naming" ]] && vcs_parts+="branch_naming=$vcs_branch_naming "
  [[ -n "$vcs_parts" ]] && lines+=("vcs: ${vcs_parts% }")

  # Agents domain
  local agents_model
  agents_model=$(load_agents_pref "default_model" "")
  [[ -n "$agents_model" ]] && lines+=("agents: default_model=$agents_model")

  # Skip injection if no domains have values
  [[ ${#lines[@]} -eq 0 ]] && return 1

  # Count pending preferences
  local pending_count
  if [[ -d "$project_root/.xgh" ]]; then
    pending_count=$(find "$project_root/.xgh" -maxdepth 1 -name "pending-preferences-*.yaml" 2>/dev/null | wc -l | tr -d ' ')
  else
    pending_count=0
  fi

  # Assemble output
  local header
  [[ -n "$branch" ]] && header="[xgh preferences] branch=$branch" || header="[xgh preferences]"
  local body
  body=$(printf '%s\n' "${lines[@]}")

  PREF_INDEX_CONTEXT="${header}
${body}
Pending preferences: ${pending_count}"
  return 0
}
