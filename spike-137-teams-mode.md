# Spike: xgh Agent-Teams Awareness
## Issue #137 — Detect `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and enable parallel team-based workflows

**Date:** 2026-03-27
**Author:** Claude (spike agent)
**Scope:** Runtime detection + per-skill feasibility + design sketch + recommendation

---

## 1. Detection Verdict

### Can it be detected? Yes — via Claude Code env injection, NOT shell inheritance.

**Test result:**
```
echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS  →  (empty)
settings.json env block: { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" }
```

**Key finding:** The env var is defined in `settings.json` under the `env` key. Claude Code injects this into the Claude process environment at session start — but it does NOT propagate to child shell processes launched via Bash tool. A skill's Bash commands cannot read it via `$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

**Detection is reliable via instruction-time declaration, not shell probe.** The correct detection pattern is:

```markdown
## Teams Mode Guard (in skill preamble)

If the user's settings.json has CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1,
teams mode is available. Skills detect this by:
1. Attempting to spawn a subagent — if Claude Code rejects it, teams mode is OFF
2. Or: include detection logic in the skill YAML/frontmatter (not yet supported)
3. Practical approach: treat it as always-enabled if set in settings.json and let
   Claude Code's own enforcement handle capability boundaries
```

**Reliability rating: HIGH** for "assume enabled when configured" pattern. The var is set once in settings.json and stable across sessions. No runtime probing needed — if it's in settings.json, it's active.

