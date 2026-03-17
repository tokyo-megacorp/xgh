# /xgh-status

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh status`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

Show xgh memory statistics, context tree health, and system status.

## Usage

```
/xgh-status
/xgh-status --detailed     # Include per-entry breakdown
```

## Instructions

When the user invokes `/xgh-status`, follow this procedure exactly:

### Step 1: Read Context Tree Manifest

1. Locate `_manifest.json` at `.xgh/context-tree/_manifest.json` (or `$XGH_CONTEXT_TREE/_manifest.json`)
2. Parse the manifest and collect statistics

If the manifest does not exist:

```markdown
## 🐴🤖 xgh status

Context tree: **NOT FOUND**

*Run the xgh installer or `/xgh-curate` to initialize.*
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

### Step 3: Test lossless-claude Connectivity

Check if `mcp__lossless-claude__lcm_search` is present in the available tool list:
- Tool absent → lossless-claude MCP not registered. Fix: add lossless-claude entry to `.claude/mcp.json`
- Tool present but call returns error → daemon not running. Fix: `lossless-claude daemon start`

Run `lcm_search("xgh health check")` to verify connectivity.

### Step 4: Display Status

```markdown
## 🐴🤖 xgh status

Team: **<team-name>** · Context tree: `<path>`

### Knowledge Base

| Metric | Count |
|--------|-------|
| Total entries | **<N>** |
| Core | <N> |
| Validated | <N> |
| Draft | <N> |

### Health

| Check | Value | Status |
|-------|-------|--------|
| Avg importance | <N>/100 | ✅/⚠️/❌ |
| Avg recency | <N> | ✅/⚠️/❌ |
| Stale entries | <N>/<total> (<percent>%) | ✅/⚠️/❌ |
| Orphaned | <N> | ✅/⚠️/❌ |
| lossless-claude | Connected/Disconnected | ✅/❌ |

### Domains

| Domain | Entries | Breakdown |
|--------|---------|-----------|
| <domain>/ | <N> | <breakdown> |

*<recommendation or "All metrics healthy — no action needed.">*
```

Health thresholds:
- **HEALTHY:** avg recency > 0.5, stale < 20%, orphaned = 0, core entries >= 3
- **WARNING:** avg recency 0.25-0.5, stale 20-50%, orphaned 1-2, core entries 1-2
- **CRITICAL:** avg recency < 0.25, stale > 50%, orphaned > 2, core entries = 0

### Step 5: Recommendations

If any metric is WARNING or CRITICAL, provide specific recommendations:

Include specific recommendations in the italicized closing line. For example:

*⚠️ Low average recency (0.32) — consider updating stale entries. ❌ No core entries — promote your most important validated entries.*

If `--detailed` flag is provided, also show a per-entry table:

```markdown
### Detailed Entries

| Path | Maturity | Importance | Recency | Last Updated |
|------|----------|------------|---------|--------------|
| api-design/rest-conventions.md | core | **92** | 0.85 | 2026-03-10 |
| auth/jwt-refresh.md | validated | **71** | 0.62 | 2026-03-05 |
```
