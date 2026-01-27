#!/bin/bash
# Update Cumulative Context
# Rebuilds the cumulative context file after each iteration
set -euo pipefail

usage() {
  cat << EOF
Update Cumulative Context

Usage: $(basename "$0") [options]

Required:
  --log-dir PATH        Path to log directory
  --iteration N         Current iteration number
  --status STATUS       approved|rejected

Optional:
  --feedback FILE       Path to feedback file (for rejected)
  -h, --help            Show this help

Examples:
  $(basename "$0") --log-dir /path/to/logs --iteration 1 --status approved
  $(basename "$0") --log-dir /path/to/logs --iteration 2 --status rejected --feedback feedback.md
EOF
}

LOG_DIR=""
ITERATION=0
STATUS=""
FEEDBACK_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    --iteration) ITERATION="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --feedback) FEEDBACK_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$LOG_DIR" ]] && { echo "ERROR: --log-dir required" >&2; exit 1; }
[[ $ITERATION -eq 0 ]] && { echo "ERROR: --iteration required" >&2; exit 1; }
[[ -z "$STATUS" ]] && { echo "ERROR: --status required" >&2; exit 1; }

CONTEXT_DIR="$LOG_DIR/context"
OUTPUT="$CONTEXT_DIR/cumulative_context.md"

mkdir -p "$CONTEXT_DIR"

{
  echo "# Cumulative Task Context"
  echo ""
  echo "Last updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Current iteration: $ITERATION"
  echo "Status: $STATUS"
  echo ""
  echo "---"
  echo ""

  # Original task
  echo "## Original Task"
  echo ""
  if [[ -f "$CONTEXT_DIR/original_task.md" ]]; then
    cat "$CONTEXT_DIR/original_task.md"
  else
    echo "(Not available)"
  fi
  echo ""
  echo "---"
  echo ""

  # Codebase overview
  echo "## Codebase Overview"
  echo ""
  if [[ -f "$CONTEXT_DIR/codebase_summary.md" ]]; then
    cat "$CONTEXT_DIR/codebase_summary.md"
  else
    echo "(Not available)"
  fi
  echo ""
  echo "---"
  echo ""

  # Iteration history
  echo "## Iteration History"
  echo ""

  for i in $(seq 1 $ITERATION); do
    ITER_DIR="$LOG_DIR/iterations/iter_$(printf '%03d' $i)"

    if [[ -d "$ITER_DIR" ]]; then
      echo "### Iteration $i"
      echo ""

      # Plan
      if [[ -f "$ITER_DIR/claude_plan.md" ]]; then
        echo "#### Plan (Claude Code)"
        echo ""
        cat "$ITER_DIR/claude_plan.md"
        echo ""
      fi

      # Implementation
      if [[ -f "$ITER_DIR/kimi_implementation.md" ]]; then
        echo "#### Implementation (Kimi K2.5)"
        echo ""
        cat "$ITER_DIR/kimi_implementation.md"
        echo ""
      fi

      # Test results
      if [[ -f "$ITER_DIR/test_results.txt" ]]; then
        echo "#### Test Results"
        echo ""
        echo "\`\`\`"
        cat "$ITER_DIR/test_results.txt" | head -30
        echo "\`\`\`"
        echo ""
      fi

      # Review/Feedback
      if [[ -f "$ITER_DIR/codex_feedback.md" ]]; then
        echo "#### Review (Codex)"
        echo ""
        cat "$ITER_DIR/codex_feedback.md"
        echo ""
      fi

      # Status for this iteration
      if [[ $i -eq $ITERATION ]]; then
        echo "#### Status: **$STATUS**"
      else
        echo "#### Status: rejected (continued to next iteration)"
      fi
      echo ""
      echo "---"
      echo ""
    fi
  done

  # Current state summary
  echo "## Current State"
  echo ""

  if [[ "$STATUS" == "approved" ]]; then
    echo "### Status: APPROVED"
    echo ""
    echo "The implementation has passed code review and is ready for PR creation."
  else
    echo "### Status: NEEDS REVISION"
    echo ""
    echo "The implementation did not pass code review."
    echo ""

    if [[ -n "$FEEDBACK_FILE" && -f "$FEEDBACK_FILE" ]]; then
      echo "### Outstanding Issues"
      echo ""
      cat "$FEEDBACK_FILE"
      echo ""
    fi

    echo "### What Needs to Happen Next"
    echo ""
    echo "1. Claude Code needs to analyze the feedback"
    echo "2. Create a revised plan addressing all issues"
    echo "3. Kimi K2.5 will implement the revised plan"
    echo "4. Codex will review again"
  fi

} > "$OUTPUT"

echo "Cumulative context updated: $OUTPUT"
