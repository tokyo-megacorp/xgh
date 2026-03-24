---
name: xgh:test-builder
description: "Use when running /xgh-test-builder or asking to generate tests or build a test suite. Generates tailored test suites from architectural analysis — module boundaries, public surfaces, and integration points — producing a structured manifest of test flows."
---

# xgh:test-builder — Test Suite Generator

## Prerequisites — Resolve active project

Follow the shared project resolution protocol in `skills/_shared/references/project-resolution.md`. Store the resolved project name for use in subsequent steps. If resolution fails, follow the error-specific guidance in the shared protocol.

## Argument Parsing

Read `$ARGUMENTS`:

- `init` → run the init phase (Steps 1–6 below)
- `run` or `run <flow-name>` → run the run phase (Phase 2 placeholder)
- No argument or unrecognized → show usage:

```
Usage:
  /xgh-test-builder init              — analyze architecture, generate manifest
  /xgh-test-builder run               — execute all test flows
  /xgh-test-builder run <flow-name>   — execute a specific flow by name
```

---

## Phase 1: Init

### Step 1 — Hard prerequisite: architecture freshness

#### 1a — Search memory for architecture entries (see `_shared/references/memory-backend.md`)

[SEARCH] tags `["xgh:architecture", "<repo-name>"]` → call `lcm_search("xgh:architecture", { tags: ["xgh:architecture", "<repo-name>"] })`.

- If no results returned → stop:
  > "No architecture analysis found for `<repo-name>`. Run `/xgh:architecture` first."

#### 1b — Check architecture age from ingest.yaml

```bash
python3 -c "
import sys, os
from datetime import datetime, timezone
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'pyyaml', '-q'])
    import yaml

name = sys.argv[1]
path = os.path.expanduser('~/.xgh/ingest.yaml')
data = yaml.safe_load(open(path))
cfg = data.get('projects', {}).get(name, {})
arch = cfg.get('architecture', {})
last_run = arch.get('last_run')
mode = arch.get('mode', 'quick')
if not last_run:
    print('NEVER|quick')
    sys.exit(0)

dt = datetime.fromisoformat(last_run)
now = datetime.now(timezone.utc)
days = (now - dt).days
print(f'{days}|{mode}')
" "<repo-name>"
```

Parse the output as `<days>|<arch-mode>`:

- If `NEVER|*` → stop: "Architecture timestamp missing for `<repo-name>`. Run `/xgh:architecture` first."
- If days > 30 → stop: "Architecture is N days old (>30 day limit). Run `/xgh:architecture` first."
- If days > 7 → warn: "Architecture analysis is N days old. Consider re-running `/xgh:architecture`." (continue)

#### 1c — Check mode adequacy

If `<arch-mode>` is `quick`:
- [SEARCH] public-surfaces artifact (tags `["xgh:architecture", "public-surfaces", "<repo-name>"]`) → call `lcm_search(...)`.
- If multiple surface types detected (e.g. cli + api, or api + web) → recommend: "Consider running `/xgh:architecture full` for deeper analysis — critical-paths and test-landscape will improve test generation."

---

### Step 2 — Read architectural definitions

[SEARCH] from memory backend → call `lcm_search`:

| Artifact | Tags | Required |
|----------|------|----------|
| module-boundaries | `["xgh:architecture", "module-boundaries", "<repo-name>"]` | yes |
| public-surfaces | `["xgh:architecture", "public-surfaces", "<repo-name>"]` | yes |
| integration-points | `["xgh:architecture", "integration-points", "<repo-name>"]` | yes |
| critical-paths | `["xgh:architecture", "critical-paths", "<repo-name>"]` | no (full only) |
| test-landscape | `["xgh:architecture", "test-landscape", "<repo-name>"]` | no (full only) |

Save all retrieved content for use in subsequent steps.

---

### Step 3 — Determine project surface type

Read `surfaces` from ingest.yaml:

```bash
python3 -c "
import sys, os, json
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'pyyaml', '-q'])
    import yaml

name = sys.argv[1]
path = os.path.expanduser('~/.xgh/ingest.yaml')
data = yaml.safe_load(open(path))
cfg = data.get('projects', {}).get(name, {})
print(json.dumps(cfg.get('surfaces', [])))
" "<repo-name>"
```

