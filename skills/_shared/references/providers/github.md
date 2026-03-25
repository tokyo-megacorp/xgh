# GitHub Provider Reference

Provider-specific quirks for GitHub PR workflows. Referenced by ship-prs, watch-prs, and pr-poller.

## Copilot Code Review Behavior

**Copilot's code review bot (`copilot-pull-request-reviewer[bot]`) never submits an `APPROVED` review.** It always posts at least one comment. It either leaves inline fix requests (review state: `COMMENTED` or `CHANGES_REQUESTED`) or submits a comment-only review with observations. There is no approval signal — at best, it simply has no change requests.

**Every Copilot comment must be addressed before merge.** For each comment:
- **Accept:** Apply the fix, push, and reply with the commit URL (e.g., "Fixed in `<commit_url>`")
- **Reject:** Reply explaining why it won't be addressed (e.g., "Not addressing: pre-existing pattern, out of scope for this PR")

### Merge-ready criteria

A PR is merge-ready when:
1. A review exists from the Copilot bot, AND
2. Every inline comment has a reply (accept or reject — no unaddressed comments), AND
3. No `CHANGES_REQUESTED` review state is pending

Do NOT wait for `reviewDecision == "APPROVED"` or `state == "APPROVED"` from Copilot.

## Two Copilot Systems — Critical Distinction

| System | Trigger | What it does | Safe? |
|--------|---------|-------------|-------|
| Code Review bot | Reviewer list cycle (`gh pr edit --add-reviewer`) | Leaves inline comments on the PR | Yes — this is what we use |
| SWE Delegation Agent | `@copilot` tag in a PR comment | Opens new sub-PRs with AI-generated fixes | **NEVER use** — creates unwanted PRs |

**NEVER use `@copilot` in any comment.** Even `@copilot review` triggers the SWE delegation agent. The reviewer list cycle is the only safe method.

## Reviewer List Cycle

The only safe way to request/re-request a Copilot review:

```bash
# gh pr edit uses GraphQL — no [bot] suffix needed
gh pr edit <PR> --repo <REPO> --remove-reviewer copilot-pull-request-reviewer 2>/dev/null
gh pr edit <PR> --repo <REPO> --add-reviewer copilot-pull-request-reviewer
```

Copilot does NOT read replies on its review comments. Re-requesting via reviewer list is the only way to get another pass.

## `[bot]` Suffix Rules

| API | Login format | Example |
|-----|-------------|---------|
| REST API (`gh api`) | Include `[bot]` suffix | `copilot-pull-request-reviewer[bot]` |
| GraphQL / `gh pr edit` | Strip `[bot]` suffix | `copilot-pull-request-reviewer` |

## Field Mapping

| project.yaml field | Value | Purpose |
|-------------------|-------|---------|
| `reviewer` | `copilot-pull-request-reviewer[bot]` | Used in REST API calls and reviewer list |
| `reviewer_comment_author` | `Copilot` (capital C) | The `.user.login` on PR review *comments* — use for `select(.user.login == ...)` |

These are different logins. The bot that submits reviews is `copilot-pull-request-reviewer[bot]`, but the comments it leaves have `.user.login == "Copilot"`.

## `review_on_push` Behavior

When `review_on_push: true` (repo setting), Copilot automatically re-reviews whenever new commits are pushed to a PR that already has it as a reviewer. Manual re-requests after pushing fixes may be redundant.

## Reply Conventions

- After a fix is pushed: `"Fixed in <commit_url>"`
- When not fixing: `"Not addressing: <one-line reasoning>"`
- **Tag human reviewers** in replies (`@username`)
- **NEVER tag bot reviewers** — any login ending in `[bot]`
