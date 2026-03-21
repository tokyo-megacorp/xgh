---
title: Safe Codex Platform Seeding
date: 2026-03-21
status: approved
reviewed-by: Codex v0.116.0 (2 rounds)
tags: [codex, seeding, idempotent, registry-driven, global-config]
---

# Safe Codex Platform Seeding

## Problem

xgh writes to Codex-owned global files (`~/.codex/AGENTS.md`) using raw overwrites, destroying user pre-existing content. `scripts/seed-global-config.sh` was built as an idempotent marker-based solution but has unresolved issues:

1. **P1 bugs** — doesn't expand `~`, doesn't create parent dirs, resolves content file relative to CWD
2. **Not wired in** — neither `/xgh-seed` nor `/xgh-init` call it
3. **No precedence statement** — the three Codex context layers lack documented priority
4. **Name drift** — `.agents/skills/xgh/SKILL.md` has `name: xgh-context` instead of `name: xgh`

## Design

### Section 1: Registry Extension

Add to the `codex` entry in `config/agents.yaml`:

```yaml
codex:
  invocation:
    global_instructions_file: "~/.codex/AGENTS.md"
    global_conventions_template: "templates/codex-global-conventions.md"
    tested_version: "0.116.0"
    # ... existing fields unchanged ...
```

These fields are the single source of truth for per-platform global seeding config.

### Section 2: `seed-global-config.sh` Bug Fixes (P1)

Four fixes before it can be safely wired in:

1. **Tilde expansion** — `TARGET` may arrive as `~/.codex/AGENTS.md`:
   ```bash
   TARGET="${TARGET/#\~/$HOME}"
   ```

2. **Parent dir creation** — target directory may not exist:
   ```bash
   mkdir -p "$(dirname "$TARGET")"
   ```

3. **Content file path** — callers pass repo-root-relative paths like `templates/codex-global-conventions.md` but the script runs from arbitrary working dirs. Calling convention: always use `$(git rev-parse --show-toplevel)/templates/...` to pass absolute paths.

4. **Corrupted marker detection** — if start marker exists but end marker is absent, the script falls through to the update path and can corrupt the file:
   ```bash
   if grep -qF "$START" "$TARGET" && ! grep -qF "$END" "$TARGET"; then
     echo "ERROR: corrupted markers in $TARGET — $START found but $END missing" >&2
     exit 2
   fi
   ```

Exit codes: `0` = success, `1` = content file not found, `2` = corrupted markers.

### Section 3: `scripts/list-seed-targets.sh` (New Helper)

Registry-driven helper that reads `config/agents.yaml` and emits resolved seed targets for each installed agent with `global_instructions_file` set.

```bash
#!/usr/bin/env bash
# list-seed-targets.sh — emit resolved global seeding targets from config/agents.yaml
# Output: one line per target: "<agent_id> <resolved_target_path> <resolved_template_path>"
# Only emits lines for agents that are: (a) installed, (b) have global_instructions_file set

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG="$REPO_ROOT/config/agents.yaml"

python3 - "$CONFIG" "$REPO_ROOT" << 'PY'
import sys, yaml, os, subprocess

config_path, repo_root = sys.argv[1], sys.argv[2]
data = yaml.safe_load(open(config_path))
agents = data.get('agents', {})

for agent_id, entry in agents.items():
    inv = entry.get('invocation', {})
    gf = inv.get('global_instructions_file')
    tmpl = inv.get('global_conventions_template')
    auto_detect = inv.get('auto_detect')
    if not (gf and tmpl and auto_detect):
        continue
    # check binary installed
    result = subprocess.run(['command', '-v', auto_detect], shell=False,
                            capture_output=True, executable='/bin/zsh')
    if result.returncode != 0:
        continue
    resolved_target = os.path.expanduser(gf)
    resolved_template = os.path.join(repo_root, tmpl)
    print(f"{agent_id} {resolved_target} {resolved_template}")
PY
```

Both `/xgh-seed` (Step 3) and `/xgh-init` (Step 0g) call this script and iterate:

```bash
while IFS=' ' read -r agent_id target template; do
  echo "Seeding global config for $agent_id..."
  bash "$REPO_ROOT/scripts/seed-global-config.sh" "$target" "${agent_id}-global-conventions" "$template"
done < <(bash "$REPO_ROOT/scripts/list-seed-targets.sh")
```

Marker name convention: `${agent_id}-global-conventions` (e.g., `codex-global-conventions`).

### Section 4: Layer Precedence Statement

Add to top of `templates/codex-global-conventions.md`:

