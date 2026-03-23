# Skill Quality TDD Epic — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run every xgh skill through a TDD quality loop — baseline test, fix, verify — achieving consistent quality across all 31 skills.

**Architecture:** Six phases executed sequentially. Phases 1-3 fix systemic issues (deduplication, descriptions, progressive disclosure). Phases 4-5 fix per-skill content gaps and style. Phase 6 runs TDD verification on all skills.

**Tech Stack:** Claude Code plugin skills (markdown), bash tests, GitHub Projects for tracking

**Spec:** `.xgh/specs/2026-03-22-skill-audit.md`

**Tracking:** [GitHub Project: Skill Quality TDD Epic](https://github.com/orgs/extreme-go-horse/projects/1)

---

## Phase Map

| Phase | Issues | Description | Blocked by |
|-------|--------|-------------|------------|
| 1: Deduplicate | #34-#37 | Extract shared references | — |
| 2: Trim descriptions | #38 | Fix CSO anti-pattern (8 skills) | — |
| 3: Progressive disclosure | #39-#45 | Extract references/ (7 skills) | Phase 1 |
| 4: Content gaps | #46-#51 | Flesh out thin skills (6 skills) | — |
| 5: Style cleanup | #52 | Fix "you" patterns (12 skills) | — |
| 6: TDD verification | #53-#59 | Per-skill TDD loops (7 skills) | Phases 1-5 |

**Total: 26 issues, 31 skills covered**

---

## Phase 1: Deduplicate (~3,550 words of shared boilerplate)

### Task 1: Extract Preamble — Execution mode (#34)
### Task 2: Extract Project Resolution (#35)
### Task 3: Extract MCP Auto-Detection (#36)
### Task 4: Unify dispatch skills (#37)

## Phase 2: Trim descriptions

### Task 5: Fix CSO anti-pattern in 8 descriptions (#38)

## Phase 3: Progressive disclosure (7 oversized skills)

### Task 6: implement (2,970 words → <2,000) (#39)
### Task 7: retrieve (2,364 words → <2,000) (#40)
### Task 8: test-builder (2,330 words → <2,000) (#41)
### Task 9: init (2,498 words → <2,000) (#42)
### Task 10: doctor (1,701 words → <1,200) (#43)
### Task 11: profile (2,018 words → <1,500) (#44)
### Task 12: track (1,910 words → <1,200) (#45)

## Phase 4: Content gaps (6 thin/incomplete skills)

### Task 13: calibrate (346 words — thinnest skill) (#46)
### Task 14: retrieve — error handling (#47)
### Task 15: analyze — common mistakes (#48)
### Task 16: collab — workflow templates (#49)
### Task 17: knowledge-handoff — file analysis (#50)
### Task 18: todo-killer — fix guidance (#51)

## Phase 5: Style cleanup

### Task 19: Fix "you" patterns in 12 skills (#52)

## Phase 6: TDD verification (per-skill loops)

### Task 20: config (#53)
### Task 21: schedule (#54)
### Task 22: trigger (#55)
### Task 23: pr-context-bridge (#56)
### Task 24: copilot-pr-review — exemplar (#57)
### Task 25: investigate — exemplar (#58)
### Task 26: curate — exemplar (#59)

---

## Execution Notes

- Each issue is self-contained with TDD steps (RED → GREEN → REFACTOR)
- Use `haiku` for mechanical tasks (description trimming, style fixes)
- Use `sonnet` for content work (progressive disclosure, content gaps)
- Use `opus` for TDD verification (pressure scenario design and evaluation)
- All changes go through PRs (develop is protected)
- Run `bash tests/test-config.sh` after every change