Cross-reference with the `public-surfaces` artifact from memory. Map detected surfaces to strategies:

| Surface | Strategy |
|---------|----------|
| CLI commands | Acceptance — run commands, assert stdout/exit codes |
| API endpoints | Contract + integration — HTTP calls, response validation |
| Web UI routes | E2E — browser-based (Playwright/Cypress) |
| Mobile app screens | E2E — device/simulator flows |
| Library/SDK exports | Contract — public API assertions |
| Mixed surfaces | Layered — multiple strategy types |

Save `<detected-surfaces>` (list) and `<strategies>` (list).

---

### Step 4 — Complexity gate

Check these 5 explicit triggers:

1. Multiple surfaces detected (`len(<detected-surfaces>) > 1`)
2. No clear entry point found in public-surfaces artifact
3. Auth/stateful setup required (detected from integration-points: auth providers, session stores)
4. External dependencies needing mocking (from integration-points: external APIs, message queues)
5. Test landscape shows <30% coverage in critical paths (if test-landscape available from full mode)

**If ANY trigger fires → interview developer using AskUserQuestion:**

Ask each question in sequence:
- "What are your critical user journeys? (e.g. 'user signs up', 'checkout completes')"
- "What breaks frequently vs what's stable?"
- "Which external dependencies should be mocked vs hit live?"
- "What's your deployment target? (local dev, CI, staging, prod)"

Save answers as `<interview-answers>`.

**If NO triggers fire → autonomous generation.** Proceed directly to Step 5.

---

### Step 5 — Generate manifest atomically

Create the output directory:

```bash
mkdir -p .xgh/test-builder
```

Write the manifest to a temp file first:

```bash
# Write to .xgh/test-builder/manifest.yaml.tmp
# Validate all required fields present, no unresolved placeholders
# Move to .xgh/test-builder/manifest.yaml
# If any step fails → delete temp file, report error, exit
```

Use Write tool to create `.xgh/test-builder/manifest.yaml.tmp` with the following schema:

```yaml
version: 1
project: <repo-name>
generated: <ISO timestamp>
architecture_ref: <architecture.last_run timestamp>

surfaces:
  - type: <api|cli|web|mobile|library>
    entry: <path or endpoint>

strategies:
  - name: <strategy-name>
    executor: <shell|http|browser|mobile|library|custom>

flows:
  - name: <flow-name>
    surface: <surface-type>
    strategy: <strategy-name>
    goal: "<what this flow validates>"
    prerequisites:
      - run: <command>
        wait_for: <condition>
    steps:
      - run: <command or action>
        assert:
          <assertion-type>: <expected>
    cleanup:
      - run: <command>
```

Populate the manifest from architectural artifacts and interview answers (if applicable). Generate one flow per critical path (if available) or per public surface entry point.

**Validation before move:** Check:
- `version` is present and equals `1`
- `project` matches `<repo-name>`
- `flows` list is non-empty
- No step contains literal placeholder text (`<`, `>` brackets in `run` or `assert` values)
- Each flow has at least one step

If validation passes → use Bash `mv` to move temp file to final path:

```bash
mv .xgh/test-builder/manifest.yaml.tmp .xgh/test-builder/manifest.yaml
```

If validation fails → delete temp file and stop:

```bash
rm -f .xgh/test-builder/manifest.yaml.tmp
```

Report: "Manifest generation failed: <reason>. No partial manifest written."

---

## Reference

### Executor Kinds Reference

| Executor | What it does | Prerequisites |
|----------|-------------|---------------|
| shell | Runs command, captures stdout/stderr/exit code | None (default) |
| http | HTTP requests via curl, asserts status/headers/body | Service running |
| browser | Delegates to Playwright/Cypress | npx playwright available |
| mobile | Delegates to XCTest/Espresso/AXe | Simulator running |
| library | Imports and calls exported functions | Native test runner |
| custom | Runs user script, exit code 0 = pass | Script exists |

### Assertion Types Reference

