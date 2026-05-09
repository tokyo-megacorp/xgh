# tests/ — Test Suite

20 test scripts + `run-all.sh` harness. Tests validate xgh pipeline components via bash assertions. CI contract: all tests pass on main.

## Running Tests

```bash
bash tests/run-all.sh            # full suite
bash tests/test-hooks.sh         # hook lifecycle only
bash tests/test-providers.sh     # provider contract
bash tests/test-commands.sh      # command execution
```

## Test Inventory

| Script | Covers |
|---|---|
| `test-analyze.sh` | `/xgh-analyze` command |
| `test-brief.sh` | `/xgh-brief` command |
| `test-briefing.sh` | Briefing generation |
| `test-commands.sh` | All slash commands (smoke) |
| `test-config.sh` | Config loading + validation |
| `test-config-drift.sh` | Config schema drift detection |
| `test-config-reader.sh` | `lib/config-reader.sh` unit |
| `test-cursor.sh` | Cursor integration |
| `test-detect-project.sh` | `scripts/detect-project.sh` |
| `test-file-refs.sh` | File reference integrity |
| `test-hook-ordering.sh` | Hook execution order |
| `test-hooks.sh` | Hook scripts (lifecycle) |
| `test-json-syntax.sh` | JSON syntax across repo |
| `test-pipeline-foundation.sh` | Pipeline core logic |
| `test-pipeline-skills.sh` | Pipeline skill integration |
| `test-post-compact-preferences.sh` | Post-compact preference rebuild |
| `test-pre-tool-use-preferences.sh` | Pre-tool-use preference injection |
| `test-preferences.sh` | Preference system end-to-end |
| `test-provider-contract.sh` | Provider interface contract |
| `test-providers.sh` | Provider integration |
| `test-retrieve.sh` | Retrieval pipeline |
| `test-retrieve-all.sh` | Full retrieve-all flow |
| `test-session-start.sh` | Session-start hook |
| `test-session-start-preferences.sh` | Session-start preferences hook |
| `test-shellcheck.sh` | ShellCheck lint across all scripts |
| `test-trigger.sh` | Trigger evaluation |
| `test-yaml-syntax.sh` | YAML syntax across repo |

## Test Contract

- Tests exit 0 on pass, non-zero on fail
- `run-all.sh` aggregates results and exits non-zero if any test fails
- `test-shellcheck.sh` enforces shell hygiene on all `.sh` files
- `skill-triggering/` subdir contains skill trigger validation fixtures
