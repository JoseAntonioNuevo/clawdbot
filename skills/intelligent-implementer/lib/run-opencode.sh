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

# Run OpenCode with expect to create a PTY and auto-approve permission prompts
# The expect script will automatically send "y" when it sees permission requests
/usr/bin/expect -c "
    log_user 1
    set timeout 1800
    spawn opencode run -m {$MODEL} {$PROMPT}

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
                # Check if process is still running
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
    grep -v '^spawn opencode' | \
    sed '/^$/d' | \
    cat > "$OUTPUT_FILE"
EXIT_CODE=${PIPESTATUS[0]}

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "COMPLETED" > "$STATUS_FILE"
    echo "=== OPENCODE COMPLETED ===" >> "$OUTPUT_FILE"
else
    echo "ERROR:$EXIT_CODE" > "$STATUS_FILE"
    echo "=== OPENCODE FAILED (exit $EXIT_CODE) ===" >> "$OUTPUT_FILE"
fi

# Print final status
echo "OpenCode finished. Status: $(cat "$STATUS_FILE")"
echo "Output file: $OUTPUT_FILE"
