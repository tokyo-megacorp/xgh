# RFC: lossless-claude — SQLite-Only Core, Zero External Dependencies

**Date:** 2026-03-19 (revised)
**Status:** Accepted
**Target:** lossless-claude upstream
**Evidence:** Real-world session data from xgh gap analysis + Voltropy LCM paper (Feb 2026)

---

## Problem

lossless-claude's episodic layer (SQLite DAG, compaction, FTS5) is sound and validated by independent research. But the semantic layer (Qdrant + vllm-mlx/Ollama + Cipher) adds 10 moving parts and is the source of every operational failure observed:

### Failure inventory (single work session, tr-ios, 2026-03-19)

| Metric | Value | Root cause |
|---|---|---|
| Silent memory failures (complex content) | 12 | Cipher extraction pipeline |
| Silent memory failures (backend crash) | 12 | Ollama died, no health check |
| SentinelOne quarantined files | 5 | vllm-mlx LaunchAgent plist |
| Time to discover backend was down | Unknown | No monitoring |

### The semantic pipeline's cost

```
vllm-mlx LaunchAgent (EDR-flagged)
  → embedding model (GPU memory, 10-30s cold start)
    → Qdrant (Docker or native, port 6333, data directory)
      → Cipher package (npm global)
        → cipher-mcp wrapper + OpenAI SDK fix
          → promotion detector (heuristics)
            → qdrant-store.js
```

10 components. Each is a failure point. Together they produce the three classes of failure above.

### External validation

Voltropy's LCM paper (Feb 2026) implements the same core architecture — immutable store, summary DAG, hierarchical compaction — and beats Claude Code by 4.5 points on OOLONG (widening to 12+ points at 256K+ tokens). **They use zero embeddings.** Retrieval is regex/FTS + DAG traversal only. They explicitly acknowledge embedding-based search as a potential "complementary pathway" they haven't needed.

This proves the episodic layer carries the value. The semantic layer is optional.

---

## Revised Architecture

lossless-claude becomes a **SQLite-only system with zero external dependencies**. Qdrant/embeddings become an optional enhancer, not a requirement.

```
┌─────────────────────────────────────────────────┐
│           lossless-claude                        │
│                                                  │
│  Agent API (unchanged):                          │
│    lcm_store · lcm_search · lcm_grep             │
│    lcm_expand · lcm_describe                     │
│                                                  │
├──────────────────────────────────────────────────┤
│                                                  │
│  Core (Tier 1 — zero external deps):             │
│                                                  │
│  SQLite per-project DB                           │
│    ├─ messages table (immutable store)            │
│    ├─ summaries table (DAG: leaf + condensed)     │
│    ├─ promoted table (cross-session, FTS5)  [NEW] │
│    └─ FTS5 index (full-text search)               │
│                                                  │
│  lcm_search(query)                               │
│    → FTS5 across summaries + promoted             │
│    → rank by recency + relevance                  │
│    → if Qdrant available: ∪ semantic results      │
│                                                  │
│  lcm_store(text, tags)                           │
│    → INSERT into promoted (SQLite)                │
│    → if Qdrant available: also embed + store      │
│                                                  │
├──────────────────────────────────────────────────┤
│                                                  │
│  Optional (Tier 2 — power users):                │
│                                                  │
│  Qdrant detected? → enhance lcm_search results   │
│  vllm-mlx/Ollama detected? → generate embeddings │
│  Neither? → FTS5-only, fully functional           │
│                                                  │
├──────────────────────────────────────────────────┤
│                                                  │
│  Process lifecycle:                              │
│                                                  │
│  No LaunchAgents. No plists. No systemd units.   │
│                                                  │
│  MCP server starts (spawned by Claude Code)      │
│    → ensureDaemon(): check PID → spawn if needed │
│  Hooks fire (compact/restore)                    │
│    → ensureDaemon(): same check                  │
│  Daemon: detached process, shared across sessions│
│    → auto-exits after idle timeout (30 min)      │
│    → manages claude-server proxy as child        │
│                                                  │
│  lcm_health() → { daemon, sqlite, qdrant? }     │
│                                                  │
└──────────────────────────────────────────────────┘
```

