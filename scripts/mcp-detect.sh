#!/usr/bin/env bash
# xgh mcp-detect.sh — MCP availability detection helpers
# Source this file in other scripts; do not execute directly.
#
# Usage:
#   source "$(dirname "$0")/mcp-detect.sh"
#   xgh_has_slack    && echo "Slack available"
#   xgh_has_jira     && echo "Jira available"
#   xgh_has_figma    && echo "Figma available"
#   xgh_has_github   && echo "GitHub CLI available"
#   xgh_has_cipher   && echo "Cipher available"
#   detect_mcps      # populates XGH_AVAILABLE_MCPS array
#   has_mcp "slack"  # returns 0 (true) or 1 (false)
#
# Each function checks for the canonical environment variable that Claude Code
# sets when the corresponding MCP server is active, or falls back to a
# tool-list check via XGH_TOOLS (set by the hook before sourcing).
#
# The functions return 0 (true) when the MCP is detected, 1 otherwise.

# Sourcing guard — safe to source multiple times
[ -n "${XGH_MCP_DETECT_LOADED:-}" ] && return 0
XGH_MCP_DETECT_LOADED=1

# Global array populated by detect_mcps
XGH_AVAILABLE_MCPS=()

# ---------------------------------------------------------------------------
# Internal helper: check if a tool name appears in XGH_TOOLS (space-separated
# list of available MCP tool names injected by the calling hook/skill).
# ---------------------------------------------------------------------------
_xgh_tool_available() {
  local tool="$1"
  # XGH_TOOLS may be unset; treat as empty
  echo "${XGH_TOOLS:-}" | tr ',' '\n' | grep -qx "$tool" 2>/dev/null
}

# ---------------------------------------------------------------------------
# xgh_has_slack
# Detects the Claude.ai first-party Slack MCP.
# Canonical tool: slack_read_thread
# ---------------------------------------------------------------------------
xgh_has_slack() {
  _xgh_tool_available "slack_read_thread" || \
  _xgh_tool_available "mcp__claude_ai_Slack__slack_read_thread"
}

# ---------------------------------------------------------------------------
# xgh_has_jira / xgh_has_atlassian
# Detects the Claude.ai first-party Atlassian (Jira) MCP.
# Canonical tool: getJiraIssue
# ---------------------------------------------------------------------------
xgh_has_jira() {
  _xgh_tool_available "getJiraIssue" || \
  _xgh_tool_available "mcp__claude_ai_Atlassian__getJiraIssue"
}

xgh_has_atlassian() {
  xgh_has_jira
}

# ---------------------------------------------------------------------------
# xgh_has_figma
# Detects the Claude.ai first-party Figma MCP.
# ---------------------------------------------------------------------------
xgh_has_figma() {
  _xgh_tool_available "figma_get_file" || \
  _xgh_tool_available "mcp__claude_ai_Figma__figma_get_file"
}

# ---------------------------------------------------------------------------
# xgh_has_github
# Detects the GitHub CLI (gh). Not an MCP — uses the local CLI.
# ---------------------------------------------------------------------------
xgh_has_github() {
  command -v gh >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# xgh_has_lossless_claude
# Detects the lossless-claude MCP server.
# Canonical tool: lcm_search
# ---------------------------------------------------------------------------
xgh_has_lossless_claude() {
  _xgh_tool_available "lcm_search" || \
  _xgh_tool_available "mcp__lossless-claude__lcm_search"
}

# Backwards-compat alias
xgh_has_cipher() {
  xgh_has_lossless_claude
}

# ---------------------------------------------------------------------------
# detect_mcps
# Populates XGH_AVAILABLE_MCPS array with all detected MCP names.
# Also checks .claude/.mcp.json for configured servers.
# ---------------------------------------------------------------------------
detect_mcps() {
  XGH_AVAILABLE_MCPS=()

  # Check .claude/.mcp.json for configured servers
  local mcp_json="${PWD}/.claude/.mcp.json"
  if [ -f "$mcp_json" ]; then
    grep -qi '"lossless-claude"' "$mcp_json" 2>/dev/null && XGH_AVAILABLE_MCPS+=("lossless-claude")
    grep -qi '"slack"' "$mcp_json" 2>/dev/null && XGH_AVAILABLE_MCPS+=("slack")
    grep -qi '"figma"' "$mcp_json" 2>/dev/null && XGH_AVAILABLE_MCPS+=("figma")
    grep -qi '"atlassian"' "$mcp_json" 2>/dev/null && XGH_AVAILABLE_MCPS+=("atlassian")
    grep -qi '"gmail"' "$mcp_json" 2>/dev/null && XGH_AVAILABLE_MCPS+=("gmail")
  fi

  # Also detect via tool availability
  xgh_has_lossless_claude && [[ ! " ${XGH_AVAILABLE_MCPS[*]} " =~ " lossless-claude " ]] && XGH_AVAILABLE_MCPS+=("lossless-claude")
  xgh_has_slack   && [[ ! " ${XGH_AVAILABLE_MCPS[*]} " =~ " slack " ]]    && XGH_AVAILABLE_MCPS+=("slack")
  xgh_has_figma   && [[ ! " ${XGH_AVAILABLE_MCPS[*]} " =~ " figma " ]]    && XGH_AVAILABLE_MCPS+=("figma")
  xgh_has_jira    && [[ ! " ${XGH_AVAILABLE_MCPS[*]} " =~ " atlassian " ]] && XGH_AVAILABLE_MCPS+=("atlassian")
  xgh_has_github  && [[ ! " ${XGH_AVAILABLE_MCPS[*]} " =~ " github " ]]   && XGH_AVAILABLE_MCPS+=("github")
}

# ---------------------------------------------------------------------------
# has_mcp <name>
# Returns 0 (true) if the named MCP is in XGH_AVAILABLE_MCPS, 1 otherwise.
# Call detect_mcps first to populate the array.
# ---------------------------------------------------------------------------
has_mcp() {
  local name="$1"
  [[ " ${XGH_AVAILABLE_MCPS[*]} " =~ " ${name} " ]]
}

# Alias: detect_mcp (singular) for backwards compat
detect_mcp() { detect_mcps "$@"; }
