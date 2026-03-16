# Hooks & Core Skills Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace the placeholder hooks with real implementations that inject context-tree knowledge and decision tables, and create the six core skills plus three slash commands that form xgh's self-learning loop.

**Architecture:** Hooks are bash scripts that read the context tree's `_manifest.json`, select relevant knowledge files, and output JSON (`{"result": "..."}`) for Claude Code's hook system. Skills are markdown files with YAML frontmatter following Claude Code's skill format (one directory per skill containing a markdown file). Commands are standalone markdown files in `commands/` that define slash-command behavior.

**Tech Stack:** Bash (hooks, tests), Markdown + YAML frontmatter (skills, commands), JSON (hook output), jq (JSON processing in hooks)

**Design doc:** `docs/plans/2026-03-13-xgh-design.md` -- Sections 4, 6, 7

---

## File Structure

```
xgh/
├── hooks/
│   ├── session-start.sh               # Real implementation (replaces placeholder)
│   └── prompt-submit.sh               # Real implementation (replaces placeholder)
├── skills/
│   ├── continuous-learning/
│   │   └── continuous-learning.md      # Iron law enforcement skill
│   ├── curate-knowledge/
│   │   └── curate-knowledge.md         # Knowledge curation guidance
│   ├── query-strategies/
│   │   └── query-strategies.md         # Tiered query routing
│   ├── context-tree-maintenance/
│   │   └── context-tree-maintenance.md # Scoring, maturity, archival
│   └── memory-verification/
│       └── memory-verification.md      # Verify store/retrieve correctness
├── commands/
│   ├── query.md                        # /xgh-query slash command
│   ├── curate.md                       # /xgh-curate slash command
│   └── status.md                       # /xgh-status slash command
└── tests/
    ├── test-hooks.sh                   # Hook output validation
    ├── test-skills.sh                  # Skill file structure validation
    └── test-commands.sh                # Command file structure validation
```

---

## Chunk 1: Hooks

### Task 1: SessionStart hook — real implementation

**Files:**
- Modify: `hooks/session-start.sh`
- Create: `tests/test-hooks.sh`

The SessionStart hook must:
1. Locate the context tree `_manifest.json` (searching `.xgh/context-tree/` relative to the repo root)
2. Find core-maturity knowledge files (maturity: core or validated, sorted by importance)
3. Read the top-5 most important files and extract their content
4. Output a single JSON object: `{"result": "...injected context..."}`
5. If no context tree exists, output a graceful fallback message

- [x] **Step 1: Write test for hooks**

Create `tests/test-hooks.sh` with assertions for both hooks:

```bash
cat > tests/test-hooks.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_eq() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' ($3)"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output does not contain '$2' ($3)"; FAIL=$((FAIL+1)); fi; }
assert_valid_json() { if echo "$1" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: invalid JSON ($2)"; FAIL=$((FAIL+1)); fi; }
assert_json_has_result() { if echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'result' in d" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: JSON missing 'result' key ($2)"; FAIL=$((FAIL+1)); fi; }

# --- SessionStart hook tests ---

# Test 1: Hook is executable
if [ -x "hooks/session-start.sh" ]; then PASS=$((PASS+1)); else echo "FAIL: session-start.sh not executable"; FAIL=$((FAIL+1)); fi

# Test 2: Hook outputs valid JSON (no context tree)
TMPDIR_TEST=$(mktemp -d)
OUT=$(XGH_CONTEXT_TREE_PATH="${TMPDIR_TEST}/nonexistent" bash hooks/session-start.sh 2>/dev/null || true)
assert_valid_json "$OUT" "session-start outputs valid JSON without context tree"
assert_json_has_result "$OUT" "session-start has result key without context tree"

# Test 3: Hook outputs valid JSON (with empty context tree)
EMPTY_TREE="${TMPDIR_TEST}/empty-tree"
mkdir -p "$EMPTY_TREE"
cat > "${EMPTY_TREE}/_manifest.json" << 'MANIFEST'
{"version":1,"team":"test-team","created":"2026-01-01T00:00:00Z","domains":[]}
MANIFEST
OUT=$(XGH_CONTEXT_TREE_PATH="$EMPTY_TREE" bash hooks/session-start.sh 2>/dev/null || true)
assert_valid_json "$OUT" "session-start outputs valid JSON with empty tree"
assert_json_has_result "$OUT" "session-start has result key with empty tree"
assert_contains "$OUT" "test-team" "session-start includes team name"

# Test 4: Hook picks up core-maturity files
RICH_TREE="${TMPDIR_TEST}/rich-tree"
mkdir -p "$RICH_TREE/api-design"
cat > "$RICH_TREE/_manifest.json" << 'MANIFEST'
{
  "version": 1,
  "team": "alpha-team",
  "created": "2026-01-01T00:00:00Z",
  "domains": [
    {
      "name": "api-design",
      "path": "api-design",
      "topics": [
        {
          "name": "rest-conventions",
          "path": "api-design/rest-conventions.md",
          "importance": 90,
          "maturity": "core"
        },
        {
          "name": "graphql-patterns",
          "path": "api-design/graphql-patterns.md",
          "importance": 40,
          "maturity": "draft"
        }
      ]
    }
  ]
}
MANIFEST
cat > "$RICH_TREE/api-design/rest-conventions.md" << 'MDFILE'
---
title: REST Conventions
importance: 90
maturity: core
tags: [api, rest]
---
## Raw Concept
Always use kebab-case for URL paths. Use plural nouns for collections.
MDFILE
cat > "$RICH_TREE/api-design/graphql-patterns.md" << 'MDFILE'
---
title: GraphQL Patterns
importance: 40
maturity: draft
tags: [api, graphql]
---
## Raw Concept
Use DataLoader for N+1 prevention.
MDFILE

OUT=$(XGH_CONTEXT_TREE_PATH="$RICH_TREE" bash hooks/session-start.sh 2>/dev/null || true)
assert_valid_json "$OUT" "session-start valid JSON with rich tree"
assert_contains "$OUT" "REST Conventions" "session-start includes core file title"
assert_contains "$OUT" "kebab-case" "session-start includes core file content"

# Test 5: Hook does NOT include draft files when core files exist
# (draft files are only included if we have fewer than 5 core/validated)
# The graphql-patterns is draft (importance 40), should NOT appear if we have enough core

# --- UserPromptSubmit hook tests ---

# Test 6: Hook is executable
if [ -x "hooks/prompt-submit.sh" ]; then PASS=$((PASS+1)); else echo "FAIL: prompt-submit.sh not executable"; FAIL=$((FAIL+1)); fi

# Test 7: Hook outputs valid JSON
OUT=$(bash hooks/prompt-submit.sh 2>/dev/null || true)
assert_valid_json "$OUT" "prompt-submit outputs valid JSON"
assert_json_has_result "$OUT" "prompt-submit has result key"

# Test 8: Hook output contains decision table keywords
assert_contains "$OUT" "cipher_memory_search" "prompt-submit mentions memory search"
assert_contains "$OUT" "cipher_extract_and_operate_memory" "prompt-submit mentions extract memory"
assert_contains "$OUT" "context tree" "prompt-submit mentions context tree"

# Cleanup
rm -rf "$TMPDIR_TEST"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
TESTEOF
chmod +x tests/test-hooks.sh
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd /path/to/xgh && bash tests/test-hooks.sh
# Expected: multiple FAILs because hooks are still placeholders
```

