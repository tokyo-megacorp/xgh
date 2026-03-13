---
name: curate-knowledge
description: "How to structure knowledge for maximum retrieval quality. Guides classification into domain/topic, frontmatter construction, and tag selection."
type: flexible
triggers:
  - after-code-change
  - after-decision
  - after-bug-fix
  - manual-curate
---

# xgh:curate-knowledge

## Purpose

This skill guides you through structuring knowledge so it can be found later. Poor curation is worse than no curation — it creates false confidence that knowledge exists when it cannot actually be retrieved.

## Step 1: Classify the Knowledge

Determine what kind of knowledge you are curating:

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

## Step 4: Store in Cipher

After writing the knowledge file to the context tree, also store it in Cipher for semantic search:

1. Use `cipher_extract_and_operate_memory` with the full content
2. Include metadata: domain, topic, category, tags
3. This enables vector-similarity search alongside the context tree's BM25 search

## Step 5: Update Manifest

After creating or updating a knowledge file:

1. Add/update the entry in `_manifest.json` under the appropriate domain
2. Include: name, path, importance, maturity
3. Update the domain's `_index.md` if it exists (or create it)

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
- [ ] Cipher memory is updated (via cipher_extract_and_operate_memory)
- [ ] Verification: `cipher_memory_search` finds the new entry
