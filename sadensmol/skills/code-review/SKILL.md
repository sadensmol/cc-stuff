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

## How agents load project skills

The 5 review agents do NOT receive language guideline files from this skill (there is no `languages/` folder — skills replace it). Instead, **each agent loads its own skills at the start of its run**, as defined in the agent's own instructions:

1. **Load a language skill for EVERY language in the diff — by file extension, NOT cwd (MUST FOLLOW).** A review diff routinely spans several languages; the cwd is only one of them, so cwd-only routing silently under-loads (a mostly-Flutter diff with a couple of `.go` files would review the Go without `go-programming` and produce findings that violate its rules). Each agent scans the changed paths and loads the matching `sadensmol:` skill for each language present: `*.go` → `go-programming` (+ `go-integration-tests` for Go tests); `*.dart` → `flutter-programming` + `dart-programming`; `*.ts`/`*.tsx` → `typescript-programming`; etc. **Any diff touching even one `.go` file MUST have `go-programming` loaded before findings are reported** — its rules (e.g. NO comment by default, so "add a doc comment" is usually wrong; naming; error handling; mappers) decide whether a finding is valid.
2. **Run the routing pass too** — also invoke `sadensmol:router` (cwd/project detection) plus any project router whose cwd matches (`<project>:router`) for project-specific conventions. This complements step 1; it does not replace it.
3. **Load concern-specific skills** — e.g. the testing-reviewer additionally loads `go-integration-tests` when reviewing Go tests.

This skill hands each agent the diff, the commits, and enough context to know what it's reviewing; each agent then loads skills by the diff's languages per the steps above.

## Project PR conventions (apply when the project defines them)

Projects carry their own PR/commit rules in their **own** skills — this sadensmol skill owns none of those mechanics, it only requires that you **discover and enforce them**. **Before reviewing, run the routing pass yourself** (`sadensmol:router` + any project router whose cwd matches) so the project's conventions are loaded, then look for its PR/commit/branch rules. Examples of where they live:

- `<project>:linear` / `<project>:jira` — task/PR **title format** (e.g. an issue-key prefix) and the project's **description style**.
- `<project>:task` — commit/PR shape (how many commits, how many PRs, the finish flow).
- `<project>:<project>` (the dev skill) — living docs that must be updated in the same change, and any other repo-wide rule.

Apply whatever the loaded project skills define:

- **Title** — the PR title (and commit titles, where the project formats them) MUST match the project's format. Flag a mismatch.
- **Description** — structure the PR body the way the project's skill prescribes; only fall back to the generic shape in PR-review step 4 when the project defines none.
- **Commit & branch hygiene** — review the branch's *commits*, not just the squashed diff:
  - **Up to date with base** — the branch is rebased on / not behind its base; no accidental base-merge commits when the project rebases. Note if a rebase is needed (`git log --oneline <base>..HEAD`, `git rev-list --count HEAD..<base>`).
  - **No junk commits** — no leftover `wip`/`fixup`/duplicate/revert-your-own-change commits that should be squashed per the project's one-commit(-per-project) rule.
  - **No stray files** — nothing committed that should be gitignored: build artifacts, generated code, IDE/ephemeral files (`ios/Flutter/ephemeral/**`, `.gradle/`, `local.properties`), logs, secrets.
  - **Message format** — each commit message follows the project's convention.

Report these under a **[Hygiene]** area in the summary, same P0/P1/P2 scale (committed secret / broken base = P0; junk commits / wrong title format = P1; message nits = P2). When the project defines no such conventions, still apply the generic checks (junk commits, stray files) and skip the project-specific title/message-format checks.

## Workflow

### 0. Choose review mode

Before anything else, ask the user what to review (use `AskUserQuestion`):

- **Local** — review the current branch's local code changes. Even in Local mode you **always detect an attached PR** (`gh pr view --json number,title,url,body,baseRefName,commits`) — a PR attached to this code is never out of scope. If one exists, also run the PR-level checks (title/description per **Project PR conventions** + commit & branch hygiene) and surface them as findings. In Local mode you **report** those PR issues and **ask the user to fix them** — you do NOT `gh pr edit`/`gh pr comment` (that's PR mode).
- **PR** — review a pull request. Detect the current branch's PR with `gh pr view --json number,title,url,body`. If one exists, use it. If none exists, ask the user to provide a PR link (or number).

