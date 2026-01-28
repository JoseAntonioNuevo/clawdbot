#!/bin/bash
# Safe Kill Wrapper - Prevents premature agent kills
#
# This wrapper BLOCKS process kill commands if the minimum elapsed time
# has not been reached. GPT-5.2 tends to ignore "wait 30 minutes" instructions,
# so this script enforces the rule at the system level.
#
# Usage: safe-kill.sh <pid> <min-seconds>
#
# Arguments:
#   pid          - Process ID to potentially kill
#   min-seconds  - Minimum seconds that must have elapsed (default: 1800 = 30 min)
#
# Returns:
#   0 - Kill was executed (enough time elapsed)
#   1 - Kill was BLOCKED (not enough time elapsed)
#   2 - Process not found or invalid arguments

set -e

PID="$1"
MIN_SECONDS="${2:-1800}"  # Default: 30 minutes

if [[ -z "$PID" ]]; then
    echo "ERROR: No PID provided" >&2
    echo "Usage: safe-kill.sh <pid> [min-seconds]" >&2
    exit 2
fi

# Check if process exists
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "NOTICE: Process $PID not found (already finished or invalid PID)"
    exit 0
fi

# Get elapsed time in seconds
# ps etime format: [[DD-]HH:]MM:SS
ETIME=$(ps -p "$PID" -o etime= 2>/dev/null | tr -d ' ')

if [[ -z "$ETIME" ]]; then
    echo "ERROR: Could not get elapsed time for PID $PID" >&2
    exit 2
fi

# Parse elapsed time to seconds
# Format can be: SS, MM:SS, HH:MM:SS, or DD-HH:MM:SS
parse_etime() {
    local etime="$1"
    local seconds=0
    local minutes=0
    local hours=0
    local days=0

    # Check for days (DD-HH:MM:SS)
    if [[ "$etime" == *-* ]]; then
        days="${etime%%-*}"
        etime="${etime#*-}"
    fi

    # Split by colon
    IFS=':' read -ra parts <<< "$etime"
    local num_parts=${#parts[@]}

    if [[ $num_parts -eq 1 ]]; then
        seconds="${parts[0]}"
    elif [[ $num_parts -eq 2 ]]; then
        minutes="${parts[0]}"
        seconds="${parts[1]}"
    elif [[ $num_parts -eq 3 ]]; then
        hours="${parts[0]}"
        minutes="${parts[1]}"
        seconds="${parts[2]}"
    fi

    # Remove leading zeros to avoid octal interpretation
    days=$((10#$days))
    hours=$((10#$hours))
    minutes=$((10#$minutes))
    seconds=$((10#$seconds))

    echo $(( days * 86400 + hours * 3600 + minutes * 60 + seconds ))
}

ELAPSED=$(parse_etime "$ETIME")

echo "========================================"
echo "SAFE-KILL CHECK"
echo "========================================"
echo "PID: $PID"
echo "Elapsed time: ${ETIME} (${ELAPSED} seconds)"
echo "Minimum required: ${MIN_SECONDS} seconds"
echo "========================================"

if [[ "$ELAPSED" -lt "$MIN_SECONDS" ]]; then
    REMAINING=$((MIN_SECONDS - ELAPSED))
    echo ""
    echo "========================================"
    echo "KILL BLOCKED - NOT ENOUGH TIME ELAPSED"
    echo "========================================"
    echo "Only ${ELAPSED} seconds have passed."
    echo "Minimum required: ${MIN_SECONDS} seconds ($(( MIN_SECONDS / 60 )) minutes)"
    echo "Time remaining: ${REMAINING} seconds ($(( REMAINING / 60 )) minutes)"
    echo ""
    echo "The agent is still working. 'No output' is NORMAL."
    echo "Agents use thinking mode which produces no stdout."
    echo ""
    echo "ACTION: Keep waiting. Do NOT attempt to kill again."
    echo "========================================"
    exit 1
else
    echo ""
    echo "========================================"
    echo "KILL APPROVED - Minimum time elapsed"
    echo "========================================"
    echo "${ELAPSED} seconds >= ${MIN_SECONDS} seconds"
    echo "Proceeding with kill..."
    echo "========================================"

    # Actually kill the process
    kill -TERM "$PID" 2>/dev/null || true
    sleep 2

    # Force kill if still running
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Process still running, sending SIGKILL..."
        kill -KILL "$PID" 2>/dev/null || true
    fi

    echo "Process $PID terminated."
    exit 0
fi
