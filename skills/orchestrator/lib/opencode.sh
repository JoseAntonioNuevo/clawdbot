#!/bin/bash
# OpenCode Adapter for Clawdbot Orchestrator
# Runs OpenCode (GLM 4.7) for code implementation
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
OpenCode Adapter for Clawdbot

Usage: $(basename "$0") <prompt> <output_file> [options]

Arguments:
  prompt        The task prompt for OpenCode
  output_file   Where to save the JSON output

Options:
  -m, --model MODEL       Model to use (default: zai/glm-4.7)
  -w, --workdir PATH      Working directory (default: current)
  --tools TOOLS           Comma-separated allowed tools
  --timeout SECONDS       Timeout in seconds (default: 600)
  -q, --quiet             Suppress progress output

Examples:
  $(basename "$0") "Fix the login bug" output.json -w /path/to/repo
  $(basename "$0") "Add user auth" output.json --tools "Bash,Read,Write,Edit"
EOF
}

# Default values
MODEL="${OPENCODE_MODEL:-zai/glm-4.7}"
WORKDIR="$(pwd)"
TOOLS="Bash,Read,Write,Edit,Glob,Grep"
TIMEOUT=600
QUIET=false
PROMPT=""
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -m|--model) MODEL="$2"; shift 2 ;;
    -w|--workdir) WORKDIR="$2"; shift 2 ;;
    --tools) TOOLS="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$PROMPT" ]]; then
        PROMPT="$1"
      elif [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="$1"
      else
        echo "Unknown argument: $1"; usage; exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$PROMPT" ]] && { echo "ERROR: prompt is required"; usage; exit 1; }
[[ -z "$OUTPUT_FILE" ]] && { echo "ERROR: output_file is required"; usage; exit 1; }

# Check if OpenCode is installed
if ! command -v opencode &>/dev/null; then
  echo "ERROR: opencode is not installed"
  echo "Install with: npm install -g opencode-ai"
  exit 1
fi

# Check API key
if [[ -z "${ZAI_API_KEY:-}" ]]; then
  echo "ERROR: ZAI_API_KEY is not set"
  exit 1
fi

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Build the command
CMD=(opencode run)
CMD+=(-m "$MODEL")
CMD+=(--allowedTools "$TOOLS")
CMD+=(-q)
CMD+=(-f json)

# Change to working directory
cd "$WORKDIR"

[[ "$QUIET" == "false" ]] && echo "Running OpenCode ($MODEL) in $WORKDIR..."

# Create temp file for prompt (to handle multiline properly)
PROMPT_FILE=$(mktemp)
echo "$PROMPT" > "$PROMPT_FILE"

# Run OpenCode with timeout
RESULT=0
timeout "$TIMEOUT" "${CMD[@]}" "$(cat "$PROMPT_FILE")" > "$OUTPUT_FILE" 2>&1 || RESULT=$?

rm -f "$PROMPT_FILE"

# Check result
if [[ $RESULT -eq 124 ]]; then
  echo "ERROR: OpenCode timed out after ${TIMEOUT}s"
  echo '{"error": "timeout", "message": "OpenCode timed out"}' > "$OUTPUT_FILE"
  exit 1
elif [[ $RESULT -ne 0 ]]; then
  echo "WARNING: OpenCode exited with code $RESULT"
  # Don't exit - output might still be useful
fi

[[ "$QUIET" == "false" ]] && echo "Output saved to: $OUTPUT_FILE"

# Return OpenCode's exit code
exit $RESULT
