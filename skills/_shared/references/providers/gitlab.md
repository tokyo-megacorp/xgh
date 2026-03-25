# GitLab Provider Reference

Provider-specific patterns for GitLab MR workflows. Framework for future support.

## Reviewer Assignment

GitLab uses MR reviewer assignment via the API or `glab` CLI:
```bash
glab mr update <MR> --reviewer <login>
```

## Approval Rules

GitLab supports configurable approval rules at the project level. MRs may require N approvals before merge.

## Thread Resolution

GitLab uses REST API for thread resolution:
```bash
# PUT /projects/:id/merge_requests/:iid/discussions/:discussion_id/notes/:note_id
# with body: { "resolved": true }
```

## Suggestion Commits

GitLab supports inline suggestion commits similar to GitHub.
