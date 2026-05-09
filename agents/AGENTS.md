# agents/ — Agent Definitions

3 agent definitions for the xgh pipeline. Each agent is a Markdown file with YAML frontmatter (`name`, `description`, `model`, optional `capabilities`).

## Agents

| Agent | File | Role |
|---|---|---|
| `xgh:context-curator` | `context-curator.md` | Audits context tree for stale entries, missing coverage, manifest consistency — dispatched after significant project changes |
| `xgh:pipeline-doctor` | `pipeline-doctor.md` | Deep investigation of xgh pipeline health — goes beyond `/xgh-doctor` to root-cause retrieval/scheduling/inbox/trigger failures |
| `xgh:retrieval-auditor` | `retrieval-auditor.md` | Audits provider health and retrieval quality — checks fetch logs, inbox quality metrics, coverage gaps |

## Dispatch Contract

- Agents are invoked via Claude Code's Agent tool with `subagent_type: "xgh:<name>"`
- Agent frontmatter `capabilities` and `tools` fields are read by `gen-agents-md.sh` to populate the root AGENTS.md Agent Roster table
- Adding a new agent: create `agents/<name>.md` with `name:` frontmatter → re-run `bash scripts/gen-agents-md.sh` to regenerate root AGENTS.md
