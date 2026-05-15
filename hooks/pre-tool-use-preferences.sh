#!/usr/bin/env bash
# hooks/pre-tool-use-preferences.sh — PreToolUse preference validation hook
#
# Epic 0.3: Validates merge methods and force-push on protected branches.
# Reads stdin JSON: { tool_name, tool_input: { command } }
# Outputs: JSON with additionalContext warning on mismatch, empty otherwise.
#
# Contract: NEVER blocks — only warns via additionalContext.
# Any failure = silent pass-through (exit 0, no output).
set -euo pipefail

# Cross-platform timeout wrapper (macOS lacks GNU timeout by default)
_run_timeout() { local secs=$1; shift; if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; else "$@"; fi; }

# ── Read stdin ──────────────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# ── Fast exit: only Bash tool ───────────────────────────────────────────
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ "$TOOL_NAME" = "Bash" ] || exit 0

# ── Extract command ─────────────────────────────────────────────────────
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0

# ── Resolve repo root and source config reader ─────────────────────────
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CONFIG_READER="${REPO_ROOT}/lib/config-reader.sh"
PROJECT_YAML="${REPO_ROOT}/config/project.yaml"

# ── Check 1: gh pr merge — merge method validation ─────────────────────
# Semantic trigger (#228): we must only fire when an actual `gh pr merge`
# shell command is present — not when that text appears inside a quoted
# string, --body/--message argument value, or heredoc body.
#
# Strategy (Option B from the spec):
#   1. Strip heredoc bodies from the command string before any analysis.
#      A heredoc `<<WORD … WORD` can span newlines; its body lines must be
#      invisible to the segment walker below.
#   2. Split the heredoc-stripped command on shell separators (&&, ||, |,
#      ;, newlines) to get individual segments.
#   3. For each segment, strip leading whitespace and check that the first
#      real token (skipping KEY=value env assignments) is `gh` and the
#      segment matches `^gh pr merge`.
#   4. Single-line quoted strings (-m "gh pr merge …", --body "…") are
#      handled implicitly: their content appears on the same line as the
#      outer command (e.g. `git commit -m "gh pr merge …"`), so after
#      splitting, the segment's first token is `git`, not `gh` — no match.
#
# _mask_quoted_regions: replace the *content* inside "..." and '...' with
# spaces so that shell operators (&&, ||, |, ;) and heredoc markers (<<)
# that appear inside quoted strings become invisible to downstream parsers.
# The original string length is preserved character-for-character.
#
# Rules: double-quoted region from first unescaped " to next unescaped ";
# single-quoted region from ' to next ' (no escape inside '...' in shell).
# Fail-open: odd quote count (unclosed) → emit original unchanged.
#
# Implementation note: the awk script is passed via -v SQ="\047" to avoid
# embedding a literal single-quote character inside the awk '...' context.
_mask_quoted_regions() {
  awk -v SQ="'" '{
    line=$0; out=""; in_dq=0; in_sq=0; dq_c=0; sq_c=0; tmp=line
    while (length(tmp)>0) {
      c=substr(tmp,1,1); tmp=substr(tmp,2)
      if (c=="\"") dq_c++; else if (c==SQ) sq_c++
    }
    if (dq_c%2!=0 || sq_c%2!=0) { print line; next }
    for (i=1; i<=length(line); i++) {
      c=substr(line,i,1); prev=(i>1)?substr(line,i-1,1):""
      if (!in_dq && !in_sq && c=="\"" && prev!="\\") { in_dq=1; out=out c; continue }
      if ( in_dq             && c=="\"" && prev!="\\") { in_dq=0; out=out c; continue }
      if (!in_dq && !in_sq && c==SQ)                   { in_sq=1; out=out c; continue }
      if ( in_sq             && c==SQ)                  { in_sq=0; out=out c; continue }
      out=out ((in_dq||in_sq) ? " " : c)
    }
    print out
  }'
}