- [x] **Step 3: Implement session-start.sh**

Replace `hooks/session-start.sh` with the full implementation:

```bash
cat > hooks/session-start.sh << 'HOOKEOF'
#!/usr/bin/env bash
# xgh SessionStart hook
# Loads context tree, injects top core/validated knowledge files into the session.
# Output: JSON {"result": "...context to inject..."}
set -euo pipefail

# ── Configuration ──────────────────────────────────────────
# XGH_CONTEXT_TREE_PATH can be set by the installer or env; defaults to repo-relative path.
# The hook searches: env var > .xgh/context-tree > fallback message.
CONTEXT_TREE="${XGH_CONTEXT_TREE_PATH:-}"
MAX_FILES=5

# If not set via env, try to find it relative to the repo root
if [ -z "$CONTEXT_TREE" ]; then
  # Walk up to find .xgh/context-tree (handles being called from .claude/hooks/)
  SEARCH_DIR="$(pwd)"
  while [ "$SEARCH_DIR" != "/" ]; do
    if [ -d "${SEARCH_DIR}/.xgh/context-tree" ]; then
      CONTEXT_TREE="${SEARCH_DIR}/.xgh/context-tree"
      break
    fi
    SEARCH_DIR="$(dirname "$SEARCH_DIR")"
  done
fi

# ── Helper: escape string for JSON ────────────────────────
json_escape() {
  python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps(text), end='')
" 2>/dev/null || {
    # Fallback: basic escaping if python3 unavailable
    sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
  }
}

# ── No context tree found ─────────────────────────────────
if [ -z "$CONTEXT_TREE" ] || [ ! -d "$CONTEXT_TREE" ]; then
  RESULT="[xgh] No context tree found. Run /xgh-curate to start building team knowledge, or run the xgh installer to initialize the context tree."
  echo "{\"result\": $(echo "$RESULT" | json_escape)}"
  exit 0
fi

MANIFEST="${CONTEXT_TREE}/_manifest.json"

if [ ! -f "$MANIFEST" ]; then
  RESULT="[xgh] Context tree exists at ${CONTEXT_TREE} but _manifest.json is missing. Run /xgh-status to diagnose."
  echo "{\"result\": $(echo "$RESULT" | json_escape)}"
  exit 0
fi

# ── Parse manifest and collect top knowledge files ─────────
# Uses python3 for reliable JSON parsing (available on macOS, most Linux)
CONTEXT_BLOCK=$(python3 << PYEOF
import json, os, sys

manifest_path = "${MANIFEST}"
context_tree = "${CONTEXT_TREE}"
max_files = ${MAX_FILES}

try:
    with open(manifest_path) as f:
        manifest = json.load(f)
except Exception as e:
    print(f"[xgh] Error reading manifest: {e}")
    sys.exit(0)

team = manifest.get("team", "unknown")

# Collect all topics with their metadata
entries = []
for domain in manifest.get("domains", []):
    for topic in domain.get("topics", []):
        maturity = topic.get("maturity", "draft")
        importance = topic.get("importance", 0)
        path = topic.get("path", "")
        name = topic.get("name", "")
        # Only consider core and validated files
        if maturity in ("core", "validated"):
            entries.append({
                "name": name,
                "path": path,
                "importance": importance,
                "maturity": maturity,
            })

# Sort by importance descending, core before validated at same importance
entries.sort(key=lambda e: (0 if e["maturity"] == "core" else 1, -e["importance"]))

# If we have fewer than max_files core/validated, fill with top draft files
if len(entries) < max_files:
    draft_entries = []
    for domain in manifest.get("domains", []):
        for topic in domain.get("topics", []):
            if topic.get("maturity", "draft") == "draft":
                draft_entries.append({
                    "name": topic.get("name", ""),
                    "path": topic.get("path", ""),
                    "importance": topic.get("importance", 0),
                    "maturity": "draft",
                })
    draft_entries.sort(key=lambda e: -e["importance"])
    entries.extend(draft_entries[:max_files - len(entries)])

# Take top N
top_entries = entries[:max_files]

# Build context block
lines = []
lines.append(f"[xgh] Team: {team} | Context tree loaded with {len(entries)} relevant entries.")
lines.append("")

if not top_entries:
    lines.append("No knowledge files found yet. Use /xgh-curate to start building team memory.")
else:
    lines.append("== Top Knowledge (auto-injected) ==")
    lines.append("")
    for entry in top_entries:
        filepath = os.path.join(context_tree, entry["path"])
        lines.append(f"--- {entry['name']} [{entry['maturity']}, importance:{entry['importance']}] ---")
        if os.path.isfile(filepath):
            try:
                with open(filepath) as f:
                    content = f.read().strip()
                # Strip YAML frontmatter for cleaner injection
                if content.startswith("---"):
                    parts = content.split("---", 2)
                    if len(parts) >= 3:
                        content = parts[2].strip()
                lines.append(content)
            except Exception:
                lines.append(f"(could not read {entry['path']})")
        else:
            lines.append(f"(file not found: {entry['path']})")
        lines.append("")

lines.append("== End xgh Context ==")

print("\n".join(lines))
PYEOF
)

# ── Output JSON ────────────────────────────────────────────
echo "{\"result\": $(echo "$CONTEXT_BLOCK" | json_escape)}"
exit 0
HOOKEOF
chmod +x hooks/session-start.sh
```

