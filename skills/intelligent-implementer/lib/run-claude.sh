#!/bin/bash
# Wrapper to run Claude CLI.
#
# Usage: run-claude.sh <working-dir> <prompt> [allowed-tools]

set -e

WORKDIR="$1"
PROMPT="$2"
ALLOWED_TOOLS="${3:-Bash,Read,Glob,Grep,WebSearch,WebFetch}"

if [[ -z "$WORKDIR" || -z "$PROMPT" ]]; then
    echo "Usage: run-claude.sh <working-dir> <prompt> [allowed-tools]" >&2
    exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
    echo "Error: Working directory does not exist: $WORKDIR" >&2
    exit 1
fi

cd "$WORKDIR"

# Run Claude in print mode
# Use --output-format text to ensure clean output
exec claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS" --output-format text
