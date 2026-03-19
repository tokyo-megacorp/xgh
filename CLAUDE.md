# CLAUDE.md — xgh (eXtreme Go Horse)

> **Primary instructions:** See [`AGENTS.md`](./AGENTS.md) for the complete guide to working on this repository — project overview, tech stack, file structure, development guidelines, test commands, implementation status, and the Superpowers methodology.

---

## Claude Code — Quick Reference

### Run tests

```bash
bash tests/test-install.sh
bash tests/test-config.sh
bash tests/test-uninstall.sh
```

### Install for development

```bash
claude plugin install .
/xgh-init
```

### Slash commands

After installing, all `/xgh-*` commands are available. Run `/xgh-help` for the full list.

### Memory usage

If lossless-claude MCP is configured in this project, use it proactively:
- `lcm_search(query)` before starting any task
- `lcm_store(summary, ["session"])` after completing significant work (extract 3-7 bullet summary first)
- `lcm_store(text, ["reasoning"])` when making non-trivial architectural decisions

Refer to [`AGENTS.md`](./AGENTS.md) for the full decision protocol table.
