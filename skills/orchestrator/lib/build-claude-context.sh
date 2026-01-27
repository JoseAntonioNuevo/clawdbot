#!/bin/bash
# Build Context for Claude Code (Planner)
# Assembles full context for Claude to create or revise implementation plans
set -euo pipefail

usage() {
  cat << EOF
Build Context for Claude Code (Planner)

Usage: $(basename "$0") [options]

Required:
  --task FILE           Path to original task description
  --codebase FILE       Path to codebase summary
  --worktree PATH       Path to worktree
  --iteration N         Current iteration number
  --output FILE         Where to write the context

Optional:
  --history DIR         Path to iterations directory (for iterations > 1)
  --base-branch BRANCH  Base branch for diff (default: main)
  -h, --help            Show this help

Examples:
  $(basename "$0") --task task.md --codebase summary.md --worktree /path --iteration 1 --output context.md
EOF
}

TASK_FILE=""
CODEBASE_FILE=""
WORKTREE=""
ITERATION=1
OUTPUT=""
HISTORY_DIR=""
BASE_BRANCH="main"

while [[ $# -gt 0 ]]; do
  case $1 in
    --task) TASK_FILE="$2"; shift 2 ;;
    --codebase) CODEBASE_FILE="$2"; shift 2 ;;
    --worktree) WORKTREE="$2"; shift 2 ;;
    --iteration) ITERATION="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --history) HISTORY_DIR="$2"; shift 2 ;;
    --base-branch) BASE_BRANCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$TASK_FILE" ]] && { echo "ERROR: --task required" >&2; exit 1; }