| Assertion | Applies to | Example |
|-----------|-----------|---------|
| exit_code | shell, custom | `exit_code: 0` |
| stdout_contains | shell, custom | `stdout_contains: "OK"` |
| stdout_matches | shell, custom | `stdout_matches: "v\\d+\\.\\d+"` |
| status | http | `status: 200` |
| body_contains | http | `body_contains: '"ok"'` |
| body_json_path | http | `body_json_path: { path: "$.id", exists: true }` |
| header_contains | http | `header_contains: { key: "content-type", value: "json" }` |
| file_exists | any | `file_exists: "./output.html"` |
| returns | library | `returns: { type: "object", has_key: "id" }` |

---

#### Step 6 — Optional native scaffold

For known ecosystems, generate test files that implement the manifest flows. The manifest remains the source of truth — native files are a convenience layer.

| Ecosystem detected | Test file generated |
|--------------------|---------------------|
| Node.js / TypeScript | `tests/xgh-generated.test.ts` (Vitest/Jest) |
| Go | `tests/xgh_generated_test.go` |
| Rust | `tests/xgh_generated.rs` |
| Python | `tests/test_xgh_generated.py` |
| Swift / iOS | `Tests/XghGeneratedTests.swift` |
| Shell (no framework) | `tests/xgh-generated.sh` |

If ecosystem is not recognized or scaffold generation is not feasible → skip silently.

---

#### Step 7 — Generate strategy.md

Write `.xgh/test-builder/strategy.md` using the Write tool. This is a human-readable companion to the manifest documenting what is being tested and why.

Format:

```markdown
# Test Strategy — <repo-name>

Generated: <ISO timestamp>
Architecture ref: <architecture.last_run>

## Surfaces

<list of detected surfaces and their strategies>

## Flows

For each flow in the manifest:
- **<flow-name>**: <goal>
  - Surface: <surface>
  - Executor: <executor>
  - Steps: <count>

## Why These Tests

<2-3 sentence rationale derived from architecture + complexity gate outcome>

## Coverage Gaps

<list any known gaps — surfaces with no flows, untested critical paths>
```

---

#### Init Completion

Print a summary:

```
Test suite manifest generated for <repo-name>
  Surfaces: <count> (<list>)
  Flows: <count>
  Strategies: <list>
  Manifest: .xgh/test-builder/manifest.yaml
  Strategy: .xgh/test-builder/strategy.md
```

*Run `/xgh:test-builder run` to execute all flows, or `/xgh:test-builder run <flow-name>` to run a specific flow.*

---

### Phase 2: Run

#### Argument Parsing

Read `$ARGUMENTS`:

- No argument or just `run` → execute all flows from manifest
- `run <flow-name>` → execute only that flow

#### Manifest Loading & Validation

Check if `.xgh/test-builder/manifest.yaml` exists:

```bash
if [ ! -f .xgh/test-builder/manifest.yaml ]; then
  echo "No manifest found. Run \`/xgh:test-builder init\` first."
  exit 1
fi
```

Parse the YAML file. Use Python to validate:

```python
import sys, yaml, re

try:
    with open('.xgh/test-builder/manifest.yaml') as f:
        manifest = yaml.safe_load(f)
except Exception as e:
    print(f"Failed to parse manifest: {e}")
    sys.exit(1)

# Validation checks
errors = []

# Check version
if 'version' not in manifest:
    errors.append("Missing 'version' field")
elif manifest['version'] != 1:
    errors.append(f"Invalid version: {manifest['version']} (expected 1)")

# Check required top-level fields
for field in ['project', 'flows']:
    if field not in manifest:
        errors.append(f"Missing '{field}' field")

# Check for unresolved placeholders in all string values
placeholder_pattern = r'(TODO|FIXME|\?\?\?|<[^>]+>)'

def check_placeholders(obj, path=""):
    issues = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            issues.extend(check_placeholders(v, f"{path}.{k}"))
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            issues.extend(check_placeholders(item, f"{path}[{i}]"))
    elif isinstance(obj, str):
        if re.search(placeholder_pattern, obj):
            issues.append(f"Unresolved placeholder at {path}: '{obj}'")
    return issues

errors.extend(check_placeholders(manifest))

# Validate flow schema
for i, flow in enumerate(manifest.get('flows', [])):
    flow_name = flow.get('name', f'<flow-{i}>')
    if 'name' not in flow:
        errors.append(f"Flow {i}: missing 'name'")
    if 'surface' not in flow:
        errors.append(f"Flow '{flow_name}': missing 'surface'")
    if 'strategy' not in flow:
        errors.append(f"Flow '{flow_name}': missing 'strategy'")
    if 'goal' not in flow:
        errors.append(f"Flow '{flow_name}': missing 'goal'")
    if 'steps' not in flow or not isinstance(flow['steps'], list):
        errors.append(f"Flow '{flow_name}': missing or invalid 'steps'")
    elif len(flow['steps']) == 0:
        errors.append(f"Flow '{flow_name}': steps list is empty")

if errors:
    print("Manifest validation failed:")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)

print("OK")
```

