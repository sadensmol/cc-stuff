---
name: task
description: "Single entry point for project task/worktree management across the personal plugins. Dispatches `/task <subcommand>` to the correct project's task skill (memoresse:task, swipegames:task, …) based on the active agterm workspace (authoritative) or the cwd. Use when the user says: \"task new <branch>\", \"new task\", \"task plan\", \"task list\", \"task switch\", \"task zed\", \"task code\", \"task console\", \"task review\", \"task finish\", \"task cleanup\", \"create worktree\", or a bare \"/task …\". Forwards all arguments verbatim to the resolved project skill — it never runs task work itself."
---

# Task (dispatcher)

`/task` is the **single visible** task entry across the personal plugins. The
per-project implementations (`memoresse:task`, `swipegames:task`, …) are hidden
from the `/` menu via `user-invocable: false` and are reached **only** through
this dispatcher (or by the model directly, since `Skill(<plugin>:task)` still
works on a hidden skill).

Your job: detect which project this session belongs to, then invoke that
project's `:task` skill via the `Skill` tool, **forwarding the user's arguments
unchanged**. Do NOT run any worktree/git/plan/finish work yourself — the
**project-specific** subcommands (`new`, `plan`, `finish`, `cleanup`) live in the
project skill.

**Handled here, NOT delegated:** `zed`, `code`, `console`, `review`, `list`,
`switch`. These are project-agnostic — opening the worktree in an editor
(`zed`/`code`) or terminal (`console`), opening plannotator at the worktree base
(`review` for real code changes, `annotate` for a plan/docs `.md`), and
enumerating (`list`) / picking (`switch`) worktrees are
identical across projects (only the single-repo vs multi-repo shape differs, and
plannotator ≥ 0.21 auto-discovers nested repos). So this dispatcher runs them
itself — with a one-time VS Code trust preflight for `code`, and `switch`
delegating only its final "open" step back to the project's `new`. See the
"handled here" sections below.

## Step 1 — detect the project (agterm workspace decides first)

Run this single Bash call:

```bash
echo "--- agterm workspace ---"
if [ -n "${AGTERM_WORKSPACE_ID:-}" ] && command -v agtermctl >/dev/null 2>&1; then
  agtermctl tree --json 2>/dev/null | python3 -c "import sys,json,os;d=json.load(sys.stdin);w=os.environ.get('AGTERM_WORKSPACE_ID');print(next((x.get('name') for x in d.get('result',{}).get('tree',{}).get('workspaces',[]) if x.get('id')==w),'(unknown)'))" 2>/dev/null || echo "(unknown)"
else
  echo "(not in agterm)"
fi
echo "--- cwd ---"; pwd
```

The **agterm workspace name**, when present, is *authoritative* — a session
lives under a named workspace (`memoresse`, `swipegames`, …) that reflects the
project even when the cwd has wandered (e.g. editing skill sources under
`work_memoresse` / `work_swipegames`). Prefer it over the cwd path.

## Step 2 — resolve to a project skill

Check in priority order (workspace wins; cwd path is the fallback when the
workspace is `(unknown)` / `(not in agterm)`). The **project root** column is the
directory holding `.worktrees/` — the dispatcher needs it for `list` / `switch`,
which run from anywhere (not just inside a worktree):

| Signal | Resolves to | Project root (for `list`/`switch`) |
|---|---|---|
| agterm workspace `memoresse`, OR cwd contains `/memoresse` or `/work_memoresse` | `memoresse:task` | `/Users/saden/work/memoresse` |
| agterm workspace `swipegames`, OR cwd contains `/swipegames` or `/work_swipegames` | `swipegames:task` | `/Users/saden/work/swipegames` |
| any OTHER named workspace, or no match at all | **no project task flow** — STOP | — |

If nothing matches (a plain personal session, or a named workspace with no
`:task` impl), STOP and tell the user: `/task` needs to run inside a project
workspace (currently `memoresse` or `swipegames`) — no personal task flow
exists. Do not guess a project.

## Step 3 — delegate, or handle here

**Handled here (do NOT delegate):** `zed`, `code`, `console`, `review`, `list`,
`switch` — see the "handled here" sections below. `zed`/`code`/`console`/`review`
work off the cwd (the current worktree); `list`/`switch` use the **project root**
from Step 2.

