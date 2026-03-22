# Root Cause Analysis: Fresh macOS Installation Broken

**Date:** 2026-03-19
**Investigator:** Claude Opus 4.6 (automated)
**Scope:** All 9 symptoms from `/xgh-doctor`

---

## Timeline of Events

| Date | Event |
|------|-------|
| 2026-03-15 15:04 | Last successful retriever run (1 log line: "2 channels, 22 items stashed, 9 urgent") |
| 2026-03-16 19:07 | `com.xgh.analyzer.plist` and `com.xgh.retriever.plist` created in `~/.xgh/schedulers/` (by a pre-migration install) |
| 2026-03-17 23:28 | Commit `8b040e3`: OS scheduler removed, replaced with Claude-internal CronCreate. Deleted `scripts/schedulers/com.xgh.analyzer.plist`, `com.xgh.retriever.plist`, and `scripts/ingest-schedule.sh` (176 lines). |
| 2026-03-18 08:28 | Last retriever cursor run (per doctor report) |
| 2026-03-18 09:44 | Commit `95de899`: 589 lines of model/backend setup removed from `install.sh`, delegated to `lossless-claude install` |
| 2026-03-18 18:39 | Commit `2935f86`: "finish scheduler migration cleanup" — removed launchd references from doctor skill and tests |
| 2026-03-19 10:35 | `com.xgh.models.plist` last modified (installer re-ran, only this plist gets copied) |

---

## Symptom-by-Symptom Root Cause Analysis

### 1. Schedulers Not Loaded (3 plists exist but not registered with launchd)

**Root cause: Intentional removal + stale artifacts on disk.**

- Commit `8b040e3` (line diff: -264 lines) deleted `scripts/ingest-schedule.sh` which was the ONLY code that ran `launchctl bootstrap` / `launchctl load`. It also deleted the analyzer and retriever plist templates from the repo.
- `install.sh` lines 580-586 actively unload legacy schedulers if `ingest-schedule.sh` exists, then deletes it.
- The 3 plist files in `~/.xgh/schedulers/` are **orphaned artifacts** from the pre-March-17 install:
  - `com.xgh.analyzer.plist` — created 2026-03-16 19:07, **no longer in repo** (deleted in `8b040e3`)
  - `com.xgh.retriever.plist` — created 2026-03-16 19:07, **no longer in repo** (deleted in `8b040e3`)
  - `com.xgh.models.plist` — updated 2026-03-19 10:35, still in repo but **installer never registers it with launchd**
- **Bug in installer (line 576-578):** The installer copies `com.xgh.models.plist` to `~/.xgh/schedulers/` but performs only a single `sed` substitution (`127.0.0.1` -> `XGH_MODEL_HOST`) and never runs `launchctl bootstrap` to register it. Furthermore, the plist still contains **7 unresolved placeholders**: `XGH_VLLM_BIN`, `XGH_LLM_MODEL`, `XGH_EMBED_MODEL`, `XGH_MODEL_PORT`, `XGH_MODEL_HOST_PLACEHOLDER`, `XGH_LOG_DIR`, `XGH_USER_HOME`.

**Verdict:** The scheduler migration (commit `8b040e3`) intentionally replaced OS-level launchd scheduling with Claude-internal `CronCreate`. The installer was updated to unload legacy schedulers. But:
1. It does NOT clean up the orphaned `.plist` files from `~/.xgh/schedulers/`
2. The `com.xgh.models.plist` it still copies has unresolved template placeholders
3. No code anywhere registers any plist with launchd anymore

**Fix needed:**
- `install.sh` line 576-578: Either (a) stop copying `com.xgh.models.plist` entirely, or (b) resolve ALL placeholders AND register with launchctl.
- `install.sh` migration block (after line 586): Add `rm -f "$HOME/.xgh/schedulers/com.xgh.analyzer.plist" "$HOME/.xgh/schedulers/com.xgh.retriever.plist"` to clean stale files.

### 2. Retriever Hitting API Rate Limits

**Root cause: Runaway headless `claude` invocations exhausting Claude API quota.**

- `retriever.log` shows: first a successful run at 2026-03-15 15:04, then immediately floods of `Error: Reached max turns (3)` followed by `You've hit your limit` messages.
- The retriever plist had `--max-turns 3` and `StartInterval 300` (every 5 minutes).
- When the retriever hits rate limits, `claude` CLI exits with an error, but the error output (`Error: Reached max turns (3)`) gets appended to the log WITHOUT newlines — indicating the process was spawning repeatedly and rapidly.
- The `--max-turns 3` is too low to complete meaningful work, so every invocation fails immediately, creating a tight retry loop.

