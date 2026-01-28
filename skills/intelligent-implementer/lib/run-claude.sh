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

# Run Claude with expect to create a PTY
# This is needed because Claude CLI hangs when spawned from a process with no controlling terminal
# expect provides a proper pseudo-terminal environment
/usr/bin/expect -c "
    log_user 1
    set timeout -1
    spawn claude -p {$PROMPT} --allowedTools {$ALLOWED_TOOLS} --output-format text
    expect eof
    catch wait result
    exit [lindex \$result 3]
" 2>&1 | \
    # Remove terminal control codes, escape sequences, and prompt artifacts
    perl -pe '
        s/\e\[[0-9;]*[a-zA-Z]//g;           # ANSI escape sequences
        s/\e\][^\a\e]*(?:\a|\e\\)?//g;      # OSC sequences
        s/\[\?[0-9]+[hl]//g;                # DEC private mode sequences
        s/\[<u//g;                           # cursor artifacts
        s/\]9;[^;]*;[^;]*;//g;              # iTerm2 sequences
        s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g;  # other control chars
    ' | \
    grep -v '^spawn claude' | \
    sed '/^$/d' | \
    cat > "$OUTPUT_FILE"
EXIT_CODE=${PIPESTATUS[0]}

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "COMPLETED" > "$STATUS_FILE"
    echo "=== CLAUDE COMPLETED ===" >> "$OUTPUT_FILE"
else
    echo "ERROR:$EXIT_CODE" > "$STATUS_FILE"
    echo "=== CLAUDE FAILED (exit $EXIT_CODE) ===" >> "$OUTPUT_FILE"
fi

# Print final status
echo "Claude finished. Status: $(cat "$STATUS_FILE")"
echo "Output file: $OUTPUT_FILE"
