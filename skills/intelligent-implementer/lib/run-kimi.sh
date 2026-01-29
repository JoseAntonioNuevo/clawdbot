#!/bin/bash
# Wrapper to run Kimi CLI with file-based output and timeout monitoring.
#
# Clawdbot's exec tool doesn't capture stdout properly from background processes.
# This wrapper redirects output to a file that the orchestrator can read.
#
# Features:
# - PTY creation via expect for proper terminal handling
# - Auto-approval of permission prompts
# - File-based output capture
# - Timeout monitoring (no-activity and max-time detection)
# - Clean terminal code removal
#
# Usage: run-kimi.sh <working-dir> <prompt>
#
# Output file: $WORKDIR/.kimi-output.txt
# Status file: $WORKDIR/.kimi-status.txt
#
# Status values:
#   RUNNING           - Agent still working
#   COMPLETED         - Agent finished successfully
#   ERROR:<code>      - Agent failed with exit code
#   TIMEOUT:NO_ACTIVITY - No output for 30 minutes
#   TIMEOUT:MAX_TIME  - Exceeded 60 minute maximum

set -e

WORKDIR="$1"
PROMPT="$2"

OUTPUT_FILE="$WORKDIR/.kimi-output.txt"
STATUS_FILE="$WORKDIR/.kimi-status.txt"
PID_FILE="$WORKDIR/.kimi-pid.txt"

# Timeout configuration (in seconds)
NO_ACTIVITY_TIMEOUT=1800   # 30 minutes without output file modification
MAX_TIME_TIMEOUT=3600      # 60 minutes maximum runtime
HEARTBEAT_INTERVAL=60      # Check every 60 seconds

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
echo "" > "$PID_FILE"

# Print startup message
echo "Kimi started. Output will be written to: $OUTPUT_FILE"
echo "Check status with: cat $STATUS_FILE"
echo "Timeout monitoring: NO_ACTIVITY=${NO_ACTIVITY_TIMEOUT}s, MAX_TIME=${MAX_TIME_TIMEOUT}s"

# Timeout monitoring function
# Runs in background and checks for activity
monitor_timeout() {
    local MAIN_PID=$1
    local START_TIME=$(date +%s)
    local LAST_ACTIVITY=$START_TIME

    while kill -0 $MAIN_PID 2>/dev/null; do
        sleep $HEARTBEAT_INTERVAL

        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))

        # Check if output file was modified (activity indicator)
        if [[ -f "$OUTPUT_FILE" ]]; then
            # Get file modification time (macOS uses -f %m, Linux uses -c %Y)
            if [[ "$(uname)" == "Darwin" ]]; then
                LAST_MOD=$(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo "$LAST_ACTIVITY")
            else
                LAST_MOD=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "$LAST_ACTIVITY")
            fi

            if [[ "$LAST_MOD" -gt "$LAST_ACTIVITY" ]]; then
                LAST_ACTIVITY=$LAST_MOD
            fi
        fi

        # Check for no activity timeout (30 minutes without file changes)
        NO_ACTIVITY=$((CURRENT_TIME - LAST_ACTIVITY))
        if [[ $NO_ACTIVITY -gt $NO_ACTIVITY_TIMEOUT ]]; then
            echo "TIMEOUT:NO_ACTIVITY" > "$STATUS_FILE"
            echo "=== TIMEOUT: No activity for ${NO_ACTIVITY_TIMEOUT}s ===" >> "$OUTPUT_FILE"
            kill -TERM $MAIN_PID 2>/dev/null || true
            return 124
        fi

        # Check for max time timeout (60 minutes total)
        if [[ $ELAPSED -gt $MAX_TIME_TIMEOUT ]]; then
            echo "TIMEOUT:MAX_TIME" > "$STATUS_FILE"
            echo "=== TIMEOUT: Maximum time ${MAX_TIME_TIMEOUT}s exceeded ===" >> "$OUTPUT_FILE"
            kill -TERM $MAIN_PID 2>/dev/null || true
            return 124
        fi
    done

    return 0
}

# Run Kimi with expect to create a PTY and auto-approve permission prompts
# Run the main command in background so we can monitor it
(
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
    echo "${PIPESTATUS[0]}" > "$WORKDIR/.kimi-exit-code.txt"
) &
MAIN_PID=$!
echo "$MAIN_PID" > "$PID_FILE"

# Start timeout monitoring in background
monitor_timeout $MAIN_PID &
MONITOR_PID=$!

# Wait for main process to complete
wait $MAIN_PID 2>/dev/null || true

# Kill monitor if still running
kill $MONITOR_PID 2>/dev/null || true

# Get exit code from file (more reliable than wait status)
if [[ -f "$WORKDIR/.kimi-exit-code.txt" ]]; then
    EXIT_CODE=$(cat "$WORKDIR/.kimi-exit-code.txt")
    rm -f "$WORKDIR/.kimi-exit-code.txt"
else
    EXIT_CODE=1
fi

# Only update status if not already set to TIMEOUT
CURRENT_STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "")
if [[ ! "$CURRENT_STATUS" =~ ^TIMEOUT ]]; then
    if [[ "$EXIT_CODE" -eq 0 ]]; then
        echo "COMPLETED" > "$STATUS_FILE"
        echo "=== KIMI COMPLETED ===" >> "$OUTPUT_FILE"
    else
        echo "ERROR:$EXIT_CODE" > "$STATUS_FILE"
        echo "=== KIMI FAILED (exit $EXIT_CODE) ===" >> "$OUTPUT_FILE"
    fi
fi

# Print final status
echo "Kimi finished. Status: $(cat "$STATUS_FILE")"
echo "Output file: $OUTPUT_FILE"

# Cleanup
rm -f "$PID_FILE" "$WORKDIR/.kimi-exit-code.txt"
