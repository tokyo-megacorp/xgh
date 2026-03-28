#!/usr/bin/env bash
set -euo pipefail

# retrieve-all.sh — Discovery-based provider orchestrator
# Finds and runs all mode:cli and mode:api fetch.sh scripts in ~/.xgh/user_providers/
# Skips mode:mcp providers (handled by separate CronCreate prompt)
# Called by CronCreate every 5 minutes (1 Bash turn, no Claude)
# Retry/backoff: up to 3 attempts (1s, 2s between attempts) on failure — always exits 0 (never blocks session)

PROVIDERS_DIR="${XGH_PROVIDERS_DIR:-$HOME/.xgh/user_providers}"
INBOX_DIR="$HOME/.xgh/inbox"
LOG_FILE="$HOME/.xgh/logs/retriever.log"
PAUSE_FILE="$HOME/.xgh/scheduler-paused"

# Portable timeout: use gtimeout (brew coreutils) or timeout if available, else skip
run_with_timeout() {
    local secs=$1; shift
    if command -v gtimeout &>/dev/null; then
        gtimeout "$secs" "$@"
    elif command -v timeout &>/dev/null; then
        timeout "$secs" "$@"
    else
        "$@"
    fi
}

# Guard: check pause file
if [ -f "$PAUSE_FILE" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: paused" >> "$LOG_FILE"
    exit 0
fi

# Guard: check inbox dir exists
mkdir -p "$INBOX_DIR" "$HOME/.xgh/logs"

# Project scoping: if XGH_PROJECT_SCOPE is set, only run providers
# whose sources include at least one project in scope
SCOPE="${XGH_PROJECT_SCOPE:-}"
in_scope() {
    local provider_yaml="$1"
    # No scope = all providers in scope
    [ -z "$SCOPE" ] && return 0
    # Check if any source project matches the scope
    python3 - "$SCOPE" "$provider_yaml" << 'PYSCOPE'
import yaml, sys
scope = set(sys.argv[1].split(','))
with open(sys.argv[2]) as f:
    cfg = yaml.safe_load(f)
for src in cfg.get('sources', []):
    if isinstance(src, dict) and src.get('project', '') in scope:
        sys.exit(0)
sys.exit(1)
PYSCOPE
}

# Parallel mode flag: XGH_PARALLEL_RETRIEVE=1 runs providers concurrently
# Each provider owns its own cursor file ($provider_dir/cursor) — no shared state,
# so parallel execution is safe. Default: sequential (backward compatible).
PARALLEL="${XGH_PARALLEL_RETRIEVE:-0}"

# run_retrieve — core provider loop; returns non-zero on unexpected failure
# Emits failure reason to stderr on ERR trap so retry harness can log it
run_retrieve() {
    trap 'echo "run_retrieve failed at line $LINENO: $BASH_COMMAND" >&2' ERR
    local total=0
    local success=0
    local failed=0
    local items_before
    items_before=$(find "$INBOX_DIR" -name "*.md" -not -name "WARN_*" | wc -l | tr -d ' ')

    # Arrays to track background jobs when running in parallel mode
    local -a pids=()
    local -a pid_names=()

    for provider_dir in "$PROVIDERS_DIR"/*/; do
        [ -d "$provider_dir" ] || continue
        local name
        name=$(basename "$provider_dir")
        local script="$provider_dir/fetch.sh"

        # Only run mode: cli and mode: api providers (mcp handled by CronCreate prompt)
        local mode
        mode=$(grep "^mode:" "$provider_dir/provider.yaml" 2>/dev/null | awk '{print $2}')
        if [ "$mode" != "cli" ] && [ "$mode" != "api" ]; then
            continue
        fi

        # Skip providers with no sources in current project scope
        if [ -f "$provider_dir/provider.yaml" ] && ! in_scope "$provider_dir/provider.yaml"; then
            continue
        fi

        if [ ! -x "$script" ]; then
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: WARN $name — fetch.sh not found or not executable" >> "$LOG_FILE"
            continue
        fi

        total=$((total + 1))

        if [ "$PARALLEL" = "1" ]; then
            # Launch provider in background; capture exit code via temp file
            local rc_file="$HOME/.xgh/logs/provider-$name.rc"
            (
                export PROVIDER_DIR="$provider_dir"
                export CURSOR_FILE="$provider_dir/cursor"
                export INBOX_DIR
                export TOKENS_FILE="$HOME/.xgh/tokens.env"
                local rc=0
                run_with_timeout 30 bash "$script" 2>>"$HOME/.xgh/logs/provider-$name.log" || rc=$?
                echo "$rc" > "$rc_file"
            ) &
            pids+=($!)
            pid_names+=("$name")
        else
            # Sequential mode (default — backward compatible)
            export PROVIDER_DIR="$provider_dir"
            export CURSOR_FILE="$provider_dir/cursor"
            export INBOX_DIR  # promote script-level var to env for fetch.sh subprocess
            export TOKENS_FILE="$HOME/.xgh/tokens.env"

            local rc=0
            # fetch.sh may write a cursor file for incremental pagination on next run
            run_with_timeout 30 bash "$script" 2>>"$HOME/.xgh/logs/provider-$name.log" || rc=$?
            if [ "$rc" -eq 0 ]; then
                success=$((success + 1))
            elif [ "$rc" -eq 2 ]; then
                success=$((success + 1))
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: WARN $name — partial failure (exit 2)" >> "$LOG_FILE"
            else
                failed=$((failed + 1))
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: ERROR $name — exit code $rc" >> "$LOG_FILE"
            fi
        fi
    done

    # Wait for all background jobs (parallel mode only)
    if [ "$PARALLEL" = "1" ] && [ "${#pids[@]}" -gt 0 ]; then
        for i in "${!pids[@]}"; do
            local pid="${pids[$i]}"
            local pname="${pid_names[$i]}"
            wait "$pid" 2>/dev/null || true
            local rc_file="$HOME/.xgh/logs/provider-$pname.rc"
            local rc=0
            [ -f "$rc_file" ] && rc=$(cat "$rc_file") && rm -f "$rc_file"
            if [ "$rc" -eq 0 ]; then
                success=$((success + 1))
            elif [ "$rc" -eq 2 ]; then
                success=$((success + 1))
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: WARN $pname — partial failure (exit 2)" >> "$LOG_FILE"
            else
                failed=$((failed + 1))
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: ERROR $pname — exit code $rc" >> "$LOG_FILE"
            fi
        done
    fi

    local items_after
    items_after=$(find "$INBOX_DIR" -name "*.md" -not -name "WARN_*" | wc -l | tr -d ' ')
    local new_items=$((items_after - items_before))

    local mode_label="sequential"
    [ "$PARALLEL" = "1" ] && mode_label="parallel"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever[$mode_label]: $total providers, $success ok, $failed failed, $new_items new items" >> "$LOG_FILE"
    return "$failed"
}

# Retry/backoff wrapper — max 3 attempts (2 retries), waits: 1s then 2s between attempts
# Always exits 0 (never blocks session start)
_err_file="/tmp/retrieve-all-err.$$"
trap 'rm -f "$_err_file"' EXIT INT TERM
_start_ts=$(date +%s)
_max_attempts=3
_attempt=0
_backoff=1
_last_reason=""

while [ "$_attempt" -lt "$_max_attempts" ]; do
    _attempt=$((_attempt + 1))

    if run_retrieve 2>"$_err_file"; then
        _elapsed=$(( $(date +%s) - _start_ts ))
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [RETRIEVE_SUCCESS: ${_elapsed}s]" >> "$LOG_FILE"
        exit 0
    fi

    _last_reason=$(tail -1 "$_err_file" 2>/dev/null)
    [ -z "$_last_reason" ] && _last_reason="unknown error"

    if [ "$_attempt" -lt "$_max_attempts" ]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [RETRIEVE_RETRY: attempt ${_attempt}/${_max_attempts} — ${_last_reason}]" >> "$LOG_FILE"
        sleep "$_backoff"
        _backoff=$((_backoff * 2))
    fi
done

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [RETRIEVE_FAILED: ${_last_reason}]" >> "$LOG_FILE"
exit 0
