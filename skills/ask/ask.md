---
name: xgh:ask
description: "This skill should be used when the user wants to query project memory, ask about architecture or decisions, or needs help routing a question to the right memory engine. Teaches tiered query routing — when to use lossless-claude semantic search vs context tree BM25 vs both — with query refinement patterns for maximum recall."
---

# xgh:ask

## Purpose

Not all queries are equal. A broad "how do we handle auth?" needs different routing than a specific "what is the JWT refresh token rotation interval?". This skill teaches tiered query routing for maximum recall.

## Query Tiers

### Tier 1: Broad Context (use BOTH engines)

**When:** Starting a new task, exploring a domain, or unsure what exists.

**Strategy:**
1. `lcm_search(query)` with a natural-language description of the task
2. Read context tree `_index.md` files for the relevant domain
3. Merge results mentally — lossless-claude catches semantic matches, context tree catches keyword matches

**Example queries:**
- "How does our authentication system work?"
- "What are our API design conventions?"
- "Past decisions about database schema"

**Expected:** Multiple results from both engines. Read top 3-5 from each.

### Tier 2: Specific Lookup (prefer context tree BM25)

**When:** You know what you are looking for and need exact details.

**Strategy:**
1. Check context tree `_manifest.json` for the specific domain/topic path
2. Read the knowledge file directly
3. Fall back to `lcm_search(query)` only if the context tree does not have it

**Example queries:**
- "JWT refresh token rotation interval"
- "PostgreSQL connection pool max size"
- "REST API error response format"

**Expected:** One or two highly relevant results. The context tree's structured hierarchy makes this fast.

### Tier 3: Reasoning Patterns (use lossless-claude reasoning tools)

**When:** Making a decision and wanting to learn from past decisions.

**Strategy:**
1. `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })` with the decision context
2. `lcm_search` to retrieve patterns → Claude evaluates inline
3. Check context tree for files with category: decision in the relevant domain

**Example queries:**
- "Choosing between REST and GraphQL for the new API"
- "Database migration strategy for adding a new column"
- "Error handling approach for third-party API calls"

**Expected:** Reasoning chains with outcomes — learn from what worked and what did not.

### Tier 4: Debugging/Bug Investigation (use lossless-claude semantic search FIRST)

**When:** Encountering an error or unexpected behavior.

**Strategy:**
1. `lcm_search(query)` with the error message or symptom description
2. Search context tree for files with category: bug-fix
3. If nothing found, broaden the search to the general area (e.g., "authentication errors" instead of "401 on /api/refresh")

**Example queries:**
- "Connection refused on external service"
- "Token refresh returns 401 intermittently"
- "Race condition in concurrent database writes"

**Expected:** Past bug fixes with root causes. Even partial matches can save hours.

## Query Refinement Patterns

When your first query returns nothing useful, do NOT give up. Refine.

### Pattern 1: Broaden

```
"JWT token refresh 401 error" → nothing
"JWT token refresh" → nothing
"authentication token errors" → found it!
```

Remove specific details. Search for the general area first, then narrow.

### Pattern 2: Synonym

```
"caching strategy" → nothing
"cache implementation" → nothing
"memoization patterns" → found it!
```

The original author may have used different terminology.

### Pattern 3: Related Concept

```
"rate limiting configuration" → nothing
"API gateway throttling" → nothing
"request quotas per user" → found it!
```

Think about what ADJACENT concepts might have been curated.

### Pattern 4: Structural

```
"how to add a new API endpoint" → nothing
Check context tree: api-design/ domain → found rest-conventions.md!
```

Sometimes browsing the context tree structure is faster than searching.

### Pattern 5: Multi-Query Fusion

For important decisions, always run at least 3 queries:
1. Direct question: "How do we handle X?"
2. Convention check: "X conventions" or "X patterns"
3. Decision history: "Decisions about X" or "Why we chose X"

Combine results from all three for complete context.

## Scoring Formula

When results come from both engines, xgh ranks them using this BM25 + semantic scoring formula:

```
score = (0.6 * bm25_score + 0.2 * importance + 0.2 * recency) * maturityBoost
```

- `bm25_score`: 0-1, keyword match score from context tree
- `importance`: 0-100 normalized to 0-1
- `recency`: 0-1, exponential decay with ~21-day half-life
- `maturityBoost`: core = 1.15, all others = 1.0

## Query refinement Stops

When to stop searching:

Search is complete when ANY of these are true:
1. You found a core/validated file that directly answers your question
2. You ran 3+ different query formulations and found nothing (document this!)
3. You found related knowledge that gives enough context to proceed
4. The context tree has no entries in the relevant domain (it is truly new territory)

**Never skip the search.** Even "nothing found" is valuable information — it means you are about to create new team knowledge.