# _strip_heredocs: remove heredoc bodies from a multi-line command string.
# Works by walking line by line in bash (avoids gawk-only match() syntax):
# once a `<<[-]WORD` or `<<'WORD'` or `<<"WORD"` marker is seen on a line,
# subsequent lines are suppressed until the bare terminator word appears
# alone on a line (with leading tabs stripped for <<- form).
#
# Fix (AR Finding 3): before testing whether a line contains `<<`, mask its
# quoted regions via _mask_quoted_regions.  This prevents `printf "<<EOF"` —
# where `<<EOF` is inside a double-quoted string — from triggering heredoc
# suppression and accidentally dropping the command that follows it.
_strip_heredocs() {
  local in_heredoc=0 terminator="" line stripped masked
  while IFS= read -r line; do
    if [ "$in_heredoc" -eq 1 ]; then
      # Strip leading tabs (<<- form allows indented terminators)
      stripped="${line#"${line%%[!	]*}"}"  # remove leading tabs
      if [ "$stripped" = "$terminator" ] || [ "$line" = "$terminator" ]; then
        in_heredoc=0
      fi
      # Suppress heredoc body line (including terminator)
      continue
    fi
    # Mask quoted regions before testing for `<<` so that `printf "<<EOF"`
    # does not start heredoc suppression (AR Finding 3).
    masked=$(printf '%s\n' "$line" | _mask_quoted_regions)
    # Detect <<[-]['"]?WORD['"]? and extract the bare WORD (from masked line)
    if printf '%s\n' "$masked" | grep -qE '<<-?[[:space:]]*'"'"'?["]?[A-Za-z_][A-Za-z0-9_]*'"'"'?["]?'; then
      # Extract the terminator word from the ORIGINAL line so quotes are right
      terminator=$(printf '%s\n' "$line" \
        | grep -oE '<<-?[[:space:]]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*'"'"'?"?' \
        | sed "s/<<-\?[[:space:]]*//; s/['\"]//g" \
        | head -1)
      if [ -n "$terminator" ]; then
        in_heredoc=1
      fi
    fi
    printf '%s\n' "$line"
  done
}

# _command_segments: emit one segment per line after heredoc-stripping and
# separator-splitting.  Each output line is the trimmed text of a segment.
#
# Fix (AR Finding 1): splitting must not break on separators that appear
# inside quoted strings (e.g. `--body "note; gh pr merge 999 --squash"`).
# Strategy: mask quoted regions in a copy of each line (same byte length),
# mark separator positions in the masked copy, then cut the ORIGINAL line at
# those exact positions.  Both strings remain byte-aligned throughout.
#
# The awk script uses -v SQ="'" to avoid embedding a literal single-quote
# inside the awk '...' shell context.
_command_segments() {
  local cmd="$1"
  printf '%s\n' "$cmd" \
    | _strip_heredocs \
    | awk -v SQ="'" '
      function quote_mask(s,    out,c,prev,in_dq,in_sq,i,dq_c,sq_c,tmp) {
        in_dq=0; in_sq=0; out=""; dq_c=0; sq_c=0; tmp=s
        while (length(tmp)>0) {
          c=substr(tmp,1,1); tmp=substr(tmp,2)
          if (c=="\"") dq_c++; else if (c==SQ) sq_c++
        }
        if (dq_c%2!=0 || sq_c%2!=0) return s
        for (i=1; i<=length(s); i++) {
          c=substr(s,i,1); prev=(i>1)?substr(s,i-1,1):""
          if (!in_dq && !in_sq && c=="\"" && prev!="\\") { in_dq=1; out=out c; continue }
          if ( in_dq             && c=="\"" && prev!="\\") { in_dq=0; out=out c; continue }
          if (!in_dq && !in_sq && c==SQ)                   { in_sq=1; out=out c; continue }
          if ( in_sq             && c==SQ)                  { in_sq=0; out=out c; continue }
          out=out ((in_dq||in_sq) ? " " : c)
        }
        return out
      }
      # mark_seps: replace separator sequences in-place with \001 (same byte
      # length) so orig and marked remain byte-aligned.
      # Two-char ops (&&, ||) → \001\001; one-char ops (|, ;) → \001.
      function mark_seps(s,    out,i,c,c2,n2) {
        out=""; i=1; n2=length(s)
        while (i<=n2) {
          c=substr(s,i,1); c2=(i<n2)?substr(s,i,2):""
          if (c2=="&&"||c2=="||") { out=out "\001\001"; i+=2; continue }
          if (c=="|"||c==";")     { out=out "\001";     i++;  continue }
          out=out c; i++
        }
        return out
      }
      {
        orig=  $0
        marked=mark_seps(quote_mask($0))
        out_seg=""
        for (i=1; i<=length(marked); i++) {
          if (substr(marked,i,1)=="\001") {
            sub(/^[[:space:]]+/,"",out_seg)
            if (out_seg!="") print out_seg
            out_seg=""
          } else {
            out_seg=out_seg substr(orig,i,1)
          }
        }
        sub(/^[[:space:]]+/,"",out_seg)
        if (out_seg!="") print out_seg
      }
    '
}