### Key changes from v1 of this RFC

| Aspect | v1 proposal | v2 (this RFC) |
|---|---|---|
| Qdrant | Required, managed as child process | Optional enhancer, not in critical path |
| vllm-mlx / Ollama | Required, managed as child process | Optional, only if Qdrant is used |
| Cipher | Required for lcm_store | Removed from pipeline entirely |
| Cross-session memory | Qdrant (vector search) | SQLite promoted table + FTS5 |
| External dependencies | Qdrant + embedding model (reduced from LaunchAgent) | Zero (SQLite only) |
| Daemon lifecycle | LaunchAgent → lazy spawn + idle timeout | Same: lazy spawn + idle timeout |
| Install complexity | Lower than before, still needs Qdrant + model | `npm install -g` and done |

---

## Daemon Lifecycle: "Lazy Daemon"

No persistent service. Daemon auto-starts on first use, auto-exits when idle.

```
lossless-claude mcp (spawned by Claude Code)
  → ensureDaemon()
    → read PID file (~/.lossless-claude/daemon.pid)
    → if PID alive + health check passes + version matches → connect
    → if not → spawn daemon as detached child (NOT LaunchAgent)
    → wait for health (with timeout)
  → proxy lcm_* tool calls to daemon via HTTP

lossless-claude compact/restore (hook commands)
  → ensureDaemon() (same logic)
  → POST to daemon
  → exit

Daemon (detached, shared across sessions)
  → listens on 127.0.0.1:3737
  → resets idle timer on every request
  → idle 30 min → exits, deletes PID file
  → manages claude-server proxy as child (existing ProxyManager pattern)
```

### Edge cases addressed

**Race condition on spawn**: Atomic PID file creation (`O_EXCL`). Loser retries with health check. Port conflict (EADDRINUSE) caught — second spawner's child killed, connects to winner's daemon.

**Version mismatch**: `/health` returns `{ status, version, uptime }`. `ensureDaemon()` checks version — if mismatched (user upgraded), sends SIGTERM to old daemon and spawns new.

**Hook timeouts**: `ensureDaemon()` should complete in <2s (PID check + health check, or spawn + wait). If daemon spawn is slow, hooks degrade gracefully (exit 0, no output) as they do today.

**Orphan cleanup**: Daemon writes PID file. On crash, PID file becomes stale. Next `ensureDaemon()` detects stale PID (process dead or wrong version), cleans up, spawns fresh.

**Idle timeout vs active session**: 30 min is conservative. A session with a 40-min implementation gap will cold-restart the daemon (~500ms). Acceptable — no vllm-mlx model loading in the critical path anymore.

---

## Cross-Session Memory via SQLite

Currently, promoted summaries go to Qdrant via Cipher. The new approach stores them in SQLite directly.

### New `promoted` table

```sql
CREATE TABLE promoted (
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  tags TEXT,                    -- JSON array
  source_summary_id TEXT,       -- FK to summaries table (provenance)
  project_id TEXT,              -- enables cross-project search
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (source_summary_id) REFERENCES summaries(id)
);

CREATE VIRTUAL TABLE promoted_fts USING fts5(
  content, tags,
  content=promoted, content_rowid=rowid
);
```

### How `lcm_store` changes

```
lcm_store(text, tags)
  → INSERT INTO promoted (content, tags, project_id)
  → UPDATE promoted_fts
  → if Qdrant available:
      → embed text via vllm-mlx/Ollama
      → upsert to Qdrant collection
      (failure here is non-fatal — FTS5 copy is authoritative)
```

### How `lcm_search` changes

```
lcm_search(query)
  → FTS5 search across promoted + summaries
  → rank by BM25 + recency boost
  → if Qdrant available:
      → semantic search (embed query → nearest neighbors)
      → merge results (union, deduplicate by source_summary_id)
  → return ranked results
```

