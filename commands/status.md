# /xgh-status

Show xgh memory statistics, context tree health, and system status.

## Usage

```
/xgh-status
/xgh-status --detailed     # Include per-entry breakdown
```

## Instructions

When the user invokes `/xgh-status`, follow this procedure exactly:

### Step 1: Read Context Tree Manifest

1. Locate `_manifest.json` at `.xgh/context-tree/_manifest.json` (or `$XGH_CONTEXT_TREE_PATH/_manifest.json`)
2. Parse the manifest and collect statistics

If the manifest does not exist:
```
== xgh Status ==
Context tree: NOT FOUND
Run the xgh installer or /xgh-curate to initialize.
== End Status ==
```

### Step 2: Compute Health Metrics

From the manifest, calculate:

| Metric | How to Calculate |
|---|---|
| Total entries | Count all topic entries across all domains |
| By maturity | Count entries with maturity: core, validated, draft |
| Average importance | Mean of all entries' importance scores |
| Average recency | Mean of all entries' recency scores (compute from updatedAt if not in manifest) |
| Stale entries | Count entries with recency < 0.1 |
| Orphaned entries | Entries in manifest whose files do not exist on disk |
| Domains | Count unique domains |

### Step 3: Test Cipher Connectivity

1. Run a simple `cipher_memory_search` with query "xgh health check"
2. If it returns results (or returns empty without error): Cipher is connected
3. If it errors: Cipher is disconnected

### Step 4: Display Status

```
== xgh Status ==

Team: <team-name>
Context Tree: <path>

Knowledge Base:
  Total entries:     <N>
  Core:              <N> (maturity >= 85)
  Validated:         <N> (maturity >= 65)
  Draft:             <N>
  Archived:          <N>

Health:
  Avg importance:    <N>/100  [HEALTHY|WARNING|CRITICAL]
  Avg recency:       <0.XX>  [HEALTHY|WARNING|CRITICAL]
  Stale entries:     <N>/<total> (<percent>%)  [HEALTHY|WARNING|CRITICAL]
  Orphaned entries:  <N>  [HEALTHY|WARNING|CRITICAL]

Cipher MCP:
  Status:            [CONNECTED|DISCONNECTED]
  Memory count:      <N> (from cipher search)

Domains:
  <domain-1>/       <N> entries (<N> core, <N> validated, <N> draft)
  <domain-2>/       <N> entries (...)
  ...

== End Status ==
```

Health thresholds:
- **HEALTHY:** avg recency > 0.5, stale < 20%, orphaned = 0, core entries >= 3
- **WARNING:** avg recency 0.25-0.5, stale 20-50%, orphaned 1-2, core entries 1-2
- **CRITICAL:** avg recency < 0.25, stale > 50%, orphaned > 2, core entries = 0

### Step 5: Recommendations

If any metric is WARNING or CRITICAL, provide specific recommendations:

```
Recommendations:
- [WARNING] Low average recency (0.32): Consider updating stale entries or running maintenance
- [CRITICAL] No core entries: Promote your most important validated entries to core maturity
- [WARNING] 3 orphaned entries: Run context tree maintenance to clean up manifest
```

If `--detailed` flag is provided, also show a per-entry table:

```
Detailed Entries:
| Path | Maturity | Importance | Recency | Last Updated |
|---|---|---|---|---|
| api-design/rest-conventions.md | core | 92 | 0.85 | 2026-03-10 |
| auth/jwt-refresh.md | validated | 71 | 0.62 | 2026-03-05 |
| ... | ... | ... | ... | ... |
```