**Delegated to the project skill:** everything else — `new`, `plan`, `finish`,
`cleanup`. Invoke the resolved skill via the `Skill` tool, passing the **full
argument string** the user gave `/task` (subcommand + args) **verbatim** as the
skill's args. Examples:

- `/task new DEV-178 DEV-135` → invoke `memoresse:task` with args `new DEV-178 DEV-135`
- `/task finish` → invoke `swipegames:task` with args `finish`
- bare `/task` (no args) → invoke the resolved skill with no args (it defaults to `new` per its own rules)

Do not re-interpret, expand, or execute a **delegated** subcommand yourself. The
project skill owns `new` / `plan` / `finish` / `cleanup`; `zed` / `code` /
`console` / `review` / `list` / `switch` are handled here.

**Issue-tracker URL as the branch argument — resolve to the tracker's REAL
branch name, never the URL slug (MUST FOLLOW).** When `/task new <url>` gets a
Linear (or similar) issue URL, do NOT derive the branch by slugifying the URL
path: issue titles use `|` separators, which the URL slug renders as `-or-`
junk (`.../ENG-1930/be-or-spribe-integration-or-inbound-...` →
`eng-1930-be-or-spribe-integration-or-...` — wrong). Use the issue's canonical
`gitBranchName` instead: fetch the issue via the tracker skill
(`get_issue`/`save_issue` responses include `gitBranchName`, e.g.
`eng-1930-be-spribe-integration-inbound-game-launch-session-auth`) and pass
THAT to the project skill. Deriving from the slug creates a second, differently
named worktree for the same ticket the moment anyone uses the real branch name.

## `zed` / `code` — handled here (not delegated)

**Triggers:** "task zed" / "open zed"; "task code" / "open code" / "open vscode".

Both just open the current worktree in an editor; the logic is identical across
projects, so the dispatcher runs it directly. `code` additionally does a
one-time **VS Code trust preflight** so worktrees never open in Restricted Mode.

First derive the worktree base **and** the trust root (the parent of
`.worktrees/`) from the cwd — this is project-agnostic:

```bash
cwd="$(pwd)"
case "$cwd" in
  */.worktrees/*)
    root="${cwd%%/.worktrees/*}"                  # e.g. /Users/saden/work/memoresse
    branch="${cwd#*/.worktrees/}"; branch="${branch%%/*}"
    base="$root/.worktrees/$branch"               # the worktree base dir
    ;;
  *) echo "NOT_IN_WORKTREE" ;;
esac
```

If it prints `NOT_IN_WORKTREE`, tell the user `zed`/`code` must be run from
inside a worktree, and stop.

Then choose what to open — works for single-repo (memoresse) and multi-repo
(swipegames) worktrees alike (`*/` matches only dirs, so hidden `.claude` and the
`PLAN.md` file are excluded):

```bash
first=""; count=0
for d in "$base"/*/; do
  [ -d "$d" ] || continue          # guard against a literal '*/' when nothing matches
  count=$((count + 1))
  [ -n "$first" ] || first="${d%/}"
done
```

### `code` (one-time VS Code trust)

VS Code opens an untrusted folder in **Restricted Mode** (forcing a manual Trust
+ reload). Worktrees are a **sibling** of the main repo
(`<root>/.worktrees/<branch>/…`), so trusting the repo does NOT cover them — but
VS Code **trusts every subfolder of a trusted folder**, so trusting `<root>`
**once** makes every current and future worktree open trusted. A marker file
records that this was done (a proxy, not live detection; if VS Code trust is ever
reset, `rm "<root>/.vscode-parent-trusted"` to re-prompt).

```bash
MARKER="$root/.vscode-parent-trusted"             # outside every repo — never committed
if [ ! -f "$MARKER" ]; then
  echo "NEEDS_TRUST"
  code "$root"                                     # open the parent so the user can trust it
else
  echo "TRUSTED"
fi
```

