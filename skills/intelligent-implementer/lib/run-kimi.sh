#!/bin/bash
# Wrapper to run Kimi CLI.
#
# Kimi CLI works fine without PTY when using --print mode.
# This wrapper simply runs Kimi with the correct arguments.
#
# Note: Do NOT use PTY wrappers (script, pty.spawn) - they cause output capture
# issues when run through clawdbot's exec tool.
#
# Usage: run-kimi.sh <working-dir> <prompt>

set -e

WORKDIR="$1"
PROMPT="$2"

if [[ -z "$WORKDIR" || -z "$PROMPT" ]]; then
    echo "Usage: run-kimi.sh <working-dir> <prompt>" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  working-dir    Path to the working directory" >&2
    echo "  prompt         The prompt to send to Kimi" >&2
    exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
    echo "Error: Working directory does not exist: $WORKDIR" >&2
    exit 1
fi

# Run Kimi in print mode - works without PTY
exec kimi --print -w "$WORKDIR" -p "$PROMPT"
