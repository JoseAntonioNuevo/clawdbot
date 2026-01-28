#!/bin/bash
# Wrapper to run Claude CLI with proper TTY using script command
#
# Claude CLI hangs when spawned without a controlling terminal, even with node-pty.
# The `script` command creates a full pseudo-terminal session that satisfies Claude's
# TTY detection requirements.
#
# See: https://github.com/anthropics/claude-code/issues/9026
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

# Use script to create proper TTY environment
# -q: quiet mode (no "Script started" messages)
# /dev/null: discard the typescript file (we don't need the recording)
# Export variables so they're available in the subshell, avoiding quote escaping issues
export CLAUDE_PROMPT="$PROMPT"
export CLAUDE_TOOLS="$ALLOWED_TOOLS"
exec script -q /dev/null /bin/bash -c 'claude -p "$CLAUDE_PROMPT" --allowedTools "$CLAUDE_TOOLS"'
