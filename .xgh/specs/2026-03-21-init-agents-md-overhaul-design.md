# /xgh-init AGENTS.md Overhaul — Design Spec

**Date:** 2026-03-21
**Source:** Codex gpt-5.4 design review session `019d1172`
**Goal:** Make `/xgh-init` generate a kick-ass `AGENTS.md` for any project and wire all AI platforms to it.

---

## New Step 7a — Generate AGENTS.md + Wire Platform Files

### Position
Between Step 7 (Initial Curation) and Step 7b (Scheduler). Always run — not optional.

### Trigger condition
Always run. Only prompt if `AGENTS.md` exists without an xgh-managed marker.

### Architecture scan inputs
- `README.md` / `README.rst` / `README.adoc`
- First package manifest: `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `Gemfile`, `build.gradle`
- Top-level `ls -1` for repo layout
- `.xgh/context-tree/` entries if present

### AGENTS.md sections (generic project)
| Section | Source |
|---------|--------|
| Header (auto-generated marker) | fixed |
| Repo Overview | README |
| Tech Stack | manifest + README |
| Repo Layout | `ls -1` |
| Dev Commands | README / package.json scripts / Makefile |
| Architecture Notes | README + context tree |
| Conventions | README / CONTRIBUTING / context tree |
| Environment | README / `.env.example` |
| Common Pitfalls | README + context tree gotchas |
| *(optional)* Agent Roster | if `agents/` or `config/agents.yaml` exists |
| *(optional)* Automation Map | if `config/triggers.yaml` + `config/workflows/` exist |
| *(optional)* Release/Deploy | if CI config or release scripts exist |

### Platform wiring
| File | Content | Tracked? |
|------|---------|---------|
| `CLAUDE.md` | `@AGENTS.md` thin include | gitignored — local only |
| `GEMINI.md` | `@AGENTS.md` thin include | gitignored — local only |
| `.github/copilot-instructions.md` | minimal stub → AGENTS.md | committed |

### Gitignore additions
```
CLAUDE.md
GEMINI.md
```
Do NOT gitignore `AGENTS.md` or `.github/copilot-instructions.md`.

### Regeneration rules
- xgh-managed marker → re-scan and rewrite silently
- Exists without marker → ask before replacing (default: keep, only wire platform files)
- Missing → create fresh

### Post-wiring
If Codex / Gemini / OpenCode detected → offer `/xgh-seed`.

---

## Critical Bugs Fixed

### Bug 1 — Pre-AGENTS architecture (lines ~100–115)
Init still copies `templates/xgh-instructions.md` → `.xgh/xgh.md` and appends `@.xgh/xgh.md` to `CLAUDE.local.md`. This is the pre-AGENTS model and conflicts with the new pattern. Replace with a note delegating to Step 7a.

### Bug 2 — `slack_user_id` schema mismatch (line ~284)
Profile Python snippet writes `slack_user_id` but live schema everywhere uses `slack_id` (`config/ingest-template.yaml:6`, `skills/doctor/doctor.md:20`, `skills/retrieve/retrieve.md:264`). Fix: rename key.

### Bug 3 — Missing `import os` (line ~279)
Profile snippet calls `os.path.expanduser` without `import os`. Will throw `NameError` at runtime.

---

## Important Improvements

- Remove any `ctx_` / context-mode references from init.md (convention: skill files don't reference context-mode)
- Update Step 8 summary to report AGENTS.md and platform files
- Update intro checklist to include step 7a
- Update Composability table
- Nice-to-have: end init with a first `/xgh-brief` so onboarding has visible output
