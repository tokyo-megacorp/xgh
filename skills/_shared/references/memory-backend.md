# Memory Backend Reference
# memory-backend: v2

xgh's memory layer is backend-agnostic. Skills declare *intent* (search, store, forget)
and this reference resolves each intent to the concrete tool call for whichever backend
is configured. Do not call `lcm_*`, `magi_*`, or any backend-specific tool directly in skills —
express intent and let this reference govern the resolution.

This abstraction exists to keep skills stable as the memory backend evolves.
MAGI (magi) is the current reference implementation.

---

## Step 1 — Detect the backend (once per skill, before any memory operation)

1. If MCP tool `magi_query` is available → **backend: magi**
2. *(future backends will be listed here)*
3. Otherwise → **backend: none** — skip all memory operations; note the limitation in output

Surface detection status alongside other MCP integrations:
```
✓ memory — MAGI
```
or
```
✗ memory — not configured (run /xgh-setup to enable)
```

---

## Step 2 — Resolve intent to tool call

Skills name an **intent**. Look up the intent below and call the corresponding tool
for the detected backend. After referencing the intent in skill prose, always restate
the concrete call in parentheses so there is no ambiguity at runtime.

Example: `[SEARCH] "past auth decisions"  → call magi_query("past auth decisions")`

### Intent: SEARCH

Search memory for relevant context.

| Backend | Concrete call |
|---------|--------------|
| magi | `magi_query(query)` or `magi_query(query, { limit: N })` |

### Intent: STORE

Persist a learning or decision. Always extract a concise summary (3–7 bullets) first —
never pass raw conversation content. **Tags are required** — untagged memories become
unsearchable. Common tags: `"session"`, `"architecture"`, `"convention"`, `"reasoning"`.

| Backend | Concrete call |
|---------|--------------|
| magi | `magi_store(path, title, body, tags)` — tags is a comma-separated string |

### Intent: FORGET

Evict a stale or incorrect memory. Use when a convention has changed or a past decision
has been superseded.

| Backend | Concrete call |
|---------|--------------|
| magi | *not yet supported — log the intent, skip silently* |

---

## Degradation (backend: none)

- Skip every memory operation
- Do not abort the skill — continue with available context
- Emit one note: `⚠️ No memory backend — run /xgh-setup to configure`
- Each skill documents the *impact* of missing memory in its own degradation section

---

## How to use this reference in a skill

### Detection line (add to MCP auto-detection section)

```
Detect memory backend per `_shared/references/memory-backend.md`.
```

### Intent + resolution pattern (in skill body)

```
[SEARCH] "past decisions on rate limiting"
  → call magi_query("past decisions on rate limiting")

[STORE] key learnings, tags: "session,architecture"
  → call magi_store("decisions/rate-limiting.md", "Rate limiting decisions", summary, "session,architecture")
```

### Degradation line (in skill degradation section)

```
No memory backend → skip Steps X and Y. [Describe the impact for this skill.]
```

---

## Adding a new backend (for contributors)

1. Add detection to Step 1 above (numbered, in priority order)
2. Add a row to each intent table with the backend name and concrete call
3. Bump the version comment at the top: `memory-backend: v3`
4. Skills referencing v2 continue to work — detection falls through to the new backend
   only when it is present
