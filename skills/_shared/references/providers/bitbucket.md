# Bitbucket Provider Reference

Provider-specific patterns for Bitbucket PR workflows. Framework for future support.

## Reviewer Assignment

Bitbucket uses PR reviewer assignment via REST API:
```
POST /2.0/repositories/{workspace}/{repo_slug}/pullrequests/{pull_request_id}/reviewers
```

## Default Reviewers

Bitbucket supports default reviewers at the repository level.

## Thread Resolution

Bitbucket does not have a thread resolution API — threads are informational only.

## Suggestion Commits

Bitbucket does not support inline suggestion commits.
