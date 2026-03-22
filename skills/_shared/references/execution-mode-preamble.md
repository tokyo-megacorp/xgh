# Shared: Execution Mode Preamble

<!-- This file is the single source of truth for the execution mode preamble.
     It is referenced by: codex, collab, gemini, implement, investigate, opencode, track.
     When updating this protocol, update only this file. -->

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('<SKILL_NAME>')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **\<SKILL_LABEL\>** in background (returns summary when done) or interactive? [b/i, default: i]"
- If "b": "Check in with a quick question before starting, or fire-and-forget? [c/f, default: c]"

**Step P3 — Write preference:**
```bash
python3 -c "
import json, os, sys
mode, autonomy = sys.argv[1], sys.argv[2]
path = os.path.expanduser('~/.xgh/prefs.json')
os.makedirs(os.path.dirname(path), exist_ok=True)
try: p = json.load(open(path))
except: p = {}
p.setdefault('skill_mode', {})
entry = {'mode': mode} if mode == 'interactive' else {'mode': mode, 'autonomy': autonomy}
p['skill_mode']['<SKILL_NAME>'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` → use background mode
- contains `--interactive` or `--fg` → use interactive mode
- contains `--checkin` → use check-in autonomy
- contains `--auto` → use fire-and-forget autonomy
- contains `--reset` → run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('<SKILL_NAME>',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** → proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context:
   - **Standard skills:** user's request verbatim, current branch (`git branch --show-current`), recent log (`git log --oneline -5`), any relevant file paths mentioned.
   - **Dispatch-type skills (codex, gemini, opencode):** user's request verbatim, dispatch type, model preference, any relevant file paths mentioned.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply:
   - **Standard skills:** "\<SKILL_LABEL\> running in background — I'll post findings when done."
   - **Dispatch-type skills (codex, gemini, opencode):** "\<SKILL_LABEL\> running in background — I'll post results when done."
5. When agent completes: post a ≤5-bullet summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions):
   - **Standard skills:** user's request verbatim, current branch (`git branch --show-current`), recent log (`git log --oneline -5`), any relevant file paths mentioned.
   - **Dispatch-type skills (codex, gemini, opencode):** user's request verbatim, dispatch type, model preference, any relevant file paths mentioned.
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "\<SKILL_LABEL\> running in background — I'll post results when done."
4. When agent completes: post a ≤5-bullet summary.

---

## Parameter reference

| Placeholder | Meaning | Examples |
|-------------|---------|---------|
| `<SKILL_NAME>` | Key used in `~/.xgh/prefs.json` under `skill_mode` | `codex`, `collab`, `gemini`, `implement`, `investigate`, `opencode`, `track` |
| `<SKILL_LABEL>` | Human-readable label shown in prompts and replies | `Codex dispatch`, `Collab`, `Gemini dispatch`, `Implementation`, `Investigation`, `OpenCode dispatch`, `Track` |
