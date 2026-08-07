#!/bin/sh
# UserPromptSubmit hook — router injector.
#
# Fires on EVERY request. Injects the FULL sadensmol:router SKILL.md into
# context every turn, so the routing rules are ALWAYS present regardless of
# whether the Skill tool was ever invoked. This closes the failure mode where
# Claude assumes "a router already ran" and skips the routing pass — leaving
# downstream skills (go-programming, typescript-programming, …) unloaded.
#
# Portable + dependency-free: resolves the router via $CLAUDE_PLUGIN_ROOT, so
# it works on any machine where the plugin is installed. No jq, no session
# marker — guaranteed to run on every prompt.

ROUTER="${CLAUDE_PLUGIN_ROOT}/skills/router/SKILL.md"

printf '%s\n\n' '<SKILL_ACTIVATION_REQUIRED priority="override-default-behavior">'
printf '%s\n\n' 'EXTREMELY IMPORTANT: The sadensmol:router rules are reproduced IN FULL below and are therefore ALWAYS in context. Evaluate them against the current cwd and prompt NOW, and invoke (via the Skill tool) EVERY downstream skill they name that is not already loaded — BEFORE reading files, editing, running tools, or answering. A different router having run is NOT this router having run; never assume routing is already handled or was cached.'

if [ -f "$ROUTER" ]; then
  cat "$ROUTER"
else
  printf '%s\n' 'router SKILL.md not found at CLAUDE_PLUGIN_ROOT — invoke the `sadensmol:router` skill via the Skill tool now if it is not already loaded.'
fi

printf '\n%s\n' '</SKILL_ACTIVATION_REQUIRED>'
