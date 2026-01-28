#!/bin/bash
# Wrapper to run Claude CLI.
#
# Claude CLI works fine without PTY when using -p (print mode).
# This wrapper simply runs Claude with the correct arguments.
#
# Note: Do NOT use PTY wrappers (script, pty.spawn) - they cause output capture
# issues when run through clawdbot's exec tool. Claude -p works fine without PTY.
#
# Usage: run-claude.sh <working-dir> <prompt> [allowed-tools]

set -e

WORKDIR="$1"
PROMPT="$2"
ALLOWED_TOOLS="${3:-Bash,Read,Glob,Grep,WebSearch,WebFetch}"

if [[ -z "$WORKDIR" || -z "$PROMPT" ]]; then
    echo "Usage: run-claude.sh <working-dir> <prompt> [allowed-tools]" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  working-dir    Path to the working directory" >&2
    echo "  prompt         The prompt to send to Claude" >&2
    echo "  allowed-tools  Comma-separated list of allowed tools (default: Bash,Read,Glob,Grep,WebSearch,WebFetch)" >&2
    exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
    echo "Error: Working directory does not exist: $WORKDIR" >&2
    exit 1
fi

cd "$WORKDIR"

# Run Claude in print mode - works without PTY
exec claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS"
