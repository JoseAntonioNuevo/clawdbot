#!/bin/bash
# Wrapper to run Claude CLI with a proper TTY.
#
# Historically we used the BSD `script` command to create a controlling terminal,
# but in some environments (e.g., when stdio is a socket) `script` fails with:
#   tcgetattr/ioctl: Operation not supported on socket
#
# This wrapper now uses Python's `pty` module to allocate a pseudo-terminal.
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

export CLAUDE_PROMPT="$PROMPT"
export CLAUDE_TOOLS="$ALLOWED_TOOLS"

python3 - <<'PY'
import os, pty
prompt = os.environ.get('CLAUDE_PROMPT','')
tools = os.environ.get('CLAUDE_TOOLS','Bash,Read,Glob,Grep,WebSearch,WebFetch')
cmd = ['claude','-p', prompt, '--allowedTools', tools]
pty.spawn(cmd)
PY
