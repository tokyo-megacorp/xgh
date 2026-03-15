# Design Context Ingestion — 5 Novel Proposals

> Product Designer perspective on bridging the design-to-code gap using the xgh automated context ingestion system.
> Date: 2026-03-15

---

## 1. Design Rationale Weaver

### Problem

The "why" behind a design decision lives in 4-5 different places: a Figma comment explaining why we chose a bottom sheet over a modal, a Slack thread where the PM pushed back on a flow, a meeting where stakeholders approved the final direction, and the designer's head. By the time an engineer picks up the ticket, they see WHAT to build but not WHY it was designed that way. They make "reasonable" changes that unknowingly violate the rationale — like swapping a bottom sheet for a modal because "it's simpler" — and nobody catches it until QA or, worse, production.

In a fintech context this is dangerous: a design choice like "show the fee breakdown BEFORE the confirmation button, never after" might exist because of a BaFin (German financial regulator) requirement discussed in a Slack thread 3 weeks ago.

### How it works technically

**Retriever cron (every 5min)** — already scans Slack. New behavior:
- When a Figma link appears in a Slack message, follow the link via Figma MCP (`get_design_context` + `get_metadata`) to identify the specific component/screen being discussed.
- Tag the Slack thread with `content_type: design_rationale` and associate it with the Figma `fileKey:nodeId`.
- Follow 1-hop into any linked Confluence pages or Jira tickets mentioned in that thread.

**Analyzer cron (every 30min)** — new extraction pattern:
- For `design_rationale` items, extract a structured memory:
  ```yaml
  type: design_rationale
  figma_ref: "fileKey:nodeId"
  component: "Fee Breakdown Bottom Sheet"
  decision: "Bottom sheet instead of modal"
  reasoning: "BaFin requires fee visibility before confirmation action"
  constraints: ["regulatory", "accessibility"]
  participants: ["@designer", "@pm", "@compliance"]
  source_threads: ["slack://channel/thread", "confluence://page"]
  ```
- Store in Cipher with both personal and shared workspace collections.

**Gmail integration** — scan for meeting notes/follow-ups:
- After calendar events tagged with "design review" or "design sync", check Gmail for follow-up emails or shared docs within 2 hours of the meeting end time.
- Extract decisions and rationale from those follow-ups.

**Consumption** — when `implement-design` runs (Phase 2: Context Enrichment):
- Query Cipher: `"design rationale for [component] [figma_ref]"`
- Surface rationale as non-negotiable constraints in the implementation plan.
- Flag any code change that would violate a rationale tagged `regulatory` or `compliance`.

### Why it matters for design-engineering collaboration

Engineers stop asking "why is it designed this way?" in standup. The rationale is embedded in the implementation context. Designers stop feeling like their decisions are arbitrary when engineers can see the reasoning chain. The compliance team gets an audit trail of which regulatory requirements drove which design decisions.

### Compliance concerns

- **Positive:** Creates an auditable trail linking regulatory requirements → design decisions → implementation. BaFin/MiFID II auditors can trace why a specific UI pattern was chosen.
- **Risk:** Slack messages may contain preliminary/speculative compliance discussions that shouldn't be treated as final guidance. The analyzer must distinguish between "we discussed this with Legal" vs "I think Legal might want this."
- **Mitigation:** Tag rationale entries with a `confidence` field. Only `confirmed` rationale (linked to a Jira ticket with compliance label or a Confluence page in the compliance space) gets the `regulatory` constraint flag.

---

## 2. Design Drift Sentinel

### Problem

A designer hands off a pixel-perfect Figma file using the team's design system (let's call it "Comet DS"). The engineer implements it, and it looks right in PR review. But three sprints later, someone refactors the component, a different engineer copies the pattern with hardcoded values instead of tokens, or a new design system version ships and nobody updates the old implementation. Over time, the same "Primary Button" renders with 3 different border-radius values across 7 screens. The design system team has no visibility into this drift until a frustrated designer opens a bug ticket.

Cross-platform drift is even worse: the iOS team interprets spacing differently from Web, Android uses a custom shadow that doesn't match Figma, and the design system components diverge silently.

### How it works technically

**New retriever behavior** — Figma version monitoring:
- Track Figma files registered in the project YAML config.
- On each 5-min cycle, call `get_metadata` on tracked files to detect `lastModified` changes.
- When a file is updated, call `get_variable_defs` to capture the current design token state.
- Diff the tokens against the last stored snapshot in Cipher.
- If tokens changed, create a `content_type: design_system_update` memory with the specific changes (e.g., "primary-500 changed from #0066FF to #0055FF").

