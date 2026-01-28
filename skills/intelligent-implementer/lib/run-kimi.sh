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

# Run Kimi with expect to create a PTY and auto-approve permission prompts
/usr/bin/expect -c "
    log_user 1
    set timeout 1800
    spawn kimi --print -w {$WORKDIR} -p {$PROMPT}

    # Loop to handle multiple permission prompts
    while {1} {
        expect {
            -re {Permission required|Allow|Approve|y/n|Y/n|\[y\]|\[Y\]} {
                send \"y\r\"
                exp_continue
            }
            eof {
                break
            }
            timeout {
                if {[catch {exec kill -0 \$spawn_id} result]} {
                    break
                }
                exp_continue
            }
        }
    }

    catch wait result
    exit [lindex \$result 3]
" 2>&1 | \
    # Remove terminal control codes and escape sequences
    perl -pe '
        s/\e\[[0-9;]*[a-zA-Z]//g;
        s/\e\][^\a\e]*(?:\a|\e\\)?//g;
        s/\[\?[0-9]+[hl]//g;
        s/\[<u//g;
        s/\]9;[^;]*;[^;]*;//g;
        s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g;
    ' | \
    grep -v '^spawn kimi' | \
    sed '/^$/d' | \
    cat > "$OUTPUT_FILE"
EXIT_CODE=${PIPESTATUS[0]}

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "COMPLETED" > "$STATUS_FILE"
    echo "=== KIMI COMPLETED ===" >> "$OUTPUT_FILE"
else
    echo "ERROR:$EXIT_CODE" > "$STATUS_FILE"
    echo "=== KIMI FAILED (exit $EXIT_CODE) ===" >> "$OUTPUT_FILE"
fi

# Print final status
echo "Kimi finished. Status: $(cat "$STATUS_FILE")"
echo "Output file: $OUTPUT_FILE"