# _strip_env_prefix: given a segment string, remove all leading KEY=VAR
# tokens (e.g. `GH_TOKEN=abc GH_HOST=x gh pr merge`) so the remaining
# string starts with the actual command word.  Portable awk (no gawk).
#
# Fix (AR Finding 2): accept lowercase variable names (shell allows them).
# Old pattern: /^[A-Z_][A-Z0-9_]*=/  (uppercase only)
# New pattern: /^[a-zA-Z_][a-zA-Z0-9_]*=/ (any valid shell identifier)
_strip_env_prefix() {
  printf '%s\n' "$1" | awk '{
    i = 1
    while (i <= NF && $i ~ /^[a-zA-Z_][a-zA-Z0-9_]*=/) i++
    out = ""
    for (; i <= NF; i++) out = (out == "" ? $i : out " " $i)
    print out
  }'
}

# _is_gh_pr_merge_segment: returns 0 if the segment (after env-prefix
# stripping and `command`/`\gh` unwrapping) starts with `gh pr merge`.
# All checks operate on the env-stripped form so KEY=VAR prefixes never
# fool the grep anchor (#228 follow-up).
_is_gh_pr_merge_segment() {
  local seg="$1"
  # Strip leading KEY=VAR tokens
  local stripped
  stripped=$(_strip_env_prefix "$seg")
  [ -z "$stripped" ] && return 1
  local first
  first=$(printf '%s\n' "$stripped" | awk '{print $1}')
  # Unwrap `command gh …` → drop "command" and recheck
  if [ "$first" = "command" ]; then
    stripped=$(printf '%s\n' "$stripped" | sed 's/^[[:space:]]*command[[:space:]]*//')
    first=$(printf '%s\n' "$stripped" | awk '{print $1}')
  fi
  # Accept `gh` or `\gh`
  case "$first" in
    gh|'\gh') ;;
    *) return 1 ;;
  esac
  # Verify next two tokens are `pr` and `merge` using awk (no grep anchor
  # needed — we already know position 1 is gh after stripping)
  printf '%s\n' "$stripped" | awk '{
    # Strip optional leading backslash from gh
    cmd = $1; sub(/^\\/, "", cmd)
    if (cmd == "gh" && $2 == "pr" && ($3 == "merge" || NF == 2)) exit 0
    exit 1
  }'
}

# _command_has_gh_pr_merge: returns 0 if any shell-level segment is a real
# `gh pr merge` invocation; 1 otherwise.
_command_has_gh_pr_merge() {
  local cmd="$1"
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    _is_gh_pr_merge_segment "$seg" && return 0
  done < <(_command_segments "$cmd")
  return 1
}

# _gh_pr_merge_segments: emit the env-stripped form of each segment that is
# a real gh pr merge invocation (used for flag/selector extraction).
_gh_pr_merge_segments() {
  local cmd="$1"
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    if _is_gh_pr_merge_segment "$seg"; then
      # Emit the env-stripped, command-unwrapped form so callers see `gh pr merge …`
      local stripped
      stripped=$(_strip_env_prefix "$seg")
      if printf '%s\n' "$stripped" | awk '{exit ($1=="command")?0:1}'; then
        stripped=$(printf '%s\n' "$stripped" | sed 's/^[[:space:]]*command[[:space:]]*//')
      fi
      printf '%s\n' "$stripped"
    fi
  done < <(_command_segments "$cmd")
}

