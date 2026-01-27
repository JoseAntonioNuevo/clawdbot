#!/bin/bash
# Build Context for Codex CLI (Reviewer)
# Assembles full context for Codex to review the implementation
set -euo pipefail

usage() {
  cat << EOF
Build Context for Codex CLI (Reviewer)

Usage: $(basename "$0") [options]

Required:
  --task FILE           Path to original task description
  --plan FILE           Path to Claude's plan
  --implementation FILE Path to implementation summary
  --worktree PATH       Path to worktree
  --base BRANCH         Base branch for diff
  --output FILE         Where to write the context

Optional:
  --tests FILE          Path to test results
  -h, --help            Show this help

Examples:
  $(basename "$0") --task task.md --plan plan.md --implementation impl.md --worktree /path --base main --output context.md
EOF
}

TASK_FILE=""
PLAN_FILE=""
IMPLEMENTATION_FILE=""
WORKTREE=""
BASE_BRANCH=""
OUTPUT=""
TESTS_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --task) TASK_FILE="$2"; shift 2 ;;
    --plan) PLAN_FILE="$2"; shift 2 ;;
    --implementation) IMPLEMENTATION_FILE="$2"; shift 2 ;;
    --worktree) WORKTREE="$2"; shift 2 ;;
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --tests) TESTS_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$TASK_FILE" ]] && { echo "ERROR: --task required" >&2; exit 1; }
[[ -z "$PLAN_FILE" ]] && { echo "ERROR: --plan required" >&2; exit 1; }
[[ -z "$WORKTREE" ]] && { echo "ERROR: --worktree required" >&2; exit 1; }
[[ -z "$BASE_BRANCH" ]] && { echo "ERROR: --base required" >&2; exit 1; }
[[ -z "$OUTPUT" ]] && { echo "ERROR: --output required" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"

{
  echo "# Code Review Request"
  echo ""
  echo "You are **Codex (GPT-5.2-Codex)**, the code reviewer."
  echo ""
  echo "Your job is to:"
  echo "1. Review the implementation against the plan and task"
  echo "2. Identify any bugs, issues, or missing functionality"
  echo "3. Approve if the code is correct and complete"
  echo "4. Reject with specific feedback if there are issues"
  echo ""
  echo "---"
  echo ""

  # Original task
  echo "## Original Task"
  echo ""
  echo "> What the user requested"
  echo ""
  if [[ -f "$TASK_FILE" ]]; then
    cat "$TASK_FILE"
  else
    echo "(Not available)"
  fi
  echo ""
  echo "---"
  echo ""

  # The plan that was supposed to be implemented
  echo "## Implementation Plan"
  echo ""
  echo "> The plan created by Claude Code that Kimi was supposed to follow"
  echo ""
  if [[ -f "$PLAN_FILE" ]]; then
    cat "$PLAN_FILE"
  else
    echo "(Not available)"
  fi
  echo ""
  echo "---"
  echo ""

  # What was implemented
  echo "## What Was Implemented"
  echo ""
  if [[ -f "$IMPLEMENTATION_FILE" ]]; then
    cat "$IMPLEMENTATION_FILE"
  else
    echo "(Implementation summary not available)"
  fi
  echo ""
  echo "---"
  echo ""

  # Code changes
  echo "## Code Changes"
  echo ""
  if [[ -d "$WORKTREE" ]]; then
    cd "$WORKTREE"

    echo "### Files Changed"
    echo "\`\`\`"
    git diff --stat "$BASE_BRANCH"...HEAD 2>/dev/null || echo "(No changes)"
    echo "\`\`\`"
    echo ""

    echo "### Full Diff"
    echo "\`\`\`diff"
    git diff "$BASE_BRANCH"...HEAD 2>/dev/null || echo "(No diff)"
    echo "\`\`\`"
  else
    echo "(Worktree not available)"
  fi
  echo ""
  echo "---"
  echo ""

  # Test results
  echo "## Test Results"
  echo ""
  if [[ -n "$TESTS_FILE" && -f "$TESTS_FILE" ]]; then
    echo "\`\`\`"
    cat "$TESTS_FILE"
    echo "\`\`\`"
  else
    echo "(No test results available)"
  fi
  echo ""
  echo "---"
  echo ""

  # Review criteria
  echo "## Review Criteria"
  echo ""
  echo "Check the following:"
  echo ""
  echo "1. **Task Completion**: Does the implementation fulfill the original task?"
  echo "2. **Plan Adherence**: Were all steps in the plan implemented?"
  echo "3. **Code Correctness**: Is the code bug-free and logically correct?"
  echo "4. **Test Results**: Do all tests pass?"
  echo "5. **Error Handling**: Are errors handled appropriately?"
  echo "6. **Edge Cases**: Are edge cases considered?"
  echo "7. **Code Quality**: Is the code clean, readable, and maintainable?"
  echo "8. **Security**: Are there any security vulnerabilities?"
  echo ""
  echo "---"
  echo ""

  # Expected response format
  echo "## Your Response Format"
  echo ""
  echo "Provide your review as JSON:"
  echo ""
  echo "\`\`\`json"
  echo "{"
  echo "  \"approved\": true|false,"
  echo "  \"summary\": \"Brief overall assessment\","
  echo "  \"issues\": ["
  echo "    {"
  echo "      \"severity\": \"critical|major|minor\","
  echo "      \"blocking\": true|false,"
  echo "      \"file\": \"path/to/file.ts\","
  echo "      \"line\": 42,"
  echo "      \"message\": \"Description of the issue\","
  echo "      \"suggestion\": \"How to fix it\""
  echo "    }"
  echo "  ],"
  echo "  \"missing\": ["
  echo "    \"List of things that are missing from the implementation\""
  echo "  ],"
  echo "  \"positives\": ["
  echo "    \"Things that were done well\""
  echo "  ]"
  echo "}"
  echo "\`\`\`"
  echo ""
  echo "**Rules:**"
  echo "- Set \`approved: true\` only if there are NO critical or blocking issues"
  echo "- Be specific about file paths and line numbers when possible"
  echo "- Provide actionable suggestions for how to fix issues"
  echo "- If tests fail, that's usually a blocking issue"

} > "$OUTPUT"

echo "Context written to: $OUTPUT"
