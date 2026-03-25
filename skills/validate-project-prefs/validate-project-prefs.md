---
name: xgh:validate-project-prefs
description: "Use when checking that skills read PR workflow values from config/project.yaml instead of hardcoding reviewer logins, repo names, or merge methods; and to audit all 11 preference domains, lib/preferences.sh health, hook ordering, and cross-domain dependencies."
---

# xgh:validate-project-prefs — Preference Compliance Checker

Scan skill files for hardcoded PR workflow values that should be read from `config/project.yaml`, then audit domain coverage, library health, hook ordering, and cross-domain dependencies.

## Checks

Run these grep patterns against `skills/` (excluding `_shared/references/providers/` and this skill):

### 1. Hardcoded reviewer logins

```bash
grep -rn "copilot-pull-request-reviewer" skills/ --include="*.md" \
  | grep -v "_shared/references/providers/" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches. **Fail:** list file:line for each match.

### 2. Hardcoded repo detection

```bash
grep -rn "gh repo view --json nameWithOwner" skills/ --include="*.md" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches (should use `load_pr_pref repo`). **Fail:** list file:line.

### 3. Inline provider profiles

```bash
grep -rn "reviewer_bot:" skills/ --include="*.md" \
  | grep -v "_shared/references/providers/" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches. **Fail:** list file:line.

### 4. Missing project.yaml read (warning only)

For skills that mention `--repo`, `--reviewer`, or `--merge-method` in their usage:
```bash
for skill in skills/ship-prs/ship-prs.md skills/watch-prs/watch-prs.md skills/review-pr/review-pr.md; do
  if ! grep -q "load_pr_pref\|project\.yaml" "$skill"; then
    echo "WARN: $skill mentions PR flags but does not reference load_pr_pref or project.yaml"
  fi
done
```

### 5. Preference domain coverage (11 domains)

Check that `config/project.yaml` has all 11 required domains under `preferences:`:

```bash
REQUIRED_DOMAINS="pr dispatch superpowers design agents pair_programming vcs scheduling notifications retrieval testing"
PRESENT_DOMAINS="$(yq -r '.preferences | keys | .[]' config/project.yaml 2>/dev/null || true)"
MISSING=""
for domain in $REQUIRED_DOMAINS; do
  if ! printf '%s\n' "$PRESENT_DOMAINS" | grep -qx "$domain"; then
    MISSING="$MISSING $domain"
  fi
done
if [ -z "$MISSING" ]; then
  echo "PASS: all 11 domains present"
else
  echo "FAIL: missing domains:$MISSING"
fi
```
**Pass:** all 11 domains found. **Fail:** list missing domain names.

### 6. lib/preferences.sh health (11 loader functions)

Check that `lib/preferences.sh` exists and declares all 11 loader functions:

```bash
PREFS_FILE="lib/preferences.sh"
if [ ! -f "$PREFS_FILE" ]; then
  echo "FAIL: lib/preferences.sh does not exist"
else
  REQUIRED_LOADERS="load_pr_pref load_dispatch_pref load_superpowers_pref load_design_pref load_agents_pref load_pair_programming_pref load_vcs_pref load_scheduling_pref load_notifications_pref load_retrieval_pref load_testing_pref"
  MISSING_LOADERS=""
  for fn in $REQUIRED_LOADERS; do
    if ! grep -q "${fn}()" "$PREFS_FILE"; then
      MISSING_LOADERS="$MISSING_LOADERS $fn"
    fi
  done
  if [ -z "$MISSING_LOADERS" ]; then
    echo "PASS: all 11 loader functions declared"
  else
    echo "FAIL: missing loaders:$MISSING_LOADERS"
  fi
fi
```
**Pass:** file exists and all 11 `load_*_pref()` functions are declared. **Fail:** file missing or list missing function names.

### 7. Hook ordering (coexistence contract)

Check `.claude/settings.json` for required hook registrations:

```bash
SETTINGS=".claude/settings.json"

