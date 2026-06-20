---
name: router
description: Sadensmol skill router — detects working context (cwd, project type, prompt intent) and invokes the right downstream skills (go-programming, typescript-programming, flutter-programming, dart-programming, go-integration-tests, plus any project-specific skills configured locally). Use IMMEDIATELY when the UserPromptSubmit hook tells you to, or at the start of any session where personal/work skills might apply. Skips skills already loaded in the conversation.
---

# Sadensmol skill router

You were invoked because a new session started (or the user changed working context). Your job is to detect the user's situation and load the appropriate downstream skills, so project-specific conventions are in place BEFORE you do real work.

## How to execute

Run this routing pass ONCE per session. Do NOT narrate it to the user — just do the work and proceed with their request afterwards.

### Step 1 — gather context

Run a single combined Bash call to gather everything at once:

```bash
echo "--- cwd ---"; pwd
echo "--- direct files ---"; ls -1 2>/dev/null | head -30
echo "--- project markers (up to 3 levels) ---"; find . -maxdepth 3 \( -name 'go.mod' -o -name 'tsconfig.json' -o -name 'pubspec.yaml' \) -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null | head -10
```

If a `pubspec.yaml` was found, also check whether it pulls in Flutter:

```bash
grep -l '^\s*flutter:' <path-to-pubspec.yaml>
```

### Step 2 — apply routing rules

Evaluate the rules below against the context. **For each match, invoke the listed skill via the `Skill` tool — UNLESS it is already loaded in this conversation, in which case skip it.**

#### A. Project-specific skills (local config — no project names hardcoded here)

Work/project skills live in separate, private plugins. Their `cwd → skill` routes are kept in a **local, unpublished** config so no project names ever appear in this published skill.

Read the routes (skip this section if the file is absent):

```bash
cat ~/.claude/sadensmol-router-routes.json 2>/dev/null
```

The file is a JSON array of `{ "cwd": "<substring>", "skill": "<skill-name>" }`. For each entry whose `cwd` substring appears in the current `pwd`, invoke its `skill` via the `Skill` tool — unless already loaded.

#### B. Project-type detection

| Signal | Skill(s) to invoke |
|---|---|
| `*.go` in cwd, OR `go.mod` anywhere (cwd → 3 levels deep) | `sadensmol:go-programming` |
| `*.ts` / `*.tsx` in cwd, OR `tsconfig.json` anywhere | `sadensmol:typescript-programming` |
| `pubspec.yaml` exists AND contains a `flutter:` dependency | `sadensmol:flutter-programming` **and** `sadensmol:dart-programming` |
| `pubspec.yaml` exists WITHOUT `flutter:` | `sadensmol:dart-programming` |
| `*.dart` in cwd and no `pubspec.yaml` matched above | `sadensmol:dart-programming` |

#### C. Intent-based (Go tests)

If `sadensmol:go-programming` was matched in section B **AND** any of:

- The user's most recent prompt mentions tests (look for: `test`, `_test.go`, `tests/`, `integration test`, `unit test`, `write test`, `fix test`, `check test`, `review test`, `run test`, `coverage`, `cover`)
- `*_test.go` files exist directly in cwd
- A `tests/` subdir contains any `*_test.go` (within 3 levels)

→ invoke `sadensmol:go-integration-tests`

### Step 3 — proceed with the user's request

Once matched skills are invoked (or confirmed already-loaded), continue with whatever the user actually asked for. Do not announce that routing happened.

## Rules

- **Skip already-loaded.** Re-invoking a loaded skill is wasted tokens and noise.
- **One pass per session is enough.** If the user later cd's into a different project type within the same conversation, you may rerun the routing — but normally once is enough.
- **No matches → no action.** Silently move on to the user's request.
- **No narration.** Don't tell the user "Loaded skills X, Y, Z." Just do the work.
- **Don't ask permission.** The user has already opted into this via the hook.

## Adding new routing rules

Edit this file directly — it lives in the repo at `cc-stuff/sadensmol/skills/router/SKILL.md`. To add a new skill route:

1. Pick a signal (cwd pattern, file existence, prompt keyword).
2. Add a row to the appropriate table above.
3. Save. Changes take effect in the next session that invokes this skill.
