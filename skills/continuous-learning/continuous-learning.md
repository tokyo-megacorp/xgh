---
name: continuous-learning
description: "The xgh iron law: every session queries memory before coding and curates learnings before ending. RIGID — no deviation permitted."
type: rigid
triggers:
  - session-start
  - before-code-write
  - session-end
---

# xgh:continuous-learning

## IRON LAW

> **EVERY CODING SESSION MUST QUERY MEMORY BEFORE WRITING CODE AND CURATE LEARNINGS BEFORE ENDING.**

This is non-negotiable. There are no exceptions. The cost of skipping is always higher than the cost of querying.

## Protocol

### Phase 1: Session Start (BEFORE any code changes)

1. **Query memory** using `cipher_memory_search` with the task description
   - Use at least 2 different query formulations
   - Example: if task is "add pagination to user list API", search for:
     - "pagination implementation patterns"
     - "user list API conventions"
2. **Check context tree** for domain-relevant knowledge files
   - Read any core/validated files in the relevant domain
3. **Search reasoning patterns** using `cipher_search_reasoning_patterns` if making design decisions
4. **Document what you found** — even if results are empty, note: "Queried memory for X, no prior knowledge found"

### Phase 2: During Work (CONTINUOUS)

After every significant code change or decision:

1. **Store reasoning** using `cipher_store_reasoning_memory` when you:
   - Choose between multiple approaches
   - Discover a non-obvious constraint
   - Work around a limitation
   - Establish a new pattern

2. **Extract learnings** using `cipher_extract_and_operate_memory` when you:
   - Complete a feature or fix
   - Discover how a system actually works (vs. how you assumed)
   - Find a pattern that should be team convention

### Phase 3: Session End (BEFORE ending)

1. **Curate all significant learnings** — use `/xgh-curate` for each:
   - New conventions discovered
   - Architectural decisions made
   - Bug fixes with non-obvious root causes
   - Patterns that should be reused
2. **Verify storage** — use `cipher_memory_search` to confirm your curated knowledge is retrievable
3. **Update context tree** — ensure new knowledge is synced to the context tree

## Rationalization Table

These are the excuses agents use to skip memory operations. Every one of them is wrong.

| Agent Thought | Why It Is Wrong | What To Do Instead |
|---|---|---|
| "This is a Simple change, no need to check memory" | Simple changes cause the most repeated mistakes. A 2-second query could reveal a team convention you are about to violate. | Query anyway. It takes 2 seconds. |
| "I already know the conventions from my training data" | Your training data is NOT this team's conventions. Teams have specific, evolving patterns that exist only in their memory. | Query. Your training data is generic; team memory is specific. |
| "Curating this would slow me down" | 30 seconds of curation now saves 30 minutes in the next session that encounters the same problem. | Curate. The next session (which might be you) will thank you. |
| "This learning is too specific to store" | Specific learnings are the MOST valuable. Generic knowledge is already in training data. Team-specific edge cases are gold. | Curate it. Specificity is value. |
| "Memory search returned nothing relevant" | Your query may have been too broad or too narrow. Try at least 2 different formulations before concluding nothing exists. | Refine query. Try synonyms, broader terms, or related concepts. |
| "I will curate at the end of the session" | Sessions end abruptly. Context is lost. Curate as you go — do not batch. | Curate NOW, after each significant action. |
| "This is just a refactor, nothing new to learn" | Refactors reveal system structure. The patterns you discover during refactoring are exactly what future sessions need. | Curate the structural insights you gained. |

## Hard Gates

These are binary pass/fail checkpoints. If any gate fails, the session is non-compliant.

- [ ] **Gate 1:** At least one `cipher_memory_search` call was made before the first code change
- [ ] **Gate 2:** At least one `cipher_extract_and_operate_memory` or `/xgh-curate` call was made during or after code changes
- [ ] **Gate 3:** Any architectural decision has a corresponding `cipher_store_reasoning_memory` call
- [ ] **Gate 4:** Session-end curation was performed (not deferred)

## Verification

After curating, always verify:
1. Run `cipher_memory_search` with keywords from what you just stored
2. Confirm the result appears in the search results
3. If it does not appear, re-curate with better keywords/tags
