#!/bin/bash
# Wrapper to run Claude CLI with file-based output.
#
# Clawdbot's exec tool doesn't capture stdout properly from background processes.
# This wrapper redirects output to a file that the orchestrator can read.
#
# Usage: run-claude.sh <working-dir> <prompt> [allowed-tools]
#
# Output file: $WORKDIR/.claude-output.txt
# Status file: $WORKDIR/.claude-status.txt (contains "RUNNING", "COMPLETED", or "ERROR")

set -e

WORKDIR="$1"
PROMPT="$2"
ALLOWED_TOOLS="${3:-Bash,Read,Glob,Grep,WebSearch,WebFetch}"

OUTPUT_FILE="$WORKDIR/.claude-output.txt"
STATUS_FILE="$WORKDIR/.claude-status.txt"

if [[ -z "$WORKDIR" || -z "$PROMPT" ]]; then
    echo "Usage: run-claude.sh <working-dir> <prompt> [allowed-tools]" >&2
    exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
    echo "Error: Working directory does not exist: $WORKDIR" >&2
    exit 1
fi

cd "$WORKDIR"

# Initialize status
echo "RUNNING" > "$STATUS_FILE"
echo "" > "$OUTPUT_FILE"

# Print startup message (this goes to stdout for immediate feedback)
echo "Claude started. Output will be written to: $OUTPUT_FILE"
echo "Check status with: cat $STATUS_FILE"

# Run Claude and capture output
if claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS" --output-format text > "$OUTPUT_FILE" 2>&1; then
    echo "COMPLETED" > "$STATUS_FILE"
    echo "=== CLAUDE COMPLETED ===" >> "$OUTPUT_FILE"
else
    EXIT_CODE=$?
    echo "ERROR:$EXIT_CODE" > "$STATUS_FILE"
    echo "=== CLAUDE FAILED (exit $EXIT_CODE) ===" >> "$OUTPUT_FILE"
fi

# Print final status
echo "Claude finished. Status: $(cat "$STATUS_FILE")"
echo "Output file: $OUTPUT_FILE"
