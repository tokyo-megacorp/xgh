#!/usr/bin/env bash
set -euo pipefail

# retrieve-all.sh — Discovery-based provider orchestrator
# Finds and runs all mode:cli and mode:api fetch.sh scripts in ~/.xgh/user_providers/
# Skips mode:mcp providers (handled by separate CronCreate prompt)
# Called by CronCreate every 5 minutes (1 Bash turn, no Claude)

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

# Discover and run providers
total=0
success=0
failed=0
items_before=$(find "$INBOX_DIR" -name "*.md" -not -name "WARN_*" | wc -l | tr -d ' ')

for provider_dir in "$PROVIDERS_DIR"/*/; do
    [ -d "$provider_dir" ] || continue
    name=$(basename "$provider_dir")
    script="$provider_dir/fetch.sh"

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

    # Export contract env vars for fetch.sh
    export PROVIDER_DIR="$provider_dir"
    export CURSOR_FILE="$provider_dir/cursor"
    export INBOX_DIR  # promote script-level var to env for fetch.sh subprocess
    export TOKENS_FILE="$HOME/.xgh/tokens.env"

    rc=0
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
done

items_after=$(find "$INBOX_DIR" -name "*.md" -not -name "WARN_*" | wc -l | tr -d ' ')
new_items=$((items_after - items_before))

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: $total providers, $success ok, $failed failed, $new_items new items" >> "$LOG_FILE"