- [x] **Step 4: Run test to verify session-start passes**

```bash
cd /path/to/xgh && bash tests/test-hooks.sh
# Expected: session-start tests pass, prompt-submit tests still fail
```

### Task 2: UserPromptSubmit hook — decision table injection

**Files:**
- Modify: `hooks/prompt-submit.sh`
- Test: `tests/test-hooks.sh` (already has tests from Task 1)

- [x] **Step 1: Implement prompt-submit.sh**

Replace `hooks/prompt-submit.sh` with the full implementation:

```bash
cat > hooks/prompt-submit.sh << 'HOOKEOF'
#!/usr/bin/env bash
# xgh UserPromptSubmit hook
# Injects the xgh decision table on every user prompt.
# This reminds the agent to query memory before coding and curate after.
# Output: JSON {"result": "...decision table..."}
set -euo pipefail

# ── Helper: escape string for JSON ────────────────────────
json_escape() {
  python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps(text), end='')
" 2>/dev/null || {
    sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
  }
}

# ── Decision Table ─────────────────────────────────────────
DECISION_TABLE='[xgh Decision Table]

Before writing or modifying code:
  -> cipher_memory_search for prior knowledge, conventions, related decisions
  -> Check context tree for team patterns

After writing or modifying code:
  -> cipher_extract_and_operate_memory to capture what you learned
  -> Sync new patterns to context tree via /xgh-curate

After making an architectural or design decision:
  -> Curate: decision + rationale + alternatives considered
  -> Use cipher_store_reasoning_memory for the reasoning chain

After fixing a bug:
  -> Curate: root cause + fix + trigger conditions
  -> Search memory first — this bug may have been seen before

When reviewing a PR or code:
  -> Query context tree for related past decisions
  -> Curate any new patterns discovered during review

When ending a session:
  -> Ensure all significant learnings are curated
  -> Run /xgh-status to verify memory health

IRON LAW: Every coding session MUST query memory before writing code AND curate learnings before ending.'

# ── Output JSON ────────────────────────────────────────────
echo "{\"result\": $(echo "$DECISION_TABLE" | json_escape)}"
exit 0
HOOKEOF
chmod +x hooks/prompt-submit.sh
```

- [x] **Step 2: Run full hook tests to verify all pass**

```bash
cd /path/to/xgh && bash tests/test-hooks.sh
# Expected: all tests pass
# Results: N passed, 0 failed
```

- [x] **Step 3: Commit hooks**

```bash
git add hooks/session-start.sh hooks/prompt-submit.sh tests/test-hooks.sh
git commit -m "feat: implement SessionStart and UserPromptSubmit hooks

SessionStart loads context tree _manifest.json, selects top-5
core/validated knowledge files by importance, and injects their
content as session context. Falls back gracefully when no tree exists.

UserPromptSubmit injects the xgh decision table on every prompt,
reminding the agent to query before coding and curate after.

Both hooks output valid JSON for Claude Code's hook system."
```

---

## Chunk 2: Core Skills (continuous-learning, curate-knowledge, query-strategies)

### Task 3: continuous-learning skill

**Files:**
- Create: `skills/continuous-learning/continuous-learning.md`
- Create: `tests/test-skills.sh`

