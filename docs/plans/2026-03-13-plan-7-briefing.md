# Session Briefing Skill Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `xgh:briefing` — an intelligent session briefing skill that aggregates Slack, Jira, GitHub, Gmail, Calendar, Figma, and xgh team memory into a prioritized executive summary with a suggested focus, triggered on session start or on demand via `/xgh-briefing`.

**Architecture:** The skill is a markdown file (`skills/briefing/briefing.md`) with a corresponding command (`commands/briefing.md`). The SessionStart hook in Plan 3 gains an opt-in call to this skill (controlled by `XGH_BRIEFING` env var). A shared `scripts/mcp-detect.sh` helper provides MCP availability detection reused across all workflow skills. The briefing output uses the `🐴🤖` prefix and follows a structured 6-section format (Needs You Now → In Progress → Incoming → Team Pulse → Today → Suggested Focus).

**Tech Stack:** Claude Code skills (markdown), Claude Code commands (markdown), Bash (MCP detection helper, tests), MCP tools (Slack, Atlassian, GitHub CLI, Gmail, Figma, Cipher)

**Design doc:** `docs/plans/2026-03-13-xgh-design.md`

---

## File Structure

```
skills/
└── briefing/
    └── briefing.md                  # xgh:briefing skill

commands/
└── briefing.md                      # /xgh-briefing command

scripts/
└── mcp-detect.sh                    # Shared MCP availability detection helper

hooks/
└── session-start.sh                 # Modified: opt-in briefing trigger (XGH_BRIEFING)

tests/
└── test-briefing.sh                 # Skill file structure + content validation
```

---

## Chunk 1: MCP Detection Helper + Briefing Skill

### Task 1: Shared MCP detection helper

**Files:**
- Create: `scripts/mcp-detect.sh`
- Create: `tests/test-briefing.sh` (partial — detection section)

The workflow skills (investigate, implement-design, implement-ticket, briefing) all need to check MCP availability. Centralise this in one helper sourced by all of them.

- [ ] **Step 1: Write the failing test for mcp-detect.sh**

Create `tests/test-briefing.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); fi
}
assert_executable() {
  if [ -x "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 not executable"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# === mcp-detect.sh ===
assert_file_exists "${REPO_ROOT}/scripts/mcp-detect.sh"
assert_executable "${REPO_ROOT}/scripts/mcp-detect.sh"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "detect_mcp"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "slack"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "figma"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "atlassian"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "cipher"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "XGH_AVAILABLE_MCPS"

echo ""
echo "Briefing test (partial): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/test-briefing.sh
```
Expected: FAIL — `scripts/mcp-detect.sh` missing

- [ ] **Step 3: Create scripts/mcp-detect.sh**

```bash
#!/usr/bin/env bash
# mcp-detect.sh — Shared MCP availability detection for xgh workflow skills
# Usage: source scripts/mcp-detect.sh
#        detect_mcps          # populates XGH_AVAILABLE_MCPS array
#        has_mcp "slack"      # returns 0 (true) or 1 (false)
#
# Detection strategy: check for known env vars or tool hints that Claude Code
# injects when an MCP is configured. Falls back to checking .claude/.mcp.json.

XGH_AVAILABLE_MCPS=()

# Known MCP signatures: env vars or markers set when MCP is active
_MCP_SIGNATURES=(
  "cipher:CIPHER_LOG_LEVEL:.claude/.mcp.json:cipher"
  "slack:SLACK_MCP_TOKEN:.claude/.mcp.json:slack"
  "figma:FIGMA_MCP_TOKEN:.claude/.mcp.json:figma"
  "atlassian:ATLASSIAN_MCP_TOKEN:.claude/.mcp.json:atlassian"
  "gmail:GMAIL_MCP_TOKEN:.claude/.mcp.json:gmail"
  "github:GH_TOKEN:gh:cli"
)

detect_mcps() {
  XGH_AVAILABLE_MCPS=()

  # Check .claude/.mcp.json for configured servers
  local mcp_json="${PWD}/.claude/.mcp.json"
  if [ -f "$mcp_json" ]; then
    if grep -qi '"cipher"' "$mcp_json" 2>/dev/null; then
      XGH_AVAILABLE_MCPS+=("cipher")
    fi
    if grep -qi '"slack"' "$mcp_json" 2>/dev/null; then
      XGH_AVAILABLE_MCPS+=("slack")
    fi
    if grep -qi '"figma"' "$mcp_json" 2>/dev/null; then
      XGH_AVAILABLE_MCPS+=("figma")
    fi
    if grep -qi '"atlassian"' "$mcp_json" 2>/dev/null; then
      XGH_AVAILABLE_MCPS+=("atlassian")
    fi
    if grep -qi '"gmail"' "$mcp_json" 2>/dev/null; then
      XGH_AVAILABLE_MCPS+=("gmail")
    fi
  fi

  # GitHub: check gh CLI auth (not an MCP — uses CLI directly)
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    XGH_AVAILABLE_MCPS+=("github")
  fi

  export XGH_AVAILABLE_MCPS
}

# has_mcp <name> — returns 0 if available, 1 if not
has_mcp() {
  local name="$1"
  for mcp in "${XGH_AVAILABLE_MCPS[@]:-}"; do
    [ "$mcp" = "$name" ] && return 0
  done
  return 1
}

# list_mcps — prints comma-separated list of available MCPs
list_mcps() {
  local IFS=","
  echo "${XGH_AVAILABLE_MCPS[*]:-none}"
}
```

