#!/bin/bash
# Wrapper to run OpenCode CLI with proper TTY using script command
#
# Like Claude CLI, OpenCode may require a controlling terminal to work correctly
# when spawned from processes without a TTY.
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

# Use script to create proper TTY environment
# -q: quiet mode (no "Script started" messages)
# /dev/null: discard the typescript file
# Export variables so they're available in the subshell, avoiding quote escaping issues
export OPENCODE_MODEL="$MODEL"
export OPENCODE_PROMPT="$PROMPT"
exec script -q /dev/null /bin/bash -c 'opencode run -m "$OPENCODE_MODEL" "$OPENCODE_PROMPT"'
