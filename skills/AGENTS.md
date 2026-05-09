# skills/ — Skill Collection

14 skill subdirs for the xgh intelligence pipeline. Each subdir contains a `SKILL.md` with YAML frontmatter (`name`, `description`, `triggers`).

## Skills

| Skill | Dir | Role |
|---|---|---|
| `xgh:analyze` | `analyze/` | Analyzes a signal or context item — produces structured findings |
| `xgh:briefing` | `briefing/` | Generates the daily briefing from retrieved inbox items |
| `xgh:calibrate` | `calibrate/` | Calibrates provider weights and scoring thresholds |
| `xgh:command-center` | `command-center/` | Unified command dispatch — routes commands to appropriate skills |
| `xgh:config` | `config/` | Reads and validates `xgh.yaml` config |
| `xgh:deep-retrieve` | `deep-retrieve/` | Deep retrieval — follows links, expands context |
| `xgh:doctor` | `doctor/` | Pipeline health check — validates providers, inbox, triggers |
| `xgh:init` | `init/` | Project initialization — scaffolds xgh.yaml and provider config |
| `xgh:init-providers` | `init-providers/` | Provider initialization — auto-generates provider configs from API specs |
| `xgh:retrieve` | `retrieve/` | Standard retrieval cycle — fetches from all active providers |
| `xgh:schedule` | `schedule/` | Manages cron-based retrieval scheduling |
| `xgh:seed` | `seed/` | Seeds the context tree with initial knowledge |
| `xgh:token-window` | `token-window/` | Token budget management and window allocation |
| `xgh:track` | `track/` | Tracks decisions and findings to MAGI vault |
| `xgh:trigger` | `trigger/` | Evaluates and fires triggers based on inbox items |

## SKILL.md Format

```yaml
---
name: xgh:<skill-name>
description: One-line summary for skill discovery
triggers:
  - pattern that triggers this skill
---
```

Body: instructions the agent follows. Keep under 500 words. Write artifacts to files, not inline.

## Adding a Skill

1. Create `skills/<name>/SKILL.md` with the frontmatter above
2. Add to the table above
3. Register in `.claude-plugin/plugin.json` under `skills:`
4. Run `bash tests/test-pipeline-skills.sh` to verify discovery