**Key property**: `lcm_search` always works. Qdrant enhances recall on fuzzy/semantic queries but is never required.

---

## What This Eliminates

| Component | Status |
|---|---|
| `com.lossless-claude.vllm-mlx.plist` (LaunchAgent) | Removed |
| `com.lossless-claude.daemon.plist` (LaunchAgent) | Removed |
| Cipher package (`@byterover/cipher`) | Not required (optional) |
| `cipher-mcp` wrapper script | Not required (optional) |
| `fix-openai-embeddings.js` | Not required (optional) |
| `cipher.yml` | Not required (optional) |
| `setup.sh` (backend picker) | Simplified — no model/backend selection in core install |
| Qdrant (Docker/native) | Not required (optional) |
| vllm-mlx / Ollama | Not required (optional) |
| `setupDaemonService()` in installer | Removed — no plist/systemd |
| `buildLaunchdPlist()` | Removed |
| `buildSystemdUnit()` | Removed |

### What stays

| Component | Role |
|---|---|
| Daemon (HTTP :3737) | SQLite operations, compaction, context assembly |
| MCP server (stdio) | Agent-callable lcm_* tools (proxy to daemon) |
| Hooks (compact, restore) | Session lifecycle (compaction, context restoration) |
| claude-server proxy (:3456) | Summarization via Claude subscription (optional) |
| SQLite per-project DBs | Episodic + cross-session memory |
| ProxyManager | Child process management (claude-server, extensible) |

---

## What changes in xgh (downstream)

| Change | Why |
|---|---|
| Remove Cipher MCP registration from settings | No longer in critical path |
| Remove `continuous-learning-activator.sh` hook | No dual guidance |
| `/xgh-doctor` calls `lcm_health()` | Real health data from daemon |
| Remove plist-related install steps | No LaunchAgents |
| Remove `XGH_SCHEDULER` env var | Scheduler just works |
| Simplify `/store-memory` skill | lcm_store handles everything, no Cipher fallback needed |
| Remove backend picker from xgh installer | lossless-claude install is self-contained |

---

## Voltropy LCM Paper — Key Takeaways to Adopt

From Ehrlich & Blackman (Voltropy, Feb 2026):

| Idea | Action |
|---|---|
| Three-level escalation (LLM → aggressive → deterministic truncation) | Adopt — guarantees compaction convergence |
| Dual-threshold compaction (τ_soft=async, τ_hard=blocking) | Adopt — zero latency until critical |
| Restrict `lcm_expand` to sub-agents only | Adopt — prevents context flooding in main loop |
| File ID propagation through summary DAG | Verify existing impl, add if missing |
| Scope-reduction invariant for delegation | Consider for sub-agent spawning |
| Zero-Cost Continuity (no overhead below soft threshold) | Already implemented (compaction is incremental) |

---

## Migration Path

1. **Phase 1: SQLite cross-session** — Add `promoted` table + FTS5. `lcm_store` writes to SQLite. `lcm_search` queries FTS5. Qdrant integration preserved but made optional (non-fatal on failure).

2. **Phase 2: Lazy daemon** — Replace LaunchAgent/systemd with `ensureDaemon()`. Add idle timeout. Add version check to `/health`. Remove `setupDaemonService()`, `buildLaunchdPlist()`, `buildSystemdUnit()` from installer.

3. **Phase 3: Voltropy improvements** — Three-level escalation, dual-threshold compaction, restrict `lcm_expand` to sub-agents.

4. **Phase 4: xgh cleanup** — Remove Cipher from critical path, simplify installer, remove dual hooks, update `/xgh-doctor`.

Phases 1-3 are lossless-claude changes. Phase 4 is downstream xgh cleanup.

---

## Non-goals

- Changing the `lcm_*` API surface — it stays exactly as-is
- Removing Qdrant support — it becomes optional, not deleted
- Changing the episodic (SQLite DAG) layer — it works and is validated
- Building embedding infrastructure into lossless-claude — embeddings remain external (if present)
