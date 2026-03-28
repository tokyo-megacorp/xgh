---
name: xgh:archive
description: "This skill should be used when the user runs /xgh-archive, asks to 'archive completed files', 'move done plans', 'clean up completed items', 'archive status:completed', or 'sweep old docs'. Scans markdown files for YAML frontmatter with status: completed or status: archived, and moves them to an archive/ subdirectory alongside the source file, preserving relative path structure."
---

> **Output format:** Follow the [xgh output style guide](../../templates/output-style.md). Start with `## 🐴🤖 xgh archive`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-archive — Completed File Archiver

Moves markdown files with `status: completed` or `status: archived` in their YAML frontmatter into an `archive/` subdirectory co-located with the source file. Keeps the repo clean while preserving historical artifacts.

## Usage

```
/xgh-archive [--path <dir>] [--dry-run] [--status <completed|archived|both>] [--since <YYYY-MM-DD>]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--path` | current repo root | Directory to scan (recursive) |
| `--dry-run` | off | Show what would be moved without moving anything |
| `--status` | both | Which status values to archive (`completed`, `archived`, or `both`) |
| `--since` | (none) | Only archive files with `date:` or `updated:` on or before this date |

## Step 1 — Guard checks

1. Confirm we are inside a git repo:
   ```bash
   git rev-parse --is-inside-work-tree 2>/dev/null || echo "NOT_GIT"
   ```
   If not a git repo: warn but proceed (archiving still makes sense outside git).

2. Confirm no uncommitted changes to the target path (optional, only warn):
   ```bash
   git status --porcelain <path> 2>/dev/null | head -5
   ```
   If there are staged changes, warn: `⚠️ Uncommitted changes in <path> — commit before archiving to preserve git history cleanly.`

## Step 2 — Discover candidates

Scan `--path` recursively for all `.md` files. Exclude:
- Files already inside any `archive/` directory (already archived)
- `node_modules/`, `.git/`, `plugins/cache/`
- Files without YAML frontmatter (no `---` block)

For each file, extract `status` from frontmatter:

```python
import re, yaml, os

def get_status(filepath):
    with open(filepath) as f:
        content = f.read()
    m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not m:
        return None
    try:
        fm = yaml.safe_load(m.group(1)) or {}
        return fm.get("status", None)
    except:
        return None
```

Filter to files where `status` matches the `--status` flag:
- `both` (default): include `status: completed` AND `status: archived`
- `completed`: only `status: completed`
- `archived`: only `status: archived`

If `--since` is set, also check `date:` or `updated:` frontmatter field — only include files where that date is on or before `--since`.

## Step 3 — Compute archive destination

For each candidate file at path `<parent>/<filename>.md`:

1. Target directory: `<parent>/archive/`
2. Target filename: same as source — `<filename>.md`
3. If `<parent>/archive/<filename>.md` already exists:
   - Check if they are identical (compare content hash)
   - If identical: skip (already archived, source is a duplicate)
   - If different: append a suffix `<filename>-<date>.md` where `<date>` is today's date

```python
import hashlib

def file_hash(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

def compute_dest(src_path):
    parent = os.path.dirname(src_path)
    filename = os.path.basename(src_path)
    archive_dir = os.path.join(parent, "archive")
    dest = os.path.join(archive_dir, filename)

    if os.path.exists(dest):
        if file_hash(src_path) == file_hash(dest):
            return None  # identical, skip
        # Conflict: use date suffix
        stem, ext = os.path.splitext(filename)
        from datetime import date
        dest = os.path.join(archive_dir, f"{stem}-{date.today()}{ext}")
    return dest
```

## Step 4 — Dry run output (--dry-run only)

If `--dry-run`, print the plan and stop:

```
## 🐴🤖 xgh archive (dry run)
Would archive 3 files:

| Source | Destination | Status |
|--------|-------------|--------|
| plans/sp1-foundation.md | plans/archive/sp1-foundation.md | completed |
| plans/sp2-validate.md | plans/archive/sp2-validate.md | completed |
| agents/old-researcher.md | agents/archive/old-researcher.md | archived |

No files moved (dry run). Run without --dry-run to apply.
```