- **`NEEDS_TRUST`** → VS Code just opened `<root>`. Ask the user (via
  `AskUserQuestion`) to click **"Yes, I trust the authors"** in that folder's
  trust dialog and confirm once done. Only **after** they confirm, record the
  marker (`touch "$root/.vscode-parent-trusted"`), then open the worktree.
- **`TRUSTED`** → open the worktree straight away.

Open the worktree (single dir → open it directly; multiple → open the base):

```bash
if [ "$count" -eq 1 ]; then code "$first"; else code "$base"; fi
```

### `zed`

No trust concept — just open (single dir → that repo; multiple → all top-level
dirs as a multiroot project):

```bash
if [ "$count" -eq 1 ]; then
  env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT zed "$first"
else
  env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT zed "$base"/*/
fi
```

The `env -u` flags unset Claude Code env vars so Zed's own Claude integration
doesn't conflict.

## `console` — handled here (not delegated)

**Triggers:** "task console" / "open console" / "open a console" / "new console".

Open a **new agterm terminal session** whose working directory is the **current
project inside the current worktree** — the git repo the cwd is in (a service
repo for a multi-repo worktree, the monorepo root for a single-repo one). This is
project-agnostic, so the dispatcher runs it directly.

Derive the worktree base from the cwd, then resolve the current project as the
**git repo root clamped to the worktree** (so a monorepo resolves to its root and
a multi-repo resolves to the specific service you're in):

```bash
cwd="$(pwd)"
case "$cwd" in
  */.worktrees/*)
    root="${cwd%%/.worktrees/*}"
    branch="${cwd#*/.worktrees/}"; branch="${branch%%/*}"
    base="$root/.worktrees/$branch"
    ;;
  *) echo "NOT_IN_WORKTREE" ;;
esac

proj="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
case "$proj" in
  "$base"|"$base"/*) : ;;      # cwd is inside a repo under the worktree — use it directly
  *) proj="$base" ;;           # cwd is the multi-repo base (not inside any repo)
esac
```

If it prints `NOT_IN_WORKTREE`, tell the user `console` must be run from inside a
worktree, and stop.

**Multi-repo base → resolve to the working repo, don't silently open the base
(MUST FOLLOW).** When the block above leaves `proj == "$base"`, the cwd wasn't
inside any single repo — the usual case for a multi-repo worktree whose Claude
session runs at the base. A console at the bare base is rarely what the user
means; they mean the service they're working on. Enumerate the child repos and
which carry uncommitted changes:

```bash
if [ "$proj" = "$base" ]; then
  repos=(); changed=()
  for d in "$base"/*/; do
    [ -d "$d" ] || continue
    git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || continue
    r="$(basename "${d%/}")"; repos+=("$r")
    [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ] && changed+=("$r")
  done
  echo "REPOS: ${repos[*]}"
  echo "CHANGED: ${changed[*]}"
fi
```

Then pick `proj` from that output:

- **0 repos** → keep `proj="$base"` (it really is a bare dir).
- **1 repo** → `proj="$base/<that repo>"` (single-repo worktree, e.g. memoresse —
  open it, no prompt).
- **2+ repos, exactly 1 changed** → `proj="$base/<the changed repo>"` — that's the
  repo being worked on; open it, no prompt.
- **2+ repos, 0 or 2+ changed** → genuinely ambiguous, so **ask** with
  `AskUserQuestion` which repo to open: list the repos with the **changed** ones
  first, labelled (e.g. `platform-integration-spribe (changes)`), plus a final
  `open the base (all repos)` option that maps to `proj="$base"`. Set
  `proj="$base/<pick>"` from the answer.

(If cwd was already inside a specific repo, this whole picker is skipped — open
that repo directly, no prompt.) Finally set `name="$(basename "$proj")"`.

Then open the terminal. **agterm is the primary target** (a new session);
tmux is a fallback so `console` still works there:

```bash
if [ -n "${AGTERM_ENABLED:-}" ] && command -v agtermctl >/dev/null 2>&1; then
  # --after "$AGTERM_SESSION_ID": open the new session in the CURRENT session's
  # workspace, right BELOW this session (the anchor carries its own workspace).
  agtermctl session new --cwd "$proj" --name "$name" --after "$AGTERM_SESSION_ID"   # new agterm session in this workspace, below current, selected + focused
elif [ -n "${TMUX:-}" ]; then
  tmux new-window -c "$proj" -n "$name"                # fallback: new tmux window in the project dir
else
  echo "NOT_IN_AGTERM_OR_TMUX"
fi
```

Each `task console` opens a **fresh** session/window (the user asked for a new
console) — no select-existing logic. If it prints `NOT_IN_AGTERM_OR_TMUX`, tell
the user `console` needs agterm (or tmux) and stop.

## Plannotator binary (shared)

The `plannotator` binary lives at `/Users/saden/.local/bin/plannotator`. It may
not be on PATH in spawned sessions — always invoke it by this absolute path.
Every `plannotator …` command below (and in the project skills' `plan` step)
means `/Users/saden/.local/bin/plannotator …`.

## Review checkpoint — stop after code changes (MUST FOLLOW)

Every time you finish a batch of code changes, **STOP before committing / before
`finish`** and put the diff in front of the user. Do one of:

- **Ask the user to review** and wait, OR
- **Run the `review` subcommand** (the default) — it **picks the mode by state**:
  a `plannotator review` of the worktree diff when a real (non-markdown) code
  change exists, or a `plannotator annotate <file.md>` when the change is only a
  plan/docs (`.md`) — because `review` can't render mermaid/tables (see the
  `review` section). plannotator ≥ 0.21 auto-discovers every nested repo, so this
  is the native path for single-repo (memoresse) AND multi-repo (swipegames)
  worktrees — no per-repo loop, no external diff tool. **A docs-only task (e.g.
  an R&D report) is therefore checkpointed with `annotate`, not `review`.**

Then wait for the user, or address the annotations, before continuing. Going
straight from writing code to `finish` without a review checkpoint is not
allowed. A review that returns no annotations = approved.

## `review` / plannotator — handled here (not delegated)

**Triggers:** "task review", "review task", "review changes", "review", "open
plannotator", "open plannotator please", "open annotate".

Opening plannotator at the worktree base and waiting is the ONLY thing this does.
But **which plannotator mode you open depends on what actually exists — pick it by
state, NEVER blindly `review` (MUST FOLLOW):**

**Markdown is ALWAYS annotate, NEVER review (MUST FOLLOW).** `plannotator review`
renders a raw code diff — it does **not** render mermaid diagrams or markdown
tables. So `.md` files (a `PLAN.md`, an R&D report / design doc under `docs/`,
any `*.md`) are **always** opened with `annotate`, never `review` — **even when
the user literally typed `task review`**. Until a **real, non-markdown code
change** exists, if the only changes are a plan and/or docs you MUST use
`annotate`. Classify the changes, then pick:

- **`plannotator review`** — opened **only when a real CODE change exists**: a
  changed/added tracked-or-untracked **non-`.md`** source/test/config file,
  beyond mechanical `go.mod`/`go.sum`/dep churn from `task new`. `.md` files
  never count as a code change.
- **`plannotator annotate <file.md>`** — opened when the only changes are
  **markdown** (`PLAN.md` and/or `*.md` docs), with no real code change:
  - **Exactly one `.md`** changed → annotate that file.
  - **Multiple `.md` files** changed → `annotate` opens **one file at a time**,
    so **ASK the user (`AskUserQuestion`) which single file to open** (list them,
    e.g. `PLAN.md`, `<repo>/docs/rag/rag-rnd.md`). Never silently pick one, and
    never fall back to `review` just to show them all at once.
  - This is a plain annotate — **no `--gate`**; the formal plan-approval gate
    belongs to the `plan` subcommand.
- **Neither a code change nor any `.md`** → there is nothing to open. Say so and
  stop. Do NOT manufacture a diff or a plan to give plannotator something to show.

Decide the mode by **classifying the actual changes** across the nested repos
(untracked included) — markdown is annotate-only, everything else is code:

```bash
# (worktree base already derived as $base, exactly as the zed/code block does)
code=0; mds=()
[ -f "$base/PLAN.md" ] && mds+=("PLAN.md")          # plan at the base is annotatable md
for d in "$base"/*/; do
  [ -d "$d" ] || continue
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || continue
  repo="$(basename "${d%/}")"
  # -uall is REQUIRED: without it git collapses an untracked dir to "docs/rag/"
  # (a non-.md path) and a new-doc-only change gets misread as a code change.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    f="${line:3}"                                    # strip the "XY " status prefix
    case "$f" in
      # machine-generated / dependency churn — NOT deliberate code work; ignore:
      go.mod|go.sum|*/go.mod|*/go.sum) : ;;          # Go dep pins (from `task new`)
      local.properties|*/local.properties) : ;;      # Flutter/Android generated
      .DS_Store|*/.DS_Store) : ;;
      *.md) mds+=("$repo/$f") ;;                      # markdown → annotate
      *) code=1 ;;                                    # real code → review
    esac
  done < <(git -C "$d" status --porcelain -uall 2>/dev/null)
done
echo "CODE=$code"; printf 'MD=%s\n' "${mds[@]}"
```

- **`CODE=1`** → `plannotator review` (real code changed).
- **`CODE=0` and exactly one `MD=`** → `plannotator annotate <that file>`.
- **`CODE=0` and multiple `MD=`** → **ask** which one, then `annotate` it.
- **`CODE=0` and no `MD=`** → nothing to open.

**Neither mode writes code (MUST FOLLOW).** Never read a review/annotate request
as "implement the plan", "start coding", "make the changes then review", or
"approved, so proceed". Writing/editing/reverting ANY file in response is a hard
violation. If opening plannotator would require you to first create a diff or a
plan, you are in the wrong phase: **STOP and ask**, don't implement.

**NEVER suggest / offer / ask about `cleanup` while work remains (MUST FOLLOW).**
When `review` finishes — approved, no annotations, or annotations addressed — do
NOT end by proposing `cleanup` (or "want me to remove the worktree?") as a next
step. `cleanup` is appropriate ONLY once the task is fully done: every PR for the
branch **merged** (not just approved) — for swipegames that includes the
`e2e-api-tests` PR / its dev regression run being green — and no outstanding
work. If any PR is still open or any work is left (implementation, `finish`,
merges, e2e), cleanup must not be mentioned at all — the natural next step is
`finish` (or continuing the work), never cleanup. Only surface `cleanup` when
nothing is left to merge and nothing is left to do, or when the user asks for it
explicitly.

**SINGLE INSTANCE — never spawn a second plannotator (MUST FOLLOW).** Every
`plannotator review`/`annotate` opens a new browser tab, so blindly relaunching
piles up tabs. Check whether one is already running before launching (either
mode); never kill-then-immediately-relaunch in a retry loop. The launch blocks
until submit — a completion/`failed` notification usually just means the user
closed the tab, NOT that the cwd was wrong; do not react by relaunching. **The one
sanctioned kill-then-relaunch is the auto-refresh below — a deliberate content
refresh, not a retry.**

```bash
pgrep -f "plannotator (review|annotate)" >/dev/null 2>&1 && echo "ALREADY_RUNNING" || echo "NONE"
```

- **`ALREADY_RUNNING`** → do NOT launch another. Tell the user one is already
  open (switch to that tab). Only on an explicit "restart"/"reopen" (or the tab is
  gone): `pkill -f "plannotator (review|annotate)"` **once**, wait ~1s, launch
  exactly one.
- **`NONE`** → launch exactly one instance, in the **mode chosen above**:

```bash
# CODE=1 (real, non-markdown code changed) → code-diff review:
cd <worktree-base> && pwd && /Users/saden/.local/bin/plannotator review
# OR — markdown only → annotate the chosen .md (PLAN.md, or the file the user picked):
cd <worktree-base> && pwd && /Users/saden/.local/bin/plannotator annotate <chosen.md>
```

`annotate` takes exactly **one** `.md` path (resolved relative to the worktree
base — so `PLAN.md`, or a nested `<repo>/docs/…/report.md`). It cannot open
several at once; that is why multiple changed `.md` files force the
`AskUserQuestion` pick above rather than a `review`.

- Derive `<worktree-base>` from the cwd (the `.worktrees/<branch>/` root, NOT a
  repo subdir) exactly as the `zed`/`code` block does. Run it from the base so
  `review` aggregates every nested repo into one view, and `PLAN.md` resolves (it
  lives at the base).
- Run it **in the background** — it blocks until the user submits, then returns
  the annotations. One launch is enough. Verify `pwd` is the base BEFORE
  launching; the session cwd persists, so it may already be correct.
- `review` shows the **uncommitted** working-tree diff — it shows NOTHING once
  work is committed, so always review **before** committing (see each project's
  finish review gate).
- When it returns, address each annotation (keyed by `<repo>/<path>` in
  multi-repo for `review`), re-run if needed. No annotations = approved.

### AUTO-REFRESH `annotate` after every doc edit (MUST FOLLOW)

`plannotator annotate` reads the file **once at launch** — so any edit you make to
that `.md` afterward leaves the open tab **stale**, showing the pre-edit content.
Therefore: **whenever you edit a `.md` file that a running `annotate` is currently
showing, automatically refresh that annotate — without being asked.** This is the
sanctioned kill-then-relaunch exception to the SINGLE INSTANCE rule.

- **Trigger:** you (via `Edit`/`Write`) changed the exact `.md` file the open
  `annotate` was launched on. Remember that path when you launch (`annotate
  <chosen.md>`), so you know which edits are relevant.
- **Debounce — refresh ONCE per turn, at the END.** Do NOT relaunch after each
  individual `Edit`. Make **all** the doc edits for this turn first, then refresh a
  single time. Relaunching mid-batch just thrashes tabs.
- **How (deliberate content refresh, not a retry):**

```bash
pkill -f "plannotator annotate" 2>/dev/null          # close the stale tab
for i in 1 2 3 4 5; do pgrep -f "plannotator annotate" >/dev/null 2>&1 || break; done
cd <worktree-base> && pwd && /Users/saden/.local/bin/plannotator annotate <same .md> &   # background, same file
```

- Relaunch on the **same** file the tab was showing (not a different `.md`). If your
  edits were to a doc that ISN'T the open one, don't hijack the user's tab — leave
  it and just tell them which file changed.
- Only refresh a `plannotator **annotate**`; never convert an open annotate into a
  `review` (or vice-versa) as part of a refresh — mode is chosen by state, not by
  the refresh.
- If NO `annotate` is running (the user closed it), a doc edit does **not** auto-open
  one — there's nothing to refresh; mention the doc changed and offer to reopen.
- A `failed`/exit-144 notification from the killed background task is the expected
  result of the `pkill`, not an error — do not react to it.

## `list` / `switch` — handled here (not delegated)

Both operate on the worktrees under the **project root** from Step 2 (`$root`).
They run from anywhere — you need not be inside a worktree.

### `list`

**Triggers:** "task list", "list tasks", "show worktrees".

```bash
ls -1d "$root"/.worktrees/*/ 2>/dev/null | xargs -I{} basename {}
```

Display as a numbered list. If none, say "No worktrees found."

### `switch`

**Triggers:** "task switch", "switch task".

1. List worktrees (as in `list`, using `$root`). If none → "No worktrees found."
   and stop.
2. Present them with `AskUserQuestion` (max 4 — if more, show the 4 most recently
   modified and let the user type "Other").
3. On selection, **delegate the open to the project** so its worktree wiring runs
   (dep refresh, session naming): invoke the resolved project `:task` skill with
   args `new <selected-branch>`. Every project's `new` treats an already-existing
   branch as a switch (reuse it, plain claude, no new branch, no auto-plan) — so
   `new <existing>` IS the open. Do not run a project's `new-task.sh` directly
   from here; go through the project skill.

## Adding a new project

1. Give the project's plugin a `task` skill with `user-invocable: false` in its
   frontmatter (so it stays out of the `/` menu but remains `Skill()`-callable).
   It implements only `new` / `plan` / `finish` / `cleanup` (+ its own preflight,
   layout, definition-of-done); `review` / `list` / `switch` / `zed` / `code` /
   `console` are owned here.
2. Add a row to the Step 2 table mapping its agterm workspace name / cwd
   substring to `<plugin>:task` **and** its project root (the dir holding
   `.worktrees/`).

That's the whole contract — one visible `/task`, N hidden per-project impls, with
the project-agnostic subcommands centralized here.
