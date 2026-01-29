#!/bin/bash
# Retry wrapper with exponential backoff for transient errors
#
# Automatically retries commands that fail with transient errors like:
# - Timeouts (exit 124)
# - Network errors (exit 125)
# - Rate limits (exit 429 or detected in output)
# - Service unavailable (exit 503)
#
# Usage: retry-with-backoff.sh [options] <command...>
#
# Options:
#   --max-retries N    Maximum retry attempts (default: 3)
#   --initial-delay N  Initial delay in seconds (default: 5)
#   --max-delay N      Maximum delay in seconds (default: 300)
#   --status-file F    File to check for rate limit indicators
#
# Exit codes:
#   0   - Command succeeded
#   1   - Permanent error (not retryable)
#   2   - Max retries exceeded
#   *   - Last command exit code

set -e

# Default configuration
MAX_RETRIES=3
INITIAL_DELAY=5
MAX_DELAY=300
STATUS_FILE=""

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        --initial-delay)
            INITIAL_DELAY="$2"
            shift 2
            ;;
        --max-delay)
            MAX_DELAY="$2"
            shift 2
            ;;
        --status-file)
            STATUS_FILE="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Remaining arguments are the command
COMMAND="$@"

if [[ -z "$COMMAND" ]]; then
    echo "Usage: retry-with-backoff.sh [options] <command...>" >&2
    echo ""
    echo "Options:"
    echo "  --max-retries N    Maximum retry attempts (default: 3)"
    echo "  --initial-delay N  Initial delay in seconds (default: 5)"
    echo "  --max-delay N      Maximum delay in seconds (default: 300)"
    echo "  --status-file F    File to check for rate limit indicators"
    exit 1
fi

# Error classification - returns 0 if transient (should retry), 1 if permanent
is_transient_error() {
    local EXIT_CODE=$1
    local OUTPUT="$2"

    # Check exit codes known to be transient
    case $EXIT_CODE in
        124)
            # Timeout - transient
            echo "[RETRY] Detected timeout (exit 124)" >&2
            return 0
            ;;
        125)
            # Network error - transient
            echo "[RETRY] Detected network error (exit 125)" >&2
            return 0
            ;;
        429)
            # Rate limit (if passed through) - transient
            echo "[RETRY] Detected rate limit (exit 429)" >&2
            return 0
            ;;
        503)
            # Service unavailable - transient
            echo "[RETRY] Detected service unavailable (exit 503)" >&2
            return 0
            ;;
    esac

    # Check output for rate limit indicators
    if [[ -n "$OUTPUT" ]]; then
        if echo "$OUTPUT" | grep -qi "rate.limit\|429\|quota.exceeded\|too.many.requests"; then
            echo "[RETRY] Detected rate limit in output" >&2
            return 0
        fi
        if echo "$OUTPUT" | grep -qi "timeout\|timed.out\|connection.refused"; then
            echo "[RETRY] Detected timeout/connection error in output" >&2
            return 0
        fi
        if echo "$OUTPUT" | grep -qi "temporarily.unavailable\|service.unavailable\|503"; then
            echo "[RETRY] Detected service unavailable in output" >&2
            return 0
        fi
    fi

    # Check status file for rate limit indicators
    if [[ -n "$STATUS_FILE" && -f "$STATUS_FILE" ]]; then
        local STATUS_CONTENT=$(cat "$STATUS_FILE" 2>/dev/null || echo "")
        if echo "$STATUS_CONTENT" | grep -qi "TIMEOUT\|rate.limit\|429\|ERROR:429"; then
            echo "[RETRY] Detected transient error in status file" >&2
            return 0
        fi
    fi

    # Permanent error - don't retry
    return 1
}

# Main retry loop
RETRY_COUNT=0
BACKOFF=$INITIAL_DELAY
LAST_OUTPUT=""
LAST_EXIT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    # Run the command and capture output
    set +e
    LAST_OUTPUT=$(eval "$COMMAND" 2>&1)
    LAST_EXIT=$?
    set -e

    # Success - exit immediately
    if [[ $LAST_EXIT -eq 0 ]]; then
        echo "$LAST_OUTPUT"
        exit 0
    fi

    # Check if error is transient
    if is_transient_error $LAST_EXIT "$LAST_OUTPUT"; then
        RETRY_COUNT=$((RETRY_COUNT + 1))

        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
            echo "[RETRY] Attempt $RETRY_COUNT/$MAX_RETRIES failed (exit $LAST_EXIT). Waiting ${BACKOFF}s before retry..." >&2
            sleep $BACKOFF

            # Exponential backoff with jitter
            JITTER=$((RANDOM % 10))
            BACKOFF=$((BACKOFF * 2 + JITTER))

            # Cap at max delay
            if [[ $BACKOFF -gt $MAX_DELAY ]]; then
                BACKOFF=$MAX_DELAY
            fi
        fi
    else
        # Permanent error - don't retry
        echo "[ERROR] Permanent error (exit $LAST_EXIT). Not retrying." >&2
        echo "$LAST_OUTPUT"
        exit $LAST_EXIT
    fi
done

# Max retries exceeded
echo "[ERROR] Max retries ($MAX_RETRIES) exceeded. Last exit code: $LAST_EXIT" >&2
echo "$LAST_OUTPUT"
exit 2
