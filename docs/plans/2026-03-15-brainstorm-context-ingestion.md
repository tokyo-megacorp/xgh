# Brainstorm: Novel Context Ingestion Ideas

> **Date:** 2026-03-15
> **Context:** Extending the xgh automated context ingestion system beyond the existing retriever/analyzer cron architecture, briefing skill, and tracked project sources.

---

## Idea 1: Pipeline Archaeologist — CI/CD Failure Context Reconstruction

### Problem

When you sit down to code and CI is red, the current system tells you "build failed" but not *why it's failing in the way it is*. The real context behind a CI failure is scattered: a flaky test that's been red 3 times this week, a dependency update in another repo that broke the contract, an infra change someone mentioned in Slack but never ticketed. You waste 20-40 minutes reconstructing the causal chain before you can even start fixing it.

### How it works

**Data flow:**

1. **GitHub Actions webhook** (or cron polling via `gh run list --json`) detects failed/flaky runs
2. For each failure, the analyzer session:
   - Pulls the failed step logs via `gh run view --log-failed`
   - Extracts the error signature (test name, error message, stack trace fingerprint)
   - Searches Cipher memory for past occurrences of the same signature
   - Searches Slack (via `slack_search_public_and_private`) for the error message or test name in the last 7 days
   - Checks `gh pr list --state merged` for recent merges that touched the failing file paths
   - Cross-references Jira for any linked tickets mentioning the affected component
3. Stores a structured **failure context record** in Cipher:
   ```yaml
   type: ci_failure_context
   signature: "OrderServiceTest.testPartialRefund - NPE at line 142"
   first_seen: 2026-03-10
   occurrences: 4
   likely_cause: "PR #892 changed refund calculation, no test update"
   related_slack: ["#payments-eng 2026-03-11 thread by @maria"]
   related_jira: ["PAY-1247"]
   flakiness_score: 0.75  # failed 3/4 recent runs
   ```
4. The briefing skill surfaces this: "CI red on main -- OrderServiceTest failing since Mar 10, likely caused by PR #892 (refund calc change). Maria discussed in #payments-eng."

**Tools:** GitHub CLI (`gh run list`, `gh run view --log-failed`, `gh pr list`), Slack MCP, Jira MCP, Cipher memory

### Why it matters

In fintech, CI being red blocks deployments and blocks other engineers. A 40-minute "what broke and why" investigation, repeated by 3 engineers who each look at the same failure independently, becomes a 5-second briefing line. The system turns CI failures from opaque signals into actionable narratives.

### Compliance concerns

- CI logs may contain PII in test fixtures (customer data in staging). The analyzer should strip/hash sensitive patterns (IBANs, emails, names) before storing to Cipher.
- Log retention policies: stored failure contexts should respect the same TTL as CI logs themselves (typically 90 days).
- Access control: failure contexts from private repos should only go to the personal Cipher workspace, not the shared team collection, unless the repo's visibility allows it.

---

## Idea 2: The Debt Collector — Informal Tech Debt Crystallizer

### Problem

Engineers constantly say things like "we should refactor this", "this is a hack, fix later", "TODO: proper error handling" -- in Slack, in PR comments, in code review threads, in standup notes. These never become tickets. They accumulate silently until someone hits a wall. The system currently tracks decisions and spec changes, but it doesn't track the *anti-decisions* -- the things people explicitly chose NOT to do yet.

### How it works

**Data flow:**

1. The retriever session (every 5 min) already scans Slack channels. Add a **debt signal detector** that flags messages matching patterns:
   - Explicit deferral language: "we'll fix this later", "tech debt", "hack for now", "not ideal but", "TODO", "FIXME", "workaround"
   - Conditional promises: "once we migrate to X", "after the deadline", "when we have time"
   - Pain signals: "this keeps breaking", "every time we deploy", "I've seen this before", "third time this sprint"
2. The analyzer (every 30 min) takes flagged messages and:
   - Groups related debt signals by component/service (using code path mentions and Cipher similarity search)
   - Tracks **debt velocity**: how often the same area generates complaints
   - Cross-references with Jira to check if a ticket already exists
   - Searches GitHub for `TODO`/`FIXME`/`HACK` comments in recent commits via `gh search code`
