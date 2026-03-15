# Product Ideas: Context Ingestion System (PO Perspective)

**Date:** 2026-03-15
**Author:** Product brainstorm session
**Status:** Draft / Brainstorm

---

## 1. Commitment Drift Detector

### Problem
As a PO I lose sleep over the gap between what was agreed in a planning session and what actually gets built. Scope silently mutates: a Slack thread redefines acceptance criteria, a developer makes a "small" architectural call that changes the feature's behavior, or a Figma revision lands after sprint start with no ticket update. I find out at demo day when the stakeholder says "that's not what I asked for."

### How it works
- **Baseline capture:** When a Jira ticket transitions to "In Progress," the analyzer snapshots its current state: description, acceptance criteria, linked Confluence spec, linked Figma frames, and any Slack threads referencing the ticket ID. This becomes the "commitment baseline."
- **Continuous diff:** The retriever's 5-min scan already watches Slack channels and follows 1-hop links. Extend it to flag when any artifact linked to an in-progress ticket changes: Confluence page edited, Figma frame modified (Figma `get_metadata` returns `lastModified`), Jira description/AC updated, or a Slack message references the ticket ID with language suggesting scope change (keywords: "actually," "instead," "let's also," "new requirement," "can we add").
- **Drift score:** The analyzer compares current state against baseline. Produce a structured drift report: what changed, who changed it, when, and whether the change was captured back into the ticket's AC. If Figma changed but Jira AC didn't update, that's unacknowledged drift.
- **Alert:** Slack DM to the PO and assignee when drift score exceeds threshold. Daily digest includes a "Drift Watch" section.
- **Data flow:** Jira (ticket state, AC) + Confluence (spec versions) + Figma (`get_metadata`, `get_design_context`) + Slack (keyword detection on ticket-ID mentions) + Cipher (store baselines, diff history).

### Why it matters
Prevents the "that's not what we agreed" conversation at sprint review. Forces scope changes to be explicit and documented. In a regulated company, undocumented spec deviations can trigger compliance findings -- especially for features touching payments, KYC, or regulatory reporting.

### Compliance concerns
Storing snapshots of ticket state is fine. Be careful not to store PII from ticket descriptions in the vector DB -- apply the same content-type filtering the analyzer already does. Drift reports should be treated as internal audit artifacts and retained per company policy.

---

## 2. Stakeholder Sentiment Radar

### Problem
I manage 4-6 stakeholders (compliance, design, backend lead, mobile lead, business). Each has a different communication style. Some escalate loudly in Slack; others go quiet when frustrated and then blindside me in a steering committee. I have no early warning system for stakeholder satisfaction. By the time someone says "I'm concerned about timeline," it's already a crisis.

### How it works
- **Stakeholder registry:** The `/xgh-track` config gains a `stakeholders` section per project: name, Slack handle, email, role (approver/informed/contributor), communication style notes.
- **Signal extraction:** The retriever already scans Slack channels. Add sentiment analysis to messages from registered stakeholders about tracked projects. The analyzer classifies each interaction on two axes: (a) sentiment (positive/neutral/concerned/frustrated) and (b) engagement level (active/passive/silent).
- **Silence detection:** For each stakeholder, track time-since-last-engagement per project. If an "approver" stakeholder hasn't commented on a project in >5 business days, flag it. Silence from approvers is often worse than complaints -- it means they've disengaged or are escalating elsewhere.
- **Gmail integration:** Search for email threads involving stakeholder addresses + project keywords. Detect when a conversation moves from Slack to email (often a formality/escalation signal). Detect when stakeholders email your skip-level without CCing you.
- **Weekly radar:** Generate a stakeholder health dashboard: green/yellow/red per stakeholder per project. Include "last engaged" dates and a 1-sentence summary of their current stance.
- **Data flow:** Slack (message sentiment, frequency) + Gmail (email thread detection, CC patterns) + Jira (comment activity by stakeholder) + Cipher (store sentiment history, trend detection).

