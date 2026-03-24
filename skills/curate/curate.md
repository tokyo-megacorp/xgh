---
name: xgh:curate
description: "This skill should be used when the user wants to store knowledge, document a decision, capture a bug fix, or asks 'how do I curate this', 'store this memory', 'save this decision'. Guides structuring knowledge for maximum retrieval quality — classification into domain/topic, frontmatter construction, and tag selection."
---

# xgh:curate

## Purpose

This skill guides structuring knowledge so it can be found later. Poor curation is worse than no curation — it creates false confidence that knowledge exists when it cannot actually be retrieved.

## Step 1: Classify the Knowledge

Determine the knowledge type:

| Category | Description | Example |
|---|---|---|
| **convention** | Team-agreed pattern or rule | "Use kebab-case for all API URLs" |
| **decision** | Architectural/design choice with rationale | "Chose PostgreSQL over MongoDB because..." |
| **pattern** | Reusable implementation approach | "Use the repository pattern for data access" |
| **bug-fix** | Root cause + fix for a non-trivial bug | "Race condition in token refresh caused by..." |
| **discovery** | How something actually works (vs. assumed) | "The payment API returns 200 even on failures" |
| **constraint** | Non-obvious limitation or requirement | "Max 100 items per GraphQL query due to gateway" |

## Step 2: Determine Domain and Topic

Map the knowledge to the context tree hierarchy:

```
domain/          → Broad area (auth, api-design, database, frontend, infra, ...)
  topic/         → Specific subject within the domain
    subtopic/    → (Optional) Further specialization
```

**Rules:**
- Domain names are singular nouns: `authentication` not `auth-stuff`
- Topic names describe the specific subject: `jwt-implementation` not `tokens`
- Use kebab-case for all path segments
- Maximum depth: 3 levels (domain/topic/subtopic)
- If unsure about domain, default to the most specific technical area

**Examples:**
- JWT token refresh logic -> `authentication/jwt-implementation/token-refresh.md`
- REST URL naming convention -> `api-design/rest-conventions.md`
- Database connection pooling config -> `database/connection-pooling.md`

## Step 3: Write the Knowledge File

Every knowledge file has three sections after the frontmatter:

### Frontmatter (YAML)

```yaml
---
title: [Clear, searchable title — think "what would someone search for?"]
tags: [3-7 tags, mix of broad and specific]
keywords: [2-5 specific terms someone might search]
importance: [0-100, start at 50 for new entries]
recency: 1.0
maturity: draft
related:
  - [path/to/related/file]
accessCount: 0
updateCount: 0
createdAt: [ISO 8601 timestamp]
updatedAt: [ISO 8601 timestamp]
source: auto-curate
fromAgent: claude-code
---
```

**Tag guidelines:**
- Include the category (convention, decision, pattern, bug-fix, discovery, constraint)
- Include the technology (react, postgresql, jwt, graphql, etc.)
- Include the team domain (auth, payments, users, etc.)
- Include 1-2 abstract concepts (caching, validation, error-handling)

**Keyword guidelines:**
- Keywords are MORE specific than tags — they are exact terms someone would type
- Include function/class names if relevant: `useAuth`, `TokenService`
- Include error messages if it is a bug-fix: `ECONNREFUSED`, `401 Unauthorized`

### Raw Concept Section

```markdown
## Raw Concept
[Technical details: file paths, function names, configuration values,
execution flow, exact commands. This section is for PRECISION — include
everything needed to reproduce or understand the technical specifics.]
```

### Narrative Section

```markdown
## Narrative
[Structured explanation in plain language. Why does this matter?
What is the context? What are the rules? Include examples.
This section is for UNDERSTANDING — someone should be able to grasp
the concept without reading the Raw Concept section.]
```

### Facts Section

```markdown
## Facts
- category: [convention|decision|pattern|bug-fix|discovery|constraint]
  fact: [One-sentence factual statement]
- category: [same or different]
  fact: [Another factual statement]
```

## Step 4: Store in lossless-claude

After writing the knowledge file to the context tree, also store it in lossless-claude for semantic search:

1. Extract key learnings as a concise summary (3-7 bullets), then [STORE] → call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store. Use tags: ["session"]
2. This enables vector-similarity search alongside the context tree's BM25 search

## Step 5: Update Manifest

After creating or updating a knowledge file:

1. Add/update the entry in `_manifest.json` under the appropriate domain
2. Include: name, path, importance, maturity
3. Update the domain's `_index.md` if it exists (or create it)

## Verification

