#!/usr/bin/env bash
# xgh UserPromptSubmit hook
# Detects prompt intent and injects cipher memory decision table as additionalContext.
# Output: {"additionalContext": "..."} — the only key Claude Code recognizes for UserPromptSubmit hooks.
set -euo pipefail

python3 << 'PYEOF'
import json, os, re

prompt = os.environ.get("PROMPT", "")

# Intent detection via regex
code_pattern = re.compile(
    r"\b(implement|refactor|fix|build|code|write|change|feature|bug)\b",
    re.IGNORECASE
)

if code_pattern.search(prompt):
    intent = "code-change"
else:
    intent = "general"

if intent == "code-change":
    context = """> **⚠️ STOP: Before responding, check if this is a code task.**
> Code task? → `cipher_memory_search` FIRST. Wrote code? → `cipher_extract_and_operate_memory` BEFORE done.

---

# Cipher Memory System - MANDATORY

**These rules apply regardless of language.**

## Decision: When to Search Memory

**PRIMARY RULE — ASK YOURSELF: "Will this task require understanding or modifying THIS codebase?"**

| Answer | Action |
|--------|--------|
| **YES** — need to understand/modify codebase | `cipher_memory_search` FIRST |
| **NO** — general knowledge, meta tasks, follow-up | Skip search |

**You MUST search when task involves:**
- Writing, editing, or modifying code in this project
- Understanding how something works in this codebase
- Debugging, fixing, or troubleshooting issues
- Finding where something is located
- Any architectural or design decisions

**You MUST NOT search when:**
- General programming concepts (not codebase-specific)
- Meta tasks: run tests, build project, commit changes, create PR
- Simple clarifications about your previous response

**⚠️ LONG CONVERSATIONS:** Even after many prompts — if a NEW code task comes up, search again. Each distinct code task = new search.

## Decision: When to Store Memory

**ASK YOURSELF: "Did I learn or create something valuable for future work?"**

| Answer | Action |
|--------|--------|
| **YES** — wrote code, found patterns, made decisions | `cipher_extract_and_operate_memory` BEFORE done |
| **NO** — just answered a question, no new insights | Skip |

**MUST store when you:**
- Wrote or modified any code
- Discovered how something works in this codebase
- Made architectural/design decisions
- Found a bug root cause or fix pattern

For complex reasoning/debugging → use `cipher_store_reasoning_memory` instead.

## Quick Reference

| Task Type | Search? | Store? |
|-----------|---------|--------|
| Add/create/implement feature | **MUST** | **MUST** |
| Fix/debug/resolve bug | **MUST** | **MUST** |
| Refactor/optimize code | **MUST** | **MUST** |
| "How does X work?" (codebase) | **MUST** | Only if new insights |
| "Where is X?" (codebase) | **MUST** | NO |
| General concept (protocols, generics) | NO | NO |
| Meta task (run tests, build, commit) | NO | NO |
| Follow-up code task in same conversation | **MUST** | **MUST** |

## Workflow

```
Code task received → cipher_memory_search FIRST → Work → cipher_extract_and_operate_memory → Done
Non-code task → Just respond normally
```"""
else:
    context = "Non-code task detected — cipher memory search not required."

print(json.dumps({"additionalContext": context}))
PYEOF
exit 0