**Caveats:**
- Experimental flag — API contract unstable
- Cannot detect via Bash (shell doesn't inherit Claude Code env vars)
- No documented callback or hook for teams-mode state changes

---

## 2. Pattern-by-Pattern Analysis

### 2a. `/xgh-retrieve` — Sequential channel scan per project

**Current behavior:**
- Step 0: detect project scope (single or all)
- Step 2: `for each project → for each Slack channel` — fully sequential
- Steps 2b–8: per-channel/per-provider, cursor updated incrementally
- Critical: cursor updates are per-channel, mid-loop — safe cursor semantics depend on sequential execution

**Teams mode opportunity:**
Parallelize the outer loop: one Haiku worker per project, each owning its own cursor slice.

**What changes:**
```
# Current (sequential)
for project in active_projects:
    for channel in project.slack:
        scan_channel(channel)
        update_cursor(channel)

# Teams mode (parallel)
spawn workers: [retrieve_worker(project) for project in active_projects]
each worker: runs steps 2–9 for its own project scope
synthesis agent: merges completion logs, updates global state
```

**Risk: MEDIUM**
- Cursor file `~/.xgh/inbox/.cursors.json` is shared — concurrent writes cause race conditions
- Mitigation: each worker writes to `~/.xgh/inbox/.cursors.<project>.json` (partitioned cursors)
- Requires cursor merge step before final log
- Rate limits per Slack/Jira/GitHub API still apply — parallelism doesn't help if all workers hit the same token bucket

**Worth it?** YES for all-projects mode (N≥3 projects). No benefit for single-project scope.

---

### 2b. `/xgh-analyze` — Sequential classification + dedup

**Current behavior:**
- Read all inbox files sequentially
- Classify each item (Steps 3–4)
- Deduplicate against existing memory (Step 5)
- Write to lossless-claude (Step 7)
- Single-pass, no parallelism

**Teams mode opportunity:**
Two sub-patterns possible:

**Pattern A: Parallel classification workers**
```
# Batch inbox files → N Haiku workers classify in parallel
# Synthesis agent runs dedup + writes to LCM
classify_workers = [haiku_classify(batch) for batch in chunk(inbox, 10)]
results = await_all(classify_workers)
dedup_and_write(merge(results))
```

**Pattern B: Enthusiast + Adversary debate for high-stakes items**
```
# Only for urgency ≥ 60 items
if item.urgency >= 60:
    enthusiast = spawn_worker("classify this as high-priority, build the case")
    adversary = spawn_worker("argue this is noise, not urgent")
    judge = synthesize(enthusiast.output, adversary.output)
```

**Risk Pattern A: LOW** — classification is embarrassingly parallel, no shared state
**Risk Pattern B: LOW-MEDIUM** — 3x token cost per high-urgency item; 5-agent limit from §2 UNBREAKABLE_RULES

**Worth it?** Pattern A: YES for large inboxes (>20 items). Pattern B: DEFER — debate overhead doesn't improve classification accuracy enough to justify cost for typical inbox items.

---

### 2c. `/xgh-briefing` — Sequential data gathering

**Current behavior:**
- Gather from 7 sources sequentially: LCM → Slack → Jira → GitHub → Gmail → Figma → Team Pulse
- Sources are independent (no cross-dependencies between gather steps)
- Synthesis happens after all sources complete

**Teams mode opportunity:**
All 7 sources are independent — perfect parallelism candidate.

```
# Teams mode briefing
workers = [
    haiku_worker("fetch LCM memory"),
    haiku_worker("fetch Slack unread"),
    haiku_worker("fetch Jira tickets"),
    haiku_worker("fetch GitHub PRs"),
    haiku_worker("fetch Gmail"),
]
results = await_all(workers)  # ≤5 concurrent per §2
synthesis_agent = sonnet_worker("synthesize all results into briefing")
```

**Risk: LOW** — sources are read-only and independent; no cursor or shared-state concerns
**Speedup estimate:** 3–5x wall-clock reduction for all-sources briefing
**Constraint:** 5-agent limit means Gmail + Figma + Team Pulse must be batched into a single worker or run sequentially after the first 5 complete

**Worth it?** YES — highest ROI of the three. Briefing is the most latency-sensitive skill (user waits synchronously), and gather steps are perfectly parallelizable.

---

### 2d. Sprint execution — Autonomous teammate coordination

**Current pattern:** Orchestrator (Sonnet) dispatches sequentially to CTO/COO/Team Lead agents via Agent tool.

**Teams mode opportunity:** True simultaneous teammate execution — multiple Sonnet agents working different tickets in parallel, coordinated by a lightweight Opus orchestrator.

**Risk: HIGH**
- Commit conflicts on shared branches (documented in LCM `feedback_parallel_agent_commits`)
- No built-in merge coordination in the current xgh workflow
- Requires worktree-per-agent pattern (superpowers:using-git-worktrees)
- Opus orchestrator cost is high — violates "Sonnet default" unless sprint is large enough to justify

**Worth it?** DEFER — requires git worktree infrastructure changes first. Not a skill-level change.

---

## 3. Design Sketch

### 3a. Retrieve — Partitioned parallel (teams mode)

```yaml
# New behavior when teams_mode=true AND all-projects scope AND N≥2 projects

guard:
  if project_scope == "single": run_sequential()  # no gain
  if num_active_projects < 2: run_sequential()

spawn_per_project:
  model: haiku  # classification/fetch work
  max_concurrent: 5  # §2 hard limit
  each_worker:
    - scope: project_N only
    - cursor_file: ~/.xgh/inbox/.cursors.<project_id>.json
    - steps: 2, 2b, 3, 4, 4b, 5, 6 (no step 7 critical path — handled by synthesis)
    - output: writes to ~/.xgh/inbox/<project_id>/ subfolder

synthesis_agent:
  model: sonnet
  inputs: worker completion logs
  steps: 7 (critical urgency), 8 (queue enrichments), 9 (verify cursors), 10 (log)
  merges: partitioned cursors → .cursors.json
```

### 3b. Briefing — Parallel source gathering (teams mode)

```yaml
# Parallel gather when teams_mode=true

gather_workers:
  - worker_1: [lcm_memory, team_pulse]        # always available, cheap
  - worker_2: [slack_unread, slack_urgent]    # if slack available
  - worker_3: [jira_assigned, jira_in_progress]  # if jira available
  - worker_4: [github_prs, github_issues]     # if github available
  - worker_5: [gmail_unread, figma_files]     # if available

synthesis_agent:
  model: sonnet
  inputs: all_worker_results
  runs: prioritization engine + output format
```

### 3c. Detection gate (skill preamble pattern)

```markdown
## Teams Mode Detection

Check if CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is active:
- This env var is injected by Claude Code from settings.json
- It cannot be read via Bash ($VAR returns empty)
- Detection strategy: attempt parallel spawn; if Claude Code errors, fall back to sequential
- Practical default: if settings.json contains CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1,
  treat as enabled. Skills include a TEAMS_MODE flag in their guard section.
```

---

## 4. Recommendation

**ADOPT_WITH_CAVEATS**

### Adopt (now):
1. **`/xgh-briefing` parallel gather** — highest ROI, lowest risk, user-visible latency improvement
2. **`/xgh-analyze` parallel classification (Pattern A)** — parallelism for large inboxes, embarrassingly parallel

### Adopt with prerequisite work:
3. **`/xgh-retrieve` partitioned parallel** — requires cursor partitioning design (1–2 day spike)

### Defer:
4. **Sprint execution parallelism** — requires git worktree infrastructure
5. **Analyze debate team (Pattern B)** — cost exceeds benefit for typical inbox

### Rationale:
- Env var is reliably detectable via settings.json presence (not shell probe)
- UNBREAKABLE_RULES §2 (max 5 concurrent subagents) is the binding constraint, not the API
- Briefing parallelism is the safest first move: read-only, no shared state, clear speedup
- Token cost tradeoff: parallel workers cost ~N×overhead tokens for coordination; worthwhile only for N≥3 projects or large inboxes
- Experimental flag caveat: build with feature flag in skills so teams-mode path can be disabled if API changes

### Implementation order:
1. `/xgh-briefing` — teams mode parallel gather (1 sprint)
2. `/xgh-analyze` — Pattern A parallel classification (1 sprint)
3. `/xgh-retrieve` — partitioned parallel + cursor merge (2 sprints, needs cursor schema change)
4. Sprint execution — defer to post-worktree infrastructure

---

## Appendix: Token budget impact

| Skill | Sequential tokens | Teams mode tokens | Delta | Speedup |
|-------|------------------|-------------------|-------|---------|
| /xgh-briefing (5 sources) | ~8K | ~10K (+25% coordination) | +2K | 3–5x |
| /xgh-analyze (20 items) | ~6K | ~7K | +1K | 2–3x |
| /xgh-retrieve (3 projects) | ~12K | ~14K | +2K | 2–3x |

Coordination overhead is real (~15–25%) but small relative to the wall-clock speedup. Net is positive for user experience, neutral-to-slightly-negative for token budget (within acceptable range per §2).