- [ ] **Step 4: Make executable and run test**

```bash
chmod +x scripts/mcp-detect.sh
bash tests/test-briefing.sh
```
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add scripts/mcp-detect.sh tests/test-briefing.sh
git commit -m "feat: add shared MCP detection helper"
```

---

### Task 2: Briefing skill and command

**Files:**
- Create: `skills/briefing/briefing.md`
- Create: `commands/briefing.md`
- Modify: `tests/test-briefing.sh` (add skill validation)

- [ ] **Step 1: Add skill validation to the test**

Append to `tests/test-briefing.sh` (before the final echo/exit):

```bash
# === briefing skill ===
assert_file_exists "${REPO_ROOT}/skills/briefing/briefing.md"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "xgh:briefing"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "NEEDS YOU NOW"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "IN PROGRESS"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "TEAM PULSE"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "SUGGESTED FOCUS"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "🐴🤖"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "XGH_BRIEFING"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "cipher_memory_search"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "mcp-setup"

# === briefing command ===
assert_file_exists "${REPO_ROOT}/commands/briefing.md"
assert_contains "${REPO_ROOT}/commands/briefing.md" "xgh-briefing"
assert_contains "${REPO_ROOT}/commands/briefing.md" "compact"
assert_contains "${REPO_ROOT}/commands/briefing.md" "focus"
```

- [ ] **Step 2: Run test to verify new assertions fail**

```bash
bash tests/test-briefing.sh
```
Expected: FAILs for skill and command files

- [ ] **Step 3: Create skills/briefing/briefing.md**

```markdown
---
name: xgh:briefing
description: Intelligent session briefing. Aggregates Slack, Jira, GitHub, Gmail, Calendar, Figma, and xgh team memory into a prioritized executive summary with a suggested focus.
type: flexible
triggers:
  - SessionStart (when XGH_BRIEFING=auto or XGH_BRIEFING=compact)
  - /xgh-briefing command
  - /xgh-briefing compact
  - /xgh-briefing focus
---

# xgh:briefing — Intelligent Session Briefing

Give the user a **prioritized executive summary** of everything relevant to their work right now, then recommend exactly one thing to focus on this session.

**Goal:** Not a notification dump — a concise briefing that answers "what's the most valuable thing I can work on right now?"

## Configuration

Controlled by `XGH_BRIEFING` environment variable:

| Value | Behavior |
|-------|----------|
| `off` (default) | Never auto-trigger; `/xgh-briefing` still works on demand |
| `auto` | Full briefing on every session start |
| `compact` | One-line status on session start, full on demand |

The briefing respects `XGH_TEAM` from the environment for workspace memory queries.

## Iron Law

> **NEVER show everything — show what matters.** A briefing that lists 40 items is noise. Surface the top 3-5 actionable items per section. If a section is empty or irrelevant, omit it entirely. The user's time is the constraint.

## MCP Detection

Before gathering data, check which MCPs are available. Call `xgh:mcp-setup` for any missing MCP the user wants to configure. Proceed with whatever is available — the briefing works with any combination.

Available MCP tools by integration:
- **Cipher**: `cipher_memory_search`, `cipher_extract_and_operate_memory`
- **Slack**: `slack_search_public_and_private`, `slack_read_thread`, `slack_read_channel`
- **Atlassian**: `searchJiraIssuesUsingJql`, `getJiraIssue`, `atlassianUserInfo`
- **Gmail**: `gmail_search_messages`, `gmail_read_message`
- **Figma**: `get_metadata`, `get_design_context`

GitHub uses `gh` CLI directly (not MCP): `gh pr list`, `gh issue list`

