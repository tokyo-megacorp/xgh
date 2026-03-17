# Context Tree Rules

> Reference documentation for `context-tree.sh` and any agent or tool that maintains the context tree. Defines scoring rules, maturity lifecycle, archival thresholds, and the maintenance procedure.

## Scoring Rules

### Importance Score (0-100)

Importance increases when knowledge is useful and decreases via natural decay.

| Event | Importance Change |
|---|---|
| Search hit (file appeared in query results) | +3 |
| Knowledge update (file content was modified) | +5 |
| Manual curate (human or agent explicitly curated) | +10 |
| Referenced in a decision (cited in reasoning memory) | +7 |
| Time decay | Exponential, ~21-day half-life |

**Calculation:**

```
importance = base_importance * recency_factor

recency_factor = exp(-0.693 * days_since_last_access / 21)
```

Where `base_importance` is the raw score from events, and `recency_factor` applies time decay.

**Bounds:** importance is clamped to [0, 100].

### Recency Score (0-1)

Recency decays automatically and resets on access:

```
recency = exp(-0.693 * days_since_last_update / 21)
```

- On update: recency resets to 1.0
- After 21 days: recency = 0.5
- After 42 days: recency = 0.25
- After 63 days: recency = 0.125

## Maturity Lifecycle

```
draft  ──────────>  validated  ──────────>  core
       importance>=65          importance>=85

core   ──────────>  validated  ──────────>  draft
       importance<50           importance<30
       (hysteresis:-35)        (hysteresis:-35)
```

### Promotion Rules

| Transition | Condition |
|---|---|
| draft -> validated | importance >= 65 AND at least 2 updates |
| validated -> core | importance >= 85 AND at least 5 search hits AND at least 1 manual review |

### Demotion Rules (with hysteresis)

Hysteresis prevents oscillation — demotion thresholds are lower than promotion thresholds.

| Transition | Condition |
|---|---|
| core -> validated | importance < 50 (i.e., 85 - 35 = 50) |
| validated -> draft | importance < 30 (i.e., 65 - 35 = 30) |

### Maturity Boost in Search

| Maturity | Search Score Multiplier |
|---|---|
| core | 1.15x |
| validated | 1.00x |
| draft | 0.90x |

## Archival

Draft files with low importance are archived to keep the active tree lean.

### Archive Trigger

A draft file is archived when:
- `importance < 35` AND `recency < 0.25` (roughly 42+ days without access)
- OR manually flagged for archival

### Archive Process

1. Create `_archived/{domain}/{topic}/{filename}.stub.md` — a searchable ghost with:
   - Original frontmatter (preserved)
   - First 3 lines of the Narrative section
   - A pointer: `Full content: _archived/{path}.full.md`

2. Create `_archived/{domain}/{topic}/{filename}.full.md` — lossless backup:
   - Complete original file content
   - Additional frontmatter: `archivedAt`, `archiveReason`

3. Remove the original file from the active tree

4. Update `_manifest.json`: set `archived: true` on the entry

### Unarchive

To restore an archived file:
1. Copy `.full.md` back to the original path
2. Update frontmatter: reset `importance` to 50, `recency` to 1.0, `maturity` to draft
3. Remove the `.stub.md` and `.full.md` from `_archived/`
4. Update `_manifest.json`: remove `archived: true`

## Maintenance Procedure

Run this periodically (suggested: every 5-10 sessions, or weekly).

### Step 1: Update Scores

For each entry in `_manifest.json`:
1. Calculate current `recency` based on `updatedAt`
2. Apply recency decay to importance: `effective_importance = importance * recency`
3. Update the entry's `importance` and `recency` in frontmatter

### Step 2: Apply Maturity Transitions

For each entry:
1. Check if it qualifies for promotion (draft->validated, validated->core)
2. Check if it qualifies for demotion (core->validated, validated->draft)
3. Update `maturity` in frontmatter and `_manifest.json`

### Step 3: Archive Stale Drafts

For each draft entry:
1. Check if `importance < 35` AND `recency < 0.25`
2. If yes, execute the archive process

### Step 4: Rebuild Index Files

For each domain directory:
1. Regenerate `_index.md` with a compressed summary of all active entries
2. Update `_manifest.json` domain-level statistics

### Step 5: Sync with lossless-claude

For each modified entry:
1. Update the corresponding memory via `lcm_store` (extract 3-7 bullet summary first)
2. The lossless-claude deduplication layer handles archival automatically

## Health Metrics

Report these in `/xgh-status`:

| Metric | Healthy | Warning | Critical |
|---|---|---|---|
| Total entries | Any | - | 0 |
| Core entries | >= 3 | 1-2 | 0 |
| Average recency | > 0.5 | 0.25-0.5 | < 0.25 |
| Stale drafts (recency < 0.1) | < 20% | 20-50% | > 50% |
| Orphaned entries (in manifest but file missing) | 0 | 1-2 | > 2 |
