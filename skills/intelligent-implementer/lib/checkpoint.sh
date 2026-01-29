#!/bin/bash
# Checkpoint management for clawdbot orchestrator
#
# Enables resume capability after orchestrator crashes or timeouts.
# Saves state before each step so workflow can be resumed from last checkpoint.
#
# Usage:
#   checkpoint.sh save <worktree> <step> <status> [data_json]
#   checkpoint.sh complete-step <worktree> <step>
#   checkpoint.sh load <worktree>
#   checkpoint.sh get-step <worktree>
#   checkpoint.sh init <worktree> <task_id> <project> <task_description>
#
# Checkpoint file: <worktree>/.checkpoint.json

set -e

ACTION="$1"
WORKTREE="$2"
CHECKPOINT_FILE="$WORKTREE/.checkpoint.json"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed" >&2
    exit 1
fi

case "$ACTION" in
    init)
        # Initialize a new checkpoint file
        TASK_ID="$3"
        PROJECT="$4"
        TASK_DESC="$5"

        if [[ -z "$TASK_ID" || -z "$PROJECT" ]]; then
            echo "Usage: checkpoint.sh init <worktree> <task_id> <project> [task_description]" >&2
            exit 1
        fi

        cat > "$CHECKPOINT_FILE" <<EOF
{
  "version": 1,
  "task_id": "$TASK_ID",
  "project": "$PROJECT",
  "task_description": $(echo "$TASK_DESC" | jq -Rs .),
  "current_step": 0,
  "completed_steps": [],
  "step_data": {},
  "iteration_counts": {
    "codex_review": 0,
    "build_fix": 0
  },
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        echo "Checkpoint initialized: $CHECKPOINT_FILE"
        ;;

    save)
        # Save checkpoint for a step
        STEP="$3"
        STATUS="$4"
        DATA="${5:-{}}"

        if [[ -z "$STEP" || -z "$STATUS" ]]; then
            echo "Usage: checkpoint.sh save <worktree> <step> <status> [data_json]" >&2
            exit 1
        fi

        if [[ ! -f "$CHECKPOINT_FILE" ]]; then
            echo "ERROR: Checkpoint file not found. Run 'init' first." >&2
            exit 1
        fi

        # Validate DATA is valid JSON
        if ! echo "$DATA" | jq . > /dev/null 2>&1; then
            DATA="{}"
        fi

        # Update checkpoint atomically
        TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq --arg step "$STEP" \
           --arg status "$STATUS" \
           --arg ts "$TIMESTAMP" \
           --argjson data "$DATA" \
            '.current_step = ($step | tonumber) |
             .step_data[$step] = (.step_data[$step] // {}) |
             .step_data[$step].status = $status |
             .step_data[$step].started_at = (if .step_data[$step].started_at then .step_data[$step].started_at else $ts end) |
             .step_data[$step] = (.step_data[$step] + $data) |
             .last_updated = $ts' \
            "$CHECKPOINT_FILE" > "$CHECKPOINT_FILE.tmp" && \
            mv "$CHECKPOINT_FILE.tmp" "$CHECKPOINT_FILE"

        echo "Checkpoint saved: step=$STEP status=$STATUS"
        ;;

    complete-step)
        # Mark a step as completed
        STEP="$3"

        if [[ -z "$STEP" ]]; then
            echo "Usage: checkpoint.sh complete-step <worktree> <step>" >&2
            exit 1
        fi

        if [[ ! -f "$CHECKPOINT_FILE" ]]; then
            echo "ERROR: Checkpoint file not found." >&2
            exit 1
        fi

        TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq --arg step "$STEP" --arg ts "$TIMESTAMP" \
            '.completed_steps = (.completed_steps + [$step | tonumber] | unique | sort) |
             .step_data[$step].status = "completed" |
             .step_data[$step].completed_at = $ts |
             .last_updated = $ts' \
            "$CHECKPOINT_FILE" > "$CHECKPOINT_FILE.tmp" && \
            mv "$CHECKPOINT_FILE.tmp" "$CHECKPOINT_FILE"

        echo "Step $STEP marked completed"
        ;;

    increment)
        # Increment an iteration counter
        COUNTER="$3"

        if [[ -z "$COUNTER" ]]; then
            echo "Usage: checkpoint.sh increment <worktree> <counter_name>" >&2
            exit 1
        fi

        if [[ ! -f "$CHECKPOINT_FILE" ]]; then
            echo "ERROR: Checkpoint file not found." >&2
            exit 1
        fi

        TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq --arg counter "$COUNTER" --arg ts "$TIMESTAMP" \
            '.iteration_counts[$counter] = ((.iteration_counts[$counter] // 0) + 1) |
             .last_updated = $ts' \
            "$CHECKPOINT_FILE" > "$CHECKPOINT_FILE.tmp" && \
            mv "$CHECKPOINT_FILE.tmp" "$CHECKPOINT_FILE"

        NEW_VALUE=$(jq -r ".iteration_counts.$COUNTER" "$CHECKPOINT_FILE")
        echo "Counter $COUNTER incremented to $NEW_VALUE"
        ;;

    load)
        # Load the entire checkpoint
        if [[ -f "$CHECKPOINT_FILE" ]]; then
            cat "$CHECKPOINT_FILE"
        else
            echo "{}"
        fi
        ;;

    get-step)
        # Get the current step number
        if [[ -f "$CHECKPOINT_FILE" ]]; then
            jq -r '.current_step // 0' "$CHECKPOINT_FILE"
        else
            echo "0"
        fi
        ;;

    get-counter)
        # Get an iteration counter value
        COUNTER="$3"

        if [[ -z "$COUNTER" ]]; then
            echo "Usage: checkpoint.sh get-counter <worktree> <counter_name>" >&2
            exit 1
        fi

        if [[ -f "$CHECKPOINT_FILE" ]]; then
            jq -r ".iteration_counts.$COUNTER // 0" "$CHECKPOINT_FILE"
        else
            echo "0"
        fi
        ;;

    is-step-completed)
        # Check if a specific step is completed
        STEP="$3"

        if [[ -z "$STEP" ]]; then
            echo "Usage: checkpoint.sh is-step-completed <worktree> <step>" >&2
            exit 1
        fi

        if [[ -f "$CHECKPOINT_FILE" ]]; then
            COMPLETED=$(jq -r ".completed_steps | contains([$STEP])" "$CHECKPOINT_FILE")
            if [[ "$COMPLETED" == "true" ]]; then
                echo "true"
                exit 0
            fi
        fi
        echo "false"
        exit 1
        ;;

    get-step-data)
        # Get data for a specific step
        STEP="$3"

        if [[ -z "$STEP" ]]; then
            echo "Usage: checkpoint.sh get-step-data <worktree> <step>" >&2
            exit 1
        fi

        if [[ -f "$CHECKPOINT_FILE" ]]; then
            jq -r ".step_data[\"$STEP\"] // {}" "$CHECKPOINT_FILE"
        else
            echo "{}"
        fi
        ;;

    *)
        echo "Checkpoint management for clawdbot orchestrator"
        echo ""
        echo "Usage: checkpoint.sh <action> <worktree> [args...]"
        echo ""
        echo "Actions:"
        echo "  init <worktree> <task_id> <project> [desc]  Initialize new checkpoint"
        echo "  save <worktree> <step> <status> [data]      Save checkpoint for step"
        echo "  complete-step <worktree> <step>             Mark step as completed"
        echo "  increment <worktree> <counter>              Increment iteration counter"
        echo "  load <worktree>                             Load full checkpoint JSON"
        echo "  get-step <worktree>                         Get current step number"
        echo "  get-counter <worktree> <counter>            Get counter value"
        echo "  is-step-completed <worktree> <step>         Check if step completed"
        echo "  get-step-data <worktree> <step>             Get data for step"
        echo ""
        echo "Counters: codex_review, build_fix"
        exit 1
        ;;
esac
