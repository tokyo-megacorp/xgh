# Azure DevOps Provider Reference

Provider-specific patterns for Azure DevOps PR workflows. Framework for future support.

## Reviewer Assignment

Azure DevOps uses required reviewers configured via branch policies:
```
PATCH https://dev.azure.com/{organization}/{project}/_apis/git/repositories/{repositoryId}/pullRequests/{pullRequestId}/reviewers
```

## Required Reviewers

Azure DevOps supports required reviewers as branch policy. PRs cannot be completed until all required reviewers approve.

## Thread Resolution

Azure DevOps uses REST API for comment thread resolution:
```
PATCH /threads/{threadId}?api-version=7.0
body: { "status": "fixed" }
```

## Suggestion Commits

Azure DevOps does not support inline suggestion commits.
