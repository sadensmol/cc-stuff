#!/bin/sh
# UserPromptSubmit hook — router activator.
#
# Fires on EVERY request. Its sole job is to tell Claude to ensure the
# sadensmol:router skill is loaded before doing anything else.
#
# Deliberately dependency-free (no jq) and stateless (no session marker)
# so it is guaranteed to run in any environment, on every prompt. The
# router itself, and the instruction below, skip redundant work when the
# skill is already loaded — so re-firing each turn is cheap.

cat <<'EOF'
<SKILL_ACTIVATION_REQUIRED priority="override-default-behavior">

EXTREMELY IMPORTANT: Ensure the `sadensmol:router` skill is active BEFORE doing anything else in this turn. It detects your working context (cwd, project type, prompt intent) and routes you to the appropriate downstream skills (Go, TypeScript, Dart/Flutter, project-specific skills, etc.).

- If `sadensmol:router` is NOT yet loaded in this conversation, invoke it via the Skill tool now, BEFORE: reading files, using other tools, responding to the user, asking clarifying questions, or running agents.
- If `sadensmol:router` IS already loaded, do NOT call the Skill tool again — just follow its rules against the current cwd and prompt.

</SKILL_ACTIVATION_REQUIRED>
EOF
