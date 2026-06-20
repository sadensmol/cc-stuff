#!/bin/bash
# UserPromptSubmit hook — minimal router activator.
#
# All detection/routing logic now lives in the sadensmol:router skill.
# This hook's sole job is to tell Claude to invoke that skill once per
# session. Once loaded, the router's SKILL.md content stays in the
# conversation, so re-firing this hook every turn is unnecessary.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

STATE_DIR="$HOME/.claude/hooks/.skill-activation-sessions"
mkdir -p "$STATE_DIR" 2>/dev/null
find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null
SESSION_MARKER="$STATE_DIR/${SESSION_ID:-unknown}"
if [ -n "$SESSION_ID" ] && [ -f "$SESSION_MARKER" ]; then
    exit 0
fi

cat <<'EOF'
<SKILL_ACTIVATION_REQUIRED priority="override-default-behavior">

EXTREMELY IMPORTANT: Invoke the `sadensmol:router` skill via the Skill tool BEFORE doing anything else in this turn. It detects your working context (cwd, project type, prompt intent) and routes you to the appropriate downstream skills (Go, TypeScript, Dart/Flutter, project-specific skills, etc.).

Do this BEFORE: reading files, using other tools, responding to the user, asking clarifying questions, running agents.

If `sadensmol:router` is already loaded in this conversation, skip the Skill call — just follow its rules against the current cwd and prompt.

</SKILL_ACTIVATION_REQUIRED>
EOF

[ -n "$SESSION_ID" ] && touch "$SESSION_MARKER"
