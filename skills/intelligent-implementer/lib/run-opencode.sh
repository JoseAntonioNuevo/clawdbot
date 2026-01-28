#!/bin/bash
# Wrapper to run OpenCode CLI with a proper TTY.
#
# BSD `script` can fail when stdio is a socket (tcgetattr/ioctl).
# Use Python's `pty` to allocate a pseudo-terminal instead.
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

export OPENCODE_MODEL="$MODEL"
export OPENCODE_PROMPT="$PROMPT"

cd "$WORKDIR"

python3 - <<'PY'
import pty
cmd = ['/bin/bash','-lc','opencode run -m "$OPENCODE_MODEL" "$OPENCODE_PROMPT"']
pty.spawn(cmd)
PY