This is the RIGID iron-law skill. It enforces: "EVERY CODING SESSION MUST QUERY MEMORY BEFORE WRITING CODE AND CURATE LEARNINGS BEFORE ENDING."

- [x] **Step 1: Write test for skills**

```bash
cat > tests/test-skills.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_dir_exists() { if [ -d "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }
assert_frontmatter() {
  # Check file starts with --- and has a closing ---
  if head -1 "$1" | grep -q "^---" && awk 'NR>1' "$1" | grep -q "^---"; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 missing YAML frontmatter"
    FAIL=$((FAIL+1))
  fi
}

# --- Skill directory structure ---
SKILLS=(continuous-learning curate-knowledge query-strategies context-tree-maintenance memory-verification)
for skill in "${SKILLS[@]}"; do
  assert_dir_exists "skills/${skill}"
  assert_file_exists "skills/${skill}/${skill}.md"
  assert_frontmatter "skills/${skill}/${skill}.md"
done

# --- continuous-learning skill ---
CL="skills/continuous-learning/continuous-learning.md"
assert_contains "$CL" "name: continuous-learning"
assert_contains "$CL" "IRON LAW"
assert_contains "$CL" "cipher_memory_search"
assert_contains "$CL" "cipher_extract_and_operate_memory"
assert_contains "$CL" "Rationalization Table"
assert_contains "$CL" "Simple change"

# --- curate-knowledge skill ---
CK="skills/curate-knowledge/curate-knowledge.md"
assert_contains "$CK" "name: curate-knowledge"
assert_contains "$CK" "domain"
assert_contains "$CK" "frontmatter"
assert_contains "$CK" "tags"
assert_contains "$CK" "importance"
assert_contains "$CK" "maturity"

# --- query-strategies skill ---
QS="skills/query-strategies/query-strategies.md"
assert_contains "$QS" "name: query-strategies"
assert_contains "$QS" "cipher_memory_search"
assert_contains "$QS" "BM25"
assert_contains "$QS" "semantic"
assert_contains "$QS" "refinement"

# --- context-tree-maintenance skill ---
CT="skills/context-tree-maintenance/context-tree-maintenance.md"
assert_contains "$CT" "name: context-tree-maintenance"
assert_contains "$CT" "importance"
assert_contains "$CT" "maturity"
assert_contains "$CT" "archive"
assert_contains "$CT" "draft"
assert_contains "$CT" "validated"
assert_contains "$CT" "core"

# --- memory-verification skill ---
MV="skills/memory-verification/memory-verification.md"
assert_contains "$MV" "name: memory-verification"
assert_contains "$MV" "verify"
assert_contains "$MV" "cipher_memory_search"
assert_contains "$MV" "retrieve"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
TESTEOF
chmod +x tests/test-skills.sh
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd /path/to/xgh && bash tests/test-skills.sh
# Expected: all FAILs (no skill files exist yet)
```

- [x] **Step 3: Create continuous-learning skill**

```bash
mkdir -p skills/continuous-learning
```

Write `skills/continuous-learning/continuous-learning.md`:

```markdown
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
| "This is a simple change, no need to check memory" | Simple changes cause the most repeated mistakes. A 2-second query could reveal a team convention you are about to violate. | Query anyway. It takes 2 seconds. |
| "I already know the conventions from my training data" | Your training data is NOT this team's conventions. Teams have specific, evolving patterns that exist only in their memory. | Query. Your training data is generic; team memory is specific. |
| "Curating this would slow me down" | 30 seconds of curation now saves 30 minutes in the next session that encounters the same problem. | Curate. The next session (which might be you) will thank you. |
| "This learning is too specific to store" | Specific learnings are the MOST valuable. Generic knowledge is already in training data. Team-specific edge cases are gold. | Curate it. Specificity is value. |
| "Memory search returned nothing relevant" | Your query may have been too broad or too narrow. Try at least 2 different formulations before concluding nothing exists. | Refine query. Try synonyms, broader terms, or related concepts. |
| "I will curate at the end of the session" | Sessions end abruptly. Context is lost. Curate as you go — do not batch. | Curate NOW, after each significant action. |
| "This is just a refactor, nothing new to learn" | Refactors reveal system structure. The patterns you discover during refactoring are exactly what future sessions need. | Curate the structural insights you gained. |

## Hard Gates

These are binary pass/fail checkpoints. If any gate fails, the session is non-compliant.

- [x] **Gate 1:** At least one `cipher_memory_search` call was made before the first code change
- [x] **Gate 2:** At least one `cipher_extract_and_operate_memory` or `/xgh-curate` call was made during or after code changes
- [x] **Gate 3:** Any architectural decision has a corresponding `cipher_store_reasoning_memory` call
- [x] **Gate 4:** Session-end curation was performed (not deferred)

## Verification

After curating, always verify:
1. Run `cipher_memory_search` with keywords from what you just stored
2. Confirm the result appears in the search results
3. If it does not appear, re-curate with better keywords/tags
```

- [x] **Step 4: Run test to check continuous-learning passes**

```bash
cd /path/to/xgh && bash tests/test-skills.sh
# Expected: continuous-learning tests pass, other skills still fail
```

### Task 4: curate-knowledge skill

**Files:**
- Create: `skills/curate-knowledge/curate-knowledge.md`

