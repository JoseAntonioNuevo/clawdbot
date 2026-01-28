#!/bin/bash
# Wrapper to run Kimi CLI with proper TTY using script command
#
# Like Claude CLI, Kimi may require a controlling terminal to work correctly
# when spawned from processes without a TTY.
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

# Use script to create proper TTY environment
# -q: quiet mode (no "Script started" messages)
# /dev/null: discard the typescript file
# Export variables so they're available in the subshell, avoiding quote escaping issues
# Kimi uses --print for non-interactive mode and -w for working directory
export KIMI_WORKDIR="$WORKDIR"
export KIMI_PROMPT="$PROMPT"
exec script -q /dev/null /bin/bash -c 'kimi --print -w "$KIMI_WORKDIR" -p "$KIMI_PROMPT"'
