# CLAUDE.md — xgh (eXtreme Go Horse)

> **Primary instructions:** See [`AGENTS.md`](./AGENTS.md) for the complete guide to working on this repository — project overview, tech stack, file structure, development guidelines, test commands, implementation status, and the Superpowers methodology.

---

## Claude Code — Quick Reference

### Run tests

```bash
bash tests/test-install.sh
bash tests/test-config.sh
bash tests/test-techpack.sh
bash tests/test-uninstall.sh
```

### Dry-run the installer

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```

### Implementation plans

Plans 1–7 are complete. Active work is tracked with `- [ ]` checkboxes in:
- `docs/plans/2026-03-16-ollama-linux-support.md` — Ollama backend (Plan 8)
- `docs/plans/2026-03-16-remote-backend-support.md` — Remote backend (Plan 9)

Mark steps complete with `- [x]` as you finish them.

### Slash commands available in this repo

After installing xgh into this project with `XGH_LOCAL_PACK=. bash install.sh`, the following commands become available:

- `/xgh-setup` — interactive MCP configuration
- `/xgh-help` — contextual guide and command reference
- `/xgh-brief` — session briefing
- `/xgh-ask` — search memory and context tree
- `/xgh-curate` — store knowledge in Cipher and context tree
- `/xgh-collab` — multi-agent collaboration
- `/xgh-design` — Figma-driven UI implementation
- `/xgh-implement` — ticket implementation
- `/xgh-investigate` — systematic debugging
- `/xgh-profile` — engineer throughput analysis
- `/xgh-retrieve` — run retrieval loop
- `/xgh-analyze` — run analysis loop
- `/xgh-track` — add project to monitoring
- `/xgh-doctor` — validate pipeline health
- `/xgh-index` — index a codebase
- `/xgh-calibrate` — calibrate dedup threshold
- `/xgh-init` — first-run onboarding

### Memory usage

If lossless-claude MCP is configured in this project, use it proactively:
- `lcm_search(query)` before starting any task
- `lcm_store(summary, ["session"])` after completing significant work (extract 3-7 bullet summary first)
- `lcm_store(text, ["reasoning"])` when making non-trivial architectural decisions

Refer to [`AGENTS.md`](./AGENTS.md) for the full decision protocol table.
