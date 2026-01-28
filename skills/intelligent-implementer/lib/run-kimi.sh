#!/bin/bash
# Wrapper to run Kimi CLI with file-based output.
#
# Clawdbot's exec tool doesn't capture stdout properly from background processes.
# This wrapper redirects output to a file that the orchestrator can read.
#
# Usage: run-kimi.sh <working-dir> <prompt>
#
# Output file: $WORKDIR/.kimi-output.txt
# Status file: $WORKDIR/.kimi-status.txt (contains "RUNNING", "COMPLETED", or "ERROR")

set -e

WORKDIR="$1"
PROMPT="$2"

OUTPUT_FILE="$WORKDIR/.kimi-output.txt"
STATUS_FILE="$WORKDIR/.kimi-status.txt"

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

cd "$WORKDIR"

# Initialize status
echo "RUNNING" > "$STATUS_FILE"
echo "" > "$OUTPUT_FILE"

# Print startup message
echo "Kimi started. Output will be written to: $OUTPUT_FILE"
echo "Check status with: cat $STATUS_FILE"

# Run Kimi and capture output
if kimi --print -w "$WORKDIR" -p "$PROMPT" > "$OUTPUT_FILE" 2>&1; then
    echo "COMPLETED" > "$STATUS_FILE"
    echo "=== KIMI COMPLETED ===" >> "$OUTPUT_FILE"
else
    EXIT_CODE=$?
    echo "ERROR:$EXIT_CODE" > "$STATUS_FILE"
    echo "=== KIMI FAILED (exit $EXIT_CODE) ===" >> "$OUTPUT_FILE"
fi

# Print final status
echo "Kimi finished. Status: $(cat "$STATUS_FILE")"
echo "Output file: $OUTPUT_FILE"