Storing memory is worthless if it cannot be retrieved. After every store operation, verify the memory can be found. Do not assume success — prove it.

### After lossless-claude Store Operations

After every `lcm_store` call:

1. **Immediate Verify:** Run [SEARCH] → call `lcm_search(query)` with 2-3 different queries:
   - Query A: Use the exact title/topic of what you stored
   - Query B: Use a natural-language question that the stored knowledge should answer
   - Query C: Use a keyword from the stored content

2. **Check Results:**
   - The stored entry MUST appear in the top 5 results for at least one query
   - If it does not appear in ANY query's top 5, the store operation effectively failed

3. **Remediation if verification fails:**
   - Re-curate with better keywords, more specific title, or different tags
   - Add more context to the content (lossless-claude needs enough text for good embeddings)
   - If it still fails after 2 retries, store it ONLY in the context tree (BM25 search will find it)

### After Context Tree Write Operations

After writing a knowledge file to the context tree:

1. **File Exists:** Verify the file was actually written to the expected path
2. **Frontmatter Valid:** Check that the YAML frontmatter parses correctly
3. **Manifest Updated:** Confirm the entry appears in `_manifest.json`
4. **Content Intact:** Verify the file contains the expected sections (Raw Concept, Narrative, Facts)

### Common Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| Store succeeds but search finds nothing | Content too short for meaningful embedding | Add more context — at least 3-4 sentences |
| Search finds it with exact title but not natural language | Keywords/tags too specific | Add broader tags and synonyms |
| Context tree file exists but not in manifest | Manifest update was skipped | Manually add entry to `_manifest.json` |
| lossless-claude returns stale version after update | Embedding not regenerated | Delete old entry, store as new |
| Search returns too many irrelevant results | Tags/keywords too generic | Make tags more specific, add discriminating keywords |

### Minimum Verification Standard

For a memory operation to be considered successful, ALL of these must be true:

1. **Retrievable:** At least one search query returns the entry in top 5 results
2. **Accurate:** The retrieved content matches what was stored (not a stale version)
3. **Discoverable:** A reasonable natural-language question about the topic finds it
4. **Indexed:** The entry appears in the context tree `_manifest.json`

If any of these fail, the memory operation is NOT complete. Fix it before proceeding.

## Convention Entries

When curating a convention, use the following storage format for consistency and retrievability.

### Frontmatter Metadata for Conventions

In addition to the standard frontmatter fields, add these to convention entries:

```yaml
type: convention
scope: team          # team-wide convention
maturity: core       # core = non-negotiable, validated = strong recommendation, draft = proposal
domain: [area]       # e.g., "api-design", "testing", "error-handling", "naming"
version: 1           # incremented on updates, history preserved
supersedes: [id]     # if this convention replaces an older one (optional)
```

### Convention Content Structure

```markdown
## Convention: [Short Name]

**Rule:** [The convention stated as a clear, actionable rule]

**Rationale:** [Why this convention exists — the problem it prevents]

**Examples:**
- Correct: [code example following the convention]
- Incorrect: [code example violating the convention]

**Exceptions:** [When it's acceptable to deviate, if ever]

**History:**
- v1 (date): [Original convention]
- v2 (date): [Updated because...] (supersedes: [old-id])
```

### Convention Naming Rules

- Use the `convention` category in tags and the Facts section
- Domain must be one of: `api-design`, `testing`, `error-handling`, `naming`, `data-access`, `authentication`, `frontend`, `infra`, or a new domain that follows kebab-case
- Title format: `[Domain]: [Short Rule]` — e.g., `"API Design: Use kebab-case for URL segments"`

### Convention Maturity Lifecycle

- `draft` → `validated`: Convention followed successfully in 3+ PRs
- `validated` → `core`: Convention followed for 2+ sprints with no exceptions needed
- Conventions are NEVER silently deleted — mark as `deprecated` with reason, increment version

## Quality Checklist

Before considering curation complete:

- [ ] Title is clear and searchable (would YOU find this by searching?)
- [ ] Tags include category + technology + domain + abstract concept
- [ ] Keywords include specific searchable terms
- [ ] Raw Concept has enough detail to reproduce/understand technically
- [ ] Narrative explains WHY, not just WHAT
- [ ] Facts are one-sentence, factual, categorized
- [ ] File is in the correct domain/topic path
- [ ] Manifest is updated
- [ ] lossless-claude memory is updated (via lcm_store)
- [ ] Verification: [SEARCH] → call `lcm_search(query)` finds the new entry
