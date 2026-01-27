#!/bin/bash
# Claude Code Adapter for Clawdbot Orchestrator
# Runs Claude Code (Opus 4.5) as the PLANNER
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Claude Code Adapter for Clawdbot (Opus 4.5 Planner)

Usage: $(basename "$0") [options]

Options:
  --mode MODE           Mode: plan (default), review, analyze
  --context FILE        Path to context file
  --prompt TEXT         Direct prompt text
  --workdir PATH        Working directory (default: current)
  --output FILE         Where to save the output
  --tools TOOLS         Comma-separated allowed tools
  --timeout SECONDS     Timeout in seconds (default: 900)
  -q, --quiet           Suppress progress output
  -h, --help            Show this help

Modes:
  plan      Create or revise implementation plans (default)
  review    Review code changes
  analyze   Analyze codebase structure

Examples:
  $(basename "$0") --mode plan --context context.md --workdir /path/to/repo --output plan.md
  $(basename "$0") --mode analyze --workdir /path/to/repo --output analysis.md
EOF
}

# Default values
MODE="plan"
WORKDIR="$(pwd)"
TOOLS="Bash,Read,Glob,Grep"  # Limited tools for planning - no Write/Edit
TIMEOUT=900
QUIET=false
CONTEXT_FILE=""
PROMPT=""
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --mode) MODE="$2"; shift 2 ;;
    --context) CONTEXT_FILE="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    -w|--workdir) WORKDIR="$2"; shift 2 ;;
    --tools) TOOLS="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      # Legacy positional args support
      if [[ -z "$PROMPT" ]]; then
        PROMPT="$1"
      elif [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="$1"
      else
        echo "Unknown argument: $1" >&2; usage >&2; exit 1
      fi
      shift
      ;;
  esac
done

# Get prompt from context file if provided
if [[ -n "$CONTEXT_FILE" ]]; then
  if [[ -f "$CONTEXT_FILE" ]]; then
    PROMPT=$(cat "$CONTEXT_FILE")
  else
    echo "ERROR: Context file not found: $CONTEXT_FILE" >&2
    exit 1
  fi
fi

[[ -z "$PROMPT" ]] && { echo "ERROR: --context or --prompt required" >&2; usage >&2; exit 1; }
[[ -z "$OUTPUT_FILE" ]] && { echo "ERROR: --output required" >&2; usage >&2; exit 1; }

# Check if Claude is installed
if ! command -v claude &>/dev/null; then
  echo "ERROR: claude is not installed" >&2
  echo "Install with: npm install -g @anthropic-ai/claude-code" >&2
  exit 1
fi

# Note: Claude Code uses its own built-in authentication

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Helper to write structured error output
write_error_output() {
  local message="$1"
  cat > "$OUTPUT_FILE" << EOF
# Error

**Error**: $message

Unable to complete the requested operation.
EOF
}

# Validate and change to working directory
if [[ ! -d "$WORKDIR" ]]; then
  echo "ERROR: Working directory does not exist: $WORKDIR" >&2
  write_error_output "Working directory does not exist: $WORKDIR"
  exit 1
fi

if ! cd "$WORKDIR" 2>/dev/null; then
  echo "ERROR: Failed to change to working directory: $WORKDIR" >&2
  write_error_output "Failed to change to working directory: $WORKDIR"
  exit 1
fi

[[ "$QUIET" == "false" ]] && echo "Running Claude Code (Opus 4.5) - Mode: $MODE"
[[ "$QUIET" == "false" ]] && echo "Working directory: $WORKDIR"

# Build the system prompt based on mode
SYSTEM_PROMPT=""
case "$MODE" in
  plan)
    SYSTEM_PROMPT="You are an expert software architect and planner. Your job is to create detailed, actionable implementation plans.

IMPORTANT:
- You are the PLANNER, not the implementer
- Create step-by-step plans that another AI will execute
- Be specific about file paths, code changes, and test cases
- If this is a revision, analyze what went wrong before and fix it
- Output your plan in clear markdown format

DO NOT write code directly - create a plan for the implementer to follow."
    TOOLS="Bash,Read,Glob,Grep"  # Read-only for planning
    ;;
  review)
    SYSTEM_PROMPT="You are a code reviewer. Analyze the code changes and provide feedback on correctness, completeness, and quality."
    TOOLS="Bash,Read,Glob,Grep"
    ;;
  analyze)
    SYSTEM_PROMPT="You are a codebase analyst. Analyze the structure, patterns, and architecture of the codebase."
    TOOLS="Bash,Read,Glob,Grep"
    ;;
  *)
    echo "ERROR: Unknown mode: $MODE" >&2
    exit 1
    ;;
esac

# Create temp file for the full prompt
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << EOF
$SYSTEM_PROMPT

---

$PROMPT
EOF

PROMPT_SIZE=$(wc -c < "$PROMPT_FILE")
[[ "$QUIET" == "false" ]] && echo "Prompt size: $PROMPT_SIZE bytes"

# Run Claude Code with timeout, capturing markdown output
# Use stdin or prompt-file to avoid ARG_MAX limits
RESULT=0
TEMP_OUTPUT=$(mktemp)
RUN_SUCCESS=false

# Try stdin first (preferred for large prompts)
if timeout "$TIMEOUT" claude --allowedTools "$TOOLS" - < "$PROMPT_FILE" > "$TEMP_OUTPUT" 2>&1; then
  RUN_SUCCESS=true
# Try --prompt-file if available
elif timeout "$TIMEOUT" claude --allowedTools "$TOOLS" --prompt-file "$PROMPT_FILE" > "$TEMP_OUTPUT" 2>&1; then
  RUN_SUCCESS=true
# Last resort: direct argument (check size first to avoid ARG_MAX)
elif [[ $PROMPT_SIZE -lt 100000 ]]; then
  if timeout "$TIMEOUT" claude -p "$(cat "$PROMPT_FILE")" --allowedTools "$TOOLS" > "$TEMP_OUTPUT" 2>&1; then
    RUN_SUCCESS=true
  else
    RESULT=$?
  fi
else
  echo "ERROR: Prompt too large ($PROMPT_SIZE bytes) and claude doesn't support stdin/file input" >&2
  write_error_output "Prompt too large ($PROMPT_SIZE bytes) for Claude CLI"
  rm -f "$PROMPT_FILE" "$TEMP_OUTPUT"
  exit 1
fi

if [[ "$RUN_SUCCESS" != "true" && $RESULT -eq 0 ]]; then
  RESULT=1
fi

rm -f "$PROMPT_FILE"

# Check result
if [[ $RESULT -eq 124 ]]; then
  echo "ERROR: Claude Code timed out after ${TIMEOUT}s" >&2
  cat > "$OUTPUT_FILE" << EOF
# Error: Timeout

Claude Code (Opus 4.5) timed out after ${TIMEOUT}s while in $MODE mode.

Please try again or simplify the request.
EOF
  rm -f "$TEMP_OUTPUT"
  exit 1
elif [[ $RESULT -ne 0 ]]; then
  echo "WARNING: Claude Code exited with code $RESULT" >&2
fi

# Process output - extract the plan/content
# Claude's output should be the plan itself
if [[ -f "$TEMP_OUTPUT" ]]; then
  # Copy the output, removing any stream-json formatting if present
  cat "$TEMP_OUTPUT" > "$OUTPUT_FILE"
fi

rm -f "$TEMP_OUTPUT"

[[ "$QUIET" == "false" ]] && echo "Output saved to: $OUTPUT_FILE"

exit $RESULT