- [x] **Step 1: Create curate-knowledge skill**

```bash
mkdir -p skills/curate-knowledge
```

Write `skills/curate-knowledge/curate-knowledge.md`:

```markdown
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

- [x] Title is clear and searchable (would YOU find this by searching?)
- [x] Tags include category + technology + domain + abstract concept
- [x] Keywords include specific searchable terms
- [x] Raw Concept has enough detail to reproduce/understand technically
- [x] Narrative explains WHY, not just WHAT
- [x] Facts are one-sentence, factual, categorized
- [x] File is in the correct domain/topic path
- [x] Manifest is updated
- [x] Cipher memory is updated (via cipher_extract_and_operate_memory)
- [x] Verification: `cipher_memory_search` finds the new entry
```

- [x] **Step 2: Run test to check curate-knowledge passes**

```bash
cd /path/to/xgh && bash tests/test-skills.sh
# Expected: continuous-learning + curate-knowledge pass, others still fail
```

### Task 5: query-strategies skill

**Files:**
- Create: `skills/query-strategies/query-strategies.md`

- [x] **Step 1: Create query-strategies skill**

```bash
mkdir -p skills/query-strategies
```

Write `skills/query-strategies/query-strategies.md`:

```markdown
---
name: query-strategies
description: "Tiered query routing: when to use Cipher semantic search vs context tree BM25 vs both. Query refinement patterns for maximum recall."
type: flexible
triggers:
  - before-code-write
  - before-decision
  - manual-query
---

# xgh:query-strategies

## Purpose

Not all queries are equal. A broad "how do we handle auth?" needs different routing than a specific "what is the JWT refresh token rotation interval?". This skill teaches tiered query routing for maximum recall.

## Query Tiers

### Tier 1: Broad Context (use BOTH engines)

**When:** Starting a new task, exploring a domain, or unsure what exists.

**Strategy:**
1. `cipher_memory_search` with a natural-language description of the task
2. Read context tree `_index.md` files for the relevant domain
3. Merge results mentally — Cipher catches semantic matches, context tree catches keyword matches

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
3. Fall back to `cipher_memory_search` only if the context tree does not have it

**Example queries:**
- "JWT refresh token rotation interval"
- "PostgreSQL connection pool max size"
- "REST API error response format"

**Expected:** One or two highly relevant results. The context tree's structured hierarchy makes this fast.

### Tier 3: Reasoning Patterns (use Cipher reasoning tools)

**When:** Making a decision and wanting to learn from past decisions.

**Strategy:**
1. `cipher_search_reasoning_patterns` with the decision context
2. `cipher_evaluate_reasoning` to check your current reasoning against stored patterns
3. Check context tree for files with category: decision in the relevant domain

**Example queries:**
- "Choosing between REST and GraphQL for the new API"
- "Database migration strategy for adding a new column"
- "Error handling approach for third-party API calls"

**Expected:** Reasoning chains with outcomes — learn from what worked and what did not.

### Tier 4: Debugging/Bug Investigation (use Cipher semantic search FIRST)

**When:** Encountering an error or unexpected behavior.

**Strategy:**
1. `cipher_memory_search` with the error message or symptom description
2. Search context tree for files with category: bug-fix
3. If nothing found, broaden the search to the general area (e.g., "authentication errors" instead of "401 on /api/refresh")

**Example queries:**
- "ECONNREFUSED on Qdrant connection"
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

When results come from both engines, xgh ranks them:

```
score = (0.5 * cipher_similarity + 0.3 * bm25_score + 0.1 * importance + 0.1 * recency) * maturityBoost
```

- `cipher_similarity`: 0-1, vector cosine similarity from Cipher
- `bm25_score`: 0-1, keyword match score from context tree
- `importance`: 0-100 normalized to 0-1
- `recency`: 0-1, exponential decay with ~21-day half-life
- `maturityBoost`: core = 1.15, validated = 1.0, draft = 0.9

## When to Stop Searching

Search is complete when ANY of these are true:
1. You found a core/validated file that directly answers your question
2. You ran 3+ different query formulations and found nothing (document this!)
3. You found related knowledge that gives enough context to proceed
4. The context tree has no entries in the relevant domain (it is truly new territory)

**Never skip the search.** Even "nothing found" is valuable information — it means you are about to create new team knowledge.
```

- [x] **Step 2: Run test to check query-strategies passes**

```bash
cd /path/to/xgh && bash tests/test-skills.sh
# Expected: 3 skills pass, 2 still fail
```

- [x] **Step 3: Commit first three skills**

```bash
git add skills/continuous-learning/ skills/curate-knowledge/ skills/query-strategies/ tests/test-skills.sh
git commit -m "feat: add continuous-learning, curate-knowledge, and query-strategies skills

continuous-learning: RIGID skill enforcing the iron law — query before
coding, curate before ending. Includes rationalization table and hard gates.

curate-knowledge: Guides structured knowledge curation with domain/topic
classification, frontmatter construction, and quality checklist.

query-strategies: Tiered query routing (broad context, specific lookup,
reasoning patterns, debugging) with refinement patterns and scoring formula."
```

---

## Chunk 3: Core Skills (context-tree-maintenance, memory-verification)

### Task 6: context-tree-maintenance skill

**Files:**
- Create: `skills/context-tree-maintenance/context-tree-maintenance.md`

