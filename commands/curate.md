# /xgh-curate

Store knowledge in Cipher memory and sync to the context tree.

## Usage

```
/xgh-curate <description of knowledge to curate>
/xgh-curate -f <filepath>           # Curate from file contents
/xgh-curate -d <directory>          # Curate from directory (scans for patterns)
```

## Instructions

When the user invokes `/xgh-curate`, follow this procedure exactly:

### Step 1: Extract Knowledge

**From text argument:**
- Parse the user's description into structured knowledge
- Identify the category (convention, decision, pattern, bug-fix, discovery, constraint)
- Ask clarifying questions if the category or context is ambiguous

**From file (`-f`):**
- Read the specified file(s) (up to 5 files)
- Extract patterns, conventions, decisions, or notable implementations
- Summarize each into a curation-ready format

**From directory (`-d`):**
- Scan the directory for code patterns, README files, config files
- Identify conventions, architectural patterns, and notable decisions
- Generate curation entries for each significant finding

### Step 2: Classify and Structure

Use the `xgh:curate-knowledge` skill to:

1. **Determine category:** convention, decision, pattern, bug-fix, discovery, constraint
2. **Determine domain/topic path:** e.g., `authentication/jwt-implementation/token-refresh.md`
3. **Write frontmatter** with:
   - Clear, searchable title
   - 3-7 tags (category + technology + domain + abstract concepts)
   - 2-5 specific keywords
   - importance: 50 (new entry) or current+5 (update)
   - maturity: draft (new) or current (update)
   - timestamps

### Step 3: Write to Context Tree

1. Create the directory structure if it does not exist:
   ```bash
   mkdir -p .xgh/context-tree/<domain>/<topic>/
   ```

2. Write the knowledge file with three sections:
   - **Raw Concept:** Technical details, file paths, exact values
   - **Narrative:** Plain-language explanation with context and examples
   - **Facts:** Categorized one-sentence factual statements

3. Update `_manifest.json`:
   - Add the new entry under the appropriate domain
   - If the domain does not exist in the manifest, create it
   - Include: name, path, importance, maturity

### Step 4: Store in Cipher

1. Call `cipher_extract_and_operate_memory` with the full knowledge content
2. Include metadata: domain, topic, category, tags, keywords
3. For decisions, also call `cipher_store_reasoning_memory` with the reasoning chain

### Step 5: Verify Storage

Use the `xgh:memory-verification` skill:

1. Run `cipher_memory_search` with the title keywords — entry must appear in top 5
2. Run `cipher_memory_search` with a natural-language question — entry must appear in top 5
3. Verify the context tree file exists and has valid frontmatter
4. Verify `_manifest.json` is updated

### Step 6: Report

Display a summary:

```
== xgh Curate Complete ==

Stored: "<title>"
Category: <category>
Path: .xgh/context-tree/<domain>/<topic>/<filename>.md
Maturity: draft (new entry)
Tags: <tag1, tag2, ...>

Verification:
  Cipher search (title): PASS (rank #N)
  Cipher search (question): PASS (rank #N)
  Context tree file: PASS
  Manifest updated: PASS

== End Curate ==
```

If any verification fails:
```
Verification:
  Cipher search (title): FAIL — re-curating with improved keywords...
  [... retry details ...]
```
