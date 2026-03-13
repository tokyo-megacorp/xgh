# /xgh-query

Search xgh memory (Cipher vectors + context tree) and return ranked results.

## Usage

```
/xgh-query <question or keywords>
```

## Instructions

When the user invokes `/xgh-query`, follow this procedure exactly:

### Step 1: Parse the Query

Extract the user's search question or keywords from the argument. If the argument is vague, ask for clarification before proceeding.

### Step 2: Run Parallel Searches

Execute BOTH search engines simultaneously:

**Cipher Semantic Search:**
1. Call `cipher_memory_search` with the user's query as-is
2. Call `cipher_memory_search` with a reformulated version (synonym or broader terms)
3. If the query relates to a decision, also call `cipher_search_reasoning_patterns`

**Context Tree BM25 Search:**
1. Read `_manifest.json` from the context tree (path: `.xgh/context-tree/_manifest.json` or `$XGH_CONTEXT_TREE_PATH/_manifest.json`)
2. Identify domains that might be relevant based on the query keywords
3. Read `_index.md` files for those domains to find matching topics
4. Read the full knowledge files for matching topics

### Step 3: Merge and Rank Results

Combine results from both engines using the xgh scoring formula to produce ranked output:

```
score = (0.5 * cipher_similarity + 0.3 * bm25_score + 0.1 * importance + 0.1 * recency) * maturityBoost
```

Where:
- `cipher_similarity`: 0-1 from Cipher's vector similarity
- `bm25_score`: 0-1, estimate based on keyword match density in context tree files
- `importance`: from the file's frontmatter, normalized to 0-1
- `recency`: from the file's frontmatter
- `maturityBoost`: core = 1.15, validated = 1.0, draft = 0.9

### Step 4: Present Results

Display results in this format:

```
== xgh Query Results ==
Query: "<user's query>"
Sources: Cipher (N results) + Context Tree (M results)

1. [CORE] <Title> (score: 0.XX)
   Path: <context-tree-path>
   Tags: <tag1, tag2, ...>
   Summary: <first 2-3 lines of Narrative section>

2. [VALIDATED] <Title> (score: 0.XX)
   Path: <context-tree-path>
   ...

3. [DRAFT] <Title> (score: 0.XX)
   ...

== End Results (showing top 5 of N total) ==
```

If no results are found from either engine:
```
== xgh Query Results ==
Query: "<user's query>"
No results found.

Suggestions:
- Try broader terms: "<suggested broader query>"
- Try synonyms: "<suggested synonym query>"
- Check context tree domains: <list available domains>
- This may be new territory — consider curating after you learn about it.
```

### Step 5: Offer Follow-Up

After presenting results, ask:
- "Would you like me to read the full content of any of these entries?"
- "Should I refine the search with different terms?"