- [x] **Step 1: Create context-tree-maintenance skill**

```bash
mkdir -p skills/context-tree-maintenance
```

Write `skills/context-tree-maintenance/context-tree-maintenance.md`:

```markdown
---
name: context-tree-maintenance
description: "Scoring updates, maturity promotion/demotion, archival triggers. Periodic maintenance of the context tree to keep knowledge fresh and relevant."
type: rigid
triggers:
  - periodic
  - after-curate
  - manual-maintenance
---

# xgh:context-tree-maintenance

## Purpose

The context tree is a living knowledge base. Without maintenance, it degrades: importance scores stagnate, obsolete knowledge stays at core maturity, and the tree fills with stale drafts. This skill defines the exact rules for keeping the context tree healthy.

## Scoring Rules

### Importance Score (0-100)

Importance increases when knowledge is useful and decreases via natural decay.

| Event | Importance Change |
|---|---|
| Search hit (file appeared in query results) | +3 |
| Knowledge update (file content was modified) | +5 |
| Manual curate (human or agent explicitly curated) | +10 |
| Referenced in a decision (cited in reasoning memory) | +7 |
| Time decay | Exponential, ~21-day half-life |

**Calculation:**

```
importance = base_importance * recency_factor

recency_factor = exp(-0.693 * days_since_last_access / 21)
```

Where `base_importance` is the raw score from events, and `recency_factor` applies time decay.

**Bounds:** importance is clamped to [0, 100].

### Recency Score (0-1)

Recency decays automatically and resets on access:

```
recency = exp(-0.693 * days_since_last_update / 21)
```

- On update: recency resets to 1.0
- After 21 days: recency = 0.5
- After 42 days: recency = 0.25
- After 63 days: recency = 0.125

## Maturity Lifecycle

```
draft  ──────────>  validated  ──────────>  core
       importance>=65          importance>=85

core   ──────────>  validated  ──────────>  draft
       importance<50           importance<30
       (hysteresis:-35)        (hysteresis:-35)
```

### Promotion Rules

| Transition | Condition |
|---|---|
| draft -> validated | importance >= 65 AND at least 2 updates |
| validated -> core | importance >= 85 AND at least 5 search hits AND at least 1 manual review |

### Demotion Rules (with hysteresis)

Hysteresis prevents oscillation — demotion thresholds are lower than promotion thresholds.

| Transition | Condition |
|---|---|
| core -> validated | importance < 50 (i.e., 85 - 35 = 50) |
| validated -> draft | importance < 30 (i.e., 65 - 35 = 30) |

### Maturity Boost in Search

| Maturity | Search Score Multiplier |
|---|---|
| core | 1.15x |
| validated | 1.00x |
| draft | 0.90x |

## Archival

Draft files with low importance are archived to keep the active tree lean.

### Archive Trigger

A draft file is archived when:
- `importance < 35` AND `recency < 0.25` (roughly 42+ days without access)
- OR manually flagged for archival

### Archive Process

1. Create `_archived/{domain}/{topic}/{filename}.stub.md` — a searchable ghost with:
   - Original frontmatter (preserved)
   - First 3 lines of the Narrative section
   - A pointer: `Full content: _archived/{path}.full.md`

2. Create `_archived/{domain}/{topic}/{filename}.full.md` — lossless backup:
   - Complete original file content
   - Additional frontmatter: `archivedAt`, `archiveReason`

3. Remove the original file from the active tree

4. Update `_manifest.json`: set `archived: true` on the entry

### Unarchive

To restore an archived file:
1. Copy `.full.md` back to the original path
2. Update frontmatter: reset `importance` to 50, `recency` to 1.0, `maturity` to draft
3. Remove the `.stub.md` and `.full.md` from `_archived/`
4. Update `_manifest.json`: remove `archived: true`

## Maintenance Procedure

Run this periodically (suggested: every 5-10 sessions, or weekly).

### Step 1: Update Scores

For each entry in `_manifest.json`:
1. Calculate current `recency` based on `updatedAt`
2. Apply recency decay to importance: `effective_importance = importance * recency`
3. Update the entry's `importance` and `recency` in frontmatter

### Step 2: Apply Maturity Transitions

For each entry:
1. Check if it qualifies for promotion (draft->validated, validated->core)
2. Check if it qualifies for demotion (core->validated, validated->draft)
3. Update `maturity` in frontmatter and `_manifest.json`

### Step 3: Archive Stale Drafts

For each draft entry:
1. Check if `importance < 35` AND `recency < 0.25`
2. If yes, execute the archive process

### Step 4: Rebuild Index Files

For each domain directory:
1. Regenerate `_index.md` with a compressed summary of all active entries
2. Update `_manifest.json` domain-level statistics

### Step 5: Sync with Cipher

For each modified entry:
1. Update the corresponding Cipher memory via `cipher_extract_and_operate_memory`
2. Delete Cipher memories for archived entries (or mark as archived)

## Health Metrics

Report these in `/xgh-status`:

| Metric | Healthy | Warning | Critical |
|---|---|---|---|
| Total entries | Any | - | 0 |
| Core entries | >= 3 | 1-2 | 0 |
| Average recency | > 0.5 | 0.25-0.5 | < 0.25 |
| Stale drafts (recency < 0.1) | < 20% | 20-50% | > 50% |
| Orphaned entries (in manifest but file missing) | 0 | 1-2 | > 2 |
```

