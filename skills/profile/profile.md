---
name: xgh:profile
description: "This skill should be used when the user runs /xgh-profile or asks about engineer capacity, assignment, or estimation. Analyzes engineer Jira history to produce throughput profiles, ticket affinity, and data-driven time estimates for task assignment — supports single engineer and team-view modes."
---

# xgh:profile — Engineer Throughput & Affinity Analysis

Analyze an engineer's Jira history to produce throughput profiles, ticket type affinity, and data-driven estimates for open work. Supports single-engineer and team-view (multi-engineer) modes.

## Trigger

```
/xgh-profile <engineer name> [project key]
/xgh-profile Alice
/xgh-profile Alice PTECH
/xgh-profile Alice,Bob,Carol PTECH
```

- `<engineer name>` — Required. The engineer's display name (or comma-separated names for team view).
- `[project key]` — Optional. If provided, fetches open tickets from that project for estimation and assignment recommendations.

---

## MCP Auto-Detection

Follow the shared detection protocol in `skills/_shared/references/mcp-auto-detection.md`. This skill uses two integrations with different availability rules:

| Integration | Detection signal | Capability |
|-------------|-----------------|------------|
| Atlassian | `searchJiraIssuesUsingJql` tool available | Ticket history, open backlog |
| lossless-claude | `mcp__lossless-claude__lcm_search` tool available | Cache profiles, recall past analyses |

If Atlassian MCP is not available, abort with:

```
Atlassian MCP is required for this skill. Run /xgh-setup to configure it.
```

If lossless-claude is available, search for a cached profile before fetching:
- Query: `lcm_search("team-profile <engineer name>")`
- If a profile exists from the last 7 days, offer to use cached data or refresh

---

## Step 1 — Fetch Jira History

For each engineer name provided:

Use `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` with:

- **JQL:** `assignee = "<name>" ORDER BY updated DESC`
- **maxResults:** 100
- **fields:** summary, status, assignee, priority, issuetype, labels, created, resolutiondate, customfield_10016 (story points), parent, components

The `cloudId` should be resolved from the project's `ingest.yaml` config if available, or by calling `mcp__claude_ai_Atlassian__getAccessibleAtlassianResources` to discover it.

If the query returns 0 results, try variations:
- Search by display name substring: `assignee = "<first name>"`
- Ask the user to confirm the exact Jira display name

---

## Step 2 — Calculate Throughput Profile

Filter to completed tickets only — status in: `Done`, `Closed`, `QA Passed`, `Released`.

### Cycle Time Calculation

For each completed ticket, compute **cycle time in working days**:

```
cycle_time = count_working_days(created, resolutiondate)
```

**Working days:** Exclude Saturdays and Sundays. For each day between `created` and `resolutiondate`, count only Mon-Fri.

### Grouping

Group completed tickets by:

1. **Issue type:** Story, Task, Bug, Sub-task, Spike, etc.
2. **Label categories:** Group by each label present on tickets
3. **Complexity (story point buckets):**
   - 0-1 SP (trivial)
   - 2-3 SP (small)
   - 4-5 SP (medium)
   - 6+ SP (large)
   - No SP (unestimated)

### Statistics per Group

For each group with 3+ tickets, compute:

| Metric | Formula |
|--------|---------|
| **Median** | Middle value of sorted cycle times |
| **P75** | 75th percentile |
| **P90** | 90th percentile |
| **Count** | Number of tickets in group |

### Throughput Windows

Count tickets completed in rolling windows:

| Window | Description |
|--------|-------------|
| Last 30 days | Tickets with `resolutiondate` in the last 30 calendar days |
| Last 60 days | Tickets with `resolutiondate` in the last 60 calendar days |
| Last 90 days | Tickets with `resolutiondate` in the last 90 calendar days |

Express as: `N tickets / 30d` for each window.

---

## Reference

### Output Format

```
## Throughput Profile — [Engineer Name]

### Cycle Times by Issue Type
| Type     | Count | Median | P75  | P90   |
|----------|-------|--------|------|-------|
| Story    | 18    | 5.0d   | 8.0d | 14.0d |
| Bug      | 12    | 2.0d   | 3.5d | 6.0d  |
| Task     | 8     | 3.0d   | 5.0d | 7.0d  |
| Sub-task | 15    | 1.0d   | 2.0d | 3.0d  |

### Cycle Times by Complexity (SP)
| SP Bucket   | Count | Median | P75  | P90   |
|-------------|-------|--------|------|-------|
| 0-1 (triv.) | 10    | 1.5d   | 2.0d | 3.0d  |
| 2-3 (small) | 14    | 3.0d   | 5.0d | 7.0d  |
| 4-5 (med.)  | 8     | 6.0d   | 9.0d | 12.0d |
| 6+ (large)  | 3     | 12.0d  | 15.0d| 18.0d |

### Throughput
| Window   | Completed | Rate         |
|----------|-----------|--------------|
| Last 30d | 7         | 7 tickets/mo |
| Last 60d | 15        | 7.5 tickets/mo |
| Last 90d | 22        | 7.3 tickets/mo |
```

