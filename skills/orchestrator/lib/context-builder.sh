#!/bin/bash
# Context Builder for Clawdbot Orchestrator
# Builds comprehensive context for Claude Code escalation
set -euo pipefail

usage() {
  cat << EOF
Context Builder for Clawdbot

Builds comprehensive context when escalating from OpenCode to Claude Code.

Usage: $(basename "$0") [options]

Options:
  -p, --project PATH      Original project path (required)
  -w, --worktree PATH     Worktree path (required)
  -t, --task TASK         Task description (required)
  -l, --log-dir PATH      Log directory (required)
  -o, --output FILE       Output file (required)
  --max-diff-lines N      Max lines of diff to include (default: 500)
  -h, --help              Show this help

Examples:
  $(basename "$0") -p /path/to/repo -w /path/to/worktree -t "Fix bug" -l /logs -o context.md
EOF
}

PROJECT_PATH=""
WORKTREE_PATH=""
TASK=""
LOG_DIR=""
OUTPUT_FILE=""
MAX_DIFF_LINES=500

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--project) PROJECT_PATH="$2"; shift 2 ;;
    -w|--worktree) WORKTREE_PATH="$2"; shift 2 ;;
    -t|--task) TASK="$2"; shift 2 ;;
    -l|--log-dir) LOG_DIR="$2"; shift 2 ;;
    -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
    --max-diff-lines) MAX_DIFF_LINES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

[[ -z "$PROJECT_PATH" ]] && { echo "ERROR: --project is required"; exit 1; }
[[ -z "$WORKTREE_PATH" ]] && { echo "ERROR: --worktree is required"; exit 1; }
[[ -z "$TASK" ]] && { echo "ERROR: --task is required"; exit 1; }
[[ -z "$LOG_DIR" ]] && { echo "ERROR: --log-dir is required"; exit 1; }
[[ -z "$OUTPUT_FILE" ]] && { echo "ERROR: --output is required"; exit 1; }

# Create output directory
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Get state info
STATE_FILE="$LOG_DIR/state.json"
if [[ -f "$STATE_FILE" ]]; then
  BASE_BRANCH=$(jq -r '.base_branch // "main"' "$STATE_FILE")
  OPENCODE_ITERS=$(jq -r '.opencode_iterations // 0' "$STATE_FILE")
  BRANCH_NAME=$(jq -r '.branch // "unknown"' "$STATE_FILE")
else
  BASE_BRANCH="main"
  OPENCODE_ITERS="unknown"
  BRANCH_NAME="unknown"
fi

# Start building context
cat > "$OUTPUT_FILE" << EOF
# Claude Code Escalation Context

You are taking over a coding task from OpenCode (GLM 4.7) which has been unable to complete it after multiple attempts. Your job is to analyze what went wrong and complete the task successfully.

## Original Task

$TASK

## Environment

- **Project**: $PROJECT_PATH
- **Working Directory**: $WORKTREE_PATH
- **Branch**: $BRANCH_NAME
- **Base Branch**: $BASE_BRANCH
- **OpenCode Iterations**: $OPENCODE_ITERS

## Why Escalated

EOF

# Add stuck reason if available
if [[ -f "$LOG_DIR/stuck_reason.md" ]]; then
  echo "### Stuck Detection Analysis" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  cat "$LOG_DIR/stuck_reason.md" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
else
  echo "OpenCode reached maximum iterations without resolving all issues." >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
fi

# Add current blocking issues
if [[ -f "$LOG_DIR/codex_feedback.md" ]]; then
  cat >> "$OUTPUT_FILE" << EOF

## Current Blocking Issues (from Codex Review)

$(cat "$LOG_DIR/codex_feedback.md")

EOF
fi

# Add recent Codex reviews summary
cat >> "$OUTPUT_FILE" << EOF

## Recent Review History

EOF

RECENT_REVIEWS=$(ls -t "$LOG_DIR/codex/review_"*.json 2>/dev/null | head -5)
if [[ -n "$RECENT_REVIEWS" ]]; then
  for review in $RECENT_REVIEWS; do
    iter=$(basename "$review" .json | sed 's/review_//')
    echo "### Iteration $iter" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Extract key info from review
    approved=$(jq -r '.approved // false' "$review" 2>/dev/null)
    echo "- Approved: $approved" >> "$OUTPUT_FILE"

    # Count issues by severity
    critical=$(jq '[.issues[]? | select(.severity == "critical")] | length' "$review" 2>/dev/null || echo "0")
    blocking=$(jq '[.issues[]? | select(.blocking == true)] | length' "$review" 2>/dev/null || echo "0")
    warnings=$(jq '[.issues[]? | select(.severity == "warning")] | length' "$review" 2>/dev/null || echo "0")

    echo "- Critical issues: $critical" >> "$OUTPUT_FILE"
    echo "- Blocking issues: $blocking" >> "$OUTPUT_FILE"
    echo "- Warnings: $warnings" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
  done
else
  echo "No review history available." >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
fi

# Add current diff
cat >> "$OUTPUT_FILE" << EOF

## Current Changes (Diff from $BASE_BRANCH)

\`\`\`diff
EOF

cd "$WORKTREE_PATH"
git diff "$BASE_BRANCH"...HEAD 2>/dev/null | head -n "$MAX_DIFF_LINES" >> "$OUTPUT_FILE" || echo "No diff available" >> "$OUTPUT_FILE"

# Add truncation notice if needed
TOTAL_DIFF_LINES=$(git diff "$BASE_BRANCH"...HEAD 2>/dev/null | wc -l)
if [[ $TOTAL_DIFF_LINES -gt $MAX_DIFF_LINES ]]; then
  echo "" >> "$OUTPUT_FILE"
  echo "... (diff truncated, $TOTAL_DIFF_LINES total lines)" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF
\`\`\`

## Files Changed

\`\`\`
$(git diff --stat "$BASE_BRANCH"...HEAD 2>/dev/null || echo "No changes")
\`\`\`

EOF

# Add test results if available
LATEST_TESTS=$(ls -t "$LOG_DIR/opencode/tests_"*.txt 2>/dev/null | head -1)
if [[ -n "$LATEST_TESTS" && -f "$LATEST_TESTS" ]]; then
  cat >> "$OUTPUT_FILE" << EOF

## Latest Test Results

\`\`\`
$(head -100 "$LATEST_TESTS")
\`\`\`

EOF
fi

# Add instructions
cat >> "$OUTPUT_FILE" << EOF

## Your Instructions

1. **Analyze** the current state of the code and understand what OpenCode was trying to do
2. **Identify** why the blocking issues haven't been resolved
3. **Fix** the issues - focus on the blocking/critical issues first
4. **Test** your changes if tests are available
5. **Ensure** your changes are complete and the task is fully implemented

**Important**: You have access to the full codebase in the working directory. Make whatever changes are necessary to complete the task and resolve all blocking issues.

**Working Directory**: $WORKTREE_PATH

Begin by examining the current state of the code and the blocking issues, then make the necessary fixes.
EOF

echo "Context built: $OUTPUT_FILE"
echo "Total lines: $(wc -l < "$OUTPUT_FILE")"
