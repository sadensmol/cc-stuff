---
name: router
description: Sadensmol skill router — detects working context (cwd, project type, prompt intent) and invokes the right downstream skills (go-programming, typescript-programming, flutter-programming, dart-programming, swift-programming, go-integration-tests, linear, jira, plus any project-specific skills configured locally). Also disambiguates ALL shared skill names (`linear`, `router`, `task`, and any future collision) across the personal plugins by workspace: a project (work_) plugin overrides sadensmol for a colliding name while layering on sadensmol's base, so defer to the owning project workspace and use the `sadensmol:` version only for a plain personal session. Use IMMEDIATELY when the UserPromptSubmit hook tells you to, or at the start of any session where personal/work skills might apply. Skips skills already loaded in the conversation.
---

# Sadensmol skill router

You were invoked because a new session started (or the user changed working context). Your job is to detect the user's situation and load the appropriate downstream skills, so project-specific conventions are in place BEFORE you do real work.

## ⚠️ ALWAYS-ON WORKTREE CONFINEMENT (applies every turn, not just at load)

Because this router text is in context on every turn, it carries the one rule that
is most often violated across ALL projects: **if the session cwd is under
`…/.worktrees/<branch>/`, then EVERY path you touch and EVERY command's working dir
for the WHOLE session MUST stay under that worktree base. NEVER `cd` to or edit a
primary checkout — a repo path with no `/.worktrees/<branch>/` segment (e.g.
`/Users/saden/work/<project>/<repo>/…`) is a different branch (often the default
branch or a stranger's WIP), so your work silently lands in the wrong place and the
task branch/PR shows nothing.** This binds ALL work (edits, `git`, builds, `make`,
`sops`, grep), not only the `task` flow, and regardless of which downstream skill is
loaded. The harness constantly surfaces primary-checkout paths that look
authoritative — ignore them; trust the worktree cwd. Derive it once:
`case "$(pwd)" in */.worktrees/*) root="${PWD%%/.worktrees/*}"; b="${PWD#*/.worktrees/}"; b="${b%%/*}"; WT="$root/.worktrees/$b";; esac`
and prefix every repo path with `$WT`. Full mechanism + recovery live in each
project's dev skill and `:task` skill.

## How to execute

Run this routing pass at the start of the session AND re-check it on every later turn that introduces a new signal (see "Re-route on drift" below). Do NOT narrate it to the user — just do the work and proceed with their request afterwards.

### Step 1 — gather context (MANDATORY, do not shortcut)

**You MUST run the FULL bash block below in a single Bash call. Do not replace it with just `pwd`. Do not skip the `find` because cwd looks unfamiliar. Section B's project-type detection cannot fire without this output, and skipping it is the #1 source of "you forgot to load `go-programming`" bugs.**

**Concrete failures (these have happened — don't repeat):**

1. *"I recognize this cwd, I'll skip the find."* At session start, ran only `pwd` + `cat ~/.claude/sadensmol-router-routes.json`. Section A matched a project-specific skill (e.g. `swipegames:swipegames`) and routing was declared done. Section B never got the `find` output it needed, so `sadensmol:go-programming` and `sadensmol:go-integration-tests` were never loaded. Eight turns of Go editing happened before the user caught the gap. **Rule:** prior knowledge of the cwd is exactly what the bash block exists to override. Familiarity is not a substitute for evidence — run the full block every time.

2. *"Some other router already ran, so I'm routed."* Another skill's router was invoked from its own hook and loaded its project skill. The main loop then treated the routing hooks as collectively satisfied and **never invoked `sadensmol:router` at all** — so Section B never ran and `sadensmol:go-programming` / `sadensmol:go-integration-tests` were never loaded. A whole task's worth of Go was written missing the language rules (`fmt.Sprintf` over `+`, comment discipline, mapper pattern) before the user caught it. **Rule:** every router has its OWN hook that fires on EVERY request — a *different* router having run is NOT this router having run. On every request, check each router's hook independently and load any that isn't loaded. Never assume one router covers another; routers know nothing about each other.

```bash
echo "--- cwd ---"; pwd
echo "--- direct files ---"; ls -1 2>/dev/null | head -30
echo "--- project markers (up to 3 levels) ---"; find . -maxdepth 3 \( -name 'go.mod' -o -name 'tsconfig.json' -o -name 'pubspec.yaml' -o -name 'Package.swift' -o -name '*.xcodeproj' \) -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null | head -10
echo "--- *_test.go presence (up to 3 levels) ---"; find . -maxdepth 3 -name '*_test.go' -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null | head -3
```

If a `pubspec.yaml` was found, also check whether it pulls in Flutter:

```bash
grep -l '^\s*flutter:' <path-to-pubspec.yaml>
```

**Pre-flight checklist before moving to Step 2 — every box MUST be ticked:**

- [ ] I ran the full bash block (cwd + direct files + project markers + *_test.go presence).
- [ ] I have the literal `find` output in front of me (even if empty).
- [ ] I am now going to evaluate Section B against that output, not against my prior assumption about the project.

If you cannot tick all three, go back and run the block.

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
| `*.swift` in cwd, OR `Package.swift` / `*.xcodeproj` / `*.xcworkspace` anywhere | `sadensmol:swift-programming` |

#### C. Intent-based (Go integration tests)

`sadensmol:go-integration-tests` covers **integration tests only**, which in this codebase means tests living **under a `tests/` directory**. Unit tests next to the implementation (e.g. `service/foo.go` + `service/foo_test.go`) are covered by the unit-test section of `sadensmol:go-programming` — do NOT load `go-integration-tests` for them.

If `sadensmol:go-programming` was matched in section B **AND** any of:

- The user's most recent prompt explicitly references integration tests or the `tests/` folder (look for: `integration test`, `tests/`, `_integration_test.go`, or `test`/`run test`/`fix test` in a context that points at integration tests)
- A `tests/` subdir contains any `*_test.go` (within 3 levels) — i.e. the project ships integration tests under `tests/`

→ invoke `sadensmol:go-integration-tests`

**Do NOT trigger on:**

- The presence of `*_test.go` files directly in cwd or alongside implementation (those are unit tests).
- A generic "test" mention with no integration-test signal.

#### D. Intent-based (Linear)

If the user's prompt mentions Linear in any form:

- the literal word `linear` or `Linear`
- a `linear.app/...` URL
- a Linear issue identifier matching `[A-Z]+-\d+` (e.g. `ENG-1276`, `PROJ-42`)
- task-management intent in a ticketing context: `my tasks`, `assigned to me`, `in progress`, `update ticket`, `update issue`, `add subtask`, `reassign`, `change status`, `mark done`, `in review`

→ invoke `sadensmol:linear` (workspace-agnostic mechanics).

Project-specific Linear conventions (team names, status names, branch mapping, task-title format, description style) live in plugin skills, not here. The local routes file (Step A) and the per-plugin routers (`swipegames:router`, `memoresse:router`) handle layering those on top — `sadensmol:linear` stays workspace-agnostic.

#### E. Intent-based (Jira)

If the user's prompt mentions Jira in any form:

- the literal word `jira` or `Jira`
- an `*.atlassian.net/...` URL
- a Jira issue key in a project known to use Jira (e.g. memoresse `DEV-\d+`)
- ticketing intent (`update ticket`, `move to in progress`, `sprint`, `backlog`, JQL) in a Jira context

→ invoke `sadensmol:jira` (REST-only: drives the Jira Cloud REST API via `curl`,
no CLI or MCP).

**Why load it BEFORE touching Jira at all:**

- It defines the exact REST recipes (correct endpoints, API v2-vs-v3, JQL
  search, the two-step transition flow) — without it you'll guess the wrong
  curl calls.
- It encodes the safety rules (fetch issue before transitioning, assign by
  `accountId` not display name, show original description before editing,
  approval before any modification, never print `$JIRA_API_TOKEN`) that
  prevent irreversible Jira mistakes and token leaks.
- It carries the **First-Time Setup** flow: if the `JIRA_BASE_URL` /
  `JIRA_EMAIL` / `JIRA_API_TOKEN` env vars are missing, the skill walks the
  user through token creation, with secrets added by the user to
  `~/.profile`. So load it **even when Jira isn't set up yet** — "Jira isn't
  configured" is itself a case the skill handles; never improvise raw `curl`
  calls against the Jira REST API without loading the skill first.

If the prompt is ambiguous between Linear and Jira (a bare `[A-Z]+-\d+` identifier with no other signal), prefer the tracker the current project uses; when unknown, ask.

#### F. Shared skill names across the personal plugins (bare-name disambiguation)

`linear`, `router` (and, in the project plugins, `task`) are skill names that
exist in more than one personal plugin (`sadensmol`, `swipegames`, `memoresse`),
so a bare `/<name>` (or `<name> <args>` typed as plain text) is ambiguous and the
harness may tie-break to the wrong one. This is **not `linear`-specific** — the
rule below covers any current or future shared name. Resolve by the session's
workspace:

| Bare name | swipegames session | memoresse session | plain personal / other |
|---|---|---|---|
| `task` | `swipegames:task` | `memoresse:task` | — (sadensmol has no `task`) |
| `linear` | `swipegames:linear` (+ `sadensmol:linear` base) | `sadensmol:linear` | `sadensmol:linear` |
| `router` | `swipegames:router` | `memoresse:router` | `sadensmol:router` |

**Rule (general — any shared name), with precedence:** a project (work_) plugin
**overrides** sadensmol for a colliding name, but builds **on top of** sadensmol's
base. So:

- If the session belongs to a project workspace (`swipegames` / `memoresse`)
  whose plugin defines the name → that plugin's version wins; defer to its
  router (it has its own hook and fires every turn). When the project skill
  *layers on* the sadensmol base (e.g. `swipegames:linear` over `sadensmol:linear`),
  **both** load — sadensmol supplies base mechanics, the project skill supplies the
  overrides.
- Otherwise (a plain personal / sadensmol session, or the owning project plugin
  doesn't define the name) → the `sadensmol:` version wins; if the harness
  pre-loaded another plugin's `<name>`, override to `sadensmol:<name>`.

The fully-qualified `/<plugin>:<name>` always targets the right one.

### Step 2.5 — verify invocations against Step 1 output (BLOCKING GATE)

**This is a hard gate, not a "cross-check you'll get to."** You MUST NOT use ANY
non-`Skill` tool for the user's task — no `Read`/`Grep`/`Glob`/`Bash` to explore
code, no reading a reference doc, no `Edit`/`Write`, no `Agent` — until you have
run this verification and every required skill below is loaded. Loading a
Section A project skill does **not** open the gate; only completing this list
does. (Re-running the Step 1 bash block is fine — that's part of routing.)

Cross-check the skills you invoked in Step 2 against the `find` output from Step 1. If the output shows:

- a `go.mod` (anywhere up to 3 levels deep) → `sadensmol:go-programming` MUST be in your invocation list (or already loaded).
- a `tsconfig.json` → `sadensmol:typescript-programming` MUST be loaded.
- a `pubspec.yaml` with `flutter:` → both `sadensmol:flutter-programming` and `sadensmol:dart-programming` MUST be loaded.
- a `Package.swift` / `*.xcodeproj` / `*.xcworkspace` (or `*.swift` in cwd) → `sadensmol:swift-programming` MUST be loaded.
- any `tests/.../*_test.go` AND a Go project AND Section C's intent rule fires → `sadensmol:go-integration-tests` MUST be loaded.

Say the quiet part to yourself before the first task tool-call: *"Step 1 showed
`go.mod` — is `sadensmol:go-programming` loaded? If not, load it now."* Substitute
the matching language for ts/dart/flutter projects.

**A Section A match (project-specific skill) is additive, not a substitute** — it never excuses skipping Section B/C/D. If you can't account for a missing skill against the Step 1 output, you skipped a section. Go back to Step 2 before proceeding.

**Concrete failure (this happened — don't repeat):** Step 1 ran fully and showed
`go/**/go.mod`. Section A matched a project skill (e.g. `memoresse:memoresse`)
and it was loaded. Then, *without* completing Step 2.5, the next move was to read
the project skill's reference doc and `grep` across `.go` files to plan a Go
refactor — `sadensmol:go-programming` was never loaded. The user caught it. **Rule:**
loading the project skill is exactly the moment the gate feels "done" — it isn't.
The `find` output already proved a Go project; Section B is mandatory regardless
of what Section A matched, and reading/grepping `.go` files IS "real work" that
the gate blocks (see Re-route on drift).

### Step 3 — proceed with the user's request

Once matched skills are invoked (or confirmed already-loaded), continue with whatever the user actually asked for. Do not announce that routing happened.

## Re-route on drift (MUST FOLLOW)

The initial pass is not "once and forget". Re-evaluate Sections B, C, D against every later turn — at minimum, **before** any of the following actions:

- **Reading, searching, editing, or creating a `*.go` file for the user's task** — `grep`/`Glob` over Go sources, opening a `.go` file to plan a change, or any `Edit`/`Write` — confirm `sadensmol:go-programming` is loaded; load it if not. "I'm only reading to understand first" is NOT an exemption: the skill tells you *how* to read Go here and what patterns to expect, so it must be loaded before the first `.go` read, not after.
- **Editing or creating a Go test file under a `tests/` directory** (e.g. `tests/internal-api/v1/foo_test.go`, `tests/repository/bar.go`) — confirm `sadensmol:go-integration-tests` is loaded; load it if not. Unit tests next to the implementation (`service/foo_test.go`) are NOT covered by this skill — they fall under `sadensmol:go-programming`.
- **Editing or creating a `*.ts` / `*.tsx` file** — confirm `sadensmol:typescript-programming` is loaded.
- **Editing or creating a `*.dart` file (or `pubspec.yaml`)** — confirm `sadensmol:dart-programming` (and `sadensmol:flutter-programming` if Flutter) are loaded.
- **Editing or creating a `*.swift` file (or `Package.swift`)** — confirm `sadensmol:swift-programming` is loaded.
- **The user's prompt newly mentions Linear / an ENG-#### identifier / a `linear.app` URL** — confirm `sadensmol:linear` is loaded.
- **The user's prompt newly mentions Jira / an `atlassian.net` URL / a Jira issue key** — confirm `sadensmol:jira` is loaded.
- **The user invokes a bare colliding skill name (`/task`, `/linear`, `/router`, or any name shared across the personal plugins)** — resolve it per Section F by the session's workspace (project plugin overrides sadensmol, layering on its base) before invoking, and override any wrong-plugin version the harness pre-loaded.

You don't need to re-run the full Step 1 bash block on drift — just check whether the skill the new action would benefit from is already loaded, and load it if it isn't. **Use the `Skill` tool (never just read the SKILL.md file).** Loading a skill on drift is cheaper than producing code that violates its rules.

## Rules

- **Skip already-loaded.** Re-invoking a loaded skill is wasted tokens and noise.
- **Initial pass is mandatory; later drift checks are mandatory too.** Step 1's bash block runs at session start; Section B/C/D rules then re-fire on every drift signal listed above.
- **No matches → no action.** Silently move on to the user's request.
- **No narration.** Don't tell the user "Loaded skills X, Y, Z." Just do the work.
- **Don't ask permission.** The user has already opted into this via the hook.
- **If the user calls out a missing skill load, fix the rule that missed it.** Don't just load it and move on — edit this `SKILL.md` so the same hole doesn't reopen in the next session.
- **NEVER invoke `superpowers:test-driven-development` for new logic.** TDD is for **bug fixes only** (the behaviour exists and misbehaves → failing test first). New features/methods/endpoints are **implementation-first**: write the code, then cover it with tests. "A skill exists, so I must load it" is not a reason — the skill's own trigger ("use when implementing any feature") is overridden by this rule. See the *Test-first vs implementation-first* section in `sadensmol:go-programming`.

## Adding new routing rules

Edit this file directly — it lives in the repo at `cc-stuff/sadensmol/skills/router/SKILL.md`. To add a new skill route:

1. Pick a signal (cwd pattern, file existence, prompt keyword).
2. Add a row to the appropriate table above.
3. Save. Changes take effect in the next session that invokes this skill.
