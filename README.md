# sadensmol — Claude Code marketplace

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace with a single plugin (`sadensmol`) that bundles a set of skills, code-review agents, and a skill-activation hook.

## Install from Git

You can add this marketplace to Claude Code straight from GitHub — no clone required.

### 1. Add the marketplace

From inside a Claude Code session, run:

```
/plugin marketplace add sadensmol/cc-stuff
```

You can also point at the full Git URL if you prefer:

```
/plugin marketplace add https://github.com/sadensmol/cc-stuff.git
```

> Using SSH instead of HTTPS? `git@github.com:sadensmol/cc-stuff.git` works too.

### 2. Install the plugin

```
/plugin install sadensmol@sadensmol
```

The format is `plugin-name@marketplace-name` — both are `sadensmol` here.

Alternatively, run `/plugin`, open **Browse marketplaces → sadensmol**, and install interactively.

### 3. Start using it

- Restart the session (or run `/plugin` and confirm it's enabled) so the skills, agents, and hook load.
- The skills activate automatically based on your prompt and working context — e.g. ask to "review my code", "write a Go service", or "write a blog post" and the matching skill kicks in.
- You can also invoke a skill explicitly, e.g. `/code-review`.

### Updating the plugin (the reliable way)

Two caveats make naive updates silently fail:

- **Plugins are cached by version.** Claude Code stores each plugin under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. Push new files but keep the same `version` and the manager keeps serving the old cache. So **always bump `version` in `plugin.json`** when you change plugin files.
- **`/plugin marketplace update` does not always re-fetch from Git.** In some setups it leaves the local marketplace clone on the old commit, so nothing downstream changes. The operation that *always* re-clones fresh from GitHub is `marketplace add`. So the dependable refresh is **remove + re-add**, not update.

**1. As the plugin author — bump the version and push:**

```bash
# edit sadensmol/.claude-plugin/plugin.json → bump "version" (e.g. 0.1.2 → 0.1.3)
git add -A && git commit -m "..." && git push origin main
```

**2. In Claude Code — remove and re-add (forces a fresh clone), then reinstall:**

```
/plugin uninstall sadensmol@sadensmol     # drop the old cached plugin
/plugin marketplace remove sadensmol      # drop the stale marketplace clone
/plugin marketplace add sadensmol/cc-stuff   # fresh git clone — pulls your latest commit
/plugin install sadensmol@sadensmol       # install the new version
/reload-plugins                           # re-register hooks/skills in this session
```

**Verify it worked** — the installed record should show your new version and commit:

```bash
grep -E '"version"|"gitCommitSha"' ~/.claude/plugins/installed_plugins.json
```

> If your environment's `/plugin marketplace update sadensmol` *does* advance the clone (check with `git -C ~/.claude/plugins/marketplaces/sadensmol log --oneline -1`), you can use that instead of the remove/re-add pair. When in doubt, remove + re-add always works.

### Removing

```
/plugin uninstall sadensmol@sadensmol
/plugin marketplace remove sadensmol
```

## What's inside

The `sadensmol` plugin ships the following skills:

| Skill | Description |
| --- | --- |
| `router` | Detects working context (cwd, project type, prompt intent) and invokes the right downstream skills. Runs at the start of a session to route to the relevant personal/work skills. |
| `code-review` | Reviews current-branch changes by launching 5 specialized review agents in parallel (documentation, implementation, quality, simplification, testing). Trigger before a PR or commit, or by saying "review my code". |
| `go-programming` | Senior-Go-developer guidance: project structure, error handling, concurrency, domain-driven design, and enforced coding standards (method signatures, comment formatting, mapper patterns, tooling). |
| `go-integration-tests` | Creates Go integration tests with the testify/suite framework — suite hierarchy, gRPC mocking via bufconn, fixtures/test-data management, and assertion patterns. |
| `typescript-programming` | Idiomatic, type-safe TypeScript guidance: strict typing, generics/discriminated unions/utility types, Vitest/Jest tests, refactoring, and project configuration. |
| `dart-programming` | Effective-Dart guidance: null safety, async, collections, records, pattern matching, modern Dart 3 features, unit/widget tests, and idiomatic style. |
| `flutter-programming` | Flutter app guidance: widget composition, const discipline, state-management decision tree, performance pitfalls, theming/navigation, and widget/golden/integration tests. |
| `system-design` | Software-architecture specialist for system design and technical decisions. Produces plan documents in `docs/plans/` with supporting docs (ADRs, mermaid diagrams, checklists). |
| `article-write` | Writes blog articles for sadensmol.com (Hugo blog) — either rewriting a source link in the author's voice or writing original posts from a topic. |
| `book-writer` | Writes original stories, short stories, and books from a brief; asks for target audience age, language, and style before writing, and outputs standalone `.md` files. |
| `github` | GitHub repository management via the `gh` CLI — reading files/docs, fetching contents, and working with pull requests and issues. |
| `linear` | Linear issue management via the claude.ai Linear MCP server — check/search/update issues, manage subtasks, and read/post comments. |
| `slack` | Direct Slack Web API recipes (Lists + chat) for reuse by other skills — read/update List items, read timestamps, and post channel messages via curl. |
| `learn` | Captures new knowledge and integrates it into existing `sadensmol` skills when you correct it or ask it to "remember this" / "update the skill". Scoped to the sadensmol namespace only. |

### Agents

The plugin also provides the five code-review agents used by the `code-review` skill: `documentation-reviewer`, `implementation-reviewer`, `quality-reviewer`, `simplification-reviewer`, and `testing-reviewer`.

### Hooks

A `UserPromptSubmit` skill-activation hook nudges the `router` skill so the right skills load automatically for each prompt.