### Why it matters
In a regulated company, the compliance officer going quiet on a payments feature is a P0 signal. This gives the PO a week's advance warning to schedule a check-in before the concern becomes a blocker. It also helps manage up -- the weekly radar is something you can bring to your 1:1 with your manager.

### Compliance concerns
Sentiment analysis of colleagues' messages is sensitive. This must be positioned as the PO's personal productivity tool, not a surveillance system. Data stays in the PO's personal Cipher collection, never shared workspace. No sentiment scores should ever appear in a Jira ticket, PR, or any artifact visible to the analyzed person. Consider making this opt-in only and transparently documented.

---

## 3. Cross-Project Dependency Graph with Impact Forecasting

### Problem
I own a feature that depends on another team's API. That team's PO reprioritized their backlog last week, but nobody told me. I find out when my engineer says "the endpoint we need doesn't exist yet" -- two days before our deadline. The system already tracks projects individually, but has no cross-project visibility.

### How it works
- **Dependency declaration:** Extend the project YAML config with a `dependencies` section: `[{project: "payments-api", type: "blocks", tickets: ["PAY-456"], contact: "@alice"}]`. The `/xgh-track` skill walks the PO through declaring these during onboarding.
- **Cross-project monitoring:** The retriever scans dependency projects' Slack channels and Jira boards (read-only). It doesn't need write access -- just enough to detect: (a) ticket status changes on depended-upon tickets, (b) sprint scope changes (tickets moved out of sprint), (c) Slack messages mentioning delays, reprioritization, or "pushed to next sprint."
- **Impact forecasting:** When a dependency ticket's status changes (e.g., moved from "In Sprint" to "Backlog"), the analyzer calculates downstream impact: which of MY tickets are blocked, what's the new critical path, and how many days of buffer remain before my deadline.
- **Proactive alert:** Slack DM: "PAY-456 (payments API endpoint) was moved out of Sprint 12. Your ticket TRADE-789 depends on it. Estimated impact: 5-day delay. Contact: @alice. Want me to draft a Slack message?"
- **Data flow:** Jira (cross-board ticket tracking, sprint changes) + Slack (delay signal detection in dependency channels) + Cipher (dependency graph storage, impact calculations) + optionally Confluence (architecture docs linking services).

### Why it matters
In a microservices architecture, almost every feature touches 2-3 teams' domains. This turns the PO from reactive ("why are we blocked?") to proactive ("I see a risk forming, let me intervene now"). Especially critical for regulatory deadlines where delays aren't just inconvenient -- they're non-compliant.

### Compliance concerns
Reading another team's Jira board requires appropriate permissions. The system should use the PO's own Jira credentials (already configured via Atlassian MCP) and only access boards the PO already has read access to. No data from other teams' boards should be stored in shared workspace -- personal collection only.

---

## 4. Meeting-to-Action Bridge (Gmail/Calendar)

### Problem
I spend 40% of my week in meetings. Action items are agreed verbally, written in someone's notes (maybe), and then evaporate. The same decision gets re-debated three weeks later because nobody can find where it was made. Meanwhile, the system has Gmail MCP available but completely unused.

### How it works
- **Pre-meeting context injection:** When the briefing skill detects a calendar event within 30 minutes (already designed in Plan 7), enhance it: search Cipher memory + Slack + Jira for all context related to the meeting's title/attendees/description. Generate a 3-bullet prep card: "Last time this group met, you agreed X. Open item Y is still pending. Stakeholder Z raised concern about W."
- **Post-meeting extraction:** After a meeting, the PO runs `/xgh-debrief` (or it auto-triggers when a meeting ends per calendar). The PO dictates or pastes their notes (even rough). The analyzer extracts: (a) decisions made, (b) action items with owners and deadlines, (c) open questions, (d) commitments given by the PO.
- **Action item tracking:** Each extracted action item becomes a tracked entity in Cipher memory with: owner, deadline, source meeting, status (pending/done/overdue). The retriever checks Slack and Jira daily for evidence that action items are being completed (e.g., a ticket was created, a Slack message says "done").
- **Aging alerts:** If an action item is >3 days old with no evidence of progress, alert the PO. If it's the PO's own action item, remind them. If it's someone else's, suggest a follow-up message.
- **Decision registry:** Decisions extracted from meetings are stored as `type: decision` memories in Cipher, linked to the meeting date, attendees, and related project. When the same topic comes up again (detected via semantic search), surface the previous decision: "This was decided on March 3rd in the API review meeting. Decision: use REST, not gRPC. Attendees: @bob, @alice."
- **Data flow:** Gmail (calendar events, meeting invites, follow-up emails) + Slack (post-meeting action evidence) + Jira (ticket creation as action completion evidence) + Cipher (decision registry, action item tracking).

