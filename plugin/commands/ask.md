# /xgh-ask

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh ask`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

Search xgh memory (lossless-claude vectors + context tree) and return ranked results.

## Usage

```
/xgh-ask <question or keywords>
```

## Instructions

When the user invokes `/xgh-ask`, follow this procedure exactly:

### Step 1: Parse the Query

Extract the user's search question or keywords from the argument. If the argument is vague, ask for clarification before proceeding.

### Step 2: Run Parallel Searches

Execute BOTH search engines simultaneously:

**lossless-claude Semantic Search:**
1. Call `lcm_search(query)` with the user's query as-is
2. Call `lcm_search(query)` with a reformulated version (synonym or broader terms)
3. If the query relates to a decision, also call `lcm_search(query, { layers: ["semantic"], tags: ["reasoning"] })`

**Context Tree BM25 Search:**
1. Read `_manifest.json` from the context tree (path: `.xgh/context-tree/_manifest.json` or `$XGH_CONTEXT_TREE/_manifest.json`)
2. Identify domains that might be relevant based on the query keywords
3. Read `_index.md` files for those domains to find matching topics
4. Read the full knowledge files for matching topics

### Step 3: Merge and Rank Results

Combine results from both engines using the xgh scoring formula to produce ranked output:

```
score = (0.5 * lcm_similarity + 0.3 * bm25_score + 0.1 * importance + 0.1 * recency) * maturityBoost
```

Where:
- `lcm_similarity`: 0-1 from lossless-claude's vector similarity
- `bm25_score`: 0-1, estimate based on keyword match density in context tree files
- `importance`: from the file's frontmatter, normalized to 0-1
- `recency`: from the file's frontmatter
- `maturityBoost`: core = 1.15, validated = 1.0, draft = 0.9

### Step 4: Present Results

Display results in this format:

```markdown
## 🐴🤖 xgh ask

Query: "<user's query>" · Sources: lossless-claude (**N**) + Context Tree (**M**)

| # | Maturity | Title | Score | Tags |
|---|----------|-------|-------|------|
| 1 | core | **<Title>** | 0.XX | <tags> |
| 2 | validated | **<Title>** | 0.XX | <tags> |
| 3 | draft | **<Title>** | 0.XX | <tags> |

*Showing top 5 of N total. Want me to read the full content of any entry?*
```

If no results are found from either engine:

```markdown
## 🐴🤖 xgh ask

Query: "<user's query>" · **No results found.**

| Suggestion | |
|------------|-|
| Broader terms | "<suggested broader query>" |
| Synonyms | "<suggested synonym query>" |
| Available domains | <list available domains> |

*This may be new territory — consider curating after you learn about it.*
```

### Step 5: Offer Follow-Up

After presenting results, ask:
- "Would you like me to read the full content of any of these entries?"
- "Should I refine the search with different terms?"