**Verdict:** This is a **design defect** in the old launchd scheduler. The plist had no `ThrottleInterval` or backoff mechanism. When Claude API returns rate-limit errors, launchd restarts the process immediately (since `KeepAlive` is false but `StartInterval` is 300, launchd fires every 5 min). Since the process fails instantly on rate-limit, 288 invocations/day hammered the API.

**Fix needed:** This is now moot since schedulers were removed in `8b040e3`. The CronCreate replacement should include rate-limit awareness (check `/xgh-retrieve` skill for backoff logic).

### 3. models.env Unconfigured (all fields empty)

**Root cause: Installer writes empty values by design; model setup was delegated to `lossless-claude install`.**

- `install.sh` lines 536-549: Writes `models.env` with the values of `XGH_LLM_MODEL`, `XGH_EMBED_MODEL`, `XGH_BACKEND`, `XGH_REMOTE_URL` — all of which default to empty string (lines 11-14).
- Commit `95de899` (2026-03-18) removed 589 lines of model/backend auto-detection, LLM picker, and vllm/ollama install logic from `install.sh`, delegating everything to `lossless-claude install`.
- Line 550 comment: `# Note: model/backend setup is handled by lossless-claude install`
- If `lossless-claude install` (line 89) fails or doesn't populate `models.env`, all fields remain empty.

**Verdict:** **Gap in the delegation chain.** The installer delegates to `lossless-claude install` (line 89), but `lossless-claude install` apparently does NOT write to `~/.xgh/models.env`. The installer writes the file at line 542 AFTER the lossless-claude step (line 89), overwriting anything lossless-claude might have set.

**Fix needed:**
- `install.sh` lines 542-549: Move `models.env` write BEFORE lossless-claude install, OR read existing values before overwriting, OR have `lossless-claude install` write to `models.env` and skip the overwrite if already populated.

### 4. Cipher Collections Empty

**Root cause: Downstream of models.env being empty.**

- Cipher MCP requires a running Qdrant instance and configured embedding model to create/populate collections.
- With `XGH_BACKEND=""` and `XGH_EMBED_MODEL=""`, the embedding pipeline cannot function.
- Without embeddings, workspace and knowledge vector stores remain empty.

**Verdict:** Transitive failure from symptom #3. Fix models.env and Cipher will populate on next indexing run.

### 5. Skills Pack Empty (~/.xgh/pack/skills/ is empty)

**Root cause: Skills are NOT in `~/.xgh/pack/skills/` — they're in the plugin cache.**

- The installer clones/pulls xgh repo to `~/.xgh/pack/` (lines 103-111).
- Skills live in the plugin at `~/.xgh/pack/plugin/skills/` (confirmed: 23 skills present there).
- The installer registers them via `register_plugin()` (lines 272-403), copying to `~/.claude/plugins/cache/extreme-go-horse/xgh/<version>/skills/` (confirmed: 23 skills present there too).
- There is no `~/.xgh/pack/skills/` directory at all — skills are at `~/.xgh/pack/plugin/skills/`.

**Verdict:** **False alarm / doctor skill bug.** The doctor check is looking at the wrong path (`~/.xgh/pack/skills/`). Skills are correctly installed at two locations:
- `~/.xgh/pack/plugin/skills/` (source)
- `~/.claude/plugins/cache/extreme-go-horse/xgh/<version>/skills/` (registered for Claude Code)

**Fix needed:** Update the doctor skill (`plugin/skills/doctor/doctor.md`) to check the correct path: `~/.xgh/pack/plugin/skills/` or `~/.claude/plugins/cache/extreme-go-horse/xgh/*/skills/`.

### 6. context-mode CLI Doctor Missing (build/cli.js not found)

**Root cause: context-mode is installed as a Claude plugin, not a standalone CLI.**

- `install.sh` lines 51-55: Installs context-mode as a Claude Code plugin via `claude plugin marketplace add` and `claude plugin install`.
- context-mode is confirmed installed (`claude plugin list` shows `context-mode@context-mode`).
- There is no `~/.xgh/context-mode/build/cli.js` — that path was never created by the installer.