# Check PreToolUse: first Bash-matcher hook references pre-tool-use-preferences
if python3 -c "
import json, sys
data = json.load(open('$SETTINGS'))
hooks = data.get('hooks', {})
pre = hooks.get('PreToolUse', [])
bash_hooks = [h for h in pre if h.get('matcher') == 'Bash']
if bash_hooks:
    first_cmd = bash_hooks[0].get('hooks', [{}])[0].get('command', '')
    sys.exit(0 if 'pre-tool-use-preferences' in first_cmd else 1)
else:
    sys.exit(2)
" 2>/dev/null; then
  echo "PreToolUse: PASS"
elif [ $? -eq 2 ]; then
  echo "PreToolUse: WARN (no Bash-matcher hook registered)"
else
  echo "PreToolUse: FAIL (first Bash hook does not reference pre-tool-use-preferences)"
fi

# Check SessionStart: last hook references session-start-preferences
if python3 -c "
import json, sys
data = json.load(open('$SETTINGS'))
hooks = data.get('hooks', {})
ss = hooks.get('SessionStart', [])
if ss:
    last_cmd = ss[-1].get('hooks', [{}])[-1].get('command', '')
    sys.exit(0 if 'session-start-preferences' in last_cmd else 1)
else:
    sys.exit(2)
" 2>/dev/null; then
  echo "SessionStart: PASS"
elif [ $? -eq 2 ]; then
  echo "SessionStart: WARN (hook type not yet registered)"
else
  echo "SessionStart: FAIL (last hook does not reference session-start-preferences)"
fi

# Check PostCompact: has post-compact-preferences registered
if python3 -c "
import json, sys
data = json.load(open('$SETTINGS'))
hooks = data.get('hooks', {})
pc = hooks.get('PostCompact', [])
if pc:
    cmds = [h.get('command', '') for entry in pc for h in entry.get('hooks', [])]
    sys.exit(0 if any('post-compact-preferences' in c for c in cmds) else 1)
else:
    sys.exit(2)
" 2>/dev/null; then
  echo "PostCompact: PASS"
elif [ $? -eq 2 ]; then
  echo "PostCompact: WARN (hook type not yet registered)"
else
  echo "PostCompact: FAIL (post-compact-preferences not found in PostCompact hooks)"
fi
```
**Pass:** all three hook types correctly wired. **Warn (⚠️):** hook type not yet registered. **Fail:** hook type registered but ordering/naming is wrong.

### 8. Cross-domain dependency check

Verify that `load_dispatch_pref` in `lib/preferences.sh` references `load_pr_pref` (the repo delegation pattern):

```bash
if [ ! -f "lib/preferences.sh" ]; then
  echo "SKIP: lib/preferences.sh does not exist (see check 6)"
elif grep -A 20 "load_dispatch_pref()" lib/preferences.sh | grep -q "load_pr_pref"; then
  echo "PASS: load_dispatch_pref references load_pr_pref"
else
  echo "FAIL: load_dispatch_pref does not reference load_pr_pref (cross-domain delegation missing)"
fi
```
**Pass:** dependency found. **Fail:** delegation pattern missing.

## Output format

```
## 🐴🤖 xgh validate-project-prefs

| Check | Status | Details |
|-------|--------|---------|
| Hardcoded reviewer logins | ✅ / ❌ | file:line matches |
| Hardcoded repo detection | ✅ / ❌ | file:line matches |
| Inline provider profiles | ✅ / ❌ | file:line matches |
| Missing project.yaml read | ✅ / ⚠️ | skill files without reference |
| Domain coverage (11/11) | ✅ / ❌ | missing: vcs scheduling notifications retrieval testing |
| preferences.sh health (11 loaders) | ✅ / ❌ | missing loaders or file absent |
| Hook ordering contract | ✅ / ⚠️ / ❌ | PreToolUse ✅  SessionStart ⚠️  PostCompact ⚠️ |
| Cross-domain dependencies | ✅ / ❌ | load_dispatch_pref → load_pr_pref |
```
