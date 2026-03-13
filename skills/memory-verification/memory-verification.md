---
name: memory-verification
description: "Verify that memory was actually stored and can be retrieved correctly. Evidence-before-claims principle applied to memory operations."
type: rigid
triggers:
  - after-curate
  - after-store
  - manual-verify
---

# xgh:memory-verification

## Purpose

Storing memory is worthless if it cannot be retrieved. This skill enforces the evidence-before-claims principle: after every store operation, verify the memory can be found. Do not assume success — prove it.

## The Problem

Memory operations can silently fail:
- Cipher may acknowledge the store but the embedding may be poor quality
- The context tree file may be written but the manifest not updated
- Tags/keywords may be too generic, causing the entry to be buried in results
- The knowledge may be stored but in a form that does not match how future queries will look

## Verification Protocol

### After Cipher Store Operations

After every `cipher_extract_and_operate_memory` or `cipher_store_reasoning_memory` call:

1. **Immediate Verify:** Run `cipher_memory_search` with 2-3 different queries:
   - Query A: Use the exact title/topic of what you stored
   - Query B: Use a natural-language question that the stored knowledge should answer
   - Query C: Use a keyword from the stored content

2. **Check Results:**
   - The stored entry MUST appear in the top 5 results for at least one query
   - If it does not appear in ANY query's top 5, the store operation effectively failed

3. **Remediation if verification fails:**
   - Re-curate with better keywords, more specific title, or different tags
   - Add more context to the content (Cipher needs enough text for good embeddings)
   - If it still fails after 2 retries, store it ONLY in the context tree (BM25 search will find it)

### After Context Tree Write Operations

After writing a knowledge file to the context tree:

1. **File Exists:** Verify the file was actually written to the expected path
2. **Frontmatter Valid:** Check that the YAML frontmatter parses correctly
3. **Manifest Updated:** Confirm the entry appears in `_manifest.json`
4. **Content Intact:** Verify the file contains the expected sections (Raw Concept, Narrative, Facts)

### After Both (Full Curate)

When curating to both Cipher and context tree:

1. Run Cipher verification (above)
2. Run context tree verification (above)
3. **Cross-Check:** Run a `cipher_memory_search` query and manually confirm it returns content consistent with the context tree file

## Verification Checklist

Use this after every curate or store operation:

- [ ] `cipher_memory_search` with title keywords returns the entry in top 5
- [ ] `cipher_memory_search` with a natural-language question returns the entry in top 5
- [ ] Context tree file exists at the expected path
- [ ] Context tree file has valid YAML frontmatter
- [ ] `_manifest.json` includes the entry with correct path and metadata
- [ ] Importance score is set appropriately (50 for new, higher for updates)
- [ ] Maturity is set correctly (draft for new entries)

## Common Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| Store succeeds but search finds nothing | Content too short for meaningful embedding | Add more context — at least 3-4 sentences |
| Search finds it with exact title but not natural language | Keywords/tags too specific | Add broader tags and synonyms |
| Context tree file exists but not in manifest | Manifest update was skipped | Manually add entry to `_manifest.json` |
| Cipher returns stale version after update | Embedding not regenerated | Delete old entry, store as new |
| Search returns too many irrelevant results | Tags/keywords too generic | Make tags more specific, add discriminating keywords |

## Minimum Verification Standard

For a memory operation to be considered successful, ALL of these must be true:

1. **Retrievable:** At least one search query returns the entry in top 5 results
2. **Accurate:** The retrieved content matches what was stored (not a stale version)
3. **Discoverable:** A reasonable natural-language question about the topic finds it
4. **Indexed:** The entry appears in the context tree `_manifest.json`

If any of these fail, the memory operation is NOT complete. Fix it before proceeding.