if _command_has_gh_pr_merge "$COMMAND"; then

  # Collect the actual gh pr merge segment(s) for flag/selector extraction.
  # Using only segment text ensures flags and PR numbers from the real
  # invocation are used, not text embedded in argument values.
  GH_SEG=$(printf '%s\n' "$(_gh_pr_merge_segments "$COMMAND")" | head -1)

  # Extract merge method from the gh pr merge segment flags
  CMD_METHOD=""
  if printf '%s\n' "$GH_SEG" | grep -qE -- '--squash'; then
    CMD_METHOD="squash"
  elif printf '%s\n' "$GH_SEG" | grep -qE -- '--merge'; then
    CMD_METHOD="merge"
  elif printf '%s\n' "$GH_SEG" | grep -qE -- '--rebase'; then
    CMD_METHOD="rebase"
  fi
  # If no flag specified, we can't determine intent — pass through
  [ -n "$CMD_METHOD" ] || exit 0

  # Extract PR number from the gh pr merge segment. `gh pr merge` accepts
  # `<number> | <url> | <branch>` per `gh pr merge --help`. We parse number
  # and URL forms here; branch selector is intentionally out of scope.
  PR_NUMBER=""
  # Number form: `gh pr merge 123 …`
  PR_NUMBER=$(printf '%s\n' "$GH_SEG" \
    | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[0-9]+' \
    | grep -oE '[0-9]+$' || true)
  if [ -z "$PR_NUMBER" ]; then
    # URL form: `gh pr merge https://…/pull/<N> …`
    PR_NUMBER=$(printf '%s\n' "$GH_SEG" \
      | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+https?://[^[:space:]]+/pull/[0-9]+' \
      | grep -oE '[0-9]+$' || true)
  fi
  # Presence of an explicit selector (number OR URL) — used to disable the
  # current-branch fallback and avoid misbinding to a different PR (#227 review).
  EXPLICIT_SELECTOR=""
  if [ -n "$PR_NUMBER" ]; then
    EXPLICIT_SELECTOR="yes"
  elif printf '%s\n' "$GH_SEG" | grep -qE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+https?://'; then
    # URL was given but we couldn't parse the PR number (e.g. malformed URL).
    # Still treat as explicit — we must not fall back to current-branch inference.
    EXPLICIT_SELECTOR="yes"
  fi

  # Determine target branch
  TARGET_BRANCH=""
  if [ -n "$PR_NUMBER" ]; then
    # Explicit selector (number or URL): trust gh pr view only. Do NOT fall
    # back to `gh pr list --head <current-branch>` — that could bind the
    # command to a different PR open on the current branch (codex review #227).
    TARGET_BRANCH=$(_run_timeout 10 gh pr view "$PR_NUMBER" --json baseRefName -q .baseRefName 2>/dev/null || true)
  elif [ -z "$EXPLICIT_SELECTOR" ]; then
    # No explicit selector at all (e.g. `gh pr merge --squash` run from the
    # feature branch). Infer target from the open PR whose head matches the
    # current branch — safe here because the command itself relies on that
    # same current-branch → PR mapping.
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [ -n "$CURRENT_BRANCH" ]; then
      TARGET_BRANCH=$(_run_timeout 10 gh pr list --head "$CURRENT_BRANCH" --json baseRefName -q '.[0].baseRefName' 2>/dev/null || true)
    fi
  fi
  # If we still can't determine the target branch, bail out silently.
  # We cannot reliably pick the branch override without knowing the target,
  # and warning against the project default would be a false positive (#223).
  [ -n "$TARGET_BRANCH" ] || exit 0

  # Load configured merge method via config-reader.sh
  CONFIGURED_METHOD=""
  if [ -f "$CONFIG_READER" ] && [ -f "$PROJECT_YAML" ]; then
    # shellcheck source=lib/config-reader.sh
    source "$CONFIG_READER"
    CONFIGURED_METHOD=$(load_pr_pref "merge_method" "" "$TARGET_BRANCH" 2>/dev/null || true)
  fi

  # If we couldn't determine the configured method, pass through
  [ -n "$CONFIGURED_METHOD" ] || exit 0

  # Compare
  if [ "$CMD_METHOD" != "$CONFIGURED_METHOD" ]; then
    BRANCH_MSG=""
    if [ -n "$TARGET_BRANCH" ]; then
      BRANCH_MSG=" for branch ${TARGET_BRANCH}"
    fi

    WARNING="[xgh] WARNING: merge method mismatch. Command uses --${CMD_METHOD} but config/project.yaml specifies ${CONFIGURED_METHOD}${BRANCH_MSG}. Consider using --${CONFIGURED_METHOD} instead."

    jq -n --arg warning "$WARNING" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": $warning
      }
    }'
    exit 0
  fi

  # Match — pass through silently
  exit 0