Then follow the matching path below. **Local** → the **Local review** section. **PR** → the **PR review** section.

## Local review

### 1. Determine the diff

Get the base branch and diff:

```
git merge-base main HEAD
git diff <merge-base>...HEAD
```

If the diff is empty, check for unstaged changes with `git diff`. If still empty, inform the user there's nothing to review.

### 1b. Check the attached PR (if any)

If `gh pr view` found a PR for this branch, run the **Project PR conventions** checks against it now — title format, description shape, and commit & branch hygiene (rebased / not behind base, no `wip`/duplicate/fixup commits, no stray or generated files committed). Collect the results as **[Hygiene]** findings for the final report. **Local mode reports and asks the user to fix** — never `gh pr edit`/`gh pr comment` here. If the user wants you to update the title/description or post the summary as a comment, that's the **PR review** path — offer to switch.

### 2. Launch all 5 agents in parallel

Use the Task tool to launch all 5 agents **in a single message** (parallel execution). Each agent receives the full diff and the commit list, then self-loads its project skills (see "How agents load project skills" above).

Agent prompts must include:
- The full diff output
- The branch name and commit messages (`git log main..HEAD --oneline`)
- Instruction to review ONLY their specific concern area
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

**Agent-specific prompts (each agent self-loads its skills first, then reviews):**

```
Task(subagent_type="sadensmol:code-reviewer:documentation-reviewer", prompt="Load your project skills first (see your agent instructions), then review this diff for missing documentation updates.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Missing docs for public API changes, breaking contract changes without doc updates, or docs that are now factually wrong and could cause production incidents.\n- **P1 (Important)**: Missing updates to internal docs, outdated examples, or version references that should be updated.\n- **P2 (Suggestion)**: Minor doc improvements, typos, or nice-to-have clarifications.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")

Task(subagent_type="sadensmol:code-reviewer:implementation-reviewer", prompt="Load your project skills first (see your agent instructions), then review whether this implementation achieves its goal.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Logic errors that cause wrong behavior, data loss or corruption, silent failures that lose data, or broken error handling on critical paths.\n- **P1 (Important)**: Backward compatibility concerns, missing edge case handling, or architectural issues that should be addressed.\n- **P2 (Suggestion)**: Alternative approaches, minor improvements, or performance considerations.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")

Task(subagent_type="sadensmol:code-reviewer:quality-reviewer", prompt="Load your project skills first (see your agent instructions), then review this diff for bugs, security issues, and quality. Run the project linter as described in your loaded skills / project docs.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Security vulnerabilities, linter errors, race conditions, resource leaks, or bugs that cause crashes/panics.\n- **P1 (Important)**: Linter warnings, code quality issues, missing error handling, or backward compatibility risks.\n- **P2 (Suggestion)**: Style improvements, minor refactoring opportunities, or non-critical linter suggestions.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")

Task(subagent_type="sadensmol:code-reviewer:simplification-reviewer", prompt="Load your project skills first (see your agent instructions), then review this diff for over-engineering and unnecessary complexity.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Abstractions that actively obscure bugs or make the code unmaintainable, or complexity that introduces correctness risks.\n- **P1 (Important)**: Premature abstractions, unnecessary indirection, or significant duplication that will cause maintenance burden.\n- **P2 (Suggestion)**: Minor simplification opportunities, style preferences, or small duplication.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")

Task(subagent_type="sadensmol:code-reviewer:testing-reviewer", prompt="Load your project skills first (see your agent instructions — including the testing skills, e.g. go-integration-tests for Go), then review this diff for test coverage and quality.\n\n## Priority Classification\n\nClassify every finding as P0, P1, or P2:\n- **P0 (Critical)**: Missing tests for critical paths (payment, auth, data mutation), untested error handling that could cause production incidents, or tests that pass but don't actually verify anything.\n- **P1 (Important)**: Missing edge case coverage, insufficient assertions, or test quality issues that reduce confidence.\n- **P2 (Suggestion)**: Minor test improvements, additional assertions, or test organization.\n\nFormat each finding as: **[P0/P1/P2] Title** followed by details.\n\n<diff>\n{diff}\n</diff>\n\nCommits: {commits}")
```

