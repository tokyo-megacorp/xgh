---
name: xgh:convention-guardian
description: Automatically query and enforce team conventions before coding
type: rigid
---

# xgh:convention-guardian — Convention Guardian

> Automatically query and enforce team conventions before coding. Conventions are stored as structured memories in Cipher with `type: convention, scope: team` and enforced by the continuous-learning hook.

## Iron Law

> **NO CODE WITHOUT CHECKING CONVENTIONS FIRST.** Before writing ANY code, query Cipher for team conventions that apply to the current domain. Conventions are team decisions — not suggestions.

## Rationalization Table

| Agent Thought | Reality |
|---|---|
| "I know the standard patterns for this" | Your training data patterns are NOT this team's conventions |
| "This is a simple utility, no conventions apply" | Naming, error handling, and testing conventions apply to ALL code |
| "The convention seems wrong for this case" | Raise the question — don't silently deviate. Conventions evolve through discussion |
| "I already checked conventions at session start" | Conventions are domain-specific. Check again when switching domains |
| "There are no conventions for this area yet" | That's useful to know. Flag it and propose one after implementation |

## Convention Storage Format

Conventions are stored in Cipher with structured metadata:

```yaml
type: convention
scope: team          # team-wide convention
maturity: core       # core = non-negotiable, validated = strong recommendation, draft = proposal
domain: [area]       # e.g., "api-design", "testing", "error-handling", "naming"
tags: [relevant tags]
version: [n]         # incremented on updates, history preserved
supersedes: [id]     # if this convention replaces an older one
```

### Convention Content Structure

```markdown
## Convention: [Short Name]

**Rule:** [The convention stated as a clear, actionable rule]

**Rationale:** [Why this convention exists — the problem it prevents]

**Examples:**
- Correct: [code example following the convention]
- Incorrect: [code example violating the convention]

**Exceptions:** [When it's acceptable to deviate, if ever]

**History:**
- v1 (date): [Original convention]
- v2 (date): [Updated because...] (supersedes: [old-id])
```

---

## Query Process

### Step 1: Identify applicable domains

Before writing code, determine which convention domains apply:
- What kind of code is being written? (API endpoint, UI component, test, migration, etc.)
- What domain area? (authentication, payments, data-access, etc.)
- What language/framework patterns? (React, Go, Swift, etc.)

### Step 2: Query conventions

```
Tool: cipher_memory_search
Parameters:
  query: "[domain] [code-type] convention rules patterns"
  scope: workspace
  filter:
    type: convention
    scope: team
    maturity: core OR validated
```

### Step 3: Present applicable conventions

Format discovered conventions as a checklist:

```
┌─ Convention Guardian ────────────────────────────────────┐
│                                                            │
│  Applicable conventions for [domain/code-type]:            │
│                                                            │
│  [CORE] Use protocol+factory for ViewControllers           │
│         → 5+ consumers, need feature flag support          │
│                                                            │
│  [CORE] All API errors return structured ErrorResponse     │
│         → { code, message, details, requestId }            │
│                                                            │
│  [VALIDATED] Prefer composition over inheritance for       │
│              data transformers                             │
│                                                            │
│  No conventions found for: [subdomain]                     │
│  → Consider proposing one after implementation             │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Step 4: Enforce during implementation

As code is written, verify each convention is followed. If a deviation is necessary:

1. **State the deviation explicitly** — never deviate silently
2. **Document the reason** — why this case is an exception
3. **Store as a question** — flag for team discussion

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    Convention deviation detected:
    Convention: [name] (maturity: [core/validated])
    Deviation: [what was done differently]
    Reason: [why]
    Recommendation: [update convention / add exception / revert deviation]
  metadata:
    type: convention-deviation
    scope: team
    thread: [current branch/PR thread]
    convention_id: [id of the convention]
```

### Step 5: Propose new conventions

When patterns emerge during implementation that should become conventions:

```
Tool: cipher_store_reasoning_memory
Parameters:
  content: |
    ## Convention Proposal: [Short Name]

    **Rule:** [proposed rule]
    **Rationale:** [why this should be a convention]
    **Evidence:** [where this pattern was discovered/validated]
    **Examples:** [code examples]
  metadata:
    type: convention
    scope: team
    maturity: draft
    domain: [area]
    status: proposed
```

---

## Convention Evolution

Conventions evolve. They are NEVER silently deleted.

### Updating a convention

1. Create the new version with `supersedes: [old-id]`
2. Increment the `version` field
3. Add history entry explaining the change
4. Old version remains searchable for audit trail

### Promoting conventions

- `draft` → `validated`: Convention has been followed successfully in 3+ PRs
- `validated` → `core`: Convention has been followed for 2+ sprints with no exceptions needed

### Demoting conventions

- Only through explicit team decision
- Old convention marked `deprecated` with reason
- New convention (or removal) documented with rationale

---

## Tool Reference

| Tool | Usage |
|---|---|
| `cipher_memory_search` | Query conventions by domain, type, scope, and maturity |
| `cipher_store_reasoning_memory` | Store new conventions, deviations, and proposals |
| `cipher_extract_and_operate_memory` | Extract emerging patterns that may become conventions |

## Composability

- Works with **continuous-learning hook**: Hook triggers convention check on every prompt
- Feeds from **knowledge-handoff**: Handoff patterns may become conventions
- Feeds into **pr-context-bridge**: PR reasoning includes which conventions were followed
- Feeds into **cross-team-pollinator**: Team conventions may promote to org-scope
- Feeds into **onboarding-accelerator**: Core conventions surfaced during onboarding
