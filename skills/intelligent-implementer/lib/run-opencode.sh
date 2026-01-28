#!/bin/bash
# Wrapper to run OpenCode CLI with file-based output.
#
# Clawdbot's exec tool doesn't capture stdout properly from background processes.
# This wrapper redirects output to a file that the orchestrator can read.
#
# Usage: run-opencode.sh <working-dir> <model> <prompt>
#
# Output file: $WORKDIR/.opencode-output.txt
# Status file: $WORKDIR/.opencode-status.txt (contains "RUNNING", "COMPLETED", or "ERROR")

set -e

WORKDIR="$1"
MODEL="$2"
PROMPT="$3"

OUTPUT_FILE="$WORKDIR/.opencode-output.txt"
STATUS_FILE="$WORKDIR/.opencode-status.txt"

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

# Initialize status
echo "RUNNING" > "$STATUS_FILE"
echo "" > "$OUTPUT_FILE"

# Print startup message
echo "OpenCode started. Output will be written to: $OUTPUT_FILE"
echo "Check status with: cat $STATUS_FILE"

# Run OpenCode and capture output
if opencode run -m "$MODEL" "$PROMPT" > "$OUTPUT_FILE" 2>&1; then
    echo "COMPLETED" > "$STATUS_FILE"
    echo "=== OPENCODE COMPLETED ===" >> "$OUTPUT_FILE"
else
    EXIT_CODE=$?
    echo "ERROR:$EXIT_CODE" > "$STATUS_FILE"
    echo "=== OPENCODE FAILED (exit $EXIT_CODE) ===" >> "$OUTPUT_FILE"
fi

# Print final status
echo "OpenCode finished. Status: $(cat "$STATUS_FILE")"
echo "Output file: $OUTPUT_FILE"
