---
name: xgh:frontmatter
description: "This skill should be used when the user runs /xgh-frontmatter, asks to 'validate frontmatter', 'check frontmatter', 'fix frontmatter', 'audit file headers', or 'add missing frontmatter'. Validates YAML frontmatter in markdown files against the schema in config/frontmatter-spec.yaml, reports missing or invalid fields, and optionally auto-adds missing required fields with --fix."
---

> **Output format:** Follow the [xgh output style guide](../../templates/output-style.md). Start with `## 🐴🤖 xgh frontmatter`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-frontmatter — Frontmatter Validator

Validates YAML frontmatter in markdown files against the per-filetype schema defined in `config/frontmatter-spec.yaml`. Detects missing required fields and invalid enum values. With `--fix`, auto-adds missing required fields.

## Usage

```
/xgh-frontmatter [--path <dir|file>] [--type <agents|plans|memory|skills>] [--fix] [--strict]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--path` | current repo root | Directory or file to validate |
| `--type` | auto-detect | Force a specific filetype schema |
| `--fix` | off | Auto-add missing required fields with placeholder values |
| `--strict` | off | Treat optional-field violations as errors |

## Step 1 — Load the spec

Read `config/frontmatter-spec.yaml` from the xgh repo root (or `~/.xgh/config/frontmatter-spec.yaml` if running from a different repo). Parse the YAML into a spec object.

If the spec file is not found:
```
❌ config/frontmatter-spec.yaml not found — run /xgh-doctor to diagnose
```
Stop.

## Step 2 — Discover files

Collect markdown files to validate:

1. If `--path` is a single file: validate only that file.
2. If `--path` is a directory (or omitted): scan recursively for `.md` files, exclude:
   - `node_modules/`
   - `.git/`
   - `plugins/cache/`
   - `archive/` subdirectories (archived files are exempt from validation)

## Step 3 — Detect filetype

For each file, determine which filetype schema applies:

1. If `--type` is specified, use that schema for all files.
2. Otherwise, match file path against `glob_patterns` in the spec:
   - `agents/**/*.md` → `agents` schema
   - `plans/**/*.md` → `plans` schema
   - `projects/*/memory/*.md` → `memory` schema
   - `skills/**/SKILL.md` or `skills/**/*.md` → `skills` schema
3. If no pattern matches: skip the file (not subject to frontmatter requirements).

## Step 4 — Parse frontmatter

For each matched file:

```python
import re, yaml

def extract_frontmatter(filepath):
    with open(filepath) as f:
        content = f.read()
    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return None, content
    try:
        fm = yaml.safe_load(match.group(1)) or {}
    except yaml.YAMLError as e:
        return "PARSE_ERROR:" + str(e), content
    return fm, content
```

- Returns `None` if no frontmatter block found (YAML `---` delimiters)
- Returns `"PARSE_ERROR:..."` if YAML is malformed

## Step 5 — Validate against schema

For each file + schema:

### 5a — Missing required fields

For each field in `schema.required`:
- If field key is absent from parsed frontmatter → **MISSING** error
- If field is present but empty string/null → **EMPTY** error

### 5b — Invalid enum values

For each required or optional field with `type: enum`:
- If field is present and its value is not in `allowed_values` → **INVALID_ENUM** error
- Report: `field 'model' = 'gpt-4o' — not in [claude-opus-4-5, claude-sonnet-4-5, ...]`

### 5c — Type mismatches (warnings)

For fields with `type: date`:
- If value doesn't match `YYYY-MM-DD` format → **TYPE_WARN** warning (not an error unless `--strict`)

For fields with `type: list`:
- If value is a plain string (not a YAML list) → **TYPE_WARN** warning

### 5d — No frontmatter block

If `extract_frontmatter` returned `None`:
- If any required fields exist for this filetype → **NO_FRONTMATTER** error
- Report: `no frontmatter block — required fields: name, description, model`

## Step 6 — Fix mode (--fix only)

If `--fix` is set, for each file with errors:

### 6a — Add missing frontmatter block

If the file has no frontmatter block at all:
```python
def add_frontmatter_block(filepath, fields_to_add, original_content):
    fm_lines = ["---"]
    for field_name, field_spec in fields_to_add.items():
        placeholder = field_spec.get("example", f"<{field_name}>")
        fm_lines.append(f"{field_name}: {placeholder}  # TODO: fill in")
    fm_lines.append("---")
    fm_lines.append("")
    new_content = "\n".join(fm_lines) + original_content
    with open(filepath, "w") as f:
        f.write(new_content)
```

### 6b — Add missing required fields to existing frontmatter

For each missing required field:
```python
def insert_field(filepath, field_name, field_spec, original_content):
    placeholder = field_spec.get("example", f"<{field_name}>")
    # Find the closing --- of the frontmatter block
    # Insert the new field before it
    new_line = f"{field_name}: {placeholder}  # TODO: fill in\n"
    content = re.sub(
        r'(^---\n.*?)(^---)',
        lambda m: m.group(1) + new_line + m.group(2),
        original_content,
        flags=re.DOTALL | re.MULTILINE
    )
    with open(filepath, "w") as f:
        f.write(content)
```

**Fix does NOT:**
- Overwrite existing values (even if invalid enum)
- Change optional fields
- Modify archive/ files

After fixing: re-validate and report the post-fix state.

## Step 7 — Output

### Summary table

```
## 🐴🤖 xgh frontmatter
Validated N files across M filetypes.
```

| File | Type | Status | Issues |
|------|------|--------|--------|
| `agents/my-agent.md` | agents | ✅ | — |
| `plans/sp4.md` | plans | ❌ | Missing: status, date |
| `skills/foo/SKILL.md` | skills | ⚠️ | Empty: description |
| `projects/x/memory/key.md` | memory | ❌ | YAML parse error |

### Detail section (only for files with issues)

For each file with errors or warnings:

```
### agents/researcher.md
❌ Missing required: model
   → Fix: add `model: claude-sonnet-4-5` (or run /xgh-frontmatter --fix)
⚠️ Type warning: date field 'created' = '27-03-2026' — expected YYYY-MM-DD
```

### Fix report (only when --fix was run)

```
### Fix summary
✅ agents/researcher.md — added: model
✅ plans/sp4.md — added: status, date
⚠️ projects/x/memory/key.md — skipped (YAML parse error, manual fix required)
```

### Footer

```
Results: N passed, M warnings, K errors
```

If errors > 0 (and `--fix` not run):
```
*Run `/xgh-frontmatter --fix` to auto-add missing required fields.*
```

If errors > 0 after `--fix`:
```
*K files still have errors that require manual attention (parse errors or invalid enum values).*
```

## Common mistakes

### Over-fixing
`--fix` only adds *missing required fields* with placeholder values. It does not resolve enum violations or parse errors. After a fix run, remind the user to replace `# TODO: fill in` placeholders with real values.

### Glob pattern ambiguity
If a file matches multiple glob patterns (e.g. `skills/doctor/doctor.md` could match both `skills/**/*.md` and `plans/**/*.md` if the directory structure is unusual), use the first matching pattern in spec order. Log: `⚠️ Multiple patterns matched — using first: skills`.

### Archive exemption
Files inside `archive/` subdirectories are exempt. Do not report them as violations — they are frozen historical artifacts.

### YAML parse errors block validation
If frontmatter YAML fails to parse, all other checks for that file are skipped. Report the parse error line number if available and suggest running a YAML linter.