---

## Step 3 — Ticket Type Affinity

Analyze the full distribution (all 100 tickets, not just completed) to determine what this engineer works on.

### Distribution Breakdowns

1. **By issue type** — percentage of total tickets per type
2. **By label/component** — top 10 labels and components by frequency
3. **By parent epic** — top 5 epics the engineer contributes to (use `parent` field)
4. **By complexity** — SP distribution histogram

### Sweet Spot Identification

The engineer's "sweet spot" is the intersection of **high volume** and **fast cycle time**:

```
sweet_spot_score = (ticket_count / max_count) * (1 / median_cycle_time)
```

Compute this score for each (issue type, SP bucket) pair. The top-scoring pair is the sweet spot.

### Output Format

```
## Ticket Affinity — [Engineer Name]

### Work Distribution
| Issue Type | Count | % of Total |
|------------|-------|------------|
| Story      | 35    | 35%        |
| Bug        | 25    | 25%        |
| Task       | 20    | 20%        |
| Sub-task   | 20    | 20%        |

### Top Labels
1. passcode (28 tickets)
2. frontend (22 tickets)
3. auth (15 tickets)
...

### Top Components
1. web-app (30 tickets)
2. api-gateway (18 tickets)
...

### Top Epics
1. PROJ-100 "Passcode Migration" (12 tickets)
2. PROJ-200 "Auth Redesign" (8 tickets)
...

### Sweet Spot
**Bug fixes in the 2-3 SP range** — high volume (14 tickets) with fast
median cycle time (2.5d). This is where [Engineer] delivers the most
value per unit time.
```

---

## Step 4 — Data-Driven Estimates

**Only execute this step if a `project key` argument was provided.**

### Fetch Open Tickets

Use `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` with:

- **JQL:** `project = <key> AND status in (Backlog, "To Do") ORDER BY priority DESC`
- **maxResults:** 50
- **fields:** key, summary, issuetype, labels, priority, customfield_10016, parent, components

If the project uses a specific label filter (e.g., `passcode`), the user can specify it. Otherwise, fetch all backlog tickets.

### Similarity Matching

For each open ticket, find the engineer's completed tickets most similar to it. Similarity is computed as:

| Factor | Match Condition | Weight |
|--------|----------------|--------|
| Issue type | Same issue type | +3 |
| Labels | Each overlapping label | +2 per label |
| SP range | Same SP bucket (0-1, 2-3, 4-5, 6+) | +2 |
| Component | Same component | +2 |
| Summary keywords | Overlapping non-stopword tokens in summary | +1 per token (max 3) |

**SP fallback:** If story points are missing on either the open ticket or the completed ticket, skip the SP factor and increase label weight to +3.

Rank completed tickets by similarity score. Take the top 3-5 matches.

### Confidence Levels

| Similar Tickets Found | Confidence |
|-----------------------|------------|
| 5+ | High |
| 3-4 | Medium |
| < 3 | Low |

### Estimate Calculation

- **Estimated days** = median cycle time of top 3-5 similar completed tickets
- **Basis** = "Based on N similar tickets with median Xd"

### Output Format

```
## Estimates for [Project Key] — assigned to [Engineer Name]

| Ticket    | Summary                  | Est. Days | Confidence | Basis                                    |
|-----------|--------------------------|-----------|------------|------------------------------------------|
| PROJ-456  | Add SSO support          | 6.0d      | High       | Based on 7 similar tickets, median 6.0d  |
| PROJ-457  | Fix password reset email | 2.5d      | Medium     | Based on 4 similar tickets, median 2.5d  |
| PROJ-458  | Redesign settings page   | 10.0d     | Low        | Based on 2 similar tickets, median 10.0d |

> Estimates are based on historical Jira data. Accuracy improves with more
> completed tickets. Low-confidence estimates should be treated as rough
> guidance only.
```

---

## Step 5 — Assignment Recommendations

**Only execute this step if a `project key` argument was provided.**

