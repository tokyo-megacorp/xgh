Bump the version across all 3 files (`package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`), open a PR to main, merge it, and wait for `publish.yml` to handle npm publish, git tag, and GitHub release. Then edit the release with polished notes.

## Usage

```
/release patch    # 2.2.1 → 2.2.2
/release minor    # 2.2.1 → 2.3.0
/release major    # 2.2.1 → 3.0.0
/release 2.5.0    # explicit version
```

Argument: $ARGUMENTS (default: patch)

## Steps

### Bump version

1. `git checkout develop && git pull origin develop`
2. Read current version from `package.json`
3. Compute new version from the argument (patch/minor/major or explicit semver)
4. Create branch: `git checkout -b release/v<new_version>`
5. Update version in all 3 files:
   - `package.json`
   - `.claude-plugin/plugin.json`
   - `.claude-plugin/marketplace.json`
6. Commit: `chore: bump version to <new_version>`
7. Push branch and open PR targeting `main`:
   ```
   gh pr create --base main --title "Release v<new_version>" --body "Bump version to <new_version> for npm publish."
   ```
8. Merge the PR: `gh pr merge --squash --delete-branch`

### Wait for release

9. Poll `gh release view v<new_version>` every 30 seconds until the release exists (max 5 minutes)
10. If timeout: tell the user to check Actions and run step 11 manually later

### Edit release notes

11. Make sure you have the latest tags: `git fetch --tags origin`
12. Gather changelog: `git log --oneline v<previous_version>..v<new_version>`
13. Write release notes to a file (for example `release-notes-v<new_version>.md`) and edit the GitHub release with `gh release edit v<new_version> --notes-file release-notes-v<new_version>.md`. The notes should:
    - Lead with a **one-liner hook** — what's the headline change a user cares about?
    - Group changes under `## Highlights` (features worth calling out with 2-3 sentence explanations) and `## Changes` (bulleted list, conventional-commit style)
    - Use active voice, present tense ("Adds", "Fixes", not "Added", "Fixed")
    - Skip internal chores unless they affect users (CI, test-only, docs-only changes are noise)
    - End with `**Full Changelog**: https://github.com/tokyo-megacorp/xgh/compare/v<previous_version>...v<new_version>`
    - Tone: confident, concise, no filler. Think Apple release notes meets open-source changelog.

## Rules

- NEVER push directly to main or develop — always go through a PR
- NEVER force-push to any protected branch
- NEVER create tags manually — publish.yml does that
- If working tree is dirty, abort and tell the user to commit or stash first
