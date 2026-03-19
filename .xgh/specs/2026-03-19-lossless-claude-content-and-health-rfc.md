# RFC: Content Resilience & Backend Health Monitoring

**Date:** 2026-03-19
**Status:** Proposal
**Target:** lossless-claude upstream
**Relates to:** [Unified Router RFC](2026-03-19-lossless-claude-unified-router-pitch.md) (Phases 2 & 3)
**Evidence:** Real-world session data, xgh gap analysis 2026-03-19

---

## Scope

Two capabilities that lossless-claude must own internally — content that agents store should never be silently dropped, and backend failures should never be invisible.

| Gap | Problem | Impact |
|---|---|---|
| **Gap 2** — Content resilience | `lcm_store` silently drops complex content (>500 chars, markdown, tables) | 12 memories lost in one session |
| **Gap 6** — Backend health | Model server / Qdrant crashes are invisible to agents and users | 12 more memories lost; failure discovered hours later by manual check |

---

## Gap 2: Content Resilience

### Observed failure mode

During a real work session (tr-ios project), the agent called `cipher_extract_and_operate_memory` (now `lcm_store`) with content that included:

- Architecture decision documents (800+ chars)
- Markdown tables (dependency matrices)
- Multi-section specs with headers and code blocks
- Thread summaries with nested bullet lists

**Result:** `extracted: 0` for every one. The cipher-pre-hook correctly detected each failure and warned the agent, but the agent bypassed the suggested fix path and called `storeWithDedup` directly — losing TTL, routing, dedup, and content-type tagging.

**Root cause:** The extraction pipeline has a fixed internal prompt that chokes on structured content. It expects short, simple text — not real-world documents.

### Proposed fix: content preprocessing in lcm_store

`lcm_store(text, tags)` should handle any content the agent throws at it. The agent already does the hard work (extracting 3-7 bullet summaries from conversations). lossless-claude's job is to never drop what it receives.

#### Strategy 1: Chunking for long content

```
lcm_store(text, tags, metadata?)
  │
  ├── len(text) <= 500 chars
  │     → store directly (current behavior, works fine)
  │
  └── len(text) > 500 chars
        → split into semantic chunks:
        │   - Split on markdown headers (## / ###)
        │   - Fall back to paragraph breaks (\n\n)
        │   - Fall back to sentence boundaries
        │   - Each chunk ≤ 500 chars
        │
        → store each chunk with:
           - Same tags as parent
           - metadata.chunk_group = uuid (links chunks together)
           - metadata.chunk_index = 0, 1, 2...
           - metadata.chunk_total = N
           - metadata.source_preview = first 100 chars of original
```

#### Strategy 2: Structured content normalization

```
Input contains markdown tables?
  → Convert to key-value pairs:
     "| Name | Role |" + "| Alice | Eng |"
     → "Alice: Eng"
  → Store normalized text (smaller, embeds better)

Input contains code blocks?
  → Extract code block language + first line as summary
  → Store summary as searchable text
  → Store full code block in metadata.code (not embedded, but retrievable)

Input contains nested lists?
  → Flatten to single-level with context prefixes:
     "- Auth\n  - Token refresh\n    - 15 min TTL"
     → "Auth > Token refresh > 15 min TTL"
```

#### Strategy 3: Graceful degradation (never drop)

```
If chunking fails (edge case):
  → Store the full text as-is in episodic (SQLite) layer
  → SQLite has no size limit — FTS5 indexes it fine
  → Skip semantic (Qdrant) embedding for this entry
  → Log warning: "Content too complex for vector embedding, stored in episodic only"
  → Return { stored: true, layers: ["episodic"], warning: "..." }

NEVER return extracted: 0. NEVER silently drop content.
```

#### lcm_store response contract

Current: no structured response — agent doesn't know if storage succeeded.

Proposed:

```json
// Success
{
  "stored": true,
  "id": "mem_abc123",
  "layers": ["episodic", "semantic"],
  "chunks": 1
}

// Success with chunking
{
  "stored": true,
  "id": "mem_abc123",
  "layers": ["episodic", "semantic"],
  "chunks": 3,
  "chunk_group": "grp_xyz789"
}

// Partial success (episodic only)
{
  "stored": true,
  "id": "mem_abc123",
  "layers": ["episodic"],
  "chunks": 1,
  "warning": "Content stored in episodic only — vector embedding failed after retry"
}

// Failure (should be exceptional)
{
  "stored": false,
  "error": "Qdrant unreachable and SQLite write failed: disk full"
}
```

The agent can trust that `stored: true` means the content is retrievable. No more guessing.

#### lcm_search behavior with chunked content

When search returns a chunk:

```json
{
  "id": "mem_chunk_1",
  "text": "Auth > Token refresh > 15 min TTL...",
  "score": 0.89,
  "metadata": {
    "chunk_group": "grp_xyz789",
    "chunk_index": 1,
    "chunk_total": 3
  }
}
```