fi

# ── Check 2: git push --force on protected branches ────────────────────
# Issue #229: match only bare --force (not --force-with-lease / --no-force)
# and short -f flag (standalone or combined, e.g. -fu, -uf).
# --force-with-lease is the safe alternative — must NOT warn for it.
# --no-force is a negating flag — must NOT warn for it.
_is_force_push() {
  local cmd="$1"
  echo "$cmd" | grep -q 'git push' || return 1
  # (a) bare --force: `--force([^-]|$)` is sufficient to exclude --force-with-lease
  #     (next char is `-`) and --no-force (prefix is `--no-`, not `--force`).
  #     No second exclusion pass needed.
  if echo "$cmd" | grep -qE -- '--force([^-]|$)'; then
    return 0
  fi
  # (b) short flag cluster containing f: -f, -fu, -uf, etc.
  # Use `(^| |\t)` to avoid requiring a literal leading space — guards against
  # commands passed without a preceding space token (e.g. start of string).
  if echo "$cmd" | grep -qE -- '(^| |\t)-[a-zA-Z]*f[a-zA-Z]*( |$|\t)'; then
    return 0
  fi
  return 1
}
if _is_force_push "$COMMAND"; then

  # Extract target branch from push command
  # Patterns: git push origin main --force, git push -f origin main, git push --force
  PUSH_BRANCH=""

  # Try to extract remote and branch from the command.
  # Issue #230: strip combined short-flag clusters that include f (e.g. -fu, -uf)
  # using a pattern that matches the entire cluster rather than just the letter f.
  # Issue #231: for refspecs like HEAD:main, use the remote (right) side.
  PUSH_ARGS=$(echo "$COMMAND" \
    | sed 's/git push//' \
    | sed 's/--force-with-lease//g' \
    | sed 's/--no-force//g' \
    | sed 's/--force//g' \
    | sed 's/--no-verify//g' \
    | sed 's/--set-upstream//g' \
    | sed 's/ -u / /g; s/ -u$/ /g' \
    | sed 's/ -[a-zA-Z]*f[a-zA-Z]*/ /g' \
    | xargs)

  if [ -n "$PUSH_ARGS" ]; then
    # Second positional arg is typically the branch (first is remote)
    RAW_REF=$(echo "$PUSH_ARGS" | awk '{print $2}')
    # Issue #231: refspec like HEAD:main — use the remote (right) side
    if echo "$RAW_REF" | grep -q ':'; then
      PUSH_BRANCH=$(echo "$RAW_REF" | cut -d: -f2)
    else
      PUSH_BRANCH="$RAW_REF"
    fi
  fi

  # If no branch specified, try current branch
  if [ -z "$PUSH_BRANCH" ]; then
    PUSH_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  fi

  [ -n "$PUSH_BRANCH" ] || exit 0

  # Check if branch is protected in project.yaml
  if [ -f "$PROJECT_YAML" ] && command -v python3 >/dev/null 2>&1; then
    IS_PROTECTED=$(_run_timeout 10 python3 -c "
import yaml, sys
branch = sys.argv[1]
with open(sys.argv[2]) as f:
    d = yaml.safe_load(f) or {}
v = d.get('preferences',{}).get('pr',{}).get('branches',{}).get(branch,{}).get('protected', False)
print(str(v).lower())
" "$PUSH_BRANCH" "$PROJECT_YAML" 2>/dev/null || echo "false")

    if [ "$IS_PROTECTED" = "true" ]; then
      WARNING="[xgh] WARNING: force-push to protected branch '${PUSH_BRANCH}'. config/project.yaml marks this branch as protected. Consider using a non-force push or targeting a different branch."

      jq -n --arg warning "$WARNING" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "additionalContext": $warning
        }
      }'
      exit 0
    fi
  fi

  exit 0
fi

# ── No checks matched — silent pass-through ─────────────────────────────
exit 0