**New analyzer behavior** — drift detection:
- Maintain a `design_system_baseline` document in the context tree (`.xgh/context-tree/design-system/baseline.md`) mapping Figma variable names → code token names → expected values.
- When a `design_system_update` is detected, cross-reference against the codebase:
  - Grep for hardcoded values that should be tokens (e.g., `#0066FF` instead of `var(--color-primary-500)`).
  - Check if the code token value matches the new Figma value.
  - Flag files that use the old value.
- Generate a `content_type: design_drift` alert with affected files and severity.

**Cross-platform coherence:**
- If the project config lists multiple repos (iOS, Android, Web), the retriever queries each repo's design token file (e.g., `tokens.json`, `Colors.swift`, `colors.xml`).
- The analyzer compares token values across all platforms against the Figma source of truth.
- Drift report includes platform-specific remediation: "iOS `primaryColor` is `#0066FF`, Figma updated to `#0055FF` — update `Colors.swift:47`."

**Alerting:**
- Drift items with severity `high` (affects primary brand colors, typography scale, or spacing grid) trigger Slack DM to the design system maintainer.
- Weekly drift digest in the team Slack channel showing cumulative drift score.

**Consumption:**
- `convention-guardian` skill gains a `design-system` domain that checks implementations against the baseline.
- `implement-design` Phase 3 (Interactive State Review) shows any known drift in existing components before the engineer builds on top of them.

### Why it matters for design-engineering collaboration

Design system teams currently rely on manual audits or expensive visual regression tools. This makes drift visible as it happens, not months later. Engineers get specific remediation guidance (which file, which line, what the value should be). Designers see their system being respected, which builds trust.

### Compliance concerns

- **Positive:** Consistent UI is a regulatory requirement in fintech — users must have a predictable experience across all touchpoints (especially for high-risk actions like transfers and trading).
- **Risk:** Automated drift detection might create noise if the design system is actively being migrated. Need a "migration mode" that suppresses alerts for components being intentionally updated.
- **Mitigation:** Add a `drift_suppression` list in the project config for components currently being migrated. The sentinel skips those until the suppression expires (configurable TTL).

---

## 3. Figma Comment Thread Materializer

### Problem

Figma comments are where micro-decisions happen: "Should this error state show an inline message or a toast?", "The icon should be 20px not 24px here because of the dense layout", "Compliance says we need a tooltip explaining this fee." These comments are invisible to engineers who don't open the Figma file, and they are buried even for those who do. When comments get resolved, they disappear from the default Figma view entirely. The decisions they contain — decisions that directly affect implementation — are effectively deleted.

### How it works technically

