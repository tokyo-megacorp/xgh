# obra/superpowers — Test Architecture Analysis
> Research date: 2026-03-21
> Repo: https://github.com/obra/superpowers (101k stars)

---

## Their Test Structure

```
tests/
├── skill-triggering/           ← "does natural language trigger the right skill?"
│   ├── run-test.sh             ← single-skill runner
│   ├── run-all.sh              ← runs all skills in loop
│   └── prompts/
│       ├── systematic-debugging.txt
│       ├── test-driven-development.txt
│       ├── writing-plans.txt
│       ├── dispatching-parallel-agents.txt
│       ├── executing-plans.txt
│       └── requesting-code-review.txt
├── explicit-skill-requests/    ← "does `please use X` work after a long conversation?"
│   ├── run-multiturn-test.sh
│   └── prompts/
├── subagent-driven-dev/        ← workflow integration tests
├── claude-code/                ← platform-specific tests
├── brainstorm-server/          ← component tests
└── opencode/                   ← alternate platform tests
```

---

## The Prompt Test Mechanism

### Skill Triggering (`run-test.sh`)

```bash
# Run Claude with a natural-language prompt (no skill name mentioned)
timeout 300 claude -p "$PROMPT" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --max-turns 3 \
    --output-format stream-json \
    > "$LOG_FILE" 2>&1

# Check if the Skill tool was invoked with the expected skill
SKILL_PATTERN='"skill":"([^"]*:)?'"${SKILL_NAME}"'"'
if grep -q '"name":"Skill"' "$LOG_FILE" && grep -qE "$SKILL_PATTERN" "$LOG_FILE"; then
    echo "✅ PASS: Skill '$SKILL_NAME' was triggered"
fi
```

The check: did `claude -p` produce JSON with `"name":"Skill"` + the right `"skill":"..."` value?

### Multi-Turn Continuity (`run-multiturn-test.sh`)

Uses `claude -p --continue` to simulate a real conversation across turns:
- Turn 1: Start a planning conversation
- Turn 2: Continue with more context
- Turn 3: "subagent-driven-development, please" ← the actual test

Tests the **failure mode** where Claude skips skill invocation after an extended conversation — not just a fresh context. This catches a real degradation that file-linting tests cannot.

---

## The Prompt Files

They are intentionally natural — no skill name, no "please use the X skill":

**`systematic-debugging.txt`**:
```
The tests are failing with this error:
  TypeError: Cannot read property 'value' of undefined
    at parse (src/utils/parser.ts:42:18)
Can you figure out what's going wrong and fix it?
```

**`test-driven-development.txt`**:
```
I need to add a new feature to validate email addresses.
[requirements list]
Can you implement this?
```

**`writing-plans.txt`**:
```
Here's the spec for our new authentication system:
[requirements]
We need to implement this. There are multiple steps involved...
```

The prompt **sounds like a real user**. The test verifies Claude recognizes the situation and invokes the skill on its own — testing the `WHEN` description of each skill.

---

## xgh's Current Tests vs. What's Missing

### What xgh currently tests (`tests/test-trigger.sh`):
- ✅ File existence (skills, commands, hooks, examples)
- ✅ Keyword presence (grep for required strings)
- ✅ Integration wiring (skill A references topic B)

These are **structural tests** — they catch missing files and broken links. Fast to run, zero AI cost.

### What xgh cannot currently test:
- ❌ Does `"what needs my attention?"` trigger `xgh:brief`?
- ❌ Does `"debug this error: ..."` trigger `xgh:investigate`?
- ❌ Does skill triggering still work after 10 conversational turns?
- ❌ Does the skill actually execute its logic coherently?
- ❌ Does the `when:` description in skill frontmatter match real user language?

---

## Recommended Additions for xgh

### Tier 1: Skill Triggering Tests

New directory: `tests/skill-triggering/`

Skills to cover and their trigger prompts:

| Skill | Natural prompt that should trigger it |
|-------|--------------------------------------|
**Selection rationale**: Only skills with natural-language trigger descriptions in their frontmatter. Command-only skills (e.g., `xgh:trigger`, `xgh:schedule`) are excluded — they have no natural-language `TRIGGER when:` text, so a prompt test would always fail by design.

| Skill | Natural prompt (real-user phrasing, not echoing skill description) |
|-------|--------------------------------------|
| `xgh:retrieve` | "I'm starting a session, let's pull in context from my projects" |
| `xgh:analyze` | "I have a bunch of new messages sitting in my inbox, can you go through them and tell me what matters?" |
| `xgh:briefing` | "What needs my attention right now?" |
| `xgh:implement` | "Implement this ticket: https://jira.example.com/PROJ-123" |
| `xgh:investigate` | "Something is crashing in prod. Here's the stack trace: [trace]. Help me debug it." |
| `xgh:track` | "Add my new iOS project to xgh monitoring" |
| `xgh:doctor` | "Is my xgh pipeline healthy?" |
| `xgh:index` | "Index this codebase into memory so you know how it works" |

The runner script is a direct adaptation of obra's `run-test.sh`. xgh-specific notes:
- Skills use `xgh:` namespace: grep pattern `'"skill":"xgh:retrieve"'` or wildcard `'"skill":"([^"]*:)?retrieve"'`
- **Stream-json format must be verified** before finalizing patterns. Run `claude -p "hello" --output-format stream-json` to confirm the Skill tool records as `"name":"Skill"` with `"skill":"..."` in the input block — not nested differently.
- Use `--max-turns 1` for Tier 1 tests: only the first dispatch matters for triggering verification.
- `--plugin-dir "$PLUGIN_DIR"` points to the local repo checkout (development mode). Tests run against the local source, not the installed plugin.
- `--dangerously-skip-permissions` grants unrestricted tool use — run in an isolated directory.

### Tier 2: Multi-Turn Continuity

New file: `tests/skill-triggering/run-multiturn-test.sh`

Tests resilience of skill dispatch after context accumulation (not natural-language recognition).

Test case:
- Turn 1: "I just got 3 slack messages about a prod issue, let me look into it"
- Turn 2: "We've been going through logs for an hour and things are getting complicated"
- Turn 3: "Something is crashing in prod. Here's the stack trace: TypeError at line 42. Help me debug it." ← does `xgh:investigate` still trigger after context accumulation?

### Tier 3 (Future): Behavior Tests

Requires mock inbox fixtures — skip for now. The above two tiers deliver 80% of the value.

---

## Implementation Cost

Low. obra's runner is ~60 lines of bash. Adapting it for xgh:
1. Replace `--plugin-dir "$PLUGIN_DIR"` with xgh plugin path
2. Adjust skill name pattern for `xgh:` namespace
3. Write 8 prompt files (~3 lines each)
4. Add `run-all.sh`

**Cost**: ~8 prompts × 1 turn × ~$0.05 ≈ ~$0.40 per full suite. They should be opt-in — a standalone `tests/skill-triggering/run-all.sh` never called from `test-config.sh`. Run manually when editing skill trigger descriptions.

---

## Key Insight

obra's prompt tests are testing the **`when:` description** of each skill. In Claude Code's skill system, the `when:` field (or the description/trigger conditions in the skill's prose) is what determines if Claude invokes it. Prompt tests are literally unit tests for that metadata — verifying that the natural language→skill mapping actually works at runtime, not just that the file exists.

For xgh, this is especially valuable because xgh skills have rich `TRIGGER when:` descriptions (e.g., `xgh:implement` triggers "when user says implement/build/create/fix + a ticket reference"). A prompt test would catch if that description drifts out of sync with real user language.
