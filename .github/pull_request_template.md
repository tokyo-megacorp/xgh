## Summary

<!-- What changed? Be specific — Copilot uses this for review context. -->

## Motivation / Why

<!-- Why is this change needed? What problem does it solve? -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring (no behavior change)
- [ ] Chore / infra / config
- [ ] Documentation

## Testing done

<!-- Describe how you tested. For provider scripts: did gh CLI calls return expected output? -->
[NO_TEST_SUITE: xgh — integration tested manually against live GitHub]

## Related issues

<!-- Closes #N -->

## Copilot review focus areas

> This repo is a GitHub ingestion pipeline using gh CLI, jq, shell scripts, and xgh skills/agents.
> Please pay extra attention to:

- **Provider script correctness**: `gh` CLI calls use correct flags? `jq` expressions handle null/empty input?
- **Error handling**: Does the script fail gracefully on API errors or empty responses? No silent failures?
- **Bash 3.2 compatibility**: No `declare -A` associative arrays, `mapfile`, `readarray`, or `&>>`?
- **YAML/frontmatter validity**: Are all YAML keys properly quoted where needed? No trailing spaces?
- **LCM tagging conventions**: Tags follow `[project:name, type:solution/gotcha, sprint:spN]` format?
- **`ingest.yaml` cron schedules**: No interval shorter than 5 minutes? Cron expression is valid?
- **Shell safety**: `set -euo pipefail`? No unquoted `$variables`? Paths use variables not literals?
- **`jq` null safety**: Are all `.field // ""` fallbacks in place for optional API fields?

## Checklist

- [ ] `set -euo pipefail` at top of every new shell script
- [ ] Bash 3.2 compatible (no bash 4+ features)
- [ ] `jq` expressions handle null/missing fields with fallbacks
- [ ] `gh` CLI calls checked for non-zero exit codes
- [ ] LCM tags follow `[project:name, type:solution/gotcha, sprint:spN]` convention
- [ ] `ingest.yaml` cron intervals are >= 5 minutes
- [ ] YAML frontmatter validated (no tabs, proper quoting)
- [ ] Manual test run documented above
