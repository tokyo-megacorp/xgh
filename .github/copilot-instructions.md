# Copilot Review Instructions — xgh (tokyo-megacorp)

This repo is a GitHub context ingestion pipeline: provider scripts pull data via `gh` CLI, transform it with `jq`, and store structured memory via MAGI. It also contains xgh skills and agent definitions.

## Primary concerns

### Provider script correctness (highest priority)
- All `gh` CLI calls must handle non-zero exit codes. Flag bare `gh api ...` without error checking.
- `jq` expressions must handle null and missing fields. Flag `.field` without `// "default"` fallback on optional API fields.
- Flag any `jq` expression that would fail on empty array input (e.g., `.[0]` without `// null` guard).

### Error handling
- Scripts must not silently swallow errors. `command || true` is only acceptable with a comment explaining why.
- Flag missing `|| exit 1` after critical operations (API calls, file writes).

### Bash 3.2 compatibility (macOS default)
- No `declare -A` associative arrays (bash 4+ only).
- No `mapfile` or `readarray`.
- No `&>>` append-redirect.
- Use `#!/usr/bin/env bash` not `#!/bin/bash`.

### YAML and frontmatter validity
- YAML keys with special characters must be quoted.
- No tab characters in YAML (use spaces).
- Markdown frontmatter must be valid YAML — flag unquoted colons in values.

### MAGI tagging conventions
- All `magi_store` calls must include tags following this pattern: `project:name,type:solution|gotcha|decision,sprint:spN`.
- Flag magi_store calls missing the `type:` or `project:` tags.
- `sprint:` tag must match the current sprint identifier format `spN` (e.g., `sp2`).

### ingest.yaml cron safety
- No cron schedule may run more frequently than every 5 minutes. Flag `*/1`, `*/2`, `*/3`, `*/4` minute intervals.
- Validate cron expression has exactly 5 fields.

### Shell safety
- `set -euo pipefail` at the top of every provider script.
- All `$variables` quoted in commands, especially file paths.

## What to skip
- Don't flag missing unit tests — this pipeline is tested by running against live GitHub data.
- Don't flag `gh` CLI usage patterns that are valid per `gh help`.