- [x] **Step 2: Run test to check context-tree-maintenance passes**

```bash
cd /path/to/xgh && bash tests/test-skills.sh
# Expected: 4 skills pass, memory-verification still fails
```

### Task 7: memory-verification skill

**Files:**
- Create: `skills/memory-verification/memory-verification.md`

- [x] **Step 1: Create memory-verification skill**

```bash
mkdir -p skills/memory-verification
```

Write `skills/memory-verification/memory-verification.md`:

```markdown
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

- [x] `cipher_memory_search` with title keywords returns the entry in top 5
- [x] `cipher_memory_search` with a natural-language question returns the entry in top 5
- [x] Context tree file exists at the expected path
- [x] Context tree file has valid YAML frontmatter
- [x] `_manifest.json` includes the entry with correct path and metadata
- [x] Importance score is set appropriately (50 for new, higher for updates)
- [x] Maturity is set correctly (draft for new entries)

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
```

- [x] **Step 2: Run full skill tests to verify all pass**

```bash
cd /path/to/xgh && bash tests/test-skills.sh
# Expected: all 5 skills pass
# Results: N passed, 0 failed
```

- [x] **Step 3: Commit remaining skills**

```bash
git add skills/context-tree-maintenance/ skills/memory-verification/
git commit -m "feat: add context-tree-maintenance and memory-verification skills

context-tree-maintenance: RIGID skill for scoring updates (importance
decay, recency half-life), maturity promotion/demotion with hysteresis,
archival triggers, and periodic maintenance procedure.

memory-verification: RIGID skill enforcing evidence-before-claims —
verify every memory store operation with retrieval tests before
considering it complete."
```

---

## Chunk 4: Slash Commands

### Task 8: /xgh-query command

**Files:**
- Create: `commands/query.md`
- Create: `tests/test-commands.sh`

- [x] **Step 1: Write test for commands**

```bash
cat > tests/test-commands.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

# --- Command files exist ---
COMMANDS=(query curate status)
for cmd in "${COMMANDS[@]}"; do
  assert_file_exists "commands/${cmd}.md"
done

# --- query command ---
Q="commands/query.md"
assert_contains "$Q" "cipher_memory_search"
assert_contains "$Q" "context tree"
assert_contains "$Q" "ranked"

# --- curate command ---
C="commands/curate.md"
assert_contains "$C" "cipher_extract_and_operate_memory"
assert_contains "$C" "context tree"
assert_contains "$C" "frontmatter"
assert_contains "$C" "_manifest.json"

# --- status command ---
S="commands/status.md"
assert_contains "$S" "context tree"
assert_contains "$S" "health"
assert_contains "$S" "_manifest.json"
assert_contains "$S" "maturity"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
TESTEOF
chmod +x tests/test-commands.sh
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd /path/to/xgh && bash tests/test-commands.sh
# Expected: all FAILs (no command files exist yet)
```

- [x] **Step 3: Create /xgh-query command**

Write `commands/query.md`:

```markdown
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

Combine results from both engines using the xgh scoring formula:

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
```

- [x] **Step 4: Run test to check query command passes**

```bash
cd /path/to/xgh && bash tests/test-commands.sh
# Expected: query passes, curate and status still fail
```

### Task 9: /xgh-curate command

**Files:**
- Create: `commands/curate.md`

- [x] **Step 1: Create /xgh-curate command**

Write `commands/curate.md`:

```markdown
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
```

### Task 10: /xgh-status command

**Files:**
- Create: `commands/status.md`

- [x] **Step 1: Create /xgh-status command**

Write `commands/status.md`:

```markdown
# /xgh-status

Show xgh memory statistics, context tree health, and system status.

## Usage

```
/xgh-status
/xgh-status --detailed     # Include per-entry breakdown
```

## Instructions

When the user invokes `/xgh-status`, follow this procedure exactly:

### Step 1: Read Context Tree Manifest

1. Locate `_manifest.json` at `.xgh/context-tree/_manifest.json` (or `$XGH_CONTEXT_TREE_PATH/_manifest.json`)
2. Parse the manifest and collect statistics

If the manifest does not exist:
```
== xgh Status ==
Context tree: NOT FOUND
Run the xgh installer or /xgh-curate to initialize.
== End Status ==
```

### Step 2: Compute Health Metrics

From the manifest, calculate:

| Metric | How to Calculate |
|---|---|
| Total entries | Count all topic entries across all domains |
| By maturity | Count entries with maturity: core, validated, draft |
| Average importance | Mean of all entries' importance scores |
| Average recency | Mean of all entries' recency scores (compute from updatedAt if not in manifest) |
| Stale entries | Count entries with recency < 0.1 |
| Orphaned entries | Entries in manifest whose files do not exist on disk |
| Domains | Count unique domains |

### Step 3: Test Cipher Connectivity

1. Run a simple `cipher_memory_search` with query "xgh health check"
2. If it returns results (or returns empty without error): Cipher is connected
3. If it errors: Cipher is disconnected

### Step 4: Display Status

```
== xgh Status ==

Team: <team-name>
Context Tree: <path>

Knowledge Base:
  Total entries:     <N>
  Core:              <N> (maturity >= 85)
  Validated:         <N> (maturity >= 65)
  Draft:             <N>
  Archived:          <N>

