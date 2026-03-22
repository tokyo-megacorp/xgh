# Codex Global Agent Instructions

Universal standards that apply to every repo and every task. Project-specific
instructions are in the repo's AGENTS.md — read that too.

---

## Core Discipline

**Test before marking done.** Always run the test command from your task. If none
was given, look for a test command in the repo's AGENTS.md. If still none, ask
before proceeding — never skip verification silently.

**Scope discipline.** Modify only the files explicitly mentioned in your task. If
you discover a related issue elsewhere, note it in your output — do not fix it.
Run `git diff --name-only` before committing to verify scope.

**Never guess on ambiguity.** If the task is unclear about what to do, what files
to touch, or what success looks like — stop and surface the ambiguity in your
output. Do not guess and proceed.

**Commit every logical unit.** Don't let work accumulate uncommitted. One commit
per logical change. If the task spans multiple files or concerns, commit each
separately where it makes sense.

---

## Self-Check Before Marking Complete

Run through this before reporting done:

1. Did the test command pass? (show the last 5 lines of output)
2. Does `git diff --name-only` show only the files you were meant to touch?
3. Is the commit message in the correct format? (`<type>: <description>`)
4. Did you note any ambiguities or adjacent issues you found but didn't fix?

---

## Commit Format

```
<type>: <description>

Types: feat, fix, docs, refactor, test, chore
```

- One line, imperative mood, under 72 characters
- No period at the end
- Examples: `fix: handle null user in auth middleware`, `feat: add retry logic to codex-driver`

---

## What Never To Do

- `git reset --hard`, `git push --force`, `git clean -f` — destructive, never
- Modify auto-generated files directly (check for "do not edit" comments at top)
- Commit secrets, credentials, or `.env` files
- Touch files outside your stated scope, even if they have obvious issues
- Silently swallow errors — always surface failures in your output
- Assume a test passes without running it

---

## Reporting Standards

Every task output must include:

- **Files changed** — list with one-line summary per file
- **Verification** — test command run + exit code + last 5 lines
- **Scope check** — `git diff --name-only` output
- **Commit(s)** — SHA + message for each commit made
- **Flags** — any ambiguity encountered, adjacent issues noted but not fixed

---

## Handling Failure

If a step fails:
1. Report the exact error (last 20 lines of output)
2. State what you tried
3. Do not retry automatically more than once with the same approach
4. Surface clearly: what worked, what didn't, what needs human judgment
