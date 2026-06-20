FROM node:22-slim

RUN apt-get update \
    && apt-get install -y git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Non-root user. UID 1000 is already taken by the base image's `node` user,
# so use 1001. Pre-create dirs and chown so the named auth volume
# (mounted at ~/.claude) and the workspace are writable.
RUN useradd -m -u 1001 claude \
    && mkdir -p /home/claude/work /home/claude/.claude \
    && chown -R claude:claude /home/claude

USER claude
WORKDIR /home/claude/work
