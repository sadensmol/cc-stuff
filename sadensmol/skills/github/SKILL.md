---
name: github
description: |
  GitHub integration and repository management. Use when working with GitHub repositories, reading documentation from GitHub, fetching file contents, managing pull requests, issues, or any GitHub-related tasks.
---

# GitHub Integration

This skill provides guidance for interacting with GitHub repositories using the `gh` CLI tool.

## Reading Files from GitHub

To read file contents from GitHub repositories, use the GitHub API via `gh` command:

### Basic Syntax

```bash
gh api repos/{owner}/{repo}/contents/{path} --jq .content | base64 -d
```

### Examples

**Read a markdown file:**
```bash
gh api repos/{owner}/{repo}/contents/docs/error-handling.md --jq .content | base64 -d
```

**Read a file with spaces in path:**
```bash
gh api repos/{owner}/{repo}/contents/docs/integrations/01.%20general.md --jq .content | base64 -d
```

**Read first 20 lines:**
```bash
gh api repos/{owner}/{repo}/contents/docs/architecture.md --jq .content | base64 -d | head -20
```

### URL Encoding

Files with spaces or special characters in their names need URL encoding:
- Space → `%20`
- Example: `01. general.md` → `01.%20general.md`

## Other GitHub Operations

### View Pull Requests

```bash
# List PRs
gh pr list

# View specific PR
gh pr view 123

# View PR diff
gh pr diff 123

# View PR comments
gh api repos/{owner}/{repo}/pulls/123/comments
```

### View Issues

```bash
# List issues
gh issue list

# View specific issue
gh issue view 456
```

### Repository Information

```bash
# View repository details
gh repo view {owner}/{repo}

# List branches
gh api repos/{owner}/{repo}/branches

# List tags
gh api repos/{owner}/{repo}/tags
```

### File and Directory Listing

```bash
# List directory contents
gh api repos/{owner}/{repo}/contents/{path}

# Get file metadata
gh api repos/{owner}/{repo}/contents/{file_path} --jq '{name, size, path, sha}'
```

## Best Practices

1. **Always use base64 decode** when reading file contents: `--jq .content | base64 -d`
2. **URL encode special characters** in file paths (spaces, dots at start of filename)
3. **Check file existence** before reading to avoid errors
4. **Use pagination** for large directory listings
5. **Cache frequently accessed** documentation locally during a session to reduce API calls

## Error Handling

**File not found:**
```bash
# Returns 404 error
# Check path and ensure file exists in repository
```

**Authentication required:**
```bash
# Ensure gh CLI is authenticated
gh auth status
gh auth login
```

**Rate limiting:**
```bash
# Check API rate limit
gh api rate_limit
```

## Tips

- Use `--jq` for JSON parsing and filtering
- Pipe to `head`, `tail`, or `grep` for large files
- Use `| wc -l` to count lines
- Use `| less` for interactive viewing of large files
