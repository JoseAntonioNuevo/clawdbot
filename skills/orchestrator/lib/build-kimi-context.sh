#!/bin/bash
# Build Context for OpenCode/Kimi K2.5 (Implementer)
# Assembles full context for Kimi to implement the plan
set -euo pipefail

usage() {
  cat << EOF
Build Context for OpenCode/Kimi K2.5 (Implementer)

Usage: $(basename "$0") [options]

Required:
  --plan FILE           Path to Claude's plan
  --task FILE           Path to original task description
  --codebase FILE       Path to codebase summary
  --iteration N         Current iteration number
  --output FILE         Where to write the context

Optional:
  --history DIR         Path to iterations directory (for iterations > 1)
  -h, --help            Show this help

Examples:
  $(basename "$0") --plan plan.md --task task.md --codebase summary.md --iteration 1 --output context.md
EOF
}

PLAN_FILE=""
TASK_FILE=""
CODEBASE_FILE=""
ITERATION=1
OUTPUT=""
HISTORY_DIR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --plan) PLAN_FILE="$2"; shift 2 ;;
    --task) TASK_FILE="$2"; shift 2 ;;
    --codebase) CODEBASE_FILE="$2"; shift 2 ;;
    --iteration) ITERATION="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --history) HISTORY_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$PLAN_FILE" ]] && { echo "ERROR: --plan required" >&2; exit 1; }
[[ -z "$TASK_FILE" ]] && { echo "ERROR: --task required" >&2; exit 1; }
[[ -z "$OUTPUT" ]] && { echo "ERROR: --output required" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"

{
  echo "# Implementation Context for Kimi K2.5 - Iteration $ITERATION"
  echo ""
  echo "---"
  echo ""

  # Role description
  echo "## Your Role"
  echo ""
  echo "You are the **IMPLEMENTER**. Your job is to:"
  echo "1. Execute the plan created by Claude Code (Opus 4.5)"
  echo "2. Write clean, working, production-ready code"
  echo "3. Follow the plan step by step"
  echo "4. Run tests to verify your implementation"
  echo ""
  if [[ $ITERATION -gt 1 ]]; then
    echo "**IMPORTANT**: This is iteration $ITERATION. Previous attempts failed code review."
    echo "Claude has created a revised plan addressing the issues. Follow it carefully."
    echo ""
  fi
  echo "Your code will be reviewed by Codex (GPT-5.2-Codex) after you finish."
  echo ""
  echo "---"
  echo ""

  # THE PLAN (most important)
  echo "## The Plan to Implement"
  echo ""
  echo "> **Follow this plan exactly. It was created by Claude Code based on the task and codebase analysis.**"
  echo ""
  if [[ -f "$PLAN_FILE" ]]; then
    cat "$PLAN_FILE"
  else
    echo "(Plan file not found: $PLAN_FILE)"
  fi
  echo ""
  echo "---"
  echo ""

  # Original task for context
  echo "## Original Task"
  echo ""
  echo "> This is what the user originally requested."
  echo ""
  if [[ -f "$TASK_FILE" ]]; then
    cat "$TASK_FILE"
  else
    echo "(Task file not found: $TASK_FILE)"
  fi
  echo ""
  echo "---"
  echo ""

  # Codebase context
  if [[ -n "$CODEBASE_FILE" && -f "$CODEBASE_FILE" ]]; then
    echo "## Codebase Overview"
    echo ""
    cat "$CODEBASE_FILE"
    echo ""
    echo "---"
    echo ""
  fi

  # Previous attempts (if iteration > 1)
  if [[ $ITERATION -gt 1 && -n "$HISTORY_DIR" && -d "$HISTORY_DIR" ]]; then
    echo "## Previous Attempts"
    echo ""
    echo "**Learn from these failures. Do not repeat the same mistakes.**"
    echo ""

    for i in $(seq 1 $((ITERATION - 1))); do
      ITER_DIR="$HISTORY_DIR/iter_$(printf '%03d' $i)"

      if [[ -d "$ITER_DIR" ]]; then
        echo "### Iteration $i"
        echo ""

        # What you implemented before
        if [[ -f "$ITER_DIR/kimi_implementation.md" ]]; then
          echo "#### What You Implemented"
          echo ""
          cat "$ITER_DIR/kimi_implementation.md" | head -100
          echo ""
        fi

        # Why it was rejected
        if [[ -f "$ITER_DIR/codex_feedback.md" ]]; then
          echo "#### Why It Was Rejected"
          echo ""
          echo "> **Address ALL these issues in your new implementation**"
          echo ""
          cat "$ITER_DIR/codex_feedback.md"
          echo ""
        fi

        echo "---"
        echo ""
      fi
    done

    echo "### How the New Plan Addresses Issues"
    echo ""
    echo "Claude has revised the plan to address the above issues. Follow the new plan carefully."
    echo ""
    echo "---"
    echo ""
  fi

  # Instructions
  echo "## Instructions"
  echo ""
  echo "1. **Follow the plan step by step** - Don't skip or modify steps"
  echo "2. **Write complete code** - No placeholders or TODOs"
  echo "3. **Handle errors properly** - Add appropriate error handling"
  echo "4. **Run tests** - Execute the test suite after implementation"
  echo "5. **Verify it works** - Make sure the implementation actually works"
  echo ""
  if [[ $ITERATION -gt 1 ]]; then
    echo "**CRITICAL for Iteration $ITERATION:**"
    echo "- Read the previous Codex feedback carefully"
    echo "- Make sure you address EVERY issue mentioned"
    echo "- If something was unclear before, the new plan should clarify it"
    echo ""
  fi
  echo "## After Implementation"
  echo ""
  echo "Once you're done:"
  echo "1. Save all files"
  echo "2. Run any build commands if needed"
  echo "3. Run the test suite"
  echo "4. Your code will be reviewed by Codex"

} > "$OUTPUT"

echo "Context written to: $OUTPUT"
