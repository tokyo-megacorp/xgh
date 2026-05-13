# Memory Backend Reference
# memory-backend: v3

xgh's memory layer is backend-agnostic. Skills declare *intent* (search, store, forget)
and the host agent resolves each intent to the available tool of choice, native memory,
or no-op fallback. Do not call backend-specific memory tools directly in skills — express
intent and let the current runtime choose the implementation.

This abstraction keeps skills stable as memory backends and native agent capabilities evolve.

---

## Step 1 — Detect memory availability (once per skill, before any memory operation)

1. If the host agent exposes native memory, use that.
2. Otherwise, if an MCP or CLI memory backend exposes search/store capabilities, use that.
3. Otherwise → **memory: none** — skip all memory operations; note the limitation in output.

Surface detection status alongside other integrations:
```
✓ memory — available
```
or
```
✗ memory — not configured; using local context only
```

---

## Step 2 — Resolve intent through the current runtime

Skills name an **intent**. The current agent/runtime resolves it to the available/native memory mechanism.
If no memory mechanism is available, skip the operation and continue.

Example: `[SEARCH] "past auth decisions"` means “search whichever memory system is available for past auth decisions.”

### Intent: SEARCH

Search memory for relevant context.

Required input:
- query text

Optional inputs:
- limit
- project/scope
- tags

### Intent: STORE

Persist a learning or decision. Always extract a concise summary (3–7 bullets) first —
never pass raw conversation content. Use tags when the selected memory mechanism supports
them. Common tags: `session`, `architecture`, `convention`, `reasoning`.

Required input:
- title or path/key
- concise body/summary

Optional inputs:
- tags
- project/scope
- stable identifier for future updates

### Intent: FORGET

Evict or supersede a stale/incorrect memory when the selected memory mechanism supports it.
If unsupported, log the intent in the output and continue.

Required input:
- stable identifier, path/key, or exact memory text
- reason for removal/supersession

---

## Degradation (memory: none)

- Skip every memory operation
- Do not abort the skill — continue with available context
- Emit one note: `⚠️ No memory backend — using local context only`
- Each skill documents the *impact* of missing memory in its own degradation section

---

## How to use this reference in a skill

### Detection line (add to MCP auto-detection section)

```
Detect memory availability per `_shared/references/memory-backend.md`.
```

### Intent pattern (in skill body)

```
[SEARCH] "past decisions on rate limiting"

[STORE] key learnings, tags: "session,architecture"
```

### Degradation line (in skill degradation section)

```
No memory backend → skip Steps X and Y. [Describe the impact for this skill.]
```

---

## Adding a new backend (for contributors)

1. Add detection guidance to Step 1 if the backend needs special handling.
2. Ensure skills continue to use only `[SEARCH]`, `[STORE]`, and `[FORGET]`.
3. Bump the version comment at the top.
4. Existing skills continue to work because runtimes resolve the same intent labels.