## Step 5 — Move files

For each candidate (not dry-run):

1. Create `archive/` directory if it does not exist:
   ```python
   os.makedirs(archive_dir, exist_ok=True)
   ```

2. Move the file:
   ```python
   import shutil
   shutil.move(src_path, dest_path)
   ```

3. If inside a git repo, use `git mv` instead of `shutil.move` to preserve history:
   ```bash
   git mv "<src>" "<dest>"
   ```
   Fall back to `shutil.move` if `git mv` fails (e.g., file not tracked).

4. Track each move result: success, skipped (identical duplicate), or error.

## Step 6 — Update references (optional, best-effort)

After moving files, search the repo for markdown links pointing to moved files:

```python
import re, pathlib

def find_references(repo_root, moved_files):
    """moved_files: dict of {old_rel_path: new_rel_path}"""
    refs = {}  # filepath -> list of (old_link, new_link)
    for md_file in pathlib.Path(repo_root).rglob("*.md"):
        content = md_file.read_text()
        for old_rel, new_rel in moved_files.items():
            old_name = os.path.basename(old_rel)
            if old_name in content or old_rel in content:
                refs.setdefault(str(md_file), []).append((old_rel, new_rel))
    return refs
```

If references found, report them but do NOT auto-update (links are content-sensitive — let the user review):

```
⚠️ References to moved files found — review and update manually:
  - README.md mentions plans/sp1-foundation.md → now at plans/archive/sp1-foundation.md
```

## Step 7 — Output

### Success case

```
## 🐴🤖 xgh archive
Archived 3 files.

| File | Destination | Result |
|------|-------------|--------|
| `plans/sp1-foundation.md` | `plans/archive/sp1-foundation.md` | ✅ moved |
| `plans/sp2-validate.md` | `plans/archive/sp2-validate.md` | ✅ moved |
| `agents/old-researcher.md` | `agents/archive/old-researcher.md` | ✅ moved |

⚠️ References to moved files found in 1 file — review manually:
  - README.md → plans/sp1-foundation.md

Results: 3 moved, 0 skipped, 0 errors
```

### Nothing to archive

```
## 🐴🤖 xgh archive
No files found with status: completed or status: archived.

*Add `status: completed` to finished plans or agents to include them in the next archive run.*
```

### Partial failure

```
## 🐴🤖 xgh archive
Archived 2 of 3 files.

| File | Result |
|------|--------|
| `plans/sp1-foundation.md` | ✅ moved |
| `plans/sp2-validate.md` | ✅ moved |
| `agents/my-agent.md` | ❌ error: permission denied |

Results: 2 moved, 0 skipped, 1 error
*Fix: check file permissions on agents/my-agent.md*
```

## archive/ directory convention

Each `archive/` directory created by this skill is a sibling of the source files:

```
plans/
  active-plan.md
  archive/
    sp1-foundation.md    ← moved here by /xgh-archive
    sp2-validate.md      ← moved here by /xgh-archive
agents/
  current-agent.md
  archive/
    old-researcher.md    ← moved here by /xgh-archive
```

Files in `archive/` are:
- Exempt from `/xgh-frontmatter` validation (historical artifacts)
- Excluded from `/xgh-doctor` frontmatter health check
- Excluded from future `/xgh-archive` runs (already archived)

## Common mistakes

### Moving files not tracked by git
If the file was never committed, `git mv` won't work. The skill falls back to `shutil.move` automatically. No history is lost since there was no history to preserve.

### Archiving the wrong status
`status: draft` and `status: active` are never archived — only `completed` and `archived`. If the user wants to archive a `draft`, they should first change the status manually.

### Broken links after archiving
The skill reports broken links but does not fix them. This is intentional — link updates require understanding the document's context (relative vs absolute paths, whether the link should be updated or removed). Always review the reference report before committing archived files.

### Running archive before committing current work
If there are staged changes, the `git mv` operations will mix into the same unstaged diff. Best practice: commit or stash current work first, then run `/xgh-archive`, then commit the archive moves separately.