## Data Gathering Protocol

Run all available source queries **in parallel** (don't wait for one before starting another). Timeout each source at **10 seconds** — a slow API should never block the whole briefing.

### 1. Last Session State (always — from xgh memory)

```
cipher_memory_search: "last session work in progress pending"
```
Extract:
- What was being worked on
- Last commit message / git status
- Any pending curations flagged
- Unresolved questions from last session

Also run: `git log --oneline -3` and `git status --short` to ground the memory in current repo state.

### 2. Slack (if available)

```
slack_search_public_and_private: "to:me" — mentions and DMs
slack_search_public_and_private: "from:me in:#channel" — threads you started awaiting reply
```

Prioritize:
- **Direct mentions** (@you) in the last 24h
- **Threads you started** with unread replies
- **DMs** unread
- Watched channels: query last significant message (skip if channel is quiet)

Limit: top 5 items total.

### 3. Jira / Task Manager (if Atlassian available)

First get the current user:
```
atlassianUserInfo → extract accountId
```

Then:
```
searchJiraIssuesUsingJql: "assignee = currentUser() AND status != Done ORDER BY priority DESC, updated DESC"
searchJiraIssuesUsingJql: "issueFunction in linkedIssuesOf('assignee = currentUser()') AND status = 'In Progress'"
```

Prioritize:
- **In Progress** tickets (your work right now)
- **Tickets blocking others** (someone else is waiting on you)
- **Due soon** (due date within 3 days)
- **Recently commented** on (someone needs your input)

Limit: top 5 tickets.

### 4. GitHub (if gh CLI available)

```bash
gh pr list --review-requested @me --json number,title,author,updatedAt,reviewDecision
gh pr list --author @me --json number,title,state,reviewDecision,statusCheckRollup,updatedAt
gh issue list --assignee @me --json number,title,labels,updatedAt --limit 5
```

Prioritize:
- **PRs awaiting your review** (reviewer = you, not yet reviewed)
- **Your PRs with new comments or failing CI**
- **Your PRs approved and ready to merge**
- **Issues assigned to you** with recent activity

Limit: top 5 items.

### 5. Gmail (if available)

```
gmail_search_messages: "is:unread from:(@yourteam.com OR your-boss-email) newer_than:1d"
```

Prioritize:
- Unread emails from teammates (last 24h)
- Subject lines with deadline signals: "urgent", "ASAP", "EOD", "blocking", "incident"

Limit: top 3 items.

### 6. Figma (if available)

```
get_metadata: check files you own for recent comments
```

Prioritize:
- Designs with new comments from developers (ready for implementation?)
- Designs marked as "ready for dev" or "handoff"

Limit: top 2 items.

### 7. Team Pulse (always — from Cipher workspace)

```
cipher_memory_search: "team curated decision convention incident last 24 hours"
```

Extract what teammates' agents curated in the last ~24h:
- New conventions or decisions
- Incidents being investigated
- Architecture changes relevant to current work

Limit: top 3 items.

## Prioritization Engine

Score each item: `urgency × impact`

| Factor | Score |
|--------|-------|
| Blocking another person | +40 |
| Due today/tomorrow | +30 |
| Direct mention (@you) | +25 |
| CI failing on your PR | +20 |
| Unread DM | +20 |
| PR review requested (>24h old) | +15 |
| In Progress ticket | +10 |
| Related to last session work | +10 |

Items scoring ≥35 → **NEEDS YOU NOW**
Items scoring 15-34 → **IN PROGRESS** or **INCOMING**
Everything else → omit or summarize as a count

## Output Format

```
🐴🤖 Session Briefing — [Day, Date Time]
[Sources checked: Slack ✓ · Jira ✓ · GitHub ✓ · Gmail — · Figma ✓]

━━ NEEDS YOU NOW ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• [Source] Item — context (age/severity)

━━ IN PROGRESS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• [Last session] What you were working on + current git state
• [Jira] In-progress tickets

━━ INCOMING ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Summary of queued work (PR reviews, ticket backlog)

━━ TEAM PULSE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• What teammates curated/shipped recently that affects your work

━━ TODAY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Calendar events (if available) + sprint/deadline context

━━ SUGGESTED FOCUS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[One concrete recommendation with reasoning]

Proceed? [Y] or tell me what you want to work on instead.
```

Rules for the output:
- **Omit empty sections entirely** — don't show `━━ TODAY ━━` with nothing under it
- **Max 5 items per section** — anything beyond that becomes "... and N more"
- **Always end with Suggested Focus** — one item, clear reasoning
- **Always ask** "Proceed?" — let the user redirect if needed

## Compact Mode (`XGH_BRIEFING=compact` or `/xgh-briefing compact`)

Single line + prompt:

```
🐴🤖 [3 items need you · 2 PRs to review · sprint ends Thu] → Suggested: resume PROJ-88. Proceed?
```

## Focus Mode (`/xgh-briefing focus`)

Skip all sections except SUGGESTED FOCUS:

```
🐴🤖 Suggested focus: [recommendation with 2-sentence reasoning]. Proceed?
```

## Pre-Meeting Mode

If a calendar event is within 30 minutes, prepend:

```
⏰ [Meeting name] in [N] minutes.
  → Relevant context: [what xgh knows about this meeting's topic]
  → What to say about your work: [1-2 sentences]
```

## After the Briefing

Once the user responds:

1. If **proceed**: load context for the suggested focus item (query xgh memory, open relevant files in mind)
2. If **redirect**: note what they want to work on, store it as session intent in Cipher memory
3. Store briefing summary in Cipher memory for next session's "last session" context

```
cipher_extract_and_operate_memory:
  content: "Session [date]: focused on [topic]. Briefing items: [top 3]. User chose: [chosen focus]."
  metadata:
    type: session-start
    date: [ISO timestamp]
    chosen_focus: [what user chose]
```

## Rationalization Table

| Agent thought | Reality |
|---------------|---------|
| "I'll just check one source to save time" | Incomplete briefing causes missed blockers. Check all available sources. |
| "This section has 8 items, I'll show them all" | Overwhelming. Hard cap at 5 per section. |
| "I'll skip Suggested Focus — the user can decide" | The whole point is reducing decision fatigue. Always suggest. |
| "The briefing is taking too long, I'll wait" | Timeout each source at 10s. Partial briefing > no briefing. |
| "Memory search returned nothing relevant" | Store last session state explicitly so next session finds it. |

## Composability

- Uses `xgh:mcp-setup` when a source MCP is missing (optional setup, not blocking)
- Feeds into `xgh:implement-ticket` (pre-loaded context for chosen ticket)
- Feeds into `xgh:investigate` (pre-loaded context for chosen incident)
- Informs `xgh:convention-guardian` (team pulse surfaces new conventions)
```

- [ ] **Step 4: Create commands/briefing.md**

```markdown
---
name: xgh-briefing
description: Session briefing — aggregates Slack, Jira, GitHub, and team memory into a prioritized summary
---

# /xgh-briefing — Session Briefing

Invoke the `xgh:briefing` skill.

## Usage

```
/xgh-briefing              # Full briefing (all sources, all sections)
/xgh-briefing compact      # One-line summary + suggested focus
/xgh-briefing focus        # Just the suggested focus, nothing else
```

## Auto-trigger

Control with `XGH_BRIEFING` env var:
- `off` (default) — manual only
- `compact` — auto one-liner on session start
- `auto` — full briefing on session start

Add to your shell profile:
```bash
export XGH_BRIEFING=compact   # Recommended for daily use
```
```

- [ ] **Step 5: Run the full test**

```bash
bash tests/test-briefing.sh
```
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add skills/briefing/briefing.md commands/briefing.md tests/test-briefing.sh
git commit -m "feat: add xgh:briefing skill and /xgh-briefing command"
```

---

## Chunk 2: SessionStart Hook Integration

### Task 3: Wire briefing into the SessionStart hook

**Files:**
- Modify: `hooks/session-start.sh`
- Modify: `tests/test-hooks.sh` (add XGH_BRIEFING check)

The SessionStart hook (implemented in Plan 3) outputs a JSON `{"result": "..."}` block. When `XGH_BRIEFING=compact` or `XGH_BRIEFING=auto`, append a trigger note to the result that tells Claude to invoke `xgh:briefing`.

- [ ] **Step 1: Add hook integration test**

In `tests/test-hooks.sh`, add:

```bash
# SessionStart with XGH_BRIEFING=compact should mention briefing
result=$(XGH_BRIEFING=compact XGH_DRY_RUN=1 bash hooks/session-start.sh 2>/dev/null || true)
assert_contains "$result" "briefing" "XGH_BRIEFING=compact should trigger briefing mention"
```

- [ ] **Step 2: Run to verify it fails**

```bash
bash tests/test-hooks.sh
```
Expected: FAIL on the new assertion

- [ ] **Step 3: Update hooks/session-start.sh**

At the end of `hooks/session-start.sh`, before the final JSON output, add:

```bash
# ── Briefing trigger ─────────────────────────────────
BRIEFING_NOTE=""
XGH_BRIEFING="${XGH_BRIEFING:-off}"
if [ "$XGH_BRIEFING" = "compact" ]; then
  BRIEFING_NOTE="\n\n**xgh:** Run \`xgh:briefing\` in compact mode now."
elif [ "$XGH_BRIEFING" = "auto" ]; then
  BRIEFING_NOTE="\n\n**xgh:** Run \`xgh:briefing\` in full mode now."
fi
```

Then include `$BRIEFING_NOTE` in the JSON result string.

- [ ] **Step 4: Run test to verify it passes**

```bash
bash tests/test-hooks.sh
```
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start.sh tests/test-hooks.sh
git commit -m "feat: wire XGH_BRIEFING into SessionStart hook"
```

---

## Chunk 3: techpack.yaml + Design Doc Update

### Task 4: Register briefing in techpack and design doc

**Files:**
- Modify: `techpack.yaml`
- Modify: `docs/plans/2026-03-13-xgh-design.md`

- [ ] **Step 1: Add briefing to techpack.yaml**

In `techpack.yaml`, under the skills components section, add after the existing skills:

```yaml
  - id: briefing
    description: "Intelligent session briefing — aggregates all sources into prioritized summary"
    skill:
      source: skills/briefing
      destination: xgh-briefing

  - id: briefing-command
    description: "Session briefing slash command"
    command:
      source: commands/briefing.md
      destination: xgh-briefing.md
```

- [ ] **Step 2: Add briefing to design doc**

In `docs/plans/2026-03-13-xgh-design.md`, in Section 7 (CLI Commands & Skills), add to the skills table:

```markdown
| `xgh:briefing` | Session start or `/xgh-briefing` — prioritized summary of Slack, Jira, GitHub, Gmail, xgh memory |
```

And add to the slash commands table:

```markdown
| `/xgh-briefing [compact\|focus]` | Session briefing — prioritized summary + suggested focus |
```

- [ ] **Step 3: Add a new Section 12 (Briefing) to the design doc**

Add before the Installation section:

```markdown
## 12. Session Briefing

`xgh:briefing` gives every session a **standing start** — instead of orienting from scratch, the agent knows what matters before the first keystroke.

### Sources (all optional, detected at runtime)

| Source | Data extracted | MCP |
|--------|---------------|-----|
| xgh memory | Last session state, pending curations | Cipher |
| Slack | Mentions, DMs, threads awaiting reply | Claude.ai Slack |
| Jira | In-progress tickets, blockers, due soon | Claude.ai Atlassian |
| GitHub | PRs awaiting review, failing CI, ready to merge | gh CLI |
| Gmail | Unread from teammates, deadline signals | Claude.ai Gmail |
| Figma | New design comments, handoff-ready | Claude.ai Figma |
| Team workspace | What teammates curated in last 24h | Cipher |

### Output Modes

| Mode | Trigger | Output |
|------|---------|--------|
| `full` | `/xgh-briefing` or `XGH_BRIEFING=auto` | All 6 sections + suggested focus |
| `compact` | `/xgh-briefing compact` or `XGH_BRIEFING=compact` | One-line summary + focus |
| `focus` | `/xgh-briefing focus` | Just the suggested focus |

### Prioritization

Items are scored by `urgency × impact`. Scores ≥35 appear in **Needs You Now**. Everything else is summarized or omitted. Hard cap: 5 items per section.

### Auto-trigger

```bash
export XGH_BRIEFING=compact   # Recommended: one-liner on every session start
export XGH_BRIEFING=auto      # Full briefing on session start
export XGH_BRIEFING=off       # Manual only (default)
```
```

- [ ] **Step 4: Run all tests to verify nothing broken**

```bash
bash tests/test-briefing.sh && bash tests/test-techpack.sh
```
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add techpack.yaml docs/plans/2026-03-13-xgh-design.md
git commit -m "feat: register xgh:briefing in techpack and design doc"
```

---

## Final Verification

- [ ] **Run all test suites**

```bash
bash tests/test-briefing.sh
bash tests/test-techpack.sh
```

- [ ] **Verify file structure**

```bash
find skills/briefing commands/briefing.md scripts/mcp-detect.sh -type f | sort
```
Expected output:
```
commands/briefing.md
scripts/mcp-detect.sh
skills/briefing/briefing.md
```

- [ ] **Final commit if any cleanup needed**

```bash
git add -A
git status  # verify only expected files
git commit -m "chore: finalize xgh:briefing implementation"
```
