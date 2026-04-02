# /xgh-curate

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh curate`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

Store knowledge in MAGI memory and sync to the context tree.

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

Use the `xgh:curate` skill to:

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

### Step 4: Store in MAGI

1. Extract key learnings as a concise summary (3-7 bullets), then call magi_store with the
   summary as body and context-appropriate tags. Do not pass raw conversation content to magi_store.
   Use tags: `"session"` (and add `"scope:project"` if project-specific)
2. For decisions, also call `magi_store` with tags including `"reasoning"` for the reasoning chain

### Step 5: Verify Storage

Verification is built into the curate workflow — see the Verification section of the `xgh:curate` skill.

1. Run `magi_query` with the title keywords — entry must appear in top 5
2. Run `magi_query` with a natural-language question — entry must appear in top 5
3. Verify the context tree file exists and has valid frontmatter
4. Verify `_manifest.json` is updated

### Step 6: Report

Display a summary:

```markdown
## 🐴🤖 xgh curate

Stored: **"<title>"**

| Field | Value |
|-------|-------|
| Category | <category> |
| Path | `<path>` |
| Maturity | draft |
| Tags | <tags> |

### Verification

| Check | Status |
|-------|--------|
| MAGI search (title) | ✅ rank #N / ❌ |
| MAGI search (question) | ✅ rank #N / ❌ |
| Context tree file | ✅ / ❌ |
| Manifest updated | ✅ / ❌ |
```

If any verification fails, show ❌ in the Status column and add a retry note below the table:

*❌ MAGI search (title) failed — re-curating with improved keywords...*
