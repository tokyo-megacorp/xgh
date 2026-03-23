---
name: xgh:design
description: "This skill should be used when the user runs /xgh-design or asks to implement a Figma design, 'build from Figma', 'implement this design', 'convert design to code'. Figma-driven UI implementation — takes a Figma design URL and produces a complete, convention-compliant implementation with TDD."
---

# xgh:design — Figma-Driven UI Implementation

Takes a Figma design URL and produces a complete, convention-compliant implementation. Gathers ALL available context from the design file, enriches with xgh memory and team conventions, confirms states interactively, then generates and executes a Superpowers writing-plans implementation plan with TDD.

## Trigger

```
/xgh-design <figma-url>
/xgh-design
```

If no URL is provided, prompt the user for a Figma file URL or node URL.

---

## MCP Auto-Detection

Follow the shared detection protocol in `skills/_shared/references/mcp-auto-detection.md`.

**Graceful degradation rules (design-specific):**
- No Figma MCP → Cannot auto-extract design. Ask user to describe the design, paste screenshots, or provide component specs manually. Skip Code Connect and variable extraction.
- No lossless-claude MCP → Skip memory search for conventions. Rely on codebase scanning only.
- No task manager MCP → Skip ticket lookup. Ask user for acceptance criteria directly.
- No Slack MCP → Skip design discussion search.

---

## Phase 1: Deep Design Mining

Extract everything possible from the Figma design file.

### Step 1.1: Parse Figma URL

Extract `fileKey` and `nodeId` from the URL:
- `https://www.figma.com/file/<fileKey>/...` → file-level
- `https://www.figma.com/file/<fileKey>?node-id=<nodeId>` → node-level
- `https://www.figma.com/design/<fileKey>/...` → design-level (same as file)

### Step 1.2: Get Design Context (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_design_context` with the extracted `fileKey` and `nodeId`.

Extract:
- Component structure and hierarchy
- Code hints (if designers added implementation notes)
- Component mappings (Figma component → code component)
- Design tokens (colors, spacing, typography, shadows)
- Layout information (flex, grid, absolute positioning)
- Responsive breakpoints and constraints

### Step 1.3: Get Screenshot (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_screenshot` to get a visual reference.

Use this for:
- Layout understanding (spatial relationships)
- Visual verification during implementation
- Identifying states not captured in component structure

### Step 1.4: Get File Metadata (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_metadata` to understand file structure.

Extract:
- Pages in the file (find related pages like "States", "Mobile", "Dark Mode")
- Component inventory (all components used in the design)
- File structure (how the designer organized the work)

### Step 1.5: Search FigJam Boards (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_figjam` to find linked FigJam boards.

Extract from FigJam:
- User flows and state diagrams
- Edge cases documented by designers
- Designer notes and annotations
- Acceptance criteria written on stickies
- Animation/interaction specifications
- Accessibility requirements

### Step 1.6: Get Design Variables (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_variable_defs` to extract design tokens.

Map to project design system:
- Colors → project color tokens/CSS variables
- Spacing → project spacing scale
- Typography → project font definitions
- Border radius, shadows, etc.

### Step 1.7: Get Code Connect Map (if Figma MCP available)

Use `mcp__claude_ai_Figma__get_code_connect_map` to find existing component mappings.

This tells us:
- Which Figma components already have code equivalents
- What code to import/reuse vs what to create new
- Existing prop mappings (Figma variants → code props)

---

## Phase 2: Context Enrichment

Supplement Figma data with xgh memory and codebase analysis.

### Step 2.1: Query xgh Memory (if lossless-claude MCP available)

Use `lcm_search(query)` to search for:
- "How do we implement [component type] in this repo?"
- Team conventions for UI components (naming, file structure, test patterns)
- Past implementations of similar designs
- Design system component inventory
- Known UI pitfalls or gotchas in this codebase

Search queries:
- Component type (e.g., "modal", "data table", "form")
- Design pattern (e.g., "loading state", "error boundary")
- Feature area (e.g., "settings page", "user profile")

### Step 2.2: Scan Codebase for Existing Components

Search the codebase to understand existing patterns:
- Find similar components already implemented
- Identify the design system / component library in use
- Check import patterns and file organization conventions
- Look for shared hooks, utilities, and patterns

