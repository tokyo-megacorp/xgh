---
name: xgh:knowledge-handoff
description: "This skill should be used when the user runs /xgh-knowledge-handoff, merges a branch, or asks to 'create handoff', 'document this merge', 'leave context for the next dev'. Generates a structured handoff summary on branch merge so the next developer gets full context — patterns, gotchas, key files, warnings — without meetings."
---

# xgh:knowledge-handoff — Knowledge Handoff

> On branch merge, generate a structured handoff summary so the next developer touching that area gets full context — patterns, gotchas, key files, warnings — without meetings.

## Iron Law

> **EVERY MERGE MUST LEAVE A TRAIL.** When your work merges, the next person touching those files deserves your hard-won context. No handoff = knowledge lost forever.

## Rationalization Table

| Agent Thought | Reality |
|---|---|
| "The code is clean enough to speak for itself" | Clean code shows current state, not the gotchas discovered getting there |
| "Nobody else will touch this area soon" | You don't know that. And when they do, you won't remember the details |
| "The PR description covers it" | PR descriptions describe one change; handoffs describe the territory |
| "This is just a refactor, nothing to hand off" | Refactors are the most important to document — they change the map |
| "Generating a handoff summary takes too long" | 60 seconds now prevents 2 hours of archaeology later |

## Trigger

This skill activates when:
1. A branch is merged to the main/default branch
2. The merged changes touch files in a recognized domain area
3. The session-end hook fires after merge-related work

The hook detects merge context via:
- `git log --merges` showing recent merge commits
- Branch deletion after merge
- PR merge event (if working with GitHub/GitLab)

---

## Handoff Summary Structure

The handoff summary follows a fixed structure optimized for the next developer's Claude to consume:

```yaml
---
title: "Handoff: [area/feature name]"
tags: [handoff, area-tag-1, area-tag-2]
keywords: [specific-terms, file-names, function-names]
importance: 75
maturity: validated
type: handoff
scope: handoff
source: auto-curate
fromAgent: claude-code
createdAt: [ISO timestamp]
mergedBranch: [branch-name]
affectedFiles: [list of key files]
---
```

### Content Sections

```markdown
## What Changed
[1-3 sentence summary of the merged work]

## Patterns Discovered
- [Pattern 1]: [description + where it applies]
- [Pattern 2]: [description + where it applies]
(Patterns the next developer should follow when extending this area)

## Gotchas and Warnings
- [Gotcha 1]: [what seems obvious but isn't, and why]
- [Gotcha 2]: [edge case that bit you, and how to avoid it]
(Things that will waste the next developer's time if not known)

## Key Files
- `[path/to/file.ts]` — [role: what this file does and why it matters]
- `[path/to/other.ts]` — [role: entry point / config / critical path]
(The files the next developer should read first)

## Architecture Decisions
- [Decision]: [what was decided + rationale]
- [Decision]: [what was decided + rationale]
(Decisions that constrain future work in this area)

## Testing Notes
- [What's tested and how]
- [What's NOT tested and why]
- [How to run relevant tests]

## Open Questions
- [Question the next developer might face]
- [Known limitation that needs future work]
```

---

## Process

### Step 1: Gather merge context

When merge is detected:

```
Tool: lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })
Query: "[branch-name] decisions patterns implementation"
```

Also gather from the PR context bridge thread (if available):

```
Tool: lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })
Query: "thread:PR-[branch-name] context summary"
```

### Step 2: Analyze affected files

Identify which domain areas were touched by the merge. Use git diff to find:
- Files changed
- Directories affected
- Modules/domains impacted

**Categorize files by type and risk:**

| File pattern | Category | Risk level |
|---|---|---|
| `**/auth/**`, `**/security/**` | Security | High |
| `**/api/**`, `**/routes/**` | API surface | High |
| `**/migration/**`, `**/*.sql` | Data | High |
| `**/config/**`, `*.yaml`, `*.json` | Config | Medium |
| `src/**/*.ts`, `lib/**/*.py` | Core logic | Medium |
| `**/*.test.*`, `**/*.spec.*` | Tests | Low |
| `**/docs/**`, `*.md` | Docs | Low |

**Assess impact breadth:**
- 1-3 files changed: narrow, low coordination overhead
- 4-10 files changed: moderate, check for cross-module coupling
- 10+ files changed: broad refactor — explicitly call out in handoff summary

**Identify coupling risks:**
Run `git diff --name-only HEAD~1` and look for files in different modules that changed together — this often signals hidden coupling the next developer should know about.

**Example output format:**
```
Affected: 7 files
High risk: src/auth/token-refresh.ts (auth), migrations/004_add_session_index.sql (data)
Medium risk: src/api/users.ts, config/rate-limits.yaml
Low risk: tests/auth.test.ts, docs/auth.md
Coupling signal: token-refresh.ts + rate-limits.yaml changed together — rate limit is tied to token lifetime
```

### Step 3: Extract learnings from session

```
Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store.
Use tags: ["workspace"]
Context: "Merge of [branch-name]. Extract patterns, gotchas, key files, architecture decisions, and warnings for the next developer."
```

### Step 4: Generate and store handoff summary

Compile the gathered information into the handoff structure above.

```
Tool: lcm_store(text, ["workspace"])
Content: [compiled handoff summary in the structure above]
Metadata:
  type: handoff
  scope: handoff
  thread: handoff-[branch-name]
  domain: [detected domain]
  affectedFiles: [list of changed files]
  status: completed
```

### Step 5: Sync to context tree

Write the handoff to the context tree at the appropriate domain path:
```
.xgh/context-tree/[domain]/handoffs/[date]-[branch-name].md
```

### Step 6: Auto-query for next developer

When any developer's Claude touches files that were part of a recent handoff, the session-start hook queries:

```
Tool: lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })
Query: "handoff [file-path] gotchas patterns warnings"
Filter:
  type: handoff
  affectedFiles: [current file]
```

The retrieved handoff context is injected into the developer's session automatically.

---

## Tool Reference

| Tool | Usage |
|---|---|
| Extract 3-7 bullet summary → `lcm_store(text, ["workspace"])` | Extract session learnings for handoff summary generation. Do not pass raw conversation content to lcm_store. |
| `lcm_store(text, ["workspace"])` | Store the compiled handoff summary to workspace |
| `lcm_search(query, { layers: ["semantic"], tags: ["workspace"] })` | Query PR thread context; auto-query handoffs for next developer |

## Composability

- Consumes from **pr-context-bridge**: Uses PR reasoning thread as input for handoff
- Feeds into **onboarding-accelerator**: Handoff summaries are surfaced during onboarding
- Feeds into **convention-guardian**: Patterns discovered in handoffs may become conventions