The agent can call `lcm_expand(chunk_group)` to retrieve all chunks in order — reconstructing the original document. This reuses the existing `lcm_expand` pattern (drill into a summary to get details).

---

## Gap 6: Backend Health Monitoring

### Observed failure mode

Ollama (the model server backend) crashed silently during a session. The MCP server continued accepting `lcm_store` calls but couldn't generate embeddings. Each call either:

- Timed out internally and returned nothing
- Fell back to episodic-only storage without informing the agent
- Failed silently with no error surfaced

**Result:** 12 memories stored without semantic embeddings — effectively invisible to `lcm_search` with `layers: ["semantic"]`. Discovered hours later during manual `/xgh-analyze`.

### Proposed fix: ensureBackend + lcm_health

#### Pre-operation health gate

Every `lcm_store` and `lcm_search` call that touches the semantic layer should first verify the backend is reachable:

```
lcm_store(text, tags) or lcm_search(query, {layers: ["semantic"]})
  │
  ├── ensureBackend()
  │     ├── Model server reachable? (HTTP health endpoint)
  │     │     ├── Yes → proceed
  │     │     └── No → attempt start (on-demand, per Unified Router RFC)
  │     │           ├── Started → proceed
  │     │           └── Failed → structured error OR episodic fallback
  │     │
  │     └── Qdrant reachable? (HTTP health endpoint)
  │           ├── Yes → proceed
  │           └── No → attempt restart
  │                 ├── Restarted → proceed
  │                 └── Failed → structured error OR episodic fallback
  │
  └── Execute operation
```

#### Fallback policy

When the semantic backend is down and can't be restarted:

| Operation | Fallback | Agent sees |
|---|---|---|
| `lcm_store` | Store in episodic (SQLite) only | `{ stored: true, layers: ["episodic"], warning: "semantic backend unavailable" }` |
| `lcm_search` (semantic) | Search episodic via FTS5 | `{ results: [...], warning: "semantic search unavailable, showing episodic results only" }` |
| `lcm_search` (hybrid) | Search episodic, note missing semantic | `{ results: [...], warning: "partial results — semantic layer offline" }` |

**Key principle:** Never silently degrade. The agent must know when it's getting partial results so it can inform the user or adjust behavior.

#### Retry queue for failed semantic stores

When content is stored in episodic-only due to backend failure:

```
Episodic-only entries are tagged: metadata.pending_semantic = true

When backend recovers (detected by next successful health check):
  → Query episodic for pending_semantic = true
  → Generate embeddings and store in Qdrant
  → Clear pending_semantic flag
  → Log: "Backfilled N entries to semantic layer"
```

This ensures no data is permanently lost to outages — it's eventually consistent.

#### lcm_health() MCP tool

Exposed to agents and external tools (like `/xgh-doctor`):

```
lcm_health() → {
  status: "healthy" | "degraded" | "unhealthy",

  model_server: {
    status: "running" | "stopped" | "error",
    backend: "vllm-mlx" | "ollama" | "openai" | "anthropic",
    uptime_seconds: 3600,
    last_request: "2026-03-19T10:30:00Z",
    model: "llama-3.2-3b"
  },

  qdrant: {
    status: "running" | "stopped" | "error",
    collections: ["memories"],
    entry_count: 847,
    size_mb: 12.4
  },

  episodic: {
    status: "running",  // SQLite — always available
    entry_count: 2341,
    size_mb: 8.2,
    pending_semantic: 3  // entries waiting for backend recovery
  },

  last_check: "2026-03-19T10:35:00Z"
}
```

**Status rollup logic:**

```
healthy   = model_server.running AND qdrant.running AND pending_semantic == 0
degraded  = episodic.running AND (model_server.error OR qdrant.error OR pending_semantic > 0)
unhealthy = episodic.error (SQLite itself is down — catastrophic)
```

---

## Implementation Priority

| Phase | What | Why first |
|---|---|---|
| **Phase 1** | `lcm_store` response contract + graceful degradation | Stop silent data loss immediately |
| **Phase 2** | `ensureBackend()` + health gate | Prevent invisible outages |
| **Phase 3** | Content chunking + normalization | Handle complex content properly |
| **Phase 4** | `lcm_health()` MCP tool | External observability |
| **Phase 5** | Retry queue for failed semantic stores | Eventually consistent backfill |

Phase 1 is the critical fix — even without chunking or health monitoring, just returning `{ stored: false }` instead of `{ extracted: 0 }` would have surfaced the 24 failures from the gap analysis session immediately.

---

## Success Criteria

1. `lcm_store` with 1000-char markdown content → `stored: true`, retrievable via `lcm_search`
2. Kill model server mid-session → next `lcm_store` returns warning, stores in episodic, auto-restarts backend
3. Restart model server → pending entries backfilled to semantic layer automatically
4. `lcm_health()` returns accurate status within 2 seconds
5. Zero silent data drops across a full work session (the 24-failure scenario from gap analysis must produce 0 lost memories)