For each open ticket from Step 4, compute an **affinity score** for the engineer:

| Factor | Condition | Points |
|--------|-----------|--------|
| Label overlap | Each label matching the engineer's history | +3 per label |
| Issue type match | Same type as engineer's fastest category | +2 |
| SP sweet spot | Within the engineer's sweet-spot SP bucket | +2 |
| Epic continuity | Same parent epic as past work | +1 |

### Output Format

```
## Top 5 Recommended Tickets for [Engineer Name]

1. **PROJ-456** "Add SSO support" — Affinity: 11
   - Labels: auth (+3), passcode (+3) | Type: Story = fastest (+2) | SP: 3 = sweet spot (+2) | Epic: PROJ-100 (+1)

2. **PROJ-459** "Refactor token service" — Affinity: 8
   - Labels: auth (+3) | Type: Task (+0) | SP: 2 = sweet spot (+2) | Epic: PROJ-100 (+1) | Keywords: token (+2)

...
```

---

## Step 6 — Team View (Multi-Engineer Mode)

**Only execute this step if multiple engineer names were provided (comma-separated).**

After completing Steps 1-5 for each engineer individually, produce a combined assignment matrix.

### Assignment Matrix

```
## Team Assignment Matrix — [Project Key]

| Ticket    | Summary              | Alice (est/aff) | Bob (est/aff) | Carol (est/aff) | Recommended |
|-----------|----------------------|------------------|----------------|------------------|-------------|
| PROJ-456  | Add SSO support      | 6.0d / 11        | 8.0d / 5       | 4.0d / 9         | Carol       |
| PROJ-457  | Fix password reset   | 2.5d / 8         | 2.0d / 10      | 5.0d / 3         | Bob         |
| PROJ-458  | Redesign settings    | 10.0d / 4        | 7.0d / 7       | 6.0d / 8         | Carol       |
```

### Optimal Assignment

Use a greedy assignment heuristic:
1. Compute a **combined score** per (engineer, ticket) pair: `combined = affinity - (estimated_days * 0.5)`
2. Sort all (engineer, ticket) pairs by combined score descending
3. Assign greedily: pick the highest-scoring pair, remove that ticket from consideration, continue
4. Balance: no engineer should have more than 2x the tickets of any other engineer (re-assign if needed)

```
### Optimal Assignment
- **Alice:** PROJ-457 (2.5d, aff 8), PROJ-460 (3.0d, aff 7) — total: 5.5d
- **Bob:** PROJ-459 (4.0d, aff 6), PROJ-461 (2.0d, aff 9) — total: 6.0d
- **Carol:** PROJ-456 (4.0d, aff 9), PROJ-458 (6.0d, aff 8) — total: 10.0d
```

---

## Report Output

Write the full profile report to: `docs/research/<engineer-name-slug>-profile.md`

- Slugify the engineer name: lowercase, replace spaces with hyphens
- For team view, use: `docs/research/team-profile-<project-key-lower>.md`

Print a concise summary to the conversation with key highlights:
- Throughput rate (tickets/month)
- Sweet spot
- Top 3 recommended tickets (if project key provided)
- Any notable findings (e.g., "cycle time has increased 40% in the last 30d vs 90d average")

### lossless-claude Storage (if available)

After generating the report, use `lcm_store(text, ["reasoning"])` to store:
- Engineer throughput baseline (for future comparison)
- Sweet spot identification (for future assignment queries)
- Estimation basis (so future sessions can reference without re-fetching)

---

## Data Quality Notes

Always include this disclaimer in the report:

> **Data quality notice:** Estimates are based on historical Jira data. Accuracy
> improves with more completed tickets (ideally 30+). Cycle time is measured from
> ticket creation to resolution, which may not reflect actual hands-on time.
> Tickets without story points use issue-type and label matching only. Weekend
> exclusion assumes a standard Mon-Fri work week.

---

## Error Handling

- **No completed tickets found:** Report throughput as 0, skip cycle time stats, note "Insufficient data for cycle time analysis"
- **Story points missing on all tickets:** Skip SP-based grouping entirely, increase weight of label and issue type matching
- **Engineer name not found:** Suggest using `mcp__claude_ai_Atlassian__lookupJiraAccountId` to verify the name, then retry
- **API rate limits:** If a query fails, wait 5 seconds and retry once. If it fails again, report partial results with a note
- **Fewer than 3 similar tickets for estimation:** Mark confidence as "Low" and note "Consider breaking this ticket down or comparing with team-wide data"