```markdown
## Layer Precedence

When working on an xgh project, context comes from four layers — read in this order:

| Priority | Layer | File | Authoritative for |
|----------|-------|------|------------------|
| 1 (highest) | Repo rules | `<repo>/AGENTS.md` | Project conventions, test commands, iron laws, what never to do |
| 2 | Platform skill | `.agents/skills/xgh/SKILL.md` | Platform-specific agent conventions, dispatch commands |
| 3 | Live project state | `.agents/skills/xgh/context.md` | Current branch, recent decisions, active focus — **snapshot, may be stale** |
| 4 (baseline) | Global baseline | `~/.codex/AGENTS.md` (this file) | Universal behavior: commit format, scope discipline, self-check |

**Conflict resolution rules:**
- Repo `AGENTS.md` wins for all project-specific matters
- This file (`~/.codex/AGENTS.md`) wins for universal behavior (commit format, self-check protocol)
- When `context.md` conflicts with actual repo files, **trust the repo files** — `context.md` is a generated snapshot and may be stale. Run `/xgh-seed` to refresh it.
```

### Section 5: SKILL.md Ownership Model

Decision: **fully managed by xgh**. xgh owns `.agents/skills/xgh/SKILL.md` completely. Users who need custom additions should create a separate file (e.g., `.agents/skills/xgh/local.md`).

This avoids the frontmatter conflict problem: if the file has frontmatter at the top and user additions anywhere else, marker-based preservation can leave conflicting frontmatter after a name drift fix. Fully managed is cleaner.

Changes to SKILL.md:

1. Fix `name: xgh-context` to `name: xgh` (aligns with directory and loader expectations)
2. No marker wrapping needed — the file is replaced on each `/xgh-seed`
3. Add a comment at top: `<!-- Managed by xgh — do not edit. Run /xgh-seed to refresh. -->`

The seed skill's Step 3 continues to write SKILL.md in full — no change to that logic except the name field.

### Section 6: Partial Failure Semantics

The seeding step in `/xgh-seed` and `/xgh-init` must report per-target status:

```
Global config seeding:
  ✓ codex: ~/.codex/AGENTS.md — updated (section: codex-global-conventions)
  ⚠ gemini: not installed — skipped
  ✗ codex: corrupted markers in ~/.codex/AGENTS.md — manual fix required
    Fix: remove lines between <!-- xgh:begin codex-global-conventions --> and <!-- xgh:end codex-global-conventions --> then re-run /xgh-seed
```

Exit behavior: corrupted marker = warn and skip that target (don't abort the whole seed). Non-zero exit from `seed-global-config.sh` = catch and report per-target, continue with remaining targets.

## Files Changed

| File | Change | Reason |
|------|--------|--------|
| `scripts/seed-global-config.sh` | Tilde expansion, mkdir -p, corrupted marker detection | P1 bug fix |
| `scripts/list-seed-targets.sh` | **New** — reads agents.yaml, emits resolved seed targets | Registry-driven completeness |
| `config/agents.yaml` | Add `global_instructions_file`, `global_conventions_template`, `tested_version` to codex | Registry extension |
| `templates/codex-global-conventions.md` | Add Layer Precedence section (4-row table with conflict rules) | Layer clarity |
| `skills/seed/seed.md` | Add Step: global seeding via list-seed-targets.sh + per-target report | Wire in seeding |
| `skills/init/init.md` | Add step 0g: global seeding (first-run, after agent detection) | Wire in seeding |
| `.agents/skills/xgh/SKILL.md` | Fix name drift (`xgh-context` → `xgh`); add managed-by comment | Naming fix |
| `tests/test-seed.sh` | Add assertions: seed skill mentions global seeding, list-seed-targets.sh exists | Test coverage |
| `tests/test-config.sh` | Add assertion: `tested_version` field present in agents.yaml | Test coverage |
| `README.md` | Update seeding table to include `~/.codex/AGENTS.md` | Docs accuracy |

## Out of Scope

- Gemini, OpenCode `global_instructions_file` values (follow-on — set `tested_version: null` now, wire when validated)
- `CLAUDE.local.md` marker protection (same class of issue, separate feature)
- `detect-agents.sh` full rewrite to be registry-driven (follow-on — binary detection is fine, `global_instructions_file` writability check is separate)

## Test Strategy

1. **`tests/test-config.sh`** — structural assertion: `tested_version` present in agents.yaml
2. **`tests/test-seed.sh`** — skill assertions: seed.md references `list-seed-targets.sh`, `global seeding` step present
3. **Script-level tests for `seed-global-config.sh`:**
   - Case 1: target doesn't exist — created with markers
   - Case 2: target exists, no markers — appended
   - Case 3: target has markers — section replaced only
   - Case 4: corrupted markers (start exists, end missing) — exit 2, error on stderr
   - Case 5: `~` in target path — correctly expanded
4. **Manual smoke test:** run `/xgh-seed`, verify `~/.codex/AGENTS.md` updated idempotently