Match Figma components to code using Code Connect map (Step 1.7) and codebase search:
```
Figma Component        → Code Component           → Action
─────────────────────────────────────────────────────────────
Button/Primary         → src/components/Button     → REUSE (exists)
DataTable              → src/components/Table       → EXTEND (needs new props)
UserAvatar             → (none found)              → CREATE NEW
StatusBadge            → src/components/Badge      → REUSE (exists)
```

### Step 2.3: Check Task Manager (if Atlassian MCP available)

Search for a ticket related to this design work:
- Use `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` with Figma URL or design name
- Fetch ticket details for acceptance criteria, requirements, notes
- Check for linked tickets (related features, dependencies)

---

## Phase 3: Interactive State Review

Present everything discovered and get user confirmation.

### Step 3.1: Present Discovered States

```
I found these states in the Figma design:

  [x] Default state (node 34079:43248) — main view with data loaded
  [x] Loading state (node 34079:43320) — skeleton loader pattern
  [x] Error state (node 34256:54416) — error message with retry CTA
  [x] Empty state (node 34256:54400) — no data illustration + CTA
  [ ] Hover states — found on buttons and table rows
  [ ] Focus states — found on form inputs

  ? Missing states I'd expect:
    - Offline/disconnected state — is there one?
    - Permission denied state — needed?
    - Mobile/responsive view — separate page or responsive?

Which states should I implement? Are there any I missed?
```

### Step 3.2: Present FigJam Notes

```
FigJam notes from the design board:

  - "Animation on transition between loading and loaded states"
  - "Skeleton loading pattern, NOT a spinner"
  - "Error state must show retry CTA that retries the failed request"
  - "Empty state CTA links to /settings/import"
  - "Table rows are clickable — navigate to detail view"

Any additional requirements or changes to these notes?
```

### Step 3.3: Present Component Mapping

```
Component mapping (Figma → Code):

  REUSE existing:
    Button/Primary   → <Button variant="primary" />
    Badge/Status     → <Badge status={...} />
    Icon/Search      → <Icon name="search" />

  CREATE new:
    DataTable        → New component (no existing table component found)
    EmptyState       → New component (illustration + CTA pattern)

  EXTEND existing:
    Card             → <Card /> needs new "compact" variant

Does this mapping look correct? Any components I should reuse instead of creating?
```

### Step 3.4: Confirm Design Token Mapping

```
Design token mapping (Figma → Project):

  Colors:
    Primary/500     → var(--color-primary-500)     ✓ exact match
    Neutral/100     → var(--color-neutral-100)      ✓ exact match
    Error/600       → var(--color-error-600)        ✓ exact match
    Custom/#7C3AED  → ⚠ no match — suggest adding to palette?

  Spacing:
    16px            → var(--space-4)                ✓ matches 4-unit scale
    24px            → var(--space-6)                ✓ matches 4-unit scale
    10px            → ⚠ not on scale — use var(--space-2.5) or round to 8/12?

  Typography:
    Heading/H2      → text-xl font-semibold         ✓ matches
    Body/Regular    → text-base                     ✓ matches

Any adjustments to the token mapping?
```

---

## Phase 4: Implementation Plan + Execute

Generate and execute a Superpowers writing-plans implementation plan.

### Step 4.1: Generate Implementation Plan

Follow the Superpowers writing-plans methodology:
- Each task is 2-5 minutes
- Exact file paths for every file to create/modify
- TDD: write a failing test for each state BEFORE implementing
- Complete code — no "add logic here" placeholders
- Map all Figma tokens to project design system tokens
- Reuse existing components (never reinvent)
- Follow ALL team conventions from context tree

Plan structure:
```
## Implementation Plan: [Component Name]

### Task 1: Create component skeleton + default state test
  Files: src/components/[Name]/[Name].tsx, src/components/[Name]/[Name].test.tsx
  - [ ] Write failing test for default state rendering
  - [ ] Verify test fails
  - [ ] Implement default state
  - [ ] Verify test passes
  - [ ] Commit

### Task 2: Loading state
  Files: src/components/[Name]/[Name].tsx, src/components/[Name]/[Name].test.tsx
  - [ ] Write failing test for loading state
  - [ ] Verify test fails
  - [ ] Implement loading state (skeleton pattern)
  - [ ] Verify test passes
  - [ ] Commit

### Task 3: Error state
  ...

### Task N: Integration + Storybook
  ...
```

