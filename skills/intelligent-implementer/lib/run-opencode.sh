#!/bin/bash
# Wrapper to run OpenCode CLI.
#
# OpenCode CLI works fine without PTY.
# This wrapper simply runs OpenCode with the correct arguments.
#
# Note: Do NOT use PTY wrappers (script, pty.spawn) - they cause output capture
# issues when run through clawdbot's exec tool.
#
# Usage: run-opencode.sh <working-dir> <model> <prompt>

set -e

WORKDIR="$1"
MODEL="$2"
PROMPT="$3"

if [[ -z "$WORKDIR" || -z "$MODEL" || -z "$PROMPT" ]]; then
    echo "Usage: run-opencode.sh <working-dir> <model> <prompt>" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  working-dir    Path to the working directory" >&2
    echo "  model          Model identifier (e.g., zai-coding-plan/glm-4.7)" >&2
    echo "  prompt         The prompt to send to OpenCode" >&2
    exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
    echo "Error: Working directory does not exist: $WORKDIR" >&2
    exit 1
fi

cd "$WORKDIR"

# Run OpenCode - works without PTY
exec opencode run -m "$MODEL" "$PROMPT"