### 3. Present results

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

Omit priority sections that have no findings. Prefix each finding with its source area in bold (e.g., **[Implementation]**, **[Testing]**, **[Quality]**, **[Docs]**, **[Simplification]**, **[Hygiene]**). The **[Hygiene]** findings come from your own project-convention + commit-hygiene pass (see **Project PR conventions**), not from the 5 agents.

## PR review

Reviews a pull request end to end. Reuses the same 5 domain agents as Local review, but adds PR description management, posts the summary as a PR comment, and handles re-reviews.

### 1. Load the platform skill

If the PR is hosted on **GitHub**, invoke the `sadensmol:github` skill via the `Skill` tool before doing anything else. (Other hosts: TBD — for now proceed with `gh`/generic tooling.)

### 2. Detect first review vs re-review

Fetch the PR body and existing review comments:

```
gh pr view <pr> --json number,title,url,body,headRefName
gh pr view <pr> --comments
```

- **First review** — the description has no code-review summary and there are no prior review comments from this skill.
- **Re-review** — the description already carries the summary (step 4) **and/or** there are prior review comments from this skill. Treat as re-review and follow step 7.

### 3. Determine the diff

```
gh pr diff <pr>
```

Also grab the commit list (`gh pr view <pr> --json commits` or `git log`) for context, same as Local review.

### 4. Ensure the PR title + description follow project conventions

First apply the project's own rules (see **Project PR conventions**): verify the **PR title** matches the project's format (issue-key/type prefix) and fix it via `gh pr edit <pr> --title ...` if it doesn't; structure the **description** the way the project's skill prescribes. Only when the project defines no description convention, fall back to the generic shape below.

The PR description must reflect **the idea of the PR** — what it changes, what feature it implements, or what bug it fixes — plus a short bullet list of the top-level changes (code, architecture, design, etc.).

- If the description **already contains** an adequate summary (someone — possibly you on a previous run, or another agent/tool — already wrote it), leave it as is. Do not rewrite a good description.
- If the description is **missing or inadequate**, write the summary from the diff and update the PR body via `gh pr edit <pr> --body ...`, preserving any existing content worth keeping.
- On a **re-review**, the description will already have this — skip the update entirely.

Summary shape:

```
## Summary
<1–3 sentences: the idea of this PR — what it changes / the feature / the bug fixed>

## Top-level changes
- <change 1 (code / architecture / design / …)>
- <change 2>
- ...
```

### 5. Run the domain agents

Launch the **same 5 agents in parallel** with the **same prompts and priority instructions** as Local review step 2. Agents self-load their project skills (routers + concern-specific), and the quality-reviewer still owns the linter. The only difference from Local is the input diff comes from `gh pr diff`.

### 6. Post the summary as a PR comment

Build the same prioritized report as Local review step 3 (grouped P0/P1/P2, per-area prefixes, linter section), then post it as a PR comment via `gh pr comment <pr> --body ...`.

**Approval suggestion:** if there are **no P0 findings**, add a line to the comment suggesting the PR is ready to approve — but **do not approve it yourself** (never run `gh pr review --approve`). If there are P0 findings, keep the BLOCKED notice instead.

### 7. Re-review: address prior comments

When step 2 detected a re-review:

- Read the previous review comments from this skill.
- Check the new diff against them: for each prior finding, verify whether it was actually fixed — confirm the fix is real and correct, not just superficially touched. Flag fixes that are wrong, incomplete, or that introduced new problems.
- Run the 5 domain agents on the current diff (step 5) to catch any newly introduced issues.
- Post a new comment (step 6) that: (a) states which prior findings are resolved vs still open, and (b) lists any new findings. Apply the same no-P0 → suggest-approve / P0 → BLOCKED logic.
