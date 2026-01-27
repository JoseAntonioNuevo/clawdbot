#!/bin/bash
# OpenCode Adapter for Clawdbot Orchestrator
# Runs OpenCode with Kimi K2.5 for code implementation
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
OpenCode Adapter for Clawdbot (Kimi K2.5 Implementer)

Usage: $(basename "$0") [options]

Options:
  --context FILE        Path to context file (replaces prompt)
  --prompt TEXT         Direct prompt text
  --workdir PATH        Working directory (default: current)
  --output FILE         Where to save the output
  -m, --model MODEL     Model to use (default: moonshot/kimi-k2.5-preview)
  --tools TOOLS         Comma-separated allowed tools
  --timeout SECONDS     Timeout in seconds (default: 900)
  -q, --quiet           Suppress progress output
  -h, --help            Show this help

Environment:
  MOONSHOT_API_KEY      API key for Moonshot/Kimi (required)
  OPENCODE_MODEL        Override default model

Examples:
  $(basename "$0") --context context.md --workdir /path/to/repo --output output.json
  $(basename "$0") --prompt "Fix the login bug" --output output.json
EOF
}

# Default values - Kimi K2.5 as implementer
MODEL="${OPENCODE_MODEL:-moonshot/kimi-k2.5-preview}"
WORKDIR="$(pwd)"
TOOLS="Bash,Read,Write,Edit,Glob,Grep"
TIMEOUT=900
QUIET=false
CONTEXT_FILE=""
PROMPT=""
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --context) CONTEXT_FILE="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    -m|--model) MODEL="$2"; shift 2 ;;
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

# Check if OpenCode is installed
if ! command -v opencode &>/dev/null; then
  echo "ERROR: opencode is not installed" >&2
  echo "Install with: npm install -g opencode-ai" >&2
  exit 1
fi

# Note: OpenCode uses its own authentication (opencode auth login)
# MOONSHOT_API_KEY may be used for direct API calls but opencode handles auth

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Helper to write structured error output
write_error_output() {
  local message="$1"
  cat > "$OUTPUT_FILE" << EOF
{
  "error": "validation_error",
  "message": "$message",
  "model": "$MODEL"
}
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

[[ "$QUIET" == "false" ]] && echo "Running OpenCode (Kimi K2.5) in $WORKDIR..."
[[ "$QUIET" == "false" ]] && echo "Model: $MODEL"

# Create temp file for prompt (to handle multiline properly and avoid ARG_MAX)
PROMPT_FILE=$(mktemp)
echo "$PROMPT" > "$PROMPT_FILE"

PROMPT_SIZE=$(wc -c < "$PROMPT_FILE")
[[ "$QUIET" == "false" ]] && echo "Prompt size: $PROMPT_SIZE bytes"

# Run OpenCode with timeout, handling ARG_MAX limits
# Try stdin first, then --prompt-file, then direct argument as last resort
RESULT=0
RUN_SUCCESS=false

# Try stdin first (preferred for large prompts)
if timeout "$TIMEOUT" opencode run -m "$MODEL" --allowedTools "$TOOLS" -q -f json - < "$PROMPT_FILE" > "$OUTPUT_FILE" 2>&1; then
  RUN_SUCCESS=true
# Try --prompt-file if available
elif timeout "$TIMEOUT" opencode run -m "$MODEL" --allowedTools "$TOOLS" -q -f json --prompt-file "$PROMPT_FILE" > "$OUTPUT_FILE" 2>&1; then
  RUN_SUCCESS=true
# Last resort: direct argument (check size first to avoid ARG_MAX)
elif [[ $PROMPT_SIZE -lt 100000 ]]; then
  if timeout "$TIMEOUT" opencode run -m "$MODEL" --allowedTools "$TOOLS" -q -f json "$(cat "$PROMPT_FILE")" > "$OUTPUT_FILE" 2>&1; then
    RUN_SUCCESS=true
  else
    RESULT=$?
  fi
else
  echo "ERROR: Prompt too large ($PROMPT_SIZE bytes) and opencode doesn't support stdin/file input" >&2
  write_error_output "Prompt too large ($PROMPT_SIZE bytes) for OpenCode CLI"
  rm -f "$PROMPT_FILE"
  exit 1
fi

if [[ "$RUN_SUCCESS" != "true" && $RESULT -eq 0 ]]; then
  RESULT=1
fi

rm -f "$PROMPT_FILE"

# Check result
if [[ $RESULT -eq 124 ]]; then
  echo "ERROR: OpenCode timed out after ${TIMEOUT}s" >&2
  cat > "$OUTPUT_FILE" << EOF
{
  "error": "timeout",
  "message": "OpenCode (Kimi K2.5) timed out after ${TIMEOUT}s",
  "model": "$MODEL"
}
EOF
  exit 1
elif [[ $RESULT -ne 0 ]]; then
  echo "WARNING: OpenCode exited with code $RESULT" >&2
  # Don't exit - output might still be useful
fi

[[ "$QUIET" == "false" ]] && echo "Output saved to: $OUTPUT_FILE"

exit $RESULT
