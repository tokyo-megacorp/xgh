# Memory Backend Reference
# memory-backend: v1

xgh's memory layer is backend-agnostic. Skills declare *intent* (search, store, forget)
and this reference resolves each intent to the concrete tool call for whichever backend
is configured. Do not call `lcm_*` or any backend-specific tool directly in skills —
express intent and let this reference govern the resolution.

This abstraction exists to keep skills stable as the memory backend evolves.
lossless-claude (lcm) is the current reference implementation.

---

## Step 1 — Detect the backend (once per skill, before any memory operation)

1. If MCP tool `lcm_search` is available → **backend: lcm** (lossless-claude)
2. *(future backends will be listed here)*
3. Otherwise → **backend: none** — skip all memory operations; note the limitation in output

Surface detection status alongside other MCP integrations:
```
✓ memory — lossless-claude
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

Example: `[SEARCH] "past auth decisions"  → call lcm_search("past auth decisions")`

### Intent: SEARCH

Search memory for relevant context. Tags are optional — omit to search broadly.

| Backend | Concrete call |
|---------|--------------|
| lcm | `lcm_search(query)` or `lcm_search(query, { tags: [tag, ...] })` |

### Intent: STORE

Persist a learning or decision. Always extract a concise summary (3–7 bullets) first —
never pass raw conversation content. **Tags are required** — untagged memories become
unsearchable. Common tags: `"session"`, `"architecture"`, `"convention"`, `"reasoning"`.

| Backend | Concrete call |
|---------|--------------|
| lcm | `lcm_store(text, [tag, ...])` |

### Intent: FORGET

Evict a stale or incorrect memory. Use when a convention has changed or a past decision
has been superseded.

| Backend | Concrete call |
|---------|--------------|
| lcm | *not yet supported — log the intent, skip silently* |

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
  → call lcm_search("past decisions on rate limiting")

[STORE] key learnings, tags: ["session", "architecture"]
  → call lcm_store(summary, ["session", "architecture"])
```

### Degradation line (in skill degradation section)

```
No memory backend → skip Steps X and Y. [Describe the impact for this skill.]
```

---

## Adding a new backend (for contributors)

1. Add detection to Step 1 above (numbered, in priority order)
2. Add a row to each intent table with the backend name and concrete call
3. Bump the version comment at the top: `memory-backend: v2`
4. Skills referencing v1 continue to work — detection falls through to the new backend
   only when it is present