### Why it matters
Turns meetings from black holes into accountable events. The decision registry alone saves hours of re-debate. For a regulated company, having a searchable record of when and why decisions were made is invaluable during audits -- "we chose this approach because of X, decided on Y date, with Z people present."

### Compliance concerns
Meeting notes may contain sensitive business information, compensation discussions, or HR matters. The system must NOT auto-ingest all meetings -- only meetings the PO explicitly debriefs. The `/xgh-debrief` command should warn if attendees include HR or legal and ask for confirmation before storing. Decision records should be flagged as internal and never surfaced in PRs or external-facing artifacts.

---

## 5. Spec-to-Ship Traceability Chain

### Problem
Our regulator asks: "Show me the chain from requirement to production for this feature." Today that means a human spending 2 hours manually linking a Confluence spec to Jira tickets to PRs to deployment. The system already tracks content across tools but doesn't maintain the directed graph of how a requirement flows through the pipeline.

### How it works
- **Automatic link harvesting:** The retriever already follows 1-hop links from Slack. Extend this to build a directed traceability graph: Confluence spec page -> Jira epic -> Jira stories -> GitHub PRs -> GitHub merges. Each edge is timestamped and attributed (who created the link, when).
- **Gap detection:** The analyzer periodically walks the graph looking for gaps: (a) Jira stories with no linked PR (work done but not code-reviewed?), (b) PRs with no linked Jira ticket (rogue work?), (c) Confluence specs with no linked Jira epic (approved but never planned?), (d) Figma designs linked in Confluence but no corresponding implementation ticket.
- **Compliance report generation:** On demand via `/xgh-trace <feature-or-epic>`, generate a complete traceability report: requirement (Confluence) -> breakdown (Jira) -> implementation (PRs) -> review (PR approvals) -> deployment (merge to main). Include timestamps, authors, and approval chains. Output as markdown suitable for attaching to a compliance artifact.
- **Regulatory deadline tracking:** For features tied to regulatory deadlines (tagged in Jira or declared in project config), add countdown tracking. The daily digest shows: "MiCA compliance: 12 features required, 8 shipped, 3 in progress, 1 not started. Critical path: TRADE-901 (KYC update) -- no PR yet, due in 14 days."
- **Data flow:** Confluence (spec pages, requirement docs) + Jira (epics, stories, links) + GitHub (`gh pr list`, PR-to-ticket links) + Figma (design links in specs) + Cipher (traceability graph storage, gap analysis results).

### Why it matters
This is the single highest-value feature for a regulated company. Manual traceability is error-prone and expensive. Automated traceability turns a 2-hour audit prep task into a 10-second command. It also catches process gaps in real time ("this story has no PR" is today's problem, not audit day's problem). BaFin, ECB, and other regulators increasingly expect digital audit trails -- this positions the team ahead of that curve.

### Compliance concerns
Traceability reports may reference internal ticket titles and PR descriptions. Ensure reports generated for external regulators are reviewed by compliance before submission. The graph itself is low-risk since it's metadata (links, timestamps, authors) rather than content. Store in shared workspace since it's team-level, not personal. Consider data retention policies aligned with regulatory requirements (typically 5-10 years for financial services).