If validation fails → refuse to execute and list all errors.

#### Execute Flows

For each flow (all flows or selected flow only):

**1. Run prerequisites (if any)**

```bash
for prereq in flow.prerequisites:
  run: <command>
  wait_for: <condition>  # e.g. "port 3000 listens" or "file exists"
```

Wait until condition is met (timeout: 30s). If timeout → skip flow with note "Prerequisite failed: <condition>".

**2. Execute steps**

For each step in the flow:

```bash
run: <command or action>
assert:
  <assertion-type>: <expected>
```

Dispatch based on executor kind from strategy:

| Executor | Action |
|----------|--------|
| shell | Run command via `/bin/bash -c`, capture stdout/stderr/exit code |
| http | Parse `run` as method+URL (e.g. `GET /api/health`), execute curl, check assertions |
| browser | Delegate to Playwright (check if `npx playwright` available; if not, skip with ⏭️) |
| mobile | Delegate to simulator tool (check if available; if not, skip with ⏭️) |
| library | Import module + call function (check if importable; if not, skip with ⏭️) |
| custom | Execute user script at path; exit 0 = pass (check if executable; if not, skip with ⏭️) |

**Step result tracking:**

- **pass**: assertion succeeded
- **fail**: assertion failed (reason: "Expected X, got Y")
- **skip**: executor unavailable or prereq failed (reason: "Executor not installed")

Evaluate assertions against captured output:

| Assertion | Against | Check |
|-----------|---------|-------|
| exit_code | shell/custom | stdout_contains \| stdout_matches \| status \| body_contains \| body_json_path \| header_contains \| file_exists \| returns |
| stdout_contains | shell/custom | stdout includes substring |
| stdout_matches | shell/custom | stdout matches regex |
| status | http | HTTP status code |
| body_contains | http | response body includes substring |
| body_json_path | http | JSONPath query returns expected value |
| header_contains | http | response header key/value match |
| file_exists | any | file exists at path |
| returns | library | function return value matches type/structure |

**3. Run cleanup (if any)**

Even if any step failed, run cleanup steps:

```bash
for cleanup in flow.cleanup:
  run: <command>
```

Failures in cleanup do NOT affect overall flow result.

**4. Collect results**

Track per step: name, executor, result (pass/fail/skip), duration (ms), notes.

#### Output Format

Generate a markdown summary table:

```markdown
## 🧪 test-builder run

| Flow | Surface | Steps | Result | Notes |
|------|---------|-------|--------|-------|
| health-check | api | 1/1 | ✅ | 200ms |
| user-reg | api | 2/2 | ✅ | |
| duplicate | api | 0/1 | ❌ | Expected 409, got 500 |
| browser-flow | web | 0/2 | ⏭️ | Playwright not installed |

4 flows · 3/6 steps passed · 1 failure · 2 skipped
```

**Legend:**
- ✅ All steps passed
- ❌ One or more steps failed (show first failure reason)
- ⏭️ All steps skipped (executor unavailable)

#### Run Completion

Print summary:

```
Test suite run completed
  Flows: <total>
  Passed: <count>
  Failed: <count>
  Skipped: <count>
  Duration: <total-ms>ms
```

Exit with:
- 0 if all flows passed or skipped
- 1 if any flow failed
