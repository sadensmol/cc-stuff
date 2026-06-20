---
name: code-review
description: "Review current branch code changes by launching 5 specialized review agents in parallel. Use when: (1) user asks to review code, (2) user asks to review current branch, (3) user asks for code review before PR or commit, (4) user says 'review my code' or 'check my changes'. Dispatches documentation-reviewer, implementation-reviewer, quality-reviewer, simplification-reviewer, and testing-reviewer agents simultaneously."
---

# Review Code

Parallel code review using 5 specialized agents, each focusing on a different aspect.

## Priority Levels

Every finding MUST be assigned a priority level:

| Priority | Meaning | Action Required |
|----------|---------|-----------------|
| **P0** | Critical defect, security vulnerability, data loss risk, or broken functionality | **Must fix before merge. PR is blocked.** |
| **P1** | Important issue that should be addressed but doesn't block the PR | Should fix in this PR or create a follow-up ticket |
| **P2** | Suggestion for improvement, minor style issue, or nice-to-have | Optional, at author's discretion |

Each agent MUST classify every finding with one of these priorities. Include the priority instruction in every agent prompt.

## Workflow

### 1. Determine the diff

Get the base branch and diff:

```
git merge-base main HEAD
git diff <merge-base>...HEAD
```

If the diff is empty, check for unstaged changes with `git diff`. If still empty, inform the user there's nothing to review.

### 2. Detect language and load guidelines

Check the project root for language markers and load the corresponding guidelines from `languages/`:

- `go.mod` → read `languages/go.md`
- `package.json` → read `languages/ts.md` (if exists)

Read the language file and include its content in every agent's prompt as `{language_guidelines}`. If no language file matches, omit it.

### 3. Launch all 5 agents in parallel

Use the Task tool to launch all 5 agents **in a single message** (parallel execution). Each agent receives the full diff and language guidelines as context.

Agent prompts must include:
- The full diff output
- The branch name and commit messages (`git log main..HEAD --oneline`)
- Instruction to review ONLY their specific concern area
- The language-specific guidelines (if detected)
- The priority classification instructions (see below)

**Important:** The **quality-reviewer** agent is responsible for running the linter. Other agents should not run the linter.

**Priority instructions to include in EVERY agent prompt:**

```
## Priority Classification

Classify every finding as P0, P1, or P2:
- **P0 (Critical)**: Must fix before merge. PR is blocked until resolved.
- **P1 (Important)**: Should fix but doesn't block the PR.
- **P2 (Suggestion)**: Nice-to-have improvement, at author's discretion.

Format each finding as: **[P0/P1/P2] Title** followed by details.
```

**Agent-specific priority guidance to append to each agent prompt:**

```
Task(subagent_type="sadensmol:code-reviewer:documentation-reviewer", prompt="Review this diff for missing documentation updates.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Missing docs for public API changes, breaking contract changes without doc updates, or docs that are now factually wrong and could cause production incidents.\n- **P1 (Important)**: Missing updates to internal docs, outdated examples, or version references that should be updated.\n- **P2 (Suggestion)**: Minor doc improvements, typos, or nice-to-have clarifications.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<language-guidelines>\n{language_guidelines}\n</language-guidelines>\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")

Task(subagent_type="sadensmol:code-reviewer:implementation-reviewer", prompt="Review whether this implementation achieves its goal.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Logic errors that cause wrong behavior, data loss or corruption, silent failures that lose data, or broken error handling on critical paths.\n- **P1 (Important)**: Backward compatibility concerns, missing edge case handling, or architectural issues that should be addressed.\n- **P2 (Suggestion)**: Alternative approaches, minor improvements, or performance considerations.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<language-guidelines>\n{language_guidelines}\n</language-guidelines>\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")

Task(subagent_type="sadensmol:code-reviewer:quality-reviewer", prompt="Review this diff for bugs, security issues, and quality. Run the project linter as described in the language guidelines.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Security vulnerabilities, linter errors, race conditions, resource leaks, or bugs that cause crashes/panics.\n- **P1 (Important)**: Linter warnings, code quality issues, missing error handling, or backward compatibility risks.\n- **P2 (Suggestion)**: Style improvements, minor refactoring opportunities, or non-critical linter suggestions.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<language-guidelines>\n{language_guidelines}\n</language-guidelines>\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")

Task(subagent_type="sadensmol:code-reviewer:simplification-reviewer", prompt="Review this diff for over-engineering and unnecessary complexity.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Abstractions that actively obscure bugs or make the code unmaintainable, or complexity that introduces correctness risks.\n- **P1 (Important)**: Premature abstractions, unnecessary indirection, or significant duplication that will cause maintenance burden.\n- **P2 (Suggestion)**: Minor simplification opportunities, style preferences, or small duplication.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<language-guidelines>\n{language_guidelines}\n</language-guidelines>\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")

Task(subagent_type="sadensmol:code-reviewer:testing-reviewer", prompt="Review this diff for test coverage and quality.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Missing tests for critical paths (payment, auth, data mutation), untested error handling that could cause production incidents, or tests that pass but don't actually verify anything.\n- **P1 (Important)**: Missing edge case coverage, insufficient assertions, or test quality issues that reduce confidence.\n- **P2 (Suggestion)**: Minor test improvements, additional assertions, or test organization.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<language-guidelines>\n{language_guidelines}\n</language-guidelines>\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")
```

### 4. Present results

After all agents complete, present a unified report grouped by priority.

**If any P0 findings exist**, start the report with a prominent blocker notice:

```
## Code Review Summary

> **BLOCKED**: This PR has P0 findings that must be resolved before merge.

### P0 — Critical (Must Fix)
{all P0 findings from all agents, prefixed with agent area}

### P1 — Important
{all P1 findings from all agents, prefixed with agent area}

### P2 — Suggestions
{all P2 findings from all agents, prefixed with agent area}

### Linter
{quality-reviewer linter output or "No issues found"}
```

**If no P0 findings exist:**

```
## Code Review Summary

> **No blockers found.** PR is clear to merge (after addressing P1s if desired).

### P1 — Important
{all P1 findings from all agents, prefixed with agent area}

### P2 — Suggestions
{all P2 findings from all agents, prefixed with agent area}

### Linter
{quality-reviewer linter output or "No issues found"}
```

Omit priority sections that have no findings. Prefix each finding with its source area in bold (e.g., **[Implementation]**, **[Testing]**, **[Quality]**, **[Docs]**, **[Simplification]**).