[[ -z "$CODEBASE_FILE" ]] && { echo "ERROR: --codebase required" >&2; exit 1; }
[[ -z "$WORKTREE" ]] && { echo "ERROR: --worktree required" >&2; exit 1; }
[[ -z "$OUTPUT" ]] && { echo "ERROR: --output required" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"

# Start building context
{
  echo "# Context for Claude Code - Iteration $ITERATION"
  echo ""
  echo "---"
  echo ""

  # Role description
  echo "## Your Role"
  echo ""
  if [[ $ITERATION -eq 1 ]]; then
    echo "You are the **PLANNER**. Your job is to:"
    echo "1. Analyze the codebase and understand its structure"
    echo "2. Understand the task requirements completely"
    echo "3. Create a detailed, step-by-step implementation plan"
    echo "4. The plan will be executed by another AI (Kimi K2.5)"
    echo ""
    echo "Be specific and detailed. The implementer will follow your plan exactly."
  else
    echo "You are the **PLANNER** revising a failed implementation."
    echo ""
    echo "Previous attempts did not pass code review. You must:"
    echo "1. Analyze what went wrong in previous attempts"
    echo "2. Understand the Codex feedback and why it rejected the code"
    echo "3. Create a REVISED plan that addresses all issues"
    echo "4. Learn from mistakes - don't repeat the same approach if it failed"
    echo ""
    echo "The implementer (Kimi K2.5) will follow your new plan."
  fi
  echo ""
  echo "---"
  echo ""

  # Original task
  echo "## Original Task"
  echo ""
  if [[ -f "$TASK_FILE" ]]; then
    cat "$TASK_FILE"
  else
    echo "(Task file not found: $TASK_FILE)"
  fi
  echo ""
  echo "---"
  echo ""

  # Codebase overview
  echo "## Codebase Overview"
  echo ""
  if [[ -f "$CODEBASE_FILE" ]]; then
    cat "$CODEBASE_FILE"
  else
    echo "(Codebase summary not found: $CODEBASE_FILE)"
  fi
  echo ""
  echo "---"
  echo ""

  # Current state of code
  echo "## Current State of the Code"
  echo ""
  if [[ -d "$WORKTREE" ]]; then
    cd "$WORKTREE"

    # Show modified files
    echo "### Modified Files"
    echo "\`\`\`"
    git diff --stat "$BASE_BRANCH"...HEAD 2>/dev/null || echo "(No changes yet)"
    echo "\`\`\`"
    echo ""

    # Show the actual diff (FULL - no truncation for complete context)
    echo "### Code Changes (Diff)"
    echo "\`\`\`diff"
    git diff "$BASE_BRANCH"...HEAD 2>/dev/null || echo "(No diff available)"
    echo "\`\`\`"
  else
    echo "(Worktree not found: $WORKTREE)"
  fi
  echo ""
  echo "---"
  echo ""

  # Previous iterations (if any)
  if [[ $ITERATION -gt 1 && -n "$HISTORY_DIR" && -d "$HISTORY_DIR" ]]; then
    echo "## Previous Iterations"
    echo ""
    echo "**IMPORTANT**: Study these carefully to understand what failed and why."
    echo ""

    for i in $(seq 1 $((ITERATION - 1))); do
      ITER_DIR="$HISTORY_DIR/iter_$(printf '%03d' $i)"

      if [[ -d "$ITER_DIR" ]]; then
        echo "### Iteration $i"
        echo ""

        # Plan from that iteration
        if [[ -f "$ITER_DIR/claude_plan.md" ]]; then
          echo "#### Plan Created"
          echo ""
          cat "$ITER_DIR/claude_plan.md"
          echo ""
        fi

        # What Kimi implemented
        if [[ -f "$ITER_DIR/kimi_implementation.md" ]]; then
          echo "#### What Was Implemented"
          echo ""
          cat "$ITER_DIR/kimi_implementation.md"
          echo ""
        fi

        # Test results
        if [[ -f "$ITER_DIR/test_results.txt" ]]; then
          echo "#### Test Results"
          echo "\`\`\`"
          cat "$ITER_DIR/test_results.txt" | head -50
          echo "\`\`\`"
          echo ""
        fi

        # Codex feedback (why it was rejected)
        if [[ -f "$ITER_DIR/codex_feedback.md" ]]; then
          echo "#### Why Codex Rejected It"
          echo ""
          echo "> **This is critical feedback - your new plan must address these issues**"
          echo ""
          cat "$ITER_DIR/codex_feedback.md"
          echo ""
        fi

        echo "---"
        echo ""
      fi
    done
  fi

  # Instructions for output
  echo "## What You Need To Do Now"
  echo ""
  if [[ $ITERATION -eq 1 ]]; then
    echo "Create a detailed implementation plan that includes:"
  else
    echo "Create a **REVISED** implementation plan that:"
    echo "1. Addresses ALL the issues from previous Codex reviews"
    echo "2. Takes a different approach if the previous one fundamentally failed"
    echo "3. Is more specific about edge cases and error handling"
    echo ""
    echo "The plan should include:"
  fi
  echo ""
  echo "1. **Step-by-step instructions** - Clear, numbered steps"
  echo "2. **Files to modify/create** - Exact file paths"
  echo "3. **Code snippets** - Key code that must be written"
  echo "4. **Test cases** - How to verify it works"
  echo "5. **Edge cases** - What could go wrong and how to handle it"
  echo "6. **Dependencies** - Any new packages or changes needed"
  echo ""
  echo "## Output Format"
  echo ""
  echo "Provide your plan in this structure:"
  echo ""
  echo "\`\`\`markdown"
  echo "# Implementation Plan"
  echo ""
  echo "## Summary"
  echo "<1-2 sentence overview>"
  echo ""
  echo "## Steps"
  echo ""
  echo "### Step 1: <title>"
  echo "<detailed instructions>"
  echo ""
  echo "### Step 2: <title>"
  echo "<detailed instructions>"
  echo ""
  echo "## Files to Modify"
  echo "- \`path/to/file.ts\` - <what changes>"
  echo ""
  echo "## Key Code"
  echo "\\\`\\\`\\\`typescript"
  echo "// Critical code snippets"
  echo "\\\`\\\`\\\`"
  echo ""
  echo "## Testing"
  echo "- <how to test>"
  echo ""
  echo "## Potential Issues"
  echo "- <edge cases and how to handle>"
  echo "\`\`\`"

} > "$OUTPUT"

echo "Context written to: $OUTPUT"