3. Stores structured debt records:
   ```yaml
   type: tech_debt_signal
   component: "payment-gateway/refund-handler"
   signals:
     - source: slack/#payments-eng
       date: 2026-03-08
       author: maria
       quote: "the retry logic is a mess, we should rewrite this"
     - source: github/PR#847/review
       date: 2026-03-12
       author: pedro
       quote: "FIXME: hardcoded timeout, should be configurable"
   velocity: 3_mentions_in_14_days
   existing_ticket: null  # no Jira ticket found
   estimated_blast_radius: high  # touches payment path
   ```
4. Weekly, the system generates a **Debt Digest** (Slack DM or briefing section) ranking debt by velocity and blast radius. When velocity crosses a threshold (e.g., 5 mentions in 30 days), it auto-drafts a Jira ticket via `createJiraIssue` (held in draft, not submitted -- the engineer reviews and submits).

**Tools:** Slack MCP (retriever already uses this), GitHub CLI (`gh search code`), Jira MCP (`searchJiraIssuesUsingJql` to check for existing tickets, `createJiraIssue` for drafts), Cipher memory

### Why it matters

Tech debt is the #1 silent productivity killer. In fintech specifically, untracked debt in payment paths or compliance-sensitive code is a regulatory risk. By making the informal visible, you turn Slack complaints into an early warning system. The velocity metric is key: one mention is noise, five mentions is a pattern that needs a ticket.

### Compliance concerns

- Auto-created Jira tickets must be clearly labeled as "AI-drafted" and require human approval before submission. In a regulated environment, tickets that drive engineering work need human accountability.
- Quoting Slack messages in Jira tickets: check your data governance policy. Some orgs prohibit cross-system PII movement. The debt record should reference the Slack message (link) rather than embedding the full quote.
- Debt velocity metrics could be perceived as tracking individual engineers ("Maria complained 5 times"). Aggregate by component, not by person. Strip author attribution from the digest.

---

## Idea 3: Blast Radius Radar — Cross-Repo Impact Awareness

### Problem

In a microservices architecture (typical fintech), changing a protobuf schema in the `shared-contracts` repo, updating an API version in `payment-gateway`, or modifying a database migration in `account-service` can silently break downstream consumers. The current system tracks projects per-repo, but has no concept of *inter-repo dependency graphs* or *change propagation*. You find out when CI breaks in repo B, not when the change lands in repo A.

### How it works

**Data flow:**

1. **Dependency graph construction** (one-time + incremental):
   - Parse `package.json`, `build.gradle`, `go.mod`, `requirements.txt`, protobuf imports, OpenAPI spec references across all tracked repos
   - Store the graph in Cipher as a structured relationship:
     ```yaml
     type: dependency_edge
     from_repo: shared-contracts
     to_repo: payment-gateway
     interface: proto/payment/v2/refund.proto
     direction: upstream
     ```
   - Update incrementally when the retriever sees merged PRs touching dependency files

