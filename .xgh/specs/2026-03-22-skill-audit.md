# xgh Skill Audit — Consolidated Improvement Plan

**Date:** 2026-03-22
**Auditor:** Claude Opus 4.6
**Skills audited:** 31

---

## Executive Summary

The xgh skill library is generally well-structured. Descriptions follow the "This skill should be used when..." pattern consistently, procedural content is clear, and most skills provide enough context for Claude to execute autonomously. However, three systemic issues stand out:

1. **Duplicated boilerplate across skills (~350 words each):** The "Preamble -- Execution mode" block is copy-pasted verbatim into 7 skills (codex, collab, gemini, implement, investigate, opencode, track). The "Project Resolution" Python code block is duplicated in 3 skills (architecture, index, test-builder). The "MCP Auto-Detection" pattern is copy-pasted into 5 skills with only the degradation rules varying. This is ~3,550 words of duplicated content across the library.

2. **CSO anti-pattern in descriptions:** 8 skills have descriptions exceeding 50 words that summarize the workflow instead of focusing on trigger phrases. The description field should be lean (routing hints for Claude's skill selector), not a mini-abstract.

3. **No references/ directories exist anywhere:** Zero skills use progressive disclosure. Several skills over 2,000 words (codex: 2,254, implement: 2,970, init: 2,498, retrieve: 2,364, test-builder: 2,330, investigate: 2,214) inline large code blocks and reference tables that should live in `references/`.

**Recommended priority:** Fix duplication first (biggest bang-for-effort), then trim descriptions, then extract reference material.

---

## Systemic Issues (affect multiple skills)

### S1: Preamble -- Execution mode duplication

**Affected:** codex, collab, gemini, implement, investigate, opencode, track (7 skills)
**Waste:** ~350 words x 7 = ~2,450 duplicated words
**Fix:** Extract to `skills/_shared/references/execution-mode-preamble.md`. Each skill includes a one-liner: "Run the execution mode preamble from `skills/_shared/references/execution-mode-preamble.md`."

### S2: Project Resolution code duplication

**Affected:** architecture, index, test-builder (3 skills)
**Waste:** ~200 words x 3 = ~600 duplicated words of identical Python code
**Fix:** Extract to `skills/_shared/references/project-resolution.md`. Skills reference it by name.

### S3: MCP Auto-Detection boilerplate

**Affected:** briefing, design, implement, investigate, profile (5 skills)
**Content:** Identical preamble + per-skill degradation rules
**Fix:** Extract the common detection protocol to `skills/_shared/references/mcp-auto-detection.md`. Each skill keeps only its specific degradation rules inline.

### S4: CSO anti-pattern in descriptions

**Affected:** ask, babysit-prs, calibrate, copilot-pr-review, deep-retrieve, knowledge-handoff, seed, test-builder (8 skills)
**Issue:** Description field summarizes the workflow instead of being a pure routing hint. The second half of each description (after the trigger phrases) describes internal steps.
**Fix:** Trim descriptions to ~30-40 words max. Move workflow summary to the skill body's first paragraph.

### S5: Missing references/ directories

**Affected:** All 31 skills (none use progressive disclosure)
**Issue:** Large code blocks, lookup tables, and schema definitions are inlined. Skills over 2,000 words would benefit from extracting reference material.
**Fix:** Create `references/` directories for skills with >2,000 words and extract: code snippets >10 lines, lookup tables, schema definitions, template examples.

### S6: Second-person "you" usage

**Affected:** 12 skills (ask, briefing, codex, collab, command-center, copilot-pr-review, curate, implement, init, knowledge-handoff, seed, track)
**Issue:** Ranges from 1-7 occurrences. Most are in rationalization tables or user-facing output templates (acceptable). A few are genuine style violations (init: "You can skip this", codex: "if you can write").
**Fix:** Audit each occurrence. Replace imperative-addressable ones with infinitive form. Leave rationalization tables and quoted output as-is.

### S7: Missing error handling sections

**Affected:** 22 skills lack explicit error handling (analyze, ask, briefing, calibrate, codex, collab, command-center, curate, deep-retrieve, design, doctor, implement, index, investigate, knowledge-handoff, opencode, pr-context-bridge, retrieve, schedule, seed, test-builder, todo-killer)
**Note:** Not all skills need formal error handling. Pipeline skills (retrieve, analyze, deep-retrieve) and complex orchestrators (implement, investigate, command-center) should have it. Simple skills like ask and curate can get by without.
**Fix:** Add error handling to at minimum: retrieve, analyze, deep-retrieve, implement, investigate, command-center, schedule.

### S8: Missing anti-patterns/common mistakes sections

**Affected:** 24 skills lack anti-patterns or pitfalls sections
**Present in:** babysit-prs, codex, copilot-pr-review, design, gemini, opencode, seed (7 skills)
**Fix:** Add common mistakes sections to skills where agents commonly go wrong: implement (scope creep), init (incomplete setup), retrieve (cursor corruption), analyze (dedup failures), track (invalid config).

---

## Per-Skill Findings

### analyze
- **Words:** 1,379
- **Description:** good -- starts with "This skill should be used when...", includes trigger phrases (/xgh-analyze, CronCreate scheduler, .urgent file)
- **Style:** pass -- no "you should" violations
- **Disclosure:** good -- word count is within range
- **Content gaps:** No error handling section. No common mistakes section for dedup failures or inbox parsing issues.
- **Other:** Has scheduler nudge and output discipline (good). Has 1 @-link but it's content reference (@mention), not file include.
- **Priority:** low

### architecture
- **Words:** 1,213
- **Description:** good -- includes trigger phrases ("analyze architecture", "show architecture", "how are the modules connected", "map the codebase")
- **Style:** pass
- **Disclosure:** good -- within range. Contains duplicated Project Resolution code block (~200 words).
- **Content gaps:** None significant. Well-structured with stack-specific analysis sections.
- **Other:** Good artifact availability table.
- **Priority:** low (fix Project Resolution duplication in S2)

### ask
- **Words:** 811
- **Description:** needs-work -- 55 words, second half summarizes workflow ("Teaches tiered query routing -- when to use lossless-claude semantic search vs context tree BM25 vs both -- with query refinement patterns for maximum recall")
- **Style:** minor -- 5 "you" occurrences but mostly in instructional context ("would YOU find this by searching?" in curate-referenced text)
- **Disclosure:** good -- lean file
- **Content gaps:** None. Clear tier system with examples.
- **Other:** Well-written exemplar for query routing. Good scoring formula.
- **Priority:** low (trim description only)

### babysit-prs
- **Words:** 1,890
- **Description:** needs-work -- 68 words, CSO anti-pattern. The phrase "Watches a batch of GitHub PRs through Copilot review cycles -- polls review status, dispatches fix agents for new comments, merges when clean, re-requests when stale, resolves merge conflicts, and terminates when all PRs are merged" summarizes the entire workflow.
- **Style:** pass
- **Disclosure:** good -- within range. Could extract the Agent Dispatch Guidelines table.
- **Content gaps:** None. Thorough state machine with clear decision branches.
- **Other:** Has Known Pitfalls section (good). Has @copilot warnings (necessary, not context-burning).
- **Priority:** medium (trim description)

### briefing
- **Words:** 1,087
- **Description:** good -- includes trigger phrases (/xgh-briefing, compact, focus, "morning briefing", "session summary")
- **Style:** minor -- 5 "you" occurrences. The `gh` commands use `@me` (legitimate).
- **Disclosure:** good -- within range
- **Content gaps:** None. Good multi-mode support (compact, focus, pre-meeting).
- **Other:** Has MCP Detection block (S3 candidate), scheduler nudge, rationalization table, output discipline. Well-rounded skill.
- **Priority:** low

### calibrate
- **Words:** 346
- **Description:** needs-work -- 53 words, CSO anti-pattern. Summarizes the full workflow ("pulls sample pairs from lossless-claude workspace memory, evaluates for semantic duplication, computes F1 scores at multiple thresholds, and offers to update analyzer.dedup_threshold")
- **Style:** pass
- **Disclosure:** good -- very lean
- **Content gaps:** HIGH. At 346 words this is the thinnest skill. Missing: how to interpret F1 results, what threshold ranges are typical, what to do if calibration fails, sample size guidance. Claude would need to guess significantly.
- **Other:** No error handling, no common mistakes.
- **Priority:** high (content gaps -- needs more procedural detail)

### codex
- **Words:** 2,254
- **Description:** good -- includes trigger phrases ("dispatch to codex", "run codex", "codex exec", "codex review", "use codex for", "send to codex")
- **Style:** minor -- 1 "you" occurrence in session mode guidance
- **Disclosure:** needs-work -- duplicated Preamble (~350 words, S1). Input Parsing section has large code-like blocks. At 2,254 words, extracting the Preamble alone brings it under 2,000.
- **Content gaps:** None. Has Anti-Patterns section. Good prompt crafting guidance.
- **Other:** Has "How to dispatch" warning box (critical content, well-placed).
- **Priority:** medium (extract Preamble)

### collab
- **Words:** 1,360
- **Description:** good -- includes trigger phrase (/xgh-collab, "multi-agent collaboration workflows")
- **Style:** minor -- 7 "you" occurrences. Some are in Rules section and workflow descriptions.
- **Disclosure:** needs-work -- duplicated Preamble (~350 words, S1). Without Preamble, the skill is ~1,000 words which is lean.
- **Content gaps:** Workflow Templates section is thin -- lists template names but doesn't explain when each applies. Could benefit from a decision tree.
- **Other:** Good message protocol documentation. Agent Registry is well-structured.
- **Priority:** medium (extract Preamble, flesh out Workflow Templates)

### command-center
- **Words:** 983
- **Description:** good -- includes trigger phrases (/xgh-command-center, "open command center", "global view", "orchestrate")
- **Style:** minor -- 6 "you" occurrences
- **Disclosure:** good -- within range
- **Content gaps:** Step 3 (Triage Loop) has three modes but `auto_dispatch` lacks detail on how dispatch decisions are made. Would benefit from a dispatch decision matrix.
- **Other:** Has rationalization table. Good multi-mode support (pulse, morning, dispatch).
- **Priority:** low

### config
- **Words:** 639
- **Description:** good -- includes trigger phrases (/xgh-config, "edit config", "configure project", "add project to xgh")
- **Style:** pass
- **Disclosure:** good -- lean
- **Content gaps:** None significant. Clear subcommand structure.
- **Other:** Has error handling (good). Complete YAML validation rules.
- **Priority:** low -- well-written, lean skill

### copilot-pr-review
- **Words:** 1,581
- **Description:** needs-work -- 52 words, slightly over. The workflow summary at the end ("Encodes all Copilot API pitfalls (bot suffix, delegation vs review, re-review cycle)") could be trimmed.
- **Style:** pass -- "you" occurrences are in warnings about @copilot behavior (legitimate)
- **Disclosure:** good -- within range. Known Pitfalls Reference is 2.3KB but worth keeping inline since it's critical safety content.
- **Content gaps:** None. Thorough coverage of Copilot API quirks.
- **Other:** EXEMPLAR skill. Has: Known Pitfalls (comprehensive), Error Handling table, clear command structure, safety warnings where needed. The "Two Copilot Systems" section prevents the most common agent mistake.
- **Priority:** low (trim description slightly)

### curate
- **Words:** 1,453
- **Description:** good -- starts with "This skill should be used when...", includes trigger phrases ("how do I curate this", "store this memory", "save this decision")
- **Style:** minor -- 4 "you" in Quality Checklist ("would YOU find this by searching?") -- acceptable for checklist context
- **Disclosure:** good -- within range. Convention Entries section could be a candidate for extraction if the skill grows.
- **Content gaps:** None. Has Verification section with Common Failure Modes table (good).
- **Other:** Quality Checklist is a strong pattern other skills should emulate.
- **Priority:** low

### deep-retrieve
- **Words:** 807
- **Description:** needs-work -- 51 words, CSO anti-pattern. "Complements xgh:retrieve (fast, cursor-based)" is good context, but the middle section summarizes the scanning workflow.
- **Style:** pass
- **Disclosure:** good -- lean
- **Content gaps:** None significant for what it does. Clear step-by-step with dedup check.
- **Other:** Has output discipline and scheduler nudge (good).
- **Priority:** low (trim description)

### design
- **Words:** 1,959
- **Description:** good -- includes trigger phrases ("implement a Figma design", "build from Figma", "implement this design", "convert design to code")
- **Style:** pass
- **Disclosure:** needs-work -- MCP Auto-Detection block (S3). Phase 1 has 7 substeps that are largely MCP tool call recipes -- good candidates for extraction to `references/figma-mining.md`.
- **Content gaps:** None. Thorough Figma-to-code pipeline.
- **Other:** Has rationalization table. Good Phase 3 (Interactive State Review) -- prevents blind implementation.
- **Priority:** medium (extract MCP detection, consider extracting Figma mining steps)

### doctor
- **Words:** 1,701
- **Description:** good -- includes trigger phrases ("check health", "run diagnostics", "validate pipeline", "check ingest", "is the pipeline running")
- **Style:** pass
- **Disclosure:** needs-work -- Check 2 (Connectivity) is 1.6KB with model server checks, remote inference details -- candidate for `references/connectivity-checks.md`. Check 3b (RTK) is 2.2KB -- candidate for extraction.
- **Content gaps:** None. Comprehensive health check with fix suggestions.
- **Other:** Output format section is well-structured. Good pass/fail with actionable fix suggestions.
- **Priority:** medium (extract connectivity and RTK checks to references)

### gemini
- **Words:** 1,594
- **Description:** good -- includes trigger phrases ("dispatch to gemini", "run gemini", "use gemini for", "send to gemini", "gemini review")
- **Style:** pass
- **Disclosure:** needs-work -- duplicated Preamble (~350 words, S1). Input Parsing section duplicates codex/opencode pattern.
- **Content gaps:** None. Has Anti-Patterns section.
- **Other:** Very similar structure to codex and opencode -- the three dispatch skills are nearly identical in structure with CLI-specific differences. Consider a shared dispatch template.
- **Priority:** medium (S1 Preamble + dispatch unification)

### implement
- **Words:** 2,970
- **Description:** good -- includes trigger phrases ("implement a ticket", "implement this Jira ticket", "build this feature", "start on this task")
- **Style:** pass -- 1 "you" occurrence in example output (legitimate)
- **Disclosure:** needs-work -- LARGEST skill at 2,970 words. Duplicated Preamble (~350 words, S1). MCP Auto-Detection (~150 words, S3). Plan Template (2.1KB) is a strong candidate for `references/implementation-plan-template.md`. Phase 2 MCP tool call recipes could be extracted.
- **Content gaps:** None. Thorough end-to-end pipeline. Good hard gate ("NO IMPLEMENTATION WITHOUT APPROVED DESIGN").
- **Other:** Has rationalization table and Skill Composition table (good cross-reference pattern).
- **Priority:** high (needs progressive disclosure -- extract Preamble, MCP detection, plan template)

### index
- **Words:** 591
- **Description:** good -- includes trigger phrases ("index repo", "index codebase", "scan the codebase")
- **Style:** pass
- **Disclosure:** good -- lean. Contains duplicated Project Resolution code (~200 words, S2).
- **Content gaps:** Thin on what "key files" to identify and what "naming conventions" to extract. Claude would need to infer conventions from the codebase without guidance on what to look for.
- **Other:** Simple, focused skill. Good completion step with lossless-claude storage.
- **Priority:** low (fix S2 duplication, minor content gaps)

### init
- **Words:** 2,498
- **Description:** good -- includes trigger phrases (/xgh-init, "set up xgh", "initialize xgh", "get started")
- **Style:** minor -- 3 "you can/should" violations ("You can skip this and do it later")
- **Disclosure:** needs-work -- at 2,498 words with many substeps. Step 0 alone has 9 substeps (0a-0i) + cleanup + migration. Bootstrap steps are reference material. Step 7a (AGENTS.md generation) is complex. Extract to `references/bootstrap-steps.md` and `references/agents-md-generation.md`.
- **Content gaps:** None. Thorough onboarding flow with error handling and composability.
- **Other:** Has error handling and composability sections (good). The `@AGENTS.md` and `@reference` patterns in init are legitimate -- they describe what to write to files, not Claude includes.
- **Priority:** high (needs progressive disclosure)

### investigate
- **Words:** 2,214
- **Description:** good -- includes trigger phrases ("investigate a bug", "debug this issue", "find root cause", "investigate this Slack thread")
- **Style:** pass
- **Disclosure:** needs-work -- duplicated Preamble (~350 words, S1). MCP Auto-Detection (~150 words, S3). Report Template (1.3KB) could go to `references/investigation-report-template.md`.
- **Content gaps:** None. Excellent debug methodology with hard gates ("After 3 failed hypotheses, STOP") and Iron Law ("NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST").
- **Other:** EXEMPLAR for Iron Laws and hard gates. Rationalization table present.
- **Priority:** medium (extract Preamble, MCP detection, report template)

### knowledge-handoff
- **Words:** 896
- **Description:** needs-work -- 52 words, CSO anti-pattern. "Generates a structured handoff summary on branch merge so the next developer gets full context -- patterns, gotchas, key files, warnings -- without meetings" summarizes the workflow.
- **Style:** minor -- 2 "you" in rationalization table (acceptable)
- **Disclosure:** good -- lean
- **Content gaps:** Step 2 ("Analyze affected files") is very thin -- just "Review changed files". Could use guidance on what to extract from diffs.
- **Other:** Has Iron Law and Rationalization Table (good). Good composability section.
- **Priority:** low (trim description, flesh out Step 2)

### opencode
- **Words:** 1,413
- **Description:** good -- includes trigger phrases ("dispatch to opencode", "run opencode", "opencode exec", "opencode review", "use opencode for", "send to opencode")
- **Style:** pass
- **Disclosure:** needs-work -- duplicated Preamble (~350 words, S1). Nearly identical structure to codex and gemini.
- **Content gaps:** None. Has Anti-Patterns section.
- **Other:** See gemini notes -- dispatch skill unification opportunity.
- **Priority:** medium (S1 Preamble + dispatch unification)

### pr-context-bridge
- **Words:** 970
- **Description:** good -- includes trigger phrases ("capture PR reasoning", "document this PR", "store PR context")
- **Style:** pass
- **Disclosure:** good -- lean
- **Content gaps:** Author Flow Phase 1 is thorough. Reviewer Flow is well-structured. No significant gaps.
- **Other:** Has Iron Law and Rationalization Table (good). Clean skill.
- **Priority:** low

### profile
- **Words:** 2,018
- **Description:** good -- includes trigger phrase ("engineer capacity, assignment, or estimation")
- **Style:** pass
- **Disclosure:** needs-work -- at 2,018 words. Output Format sections (3 of them, each ~0.5-0.9KB) with markdown template examples are candidates for `references/profile-output-templates.md`. MCP Auto-Detection block (S3).
- **Content gaps:** None. Thorough statistical methodology.
- **Other:** Has Error Handling and Data Quality Notes (good).
- **Priority:** medium (extract output templates and MCP detection)

### retrieve
- **Words:** 2,364
- **Description:** good -- includes trigger phrases (/xgh-retrieve, CronCreate scheduler)
- **Style:** pass
- **Disclosure:** needs-work -- at 2,364 words. Step 2 (Scan Slack channels) is 2.8KB. Step 2b (MCP Provider Dispatch) is 2.3KB. Step 4 (Urgency scoring) is 1.6KB. These are reference-material candidates. Architecture Note section (0.7KB) explaining provider-based retrieval could go to references.
- **Content gaps:** None. Very thorough pipeline with cursor management.
- **Other:** Has output discipline and scheduler nudge (good). Missing error handling section -- this is a critical pipeline skill that runs every 5 minutes and should have explicit error recovery.
- **Priority:** high (needs progressive disclosure + error handling)

### schedule
- **Words:** 1,098
- **Description:** good -- includes trigger phrases (/xgh-schedule, "check, pause, resume, or manage the scheduler", "skill mode preferences")
- **Style:** pass
- **Disclosure:** good -- within range
- **Content gaps:** None significant. Clear subcommand structure.
- **Other:** Has output discipline (good). Good trigger evaluation integration.
- **Priority:** low

### seed
- **Words:** 706
- **Description:** needs-work -- 70 words (highest of all), CSO anti-pattern. "Writes a project-context brief into .gemini/skills/xgh/, .agents/skills/xgh/, .opencode/skills/xgh/ so dispatched agents have project memory pre-loaded" summarizes the output format in detail.
- **Style:** minor -- 1 "you" occurrence
- **Disclosure:** good -- lean
- **Content gaps:** None. Has Anti-Patterns section.
- **Other:** Clean, focused skill.
- **Priority:** low (trim description)

### test-builder
- **Words:** 2,330
- **Description:** needs-work -- 57 words, CSO anti-pattern. "Generates and executes tailored test suites from architectural analysis -- reads module boundaries, public surfaces, and integration points from memory to produce a structured manifest of test flows" describes the internal process.
- **Style:** pass
- **Disclosure:** needs-work -- duplicated Project Resolution code (~200 words, S2). Phase 1 Step 5 manifest generation is 1.8KB with Executor Kinds Reference (0.5KB) and Assertion Types Reference (0.6KB) -- prime extraction candidates for `references/test-manifest-schema.md`. Phase 2 Run section's Manifest Loading & Validation is 2.4KB.
- **Content gaps:** None. Thorough two-phase (init + run) approach.
- **Other:** Highest cross-reference count (17 xgh: refs) -- healthy interconnection.
- **Priority:** high (needs progressive disclosure + S2 duplication fix)

### todo-killer
- **Words:** 836
- **Description:** good -- includes trigger phrases ("kill todos", "fix todos", "clean up comments")
- **Style:** pass
- **Disclosure:** good -- lean
- **Content gaps:** Phase 2 (Fix) is thin. "2c. Fix" just says to fix without guidance on safe patterns (e.g., when to refactor vs just remove the comment, when to create a ticket instead of fixing).
- **Other:** Good integration with patterns.yaml. Has "When to Skip" section.
- **Priority:** low (flesh out fix guidance)

### track
- **Words:** 1,910
- **Description:** good -- includes trigger phrases ("add project", "track project", "monitor new project")
- **Style:** minor -- 6 "you" occurrences
- **Disclosure:** needs-work -- duplicated Preamble (~350 words, S1). Step 1 (Collect project details) is 2.6KB -- it's a giant interactive prompt list that could be extracted to `references/project-onboarding-prompts.md`.
- **Content gaps:** None. Thorough onboarding flow with connectivity validation.
- **Other:** Has trigger suggestion step (good forward-looking feature).
- **Priority:** medium (extract Preamble, consider extracting prompt list)

### trigger
- **Words:** 890
- **Description:** good -- includes trigger phrases (/xgh-trigger, "list triggers", "test triggers", "silence noisy triggers", "view trigger firing history")
- **Style:** pass
- **Disclosure:** good -- lean. The Trigger Evaluation Logic (reference) section is explicitly labeled as reference material but kept inline. At 890 words total, this is acceptable.
- **Content gaps:** None. Good reference section covering matching, cooldown, dedup, and template variables.
- **Other:** Has error handling.
- **Priority:** low

---

## Exemplar Skills (worth emulating)

1. **copilot-pr-review** -- Best-in-class for safety-critical skills. Has Known Pitfalls with numbered entries, Error Handling table, clear "Two Copilot Systems" disambiguation. Other skills that interact with external APIs should follow this pattern.

2. **curate** -- Best-in-class for verification. Has Common Failure Modes table, Quality Checklist, and Verification section with minimum standards. Skills that write to storage (analyze, retrieve, knowledge-handoff) should add similar verification.

3. **investigate** -- Best-in-class for methodology enforcement. Iron Law, hard gates ("After 3 failed hypotheses, STOP"), and systematic hypothesis verification. Skills with complex decision trees should follow this pattern.

4. **config** -- Best-in-class for lean skills. 639 words, complete subcommand coverage, error handling, no waste.

---

## Recommended Fix Order

### Phase 1: Deduplicate (high impact, moderate effort)

1. **Extract Preamble -- Execution mode** to shared reference (saves ~2,450 words across 7 skills)
2. **Extract Project Resolution** to shared reference (saves ~600 words across 3 skills)
3. **Extract MCP Auto-Detection** protocol to shared reference (saves ~500 words across 5 skills)
4. **Unify dispatch skills** (codex, gemini, opencode) -- create a dispatch template with CLI-specific overrides

### Phase 2: Trim descriptions (high impact, low effort)

5. **Trim 8 over-long descriptions** (babysit-prs, seed, test-builder, ask, calibrate, copilot-pr-review, deep-retrieve, knowledge-handoff) -- move workflow summaries from description to body

### Phase 3: Progressive disclosure (medium impact, moderate effort)

6. **implement** -- extract plan template, MCP detection
7. **retrieve** -- extract Slack scanning, provider dispatch, urgency scoring
8. **test-builder** -- extract manifest schema, assertion types, executor kinds
9. **init** -- extract bootstrap steps, AGENTS.md generation
10. **doctor** -- extract connectivity checks, RTK checks
11. **profile** -- extract output format templates
12. **track** -- extract project onboarding prompts

### Phase 4: Content gaps (medium impact, low effort)

13. **calibrate** -- add procedural detail (currently 346 words, thinnest skill)
14. **retrieve** -- add error handling section
15. **analyze** -- add common mistakes section
16. **collab** -- flesh out Workflow Templates
17. **knowledge-handoff** -- flesh out Step 2 (affected file analysis)
18. **todo-killer** -- flesh out Phase 2 fix guidance

### Phase 5: Style cleanup (low impact, low effort)

19. **Fix "you should/can/must" patterns** in init (3), codex (1)
20. **Fix casual "you" usage** in collab (7), track (6), command-center (6), briefing (5), ask (5)

---

## Metrics Summary

| Metric | Count |
|--------|-------|
| Skills audited | 31 |
| Skills with good descriptions | 23 |
| Skills with CSO anti-pattern descriptions | 8 |
| Skills with duplicated Preamble | 7 |
| Skills with duplicated Project Resolution | 3 |
| Skills with MCP Auto-Detection boilerplate | 5 |
| Skills needing progressive disclosure | 7 (>2,000 words) |
| Skills with anti-patterns/pitfalls section | 7 |
| Skills with error handling | 9 |
| Skills with rationalization tables | 7 |
| Skills with output discipline | 10 |
| Skills with "you" style violations | 12 (most minor) |
| Thinnest skill | calibrate (346 words) |
| Largest skill | implement (2,970 words) |
| Estimated duplicated words | ~3,550 |
