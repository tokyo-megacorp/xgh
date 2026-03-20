# xgh — Feature Ideas Backlog

Unordered ideas for future features and improvements.

| # | Idea | Status | Effort |
|---|------|--------|--------|
| 1 | GitHub provider (bash mode) | **Done** (dynamic generation) | — |
| 2 | `/xgh-standup` | Not started | Medium |
| 3 | `/xgh-pr-review` | Partial (via pr-context-bridge + code-reviewer) | Low |
| 4 | Delta briefing | Not started | Medium |
| 5 | Slack thread depth | **Done** | — |
| 6 | `/xgh-timeline` | Not started | Large |
| 7 | Fix pre-existing test failures | Partial (down to 7 fails) | Small |
| 8 | Provider failure recovery | **Done** | — |
| 9 | Inbox aging | Partial (awaiting-reply only) | Small |
| 10 | `/xgh-release-notes` | Not started | Medium |
| 11 | Trigger engine (IFTTT for devs) | Brainstorming | Large |

---

## 1. GitHub provider (bash mode) — `Effort: Medium`

**Status:** Spec only — `providers/github/spec.md` exists with full design (PRs, issues, notifications, releases via `gh` CLI), but no runtime `fetch.sh` is generated until `/xgh-track` adds a GitHub source. The spec is solid; implementation means wiring it into the track flow and testing the generated scripts.

Currently GitHub is listed as a provider spec but the bash fetch is incomplete. Pull PRs, Actions runs, security alerts, discussions, and releases into the retrieval pipeline as a proper `mode: bash` provider alongside Slack/Jira.

---

## 2. `/xgh-standup` — `Effort: Medium`

**Status:** Not started. Referenced in momentum PRD (M-P2-07) and developer-experience proposal but no skill file exists.

Generate a daily standup from recent activity: what moved in Jira, what PRs were opened/merged, what decisions were made. Output a ready-to-paste 3-section summary (done / doing / blocked). Would query lossless-claude for yesterday's session activity + Jira/GitHub for ticket/PR movement.

---

## 3. `/xgh-pr-review` — `Effort: Low (incremental)`

**Status:** Partially addressed. `pr-context-bridge` skill captures PR reasoning during development and loads context for reviewers. `code-reviewer` agent evaluates against conventions. Missing: a single entry point that takes a PR URL, fetches the diff, cross-references Jira + Slack threads, and outputs a structured review. This would be a composition skill wrapping existing pieces.

Given a PR URL: fetch the diff, look up the Jira ticket, retrieve related Slack threads, check conventions in the context tree, and produce a structured review with context the reviewer would otherwise miss.

---

## 4. Delta briefing — `Effort: Medium`

**Status:** Not started. Briefing is fully stateless — no timestamp tracking, no digest history. Every invocation queries all sources fresh.

`/xgh-brief` currently always runs everything. Add a `--since` flag (or auto-detect last brief timestamp) to only surface items that changed since the last brief. Needs: a `.briefing-last-run` state file, filtering logic, and possibly a `~/.xgh/digests/` history directory.

---

## ~~5. Slack thread depth~~ — **Done**

**Already implemented.** Fast retrieve (Step 2) has a thread reply pass using `slack_read_thread` with 24h lookback. Deep retrieve (hourly) catches thread replies on messages up to 7 days old. Both stash with `source_type: slack_thread`, include parent context, and dedup by reply timestamp.

---

## 6. `/xgh-timeline` — `Effort: Large`

**Status:** Not started. No skill, no command. Research docs have manual timeline examples but no automated generation.

Given a project and date range, produce a chronological event feed across all providers: Slack decisions, Jira status changes, PR merges, Figma updates. Useful for retrospectives and incident postmortems. Requires fetching + merging + sorting events from all providers with a unified timestamp model.

---

## 7. Fix pre-existing test failures — `Effort: Small`

**Status:** Partially fixed. Down from 20+ fails to 7 across 4 test files:
- `test-brief.sh` (1 fail) — missing `XGH_BRIEFING` in session-start hook
- `test-briefing.sh` (1 fail) — missing `XGH_BRIEFING` in briefing skill
- `test-multi-agent.sh` (2 fails) — missing `skills/agent-collaboration/instructions.md`
- `test-plan4-integration.sh` (3 fails) — missing cross-references between Plan 4 skills

All are missing-file/missing-text assertions, not functional failures. Quick fixes.

---

## ~~8. Provider failure recovery~~ — **Done**

**Already implemented.** `retrieve-all.sh` uses `|| rc=$?` pattern to capture provider exit codes without aborting. Failed providers are logged to `provider-<name>.log`, counted separately, and the loop continues. Final summary reports `N providers, M ok, K failed`.

---

## 9. Inbox aging — `Effort: Small`

**Status:** Partially implemented. Awaiting-reply items get aging boosts in retrieve (Step 4): +15 at 2h, +30 at 8h, +50 at 24h, +70 at 48h+. But general unprocessed inbox items do NOT get rescored — they keep their original urgency indefinitely.

Items in `~/.xgh/inbox/` that are older than N hours but unprocessed should have their `urgency_score` bumped automatically. Extend the aging boost to all inbox item types in the analyze step.

---

## 10. `/xgh-release-notes` — `Effort: Medium`

**Status:** Not started. No skill, no command, no changelog generation logic.

Given a Jira fix version or a date range: pull all closed tickets, merged PRs, and relevant Slack decisions. Synthesize a changelog grouped by category (features, fixes, infra). Useful right before a release cut.

---

---

## 11. Trigger engine (IFTTT for devs) — `Effort: Large`

**Status:** Brainstorming

Every provider is a source (IF) and potentially a target (THEN). When the analyze step classifies an inbox item, evaluate it against user-defined trigger rules. If matched, execute actions — post to Slack, create issues, dispatch agents, pause deployments, send DMs.

Examples: P0 created → alert #incidents. PR stale >24h → DM reviewer. Sentry spike → pause Vercel. Figma updated → create Jira ticket. Agent finishes → create PR. Build breaks → dispatch `/xgh-investigate`.

The `fetch.sh` contract is read-only today. Add a `push.sh` contract for write-back actions. Triggers stored in `~/.xgh/triggers/`.

---

*Added: 2026-03-20 | Assessed: 2026-03-20*
