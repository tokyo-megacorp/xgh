#!/usr/bin/env bash
# parallel-backtest.sh — Backtest for XGH_PARALLEL_RETRIEVE feature flag
#
# Runs the parallel retrieval path 100 times with mock providers in a dry-run
# sandbox environment. Checks for cursor file conflicts and race conditions
# (concurrent writes to the same per-provider cursor file).
#
# Usage:
#   bash tests/parallel-backtest.sh
#
# Exit codes:
#   0 — all 100 runs passed, 0 collisions
#   1 — one or more collision events detected

set -uo pipefail

RUNS=100
PROVIDERS=5          # number of mock parallel providers per run
PASS=0
FAIL=0
COLLISIONS=0

# Portable millisecond timer: uses python3 as fallback on macOS (BSD date lacks %3N)
now_ms() {
    if date +%s%3N 2>/dev/null | grep -qE '^[0-9]+$'; then
        date +%s%3N
    else
        python3 -c 'import time; print(int(time.time()*1000))'
    fi
}

# ── helpers ──────────────────────────────────────────────────────────────────

log() { printf '%s\n' "$*"; }
ok()  { PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

# ── setup mock environment ───────────────────────────────────────────────────

TMPBASE=$(mktemp -d)
trap 'rm -rf "$TMPBASE"' EXIT

PROVIDERS_DIR="$TMPBASE/user_providers"
# retrieve-all.sh derives its INBOX_DIR from HOME: $HOME/.xgh/inbox
# Set HOME=$TMPBASE so the script uses $TMPBASE/.xgh/inbox as the inbox
INBOX_DIR="$TMPBASE/.xgh/inbox"
LOGS_DIR="$TMPBASE/.xgh/logs"
mkdir -p "$INBOX_DIR" "$LOGS_DIR"

# Create N mock providers with their own cursor files
setup_providers() {
    rm -rf "$PROVIDERS_DIR"
    mkdir -p "$PROVIDERS_DIR"
    for i in $(seq 1 "$PROVIDERS"); do
        local pdir="$PROVIDERS_DIR/mock-provider-$i"
        mkdir -p "$pdir"
        # provider.yaml with mode: cli
        printf 'mode: cli\nsources: []\n' > "$pdir/provider.yaml"
        # fetch.sh: simulate work (write inbox item, update own cursor)
        cat > "$pdir/fetch.sh" << 'FETCHEOF'
#!/usr/bin/env bash
set -euo pipefail
NAME=$(basename "$PROVIDER_DIR")
# Portable unique timestamp (works on macOS BSD date)
TS=$(python3 -c 'import time; print(int(time.time()*1e9))' 2>/dev/null || date -u +%s)
# Write inbox item (provider-specific filename — no collision)
echo "# item from $NAME at $TS" > "$INBOX_DIR/${NAME}-${TS}-$$.md"
# Update this provider's own cursor file — each provider owns exactly one file
echo "$TS" > "$CURSOR_FILE"
# Small sleep to overlap execution windows and stress-test concurrency
sleep 0.$(( RANDOM % 50 + 10 ))
exit 0
FETCHEOF
        chmod +x "$pdir/fetch.sh"
    done
}

# Check cursor file integrity: each provider's cursor file should have exactly
# one line written by exactly one writer (no torn writes / partial content).
check_cursor_integrity() {
    local run_id="$1"
    local collision=0
    for i in $(seq 1 "$PROVIDERS"); do
        local cursor_file="$PROVIDERS_DIR/mock-provider-$i/cursor"
        if [ ! -f "$cursor_file" ]; then
            fail "run $run_id: provider $i cursor file missing"
            collision=1
            continue
        fi
        local line_count
        line_count=$(wc -l < "$cursor_file" | tr -d ' ')
        # Cursor file must have exactly 1 line (last write wins, no corruption)
        if [ "$line_count" -ne 1 ]; then
            fail "run $run_id: provider $i cursor has $line_count lines (expected 1) — torn write detected"
            collision=1
        fi
        # Content must be numeric (nanosecond timestamp)
        local content
        content=$(tr -d '[:space:]' < "$cursor_file")
        if ! [[ "$content" =~ ^[0-9]+$ ]]; then
            fail "run $run_id: provider $i cursor content corrupted: '$content'"
            collision=1
        fi
    done
    echo "$collision"
}

# ── locate retrieve-all.sh ────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RETRIEVE_ALL="$SCRIPT_DIR/scripts/retrieve-all.sh"
if [ ! -x "$RETRIEVE_ALL" ]; then
    log "ERROR: $RETRIEVE_ALL not found or not executable"
    exit 1
fi

# ── sequential baseline (1 run) ──────────────────────────────────────────────

log "── Sequential baseline (1 run) ──"
setup_providers
t0=$(now_ms)
XGH_PROVIDERS_DIR="$PROVIDERS_DIR" \
    HOME="$TMPBASE" \
    XGH_PARALLEL_RETRIEVE=0 \
    bash "$RETRIEVE_ALL" 2>/dev/null
t1=$(now_ms)
seq_ms=$(( t1 - t0 ))
log "  Sequential: ${seq_ms}ms for $PROVIDERS providers"

# ── parallel runs (100 iterations) ───────────────────────────────────────────

log ""
log "── Parallel backtest (${RUNS} runs × ${PROVIDERS} providers) ──"

total_parallel_ms=0

for run in $(seq 1 "$RUNS"); do
    setup_providers
    # Clear inbox between runs to count items accurately
    rm -f "$INBOX_DIR"/*.md 2>/dev/null || true

    t0=$(now_ms)
    rc=0
    XGH_PROVIDERS_DIR="$PROVIDERS_DIR" \
        HOME="$TMPBASE" \
        XGH_PARALLEL_RETRIEVE=1 \
        bash "$RETRIEVE_ALL" 2>/dev/null || rc=$?
    t1=$(now_ms)
    run_ms=$(( t1 - t0 ))
    total_parallel_ms=$(( total_parallel_ms + run_ms ))

    if [ "$rc" -ne 0 ]; then
        fail "run $run: retrieve-all.sh exited with code $rc"
        COLLISIONS=$((COLLISIONS + 1))
        continue
    fi

    # Check inbox: expect exactly PROVIDERS items
    item_count=$(find "$INBOX_DIR" -name "*.md" -not -name "WARN_*" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$item_count" -ne "$PROVIDERS" ]; then
        fail "run $run: expected $PROVIDERS inbox items, got $item_count"
        COLLISIONS=$((COLLISIONS + 1))
    fi

    # Check cursor integrity for each provider
    collision_flag=$(check_cursor_integrity "$run")
    if [ "$collision_flag" -eq 1 ]; then
        COLLISIONS=$((COLLISIONS + 1))
    else
        ok
    fi
done

# ── timing summary ────────────────────────────────────────────────────────────

avg_parallel_ms=$(( total_parallel_ms / RUNS ))
log ""
log "── Timing ──"
log "  Sequential (baseline): ${seq_ms}ms"
log "  Parallel avg (${RUNS} runs): ${avg_parallel_ms}ms"
if [ "$seq_ms" -gt 0 ]; then
    speedup=$(echo "scale=1; $seq_ms / $avg_parallel_ms" | bc 2>/dev/null || echo "n/a")
    log "  Speedup: ~${speedup}x"
fi

# ── results ───────────────────────────────────────────────────────────────────

log ""
log "── Results ──"
log "  Runs:      $RUNS"
log "  Providers: $PROVIDERS per run"
log "  Passed:    $PASS"
log "  Failed:    $FAIL"
log "  Collisions: $COLLISIONS"

if [ "$COLLISIONS" -eq 0 ]; then
    log ""
    log "BACKTEST PASSED — 0 collisions in $RUNS runs"
    exit 0
else
    log ""
    log "BACKTEST FAILED — $COLLISIONS collision events detected"
    exit 1
fi
