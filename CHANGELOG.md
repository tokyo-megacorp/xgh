# Changelog

All notable changes to this project will be documented in this file.

## [2.3.0] - 2026-03-30

### Features

- **ci**: quality-gates label-based merge requirements (#185)
- **ship-prs**: Copilot suggestion negotiation + round-count metric (#173)
- **retrieve**: retry/backoff on session-start failure (#169)
- **retrieve**: cursor partitioning for parallel workers (#155)
- **doctor**: validate active ingest.yaml projects are in provider.yaml sources (#181)
- **doctor**: warn on unsupported github_sources values (#183)
- **inbox**: content-hash dedup at write layer (#176)
- **watch-prs**: discover subcommand for auto-discovery of open PRs (#160)
- **brief**: parallel gather via teams mode when AGENT_TEAMS=1 (#151)
- **autoimprove**: scaffold autoimprove.yaml with test/skill/agent benchmarks (#186)
- **decision**: xgh:decision skill — LCM decision → GitHub Issue pipeline (#142)
- **skill**: xgh:archive with --obituary flag (#138)
- **token-window**: budget-aware session management skill (#136)
- **cron**: PR babysitter — watch-prs every 15min, notify Pedro on changes
- **frontmatter**: team lead frontmatter awareness (#134)
- **providers**: add /xgh-init-providers command for repairing empty providers (#145)

### Bug Fixes

- **retrieve**: update last_scan in ingest.yaml after successful retrieve (#175)
- **providers**: fix Check 6 for empty providers detection (#145)

### Documentation

- **retrieve**: document XGH_PROJECT_SCOPE env var (#174)

### CI

- AR coverage gate — default-yes adversarial review (#162)
- Enable Dependabot + CodeQL scanning (#163)

### Chores

- Remove deprecated codex-driver (#184)
- Scaffold autoimprove.yaml for benchmarks (#144)
- Bump actions/checkout from 4 to 6 (#167)
- Bump actions/setup-python from 5 to 6 (#165)
- Bump actions/setup-node from 4 to 6 (#164)
- Bump github/codeql-action from 3 to 4 (#166)
