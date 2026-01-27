#!/bin/bash
# Claude Code Adapter for Clawdbot Orchestrator
# Runs Claude Code (Opus 4.5) as fallback implementer
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Claude Code Adapter for Clawdbot

Usage: $(basename "$0") <prompt> <output_file> [options]

Arguments:
  prompt        The task prompt for Claude Code
  output_file   Where to save the JSON output

Options:
  -w, --workdir PATH      Working directory (default: current)
  --tools TOOLS           Comma-separated allowed tools
  --timeout SECONDS       Timeout in seconds (default: 900)
  -q, --quiet             Suppress progress output

Examples:
  $(basename "$0") "Fix the complex issue" output.json -w /path/to/repo
  $(basename "$0") "Refactor module" output.json --tools "Bash,Read,Write,Edit"
EOF
}

# Default values
WORKDIR="$(pwd)"
TOOLS="Bash,Read,Write,Edit,Glob,Grep"
TIMEOUT=900
QUIET=false
PROMPT=""
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
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

# Check if Claude is installed
if ! command -v claude &>/dev/null; then
  echo "ERROR: claude is not installed"
  echo "Install with: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

# Note: Claude Code uses its own built-in authentication

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Change to working directory
cd "$WORKDIR"

[[ "$QUIET" == "false" ]] && echo "Running Claude Code (Opus 4.5) in $WORKDIR..."

# Create temp file for prompt (to handle multiline properly)
PROMPT_FILE=$(mktemp)
echo "$PROMPT" > "$PROMPT_FILE"

# Build command
CMD=(claude)
CMD+=(-p "$(cat "$PROMPT_FILE")")
CMD+=(--output-format stream-json)
CMD+=(--allowedTools "$TOOLS")

# Run Claude Code with timeout
RESULT=0
timeout "$TIMEOUT" "${CMD[@]}" > "$OUTPUT_FILE" 2>&1 || RESULT=$?

rm -f "$PROMPT_FILE"

# Check result
if [[ $RESULT -eq 124 ]]; then
  echo "ERROR: Claude Code timed out after ${TIMEOUT}s"
  echo '{"error": "timeout", "message": "Claude Code timed out"}' > "$OUTPUT_FILE"
  exit 1
elif [[ $RESULT -ne 0 ]]; then
  echo "WARNING: Claude Code exited with code $RESULT"
fi

[[ "$QUIET" == "false" ]] && echo "Output saved to: $OUTPUT_FILE"

exit $RESULT