**Verdict:** **False alarm / doctor skill checking wrong path.** context-mode was installed as a Claude Code MCP plugin, not as a local npm package with a `build/cli.js` entry point. The doctor check is looking for a file that doesn't exist in the plugin install model.

**Fix needed:** Update the doctor skill to check `claude plugin list | grep context-mode` instead of looking for `build/cli.js`.

### 7. Retrieval Freshness Stale (25h+ since last run)

**Root cause: OS schedulers were removed; CronCreate replacement not yet configured.**

- The old launchd scheduler (removed in `8b040e3`) ran retriever every 5 minutes.
- The replacement (`CronCreate`) is a Claude-internal mechanism that requires `XGH_SCHEDULER=on` in the environment and manual setup via `/xgh-schedule`.
- No cron jobs exist (`crontab -l` returns nothing, exit code 1).
- No launchd agents are loaded (`launchctl list | grep xgh` returns nothing).

**Verdict:** Expected behavior given the migration. The user needs to either:
- Set `export XGH_SCHEDULER=on` and run `/xgh-schedule resume`, OR
- Manually invoke `/xgh-retrieve` when needed.

### 8. No Crontab Entries

**Root cause: By design — xgh never used crontab.**

- xgh historically used launchd (macOS), then migrated to Claude-internal CronCreate.
- The installer has never written crontab entries.

**Verdict:** Not a bug. crontab was never part of the xgh scheduling mechanism.

### 9. No LaunchD Agents Loaded

**Root cause: Same as #1 — intentional migration away from launchd.**

- Commit `8b040e3` removed all launchd registration code.
- `install.sh` lines 580-586 actively unload any previously installed launchd agents.

**Verdict:** Expected behavior post-migration.

---

## Summary: Bugs vs. Expected Behavior

| # | Symptom | Classification | Action Required |
|---|---------|---------------|-----------------|
| 1 | Schedulers not loaded | **Bug** — orphaned plist files + unresolved placeholders in models.plist | Clean up stale plists; fix or remove models.plist copy |
| 2 | Retriever rate limits | **Design defect** (now moot) | Already resolved by scheduler removal |
| 3 | models.env empty | **Bug** — installer overwrites with empty values after lossless-claude | Fix write order or preserve existing values |
| 4 | Cipher empty | **Transitive** — blocked by #3 | Fix #3 |
| 5 | Skills pack empty | **False alarm** — doctor checks wrong path | Fix doctor skill path check |
| 6 | context-mode CLI missing | **False alarm** — doctor checks wrong install model | Fix doctor skill check |
| 7 | Retrieval stale | **Expected** — migration gap | User must enable CronCreate |
| 8 | No crontab | **Expected** — never used | No action |
| 9 | No launchd agents | **Expected** — intentionally removed | No action |

---

## Specific Code Fixes Needed

### Fix 1: Clean up orphaned plist files (`install.sh`, after line 586)
Add cleanup of analyzer and retriever plists that are no longer used:
```bash
rm -f "$HOME/.xgh/schedulers/com.xgh.analyzer.plist"
rm -f "$HOME/.xgh/schedulers/com.xgh.retriever.plist"
```

### Fix 2: Stop copying unresolvable models.plist OR resolve all placeholders (`install.sh`, lines 575-578)
Either remove the `sed`/`cp` of `com.xgh.models.plist` entirely (since model serving is now delegated), or resolve all 7 placeholders (`XGH_VLLM_BIN`, `XGH_LLM_MODEL`, `XGH_EMBED_MODEL`, `XGH_MODEL_PORT`, `XGH_LOG_DIR`, `XGH_USER_HOME`, `XGH_MODEL_HOST_PLACEHOLDER`).

### Fix 3: Don't overwrite populated models.env (`install.sh`, lines 542-549)
Change to only write if `models.env` doesn't exist or all fields are empty:
```bash
if [ ! -f "$HOME/.xgh/models.env" ] || ! grep -q '[^[:space:]="]' "$HOME/.xgh/models.env" 2>/dev/null; then
  cat > "$HOME/.xgh/models.env" <<MODELSEOF
...
MODELSEOF
fi
```

### Fix 4: Update doctor skill path checks (`plugin/skills/doctor/doctor.md`)
- Skills check: look at `~/.claude/plugins/cache/extreme-go-horse/xgh/*/skills/` instead of `~/.xgh/pack/skills/`
- context-mode check: use `claude plugin list | grep context-mode` instead of checking for `build/cli.js`