Health:
  Avg importance:    <N>/100  [HEALTHY|WARNING|CRITICAL]
  Avg recency:       <0.XX>  [HEALTHY|WARNING|CRITICAL]
  Stale entries:     <N>/<total> (<percent>%)  [HEALTHY|WARNING|CRITICAL]
  Orphaned entries:  <N>  [HEALTHY|WARNING|CRITICAL]

Cipher MCP:
  Status:            [CONNECTED|DISCONNECTED]
  Memory count:      <N> (from cipher search)

Domains:
  <domain-1>/       <N> entries (<N> core, <N> validated, <N> draft)
  <domain-2>/       <N> entries (...)
  ...

== End Status ==
```

Health thresholds:
- **HEALTHY:** avg recency > 0.5, stale < 20%, orphaned = 0, core entries >= 3
- **WARNING:** avg recency 0.25-0.5, stale 20-50%, orphaned 1-2, core entries 1-2
- **CRITICAL:** avg recency < 0.25, stale > 50%, orphaned > 2, core entries = 0

### Step 5: Recommendations

If any metric is WARNING or CRITICAL, provide specific recommendations:

```
Recommendations:
- [WARNING] Low average recency (0.32): Consider updating stale entries or running maintenance
- [CRITICAL] No core entries: Promote your most important validated entries to core maturity
- [WARNING] 3 orphaned entries: Run context tree maintenance to clean up manifest
```

If `--detailed` flag is provided, also show a per-entry table:

```
Detailed Entries:
| Path | Maturity | Importance | Recency | Last Updated |
|---|---|---|---|---|
| api-design/rest-conventions.md | core | 92 | 0.85 | 2026-03-10 |
| auth/jwt-refresh.md | validated | 71 | 0.62 | 2026-03-05 |
| ... | ... | ... | ... | ... |
```
```

- [x] **Step 2: Run full command tests to verify all pass**

```bash
cd /path/to/xgh && bash tests/test-commands.sh
# Expected: all 3 commands pass
# Results: N passed, 0 failed
```

- [x] **Step 3: Commit commands**

```bash
git add commands/query.md commands/curate.md commands/status.md tests/test-commands.sh
git commit -m "feat: add /xgh-query, /xgh-curate, and /xgh-status slash commands

/xgh-query: searches both Cipher vectors and context tree BM25,
merges results with the xgh scoring formula, presents ranked output.

/xgh-curate: structures knowledge into domain/topic, writes to context
tree with proper frontmatter, stores in Cipher, and verifies retrieval.

/xgh-status: reports context tree health metrics (maturity distribution,
recency, stale entries, orphans) and Cipher connectivity."
```

---

## Chunk 5: Integration and Final Verification

### Task 11: Run all tests and verify integration

**Files:**
- Test: `tests/test-hooks.sh`
- Test: `tests/test-skills.sh`
- Test: `tests/test-commands.sh`
- Test: `tests/test-config.sh` (existing, should still pass)

- [x] **Step 1: Run all test suites**

```bash
cd /path/to/xgh
echo "=== Config Tests ===" && bash tests/test-config.sh
echo "=== Hook Tests ===" && bash tests/test-hooks.sh
echo "=== Skill Tests ===" && bash tests/test-skills.sh
echo "=== Command Tests ===" && bash tests/test-commands.sh
```

Expected output: all suites pass with 0 failures.

- [x] **Step 2: Verify hook JSON output manually**

```bash
# Session start with no context tree
XGH_CONTEXT_TREE_PATH=/nonexistent bash hooks/session-start.sh
# Expected: {"result": "[xgh] No context tree found..."}

# Prompt submit
bash hooks/prompt-submit.sh
# Expected: {"result": "[xgh Decision Table]...IRON LAW..."}

# Verify both are valid JSON
XGH_CONTEXT_TREE_PATH=/nonexistent bash hooks/session-start.sh | python3 -c "import sys,json; print('VALID' if 'result' in json.load(sys.stdin) else 'INVALID')"
bash hooks/prompt-submit.sh | python3 -c "import sys,json; print('VALID' if 'result' in json.load(sys.stdin) else 'INVALID')"
```

- [x] **Step 3: Verify file structure matches techpack.yaml expectations**

The `techpack.yaml` expects:
- `hooks/session-start.sh` -> installs as `xgh-session-start.sh` (checked)
- `hooks/prompt-submit.sh` -> installs as `xgh-prompt-submit.sh` (checked)
- Skills in `skills/<name>/` -> installs as `xgh-<name>/` (checked)
- Commands in `commands/<name>.md` -> installs as `xgh-<name>.md` (checked)

```bash
# Verify all expected files exist
for f in hooks/session-start.sh hooks/prompt-submit.sh; do
  [ -f "$f" ] && echo "OK: $f" || echo "MISSING: $f"
done

for s in continuous-learning curate-knowledge query-strategies context-tree-maintenance memory-verification; do
  [ -f "skills/${s}/${s}.md" ] && echo "OK: skills/${s}/${s}.md" || echo "MISSING: skills/${s}/${s}.md"
done

for c in query curate status; do
  [ -f "commands/${c}.md" ] && echo "OK: commands/${c}.md" || echo "MISSING: commands/${c}.md"
done
```

- [x] **Step 4: Final commit (if any loose changes)**

```bash
git status
# If clean: done
# If changes: stage and commit with appropriate message
```