2. **Change propagation detection** (added to the analyzer's 30-min cycle):
   - For each merged PR in tracked repos, check if changed files are dependency-graph nodes
   - If yes, identify all downstream repos
   - Search for open PRs or recent commits in downstream repos that might conflict
   - Check if downstream repos' CI has run against the new version yet

3. **Alert generation:**
   ```
   type: blast_radius_alert
   trigger: PR #201 merged in shared-contracts (changed refund.proto)
   affected_repos:
     - payment-gateway (direct consumer, CI not yet run)
     - merchant-dashboard (transitive via payment-gateway)
   recommended_action: "Verify payment-gateway builds against new proto. Breaking field rename: `refund_amount` -> `refund_value`."
   ```

4. Surface in briefing under INCOMING: "shared-contracts changed refund.proto (PR #201). payment-gateway and merchant-dashboard may be affected. CI not yet validated."

**Tools:** GitHub CLI (`gh pr list`, `gh api repos/{owner}/{repo}/contents/{path}` for dep files), Cipher memory (graph storage), Slack MCP (alert to affected repo owners)

### Why it matters

In fintech, a breaking change in a payment contract that isn't caught until production is potentially a regulatory incident. This transforms a reactive "CI broke, why?" into a proactive "heads up, this change is coming downstream." It's especially valuable for teams that don't have a monorepo and rely on contract testing that may not run on every commit.

### Compliance concerns

- The dependency graph itself is sensitive: it maps your entire system architecture. Store only in personal Cipher workspace, not shared, unless the team explicitly opts in.
- Cross-repo access: the system needs read access to multiple repos. Use a GitHub App or fine-grained PAT with minimal scopes, not a personal token with full org access. Audit which repos the system reads.
- Change propagation alerts should never auto-merge or auto-close PRs. They are advisory only. In a regulated environment, all code changes must have explicit human approval.

---

## Idea 4: Meeting-to-Memory Bridge — Calendar-Driven Decision Capture

### Problem

Critical engineering decisions happen in meetings and never make it into tickets or docs. "We agreed to deprecate v1 API by Q3" lives in someone's meeting notes (or nowhere). The standup where someone said "I'm blocked on the schema migration" produces no artifact. Retro action items ("improve deploy rollback time") evaporate by Monday. The system currently has Gmail integration but doesn't use it, and has no calendar awareness at all.

### How it works

**Data flow:**

1. **Calendar scanning** (new retriever capability, every 5 min):
   - Use Gmail MCP to find calendar invites and meeting-related emails: `gmail_search_messages: "subject:(meeting notes OR standup OR retro OR design review OR RFC) newer_than:1d"`
   - Detect meetings that just ended (invite time + duration < now) to trigger post-meeting analysis
   - Detect meetings starting soon (for the briefing's pre-meeting mode)

2. **Post-meeting analysis** (analyzer, triggered by meeting end detection):
   - Search Slack for messages posted during the meeting window in the relevant channel (meetings often have a companion Slack thread)
   - Search Gmail for any "meeting notes" or "action items" emails sent within 30 min of meeting end
   - Search Confluence (`searchConfluenceUsingCql: "type=page AND lastModified > 'now-1h' AND text ~ 'meeting notes'"`) for recently created/updated meeting note pages
   - Extract structured content:
     ```yaml
     type: meeting_decision
     meeting: "Payments Team Sync"
     date: 2026-03-15
     decisions:
       - "Deprecate v1 refund API by end of Q2"
       - "Use saga pattern for multi-step refunds"
     action_items:
       - owner: pedro
         item: "Draft RFC for saga-based refund flow"
         deadline: 2026-03-22
       - owner: maria
         item: "Set up contract tests for refund.proto"
     blockers_raised:
       - "Schema migration blocked on DBA approval (INFRA-445)"
     ```

3. **Action item tracking** (persistent):
   - Store action items with deadlines in Cipher
   - The briefing skill surfaces approaching deadlines: "Action item from Payments Sync (Mar 15): Draft RFC for saga-based refund flow -- due in 7 days"
   - If a deadline passes without a corresponding Jira ticket or PR, escalate visibility in next briefing

4. **Decision cross-referencing:**
   - When an engineer starts working on something that contradicts a stored meeting decision, surface it: "Note: Payments Sync on Mar 15 decided to use saga pattern for multi-step refunds. Your current approach uses choreography -- intentional?"

**Tools:** Gmail MCP (`gmail_search_messages`, `gmail_read_message`), Confluence MCP (`searchConfluenceUsingCql`, `getConfluencePage`), Slack MCP, Cipher memory

### Why it matters

Meetings are the #1 source of decisions and the #1 place decisions go to die. In fintech, undocumented decisions about API contracts, data handling, or compliance controls are audit risks. This creates an automatic paper trail. The action item tracking alone would save hours of "did we ever do that thing we said we'd do?" conversations.

### Compliance concerns

- **Major concern:** Meeting content may contain confidential business discussions, salary information, HR matters, or legally privileged content. The system MUST NOT ingest meetings from HR, Legal, or executive-only channels without explicit opt-in.
- Implement a meeting allow-list in the YAML config: only ingest meetings matching specified calendar names or channel patterns (e.g., `#payments-*`, `#platform-*` but not `#hr-*`, `#legal-*`).
- Meeting notes stored in Cipher should be tagged with a retention policy and purged when the originating Confluence page or email is deleted.
- Action items with named owners: storing "pedro must do X by Y" creates accountability artifacts. Ensure this aligns with your works council / labor relations policies where applicable.

---

## Idea 5: Session Replay Context — "What Was the AI Thinking?"

### Problem

The current system tracks *what* a Claude session worked on (session-to-ticket mapping, last commit), but not *why* it made the choices it did. When you come back to code that an AI session wrote yesterday, or when a teammate's AI agent made a decision you disagree with, there's no way to understand the reasoning. You see the diff, but not the deliberation. This is especially painful during code review: "Why was this implemented as a saga instead of a simple transaction?" The PR description might say what, but the *architectural reasoning* is lost.

### How it works

**Data flow:**

1. **Enhanced session capture** (modification to the existing session-end memory storage):
   - Currently, `cipher_extract_and_operate_memory` stores a summary. Enhance this to also store:
     ```yaml
     type: session_replay_context
     session_id: "2026-03-15-a3f2"
     ticket: "PAY-1247"
     branch: "feat/saga-refunds"
     duration_minutes: 45
     key_decisions:
       - question: "Saga vs choreography for multi-step refunds?"
         decision: "Saga pattern"
         reasoning: "Need compensating transactions for partial failures. Choreography would require every service to handle rollback independently, which conflicts with our existing error handling in payment-gateway."
         alternatives_considered:
           - "Choreography -- rejected because rollback complexity"
           - "Simple transaction -- rejected because spans 3 services"
         files_affected: ["src/refund/saga.ts", "src/refund/steps/"]
       - question: "Where to store saga state?"
         decision: "Dedicated saga_state table"
         reasoning: "Redis was considered but saga state must survive restarts for compliance (audit trail)."
     rejected_approaches:
       - approach: "Modifying existing RefundService directly"
         reason: "Would break the existing v1 API contract, decided to create new SagaRefundService"
     ```

2. **PR enrichment** (triggered when a PR is created or updated):
   - When `gh pr list --author @me` shows a new/updated PR, search Cipher for session replay context matching the branch
   - Generate a structured "Reasoning" section for the PR description or as a PR comment:
     ```markdown
     ## AI Session Context
     **Sessions:** 3 sessions over 2 days (total ~2h of AI work)
     **Key decisions:**
     - Chose saga pattern over choreography (compensating transactions needed)
     - New SagaRefundService instead of modifying RefundService (v1 API preservation)
     - Saga state in PostgreSQL, not Redis (audit trail requirement)
     **What was NOT done and why:**
     - Did not add retry logic to individual saga steps (out of scope per PAY-1247)
     ```

3. **Code review assist** (on-demand, when reviewing a PR):
   - When an engineer is reviewing a PR, search Cipher for session replay context on that branch
   - Surface the reasoning behind specific file changes: "This file was changed because [reasoning from session context]"

**Tools:** Cipher memory (enhanced session capture via `cipher_store_reasoning_memory`), GitHub CLI (`gh pr list`, `gh pr comment`), existing session hooks

### Why it matters

Code review in fintech is high-stakes: reviewers need to validate not just correctness but also compliance with regulations, security policies, and architectural standards. Understanding *why* an AI made a choice lets reviewers catch "the AI didn't know about requirement X" errors that would otherwise ship. It also dramatically reduces the "wait, why did you do it this way?" back-and-forth that adds days to PR review cycles.

### Compliance concerns

- Session reasoning may reveal information about internal decision-making processes. If stored in GitHub PR comments, this becomes part of the permanent record. Consider whether this creates discovery risk in legal proceedings.
- Reasoning that references compliance requirements ("we did X because of regulation Y") should be reviewed by a human before being posted publicly on the PR. An AI mischaracterizing a regulatory requirement in a PR comment could be problematic.
- Access control: session replay context should only be visible to the PR author and reviewers, not the entire org. Use Cipher personal workspace for storage, surface via PR comments only with explicit opt-in.
- Data minimization: store the reasoning chain, not the full conversation transcript. The transcript may contain sensitive context (API keys discussed, security vulnerabilities explored) that shouldn't persist.