### Step 4.2: Execute Plan (Subagent-Driven)

If the user approves the plan, execute it:
- Use Superpowers subagent-driven-development if subagents are available
- Fresh subagent per component/state
- TDD enforced as an iron law — no implementation without a failing test first
- Two-stage review per task: design fidelity + code quality
- After each component: visual comparison (if screenshot available)

### Step 4.3: Design Fidelity Check

After implementation:
```
Design fidelity check:

  [x] Default state matches Figma layout and spacing
  [x] Loading state uses skeleton pattern (not spinner)
  [x] Error state shows retry CTA
  [x] Empty state shows illustration + CTA to /settings/import
  [x] Colors match design token mapping
  [x] Typography matches design token mapping
  [x] Spacing matches 4-unit grid
  [ ] Animation between states — TODO (requires additional work)

Deviations from design:
  - Used var(--space-3) instead of 10px (designer used non-standard spacing)
  - Rounded corner on empty state illustration: 8px instead of 10px (matches grid)
```

---

## Phase 5: Curate & Report

### Step 5.1: Curate New Component Mappings

Store new Figma → code mappings — extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store. Use tags: ["session"]. Content to store:
- New components created and their Figma node IDs
- Design token mappings established
- Convention decisions made during implementation

### Step 5.2: Update Code Connect (if Figma MCP available)

Use `mcp__claude_ai_Figma__send_code_connect_mappings` to register new component mappings:
- Map newly created components back to Figma nodes
- Map props to Figma variants
- Enable future designers/developers to find the code for any Figma component

Use `mcp__claude_ai_Figma__add_code_connect_map` to add new entries to the mapping.

### Step 5.3: Update Context Tree

Save implementation details to `.xgh/context-tree/design-system/[component-name].md`:
- Component purpose and when to use
- Props and variants
- Figma node references
- Design token mappings
- Test coverage summary

YAML frontmatter: `importance: 65`, `maturity: validated`, `tags: [ui, component, design-system, <component-type>]`

### Step 5.4: Generate Report

```markdown
# Implementation Report: [Component Name]

**Design:** [Figma URL]
**Ticket:** [PROJ-1234 or "N/A"]
**Date:** [YYYY-MM-DD]

## Components
| Component | Action | Files |
|-----------|--------|-------|
| DataTable | Created | src/components/DataTable/DataTable.tsx |
| EmptyState | Created | src/components/EmptyState/EmptyState.tsx |
| Card | Extended | src/components/Card/Card.tsx (added "compact" variant) |

## States Implemented
- [x] Default, Loading, Error, Empty
- [ ] Animation transitions (deferred)

## Design Decisions
- Used skeleton loading per FigJam note (not spinner)
- Rounded 10px spacing to 12px to match 4-unit grid
- Added aria-label to retry CTA for accessibility

## Test Coverage
- 14 tests across 4 states
- Snapshot tests for visual regression
- Interaction tests for retry CTA and table row clicks

## Code Connect Updates
- DataTable → node 34079:43248
- EmptyState → node 34256:54400
```

---

## Rationalization Table

| Decision | Rationale |
|----------|-----------|
| Deep design mining (6 Figma MCP calls) | Extracts ALL context before coding. Prevents back-and-forth with designers. |
| Interactive state review | Catches missing states early. Gets user buy-in before implementation. |
| TDD per state | Each state is independently testable. Prevents regressions. |
| Map Figma tokens → project tokens | Maintains design system consistency. No magic numbers. |
| Code Connect updates | Future implementations of similar designs auto-discover reusable components. |
| Reuse over reinvent | Convention from most mature design systems. Less code, fewer bugs. |
| Graceful degradation without Figma MCP | Still works — user provides specs manually. Less automated but same methodology. |
| writing-plans methodology | Each task is 2-5 minutes, TDD enforced, exact paths. No ambiguity. |
