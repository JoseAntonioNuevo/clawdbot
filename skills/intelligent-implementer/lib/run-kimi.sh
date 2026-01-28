#!/bin/bash
# Wrapper to run Kimi CLI with a proper TTY.
#
# BSD `script` can fail when stdio is a socket (tcgetattr/ioctl).
# Use Python's `pty` to allocate a pseudo-terminal instead.
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

export KIMI_WORKDIR="$WORKDIR"
export KIMI_PROMPT="$PROMPT"

python3 - <<'PY'
import pty
cmd = ['/bin/bash','-lc','kimi --print -w "$KIMI_WORKDIR" -p "$KIMI_PROMPT"']
pty.spawn(cmd)
PY