**Retriever cron** — Figma comment polling:
- For each tracked Figma file in the project config, call `get_metadata` to detect comment activity (Figma MCP doesn't have a direct "get comments" tool, but `get_design_context` returns comments attached to specific nodes).
- When new or resolved comments are detected, capture:
  ```yaml
  content_type: figma_comment_thread
  figma_ref: "fileKey:nodeId"
  component: "Transfer Confirmation Screen"
  thread_summary: "Decided: inline error, not toast. Reason: user must acknowledge before retrying."
  participants: ["@designer", "@pm"]
  status: resolved
  resolution: "Inline error pattern with retry CTA"
  ```

**Analyzer cron** — decision extraction:
- Process `figma_comment_thread` items to extract actionable decisions.
- Classify each resolved thread as one of:
  - `spec_change` — the design changed based on the discussion
  - `clarification` — no change, but intent was clarified
  - `deferral` — decided to handle this later (creates a follow-up)
  - `constraint` — external constraint was surfaced (accessibility, compliance, technical)
- Link decisions to the Figma node and any related Jira ticket.

**Gmail tie-in:**
- Figma sends email notifications for comment threads. The Gmail retriever can catch these as a backup signal, especially for comments on files not yet tracked in the project config. Pattern: emails from `notifications@figma.com` with the project's file names.

**Consumption:**
- `implement-design` Phase 1 (Deep Design Mining) already reads Figma context. This adds: "There were 3 resolved comment threads on this component. Key decisions: [list]."
- The briefing skill gains a Figma section: "2 new comment threads on your designs awaiting response."
- When an engineer asks "why is this an inline error and not a toast?", Cipher returns the original Figma comment thread with full reasoning.

### Why it matters for design-engineering collaboration

Figma comments are the most granular design decisions, and they're the most likely to be lost. Materializing them into the memory system means every micro-decision has a retrievable, searchable record. Engineers can self-serve answers to "why" questions without interrupting the designer.

### Compliance concerns

- **Positive:** Comment threads often contain compliance-related decisions ("Legal says we must show this disclaimer"). Capturing these creates an audit trail.
- **Risk:** Figma comments may contain casual/personal remarks not intended for permanent storage. Need filtering for signal vs. noise.
- **Mitigation:** Only materialize resolved threads (resolved = someone made a decision). Unresolved threads are surfaced in briefings as "awaiting response" but not stored as decisions. Add a `#no-capture` tag convention for comments designers want to keep ephemeral.

---

## 4. Design Review Outcome Tracker

### Problem

Design reviews happen in meetings (Zoom/Google Meet), Slack threads, and async Figma sessions. The outcomes — "approved with changes", "needs another round", "blocked on content from marketing" — are communicated verbally or in a Slack message that gets buried. There is no structured record of: (a) what was reviewed, (b) who approved it, (c) what conditions were attached, (d) whether those conditions were met before implementation started. In a fintech, this is especially problematic because certain UI changes (e.g., changes to the trading flow, KYC screens, or fee displays) may require sign-off from compliance or product before engineering begins.

### How it works technically

**Calendar + Gmail integration:**
- The retriever watches for calendar events matching patterns: "design review", "design crit", "UX review", "UI walkthrough", "[project] review".
- After the meeting ends (detected via calendar event end time), the retriever:
  1. Checks Gmail for any follow-up emails or shared meeting notes within a 2-hour window.
  2. Checks Slack channels associated with the project for messages posted during or shortly after the meeting window.
  3. Checks Figma for comments added during the meeting window (timestamps from `get_metadata`).

**Analyzer** — outcome extraction:
- Synthesize signals from all three sources into a structured review record:
  ```yaml
  content_type: design_review_outcome
  design_ref: "figma_file:node or Jira ticket"
  component: "New KYC Flow"
  status: approved_with_changes | needs_revision | blocked | approved
  conditions:
    - "Update error copy — waiting on content from @marketing"
    - "Add biometric fallback flow for accessibility"
  approvers: ["@product-lead", "@design-lead"]
  blockers: ["content from marketing"]
  next_review_date: null  # or ISO date if scheduled
  compliance_sign_off: pending | not_required | approved
  ```
- Track condition completion: on each cycle, check if blocker conditions have been resolved (e.g., marketing posted the copy in Slack, the Figma file was updated with the biometric flow).

**Jira integration:**
- When a review outcome is captured, update the linked Jira ticket:
  - Add a comment summarizing the review outcome.
  - If `blocked`, add a blocker link to the blocking issue.
  - If `approved`, transition the ticket to "Ready for Dev" (or whatever the team's workflow state is).

**Consumption:**
- Briefing skill: "KYC Flow design was approved with 2 conditions — 1 met, 1 pending (content from marketing)."
- `implement-design`: refuses to start implementation if the design review status is `needs_revision` or `blocked`. Shows: "This design has unmet review conditions: [list]. Proceed anyway? (This will be flagged in the PR.)"
- `implement-ticket`: when a ticket is picked up, checks if there's a pending design review outcome and surfaces it.

### Why it matters for design-engineering collaboration

Eliminates the "I thought it was approved" problem. Engineers know exactly when a design is ready for implementation and what caveats exist. Designers know their review feedback is being tracked and conditions enforced. Product leads see review status without asking. Compliance gets visibility into whether regulated screens were properly reviewed before implementation.

### Compliance concerns

- **Positive:** Creates a formal approval chain for UI changes to regulated flows. Auditors can verify that KYC, trading, and payment screens went through proper design review with compliance sign-off.
- **Risk:** Meeting content may include confidential business strategy discussions. The system should only extract design-related decisions, not general business context.
- **Mitigation:** The analyzer uses the Figma file/Jira ticket as an anchor — only extract content that references the specific design being reviewed. Discard unrelated meeting content. Add a `compliance_required: true` flag in the project config for regulated flows that enforces the sign-off field.

---

## 5. Accessibility & Regulatory Pattern Library

### Problem

Fintech products must meet WCAG 2.1 AA (soon AAA for some jurisdictions), PSD2 strong customer authentication UX requirements, BaFin disclosure rules, and MiFID II suitability assessment UI patterns. These requirements are scattered across legal documents, Confluence pages, and tribal knowledge. A designer might know "the transfer confirmation needs a 2-second delay before the confirm button activates" (PSD2 requirement), but that knowledge isn't codified anywhere an engineer or AI agent can consume it. Each new feature risks reinventing (or missing) the same compliance patterns.

### How it works technically

**Confluence integration** — one-time + incremental:
- On first setup (via `/xgh-track`), the retriever crawls Confluence spaces tagged with "compliance", "accessibility", "legal", "regulatory" in the project config.
- Extracts regulatory UI requirements and stores them as `content_type: regulatory_pattern` memories:
  ```yaml
  content_type: regulatory_pattern
  regulation: "PSD2 SCA"
  requirement: "Payment confirmation must include a deliberate user action with minimum 2s delay"
  ui_pattern: "Disabled confirm button with countdown timer"
  applies_to: ["payment_confirmation", "transfer_confirmation"]
  source: "confluence://legal/psd2-requirements#section-4.3"
  severity: mandatory  # mandatory | recommended | best_practice
  last_verified: "2026-02-15"
  ```

**Incremental updates:**
- The retriever monitors the compliance Confluence spaces for page updates.
- When a compliance page is updated, re-extract and diff against stored patterns.
- If a pattern changed, create a `content_type: regulatory_update` alert with the delta.

**Figma integration** — design-time validation:
- When the analyzer processes a Figma design for a regulated flow (matched via Jira ticket labels or project config tags), it checks the design against applicable regulatory patterns.
- Example: "This is a payment confirmation screen. Checking PSD2 patterns... WARNING: No deliberate action delay detected in the flow. The confirm button appears immediately after amount entry."

**Accessibility layer:**
- Store WCAG 2.1 patterns as `accessibility_pattern` memories with concrete implementation guidance:
  ```yaml
  content_type: accessibility_pattern
  wcag_criterion: "1.4.3 Contrast (Minimum)"
  level: "AA"
  requirement: "Text contrast ratio >= 4.5:1, large text >= 3:1"
  design_system_tokens: ["color-text-primary", "color-text-secondary"]
  validation: "Check all text colors against background colors in Figma variables"
  ```
- The Design Drift Sentinel (Proposal 2) can run accessibility checks when token values change — e.g., "The new `color-text-secondary` value #999999 on white background has a 2.8:1 contrast ratio, failing WCAG AA."

**Consumption:**
- `convention-guardian` gains a `regulatory` domain that checks implementations against stored patterns. `severity: mandatory` patterns are treated as CORE conventions that cannot be deviated from without explicit compliance sign-off.
- `implement-design` Phase 3 (Interactive State Review) includes a "Regulatory & Accessibility Checklist" section:
  ```
  Regulatory patterns for payment_confirmation:
    [x] PSD2: Deliberate action delay (2s countdown timer)
    [x] BaFin: Fee breakdown visible before confirmation
    [ ] MiFID II: Risk disclosure for investment products — N/A (not investment)

  Accessibility (WCAG 2.1 AA):
    [x] Contrast ratios meet minimum
    [x] Touch targets >= 44x44px
    [ ] Screen reader flow verified — MANUAL CHECK NEEDED
  ```
- Briefing skill: "Regulatory update: PSD2 SCA requirements updated in Confluence. 3 screens may be affected."

### Why it matters for design-engineering collaboration

Compliance requirements become first-class citizens in the design-to-code pipeline instead of afterthoughts caught in QA. Designers can validate their designs against regulatory patterns before handoff. Engineers get concrete implementation guidance ("2-second countdown timer") instead of vague legal text. The compliance team can update requirements in Confluence and know they'll propagate to all future implementations automatically.

### Compliance concerns

- **Positive:** This IS the compliance solution. It codifies regulatory requirements into enforceable, traceable patterns. Auditors can verify that every regulated screen was checked against the pattern library during implementation.
- **Risk:** Regulatory interpretations may be wrong or outdated. The pattern library must be maintained by someone with legal/compliance authority, not auto-generated from Confluence without review.
- **Mitigation:** All `regulatory_pattern` memories require a `last_verified` date and a `verified_by` field (a human). Patterns older than 90 days trigger a "verification needed" alert in the briefing. The system surfaces patterns but never overrides human compliance judgment — it flags, it doesn't block (except for `mandatory` patterns in `implement-design`, which show a warning, not a hard block).
