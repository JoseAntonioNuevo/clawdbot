#!/bin/bash
# Codex CLI Adapter for Clawdbot Orchestrator
# Runs Codex (GPT-5.2-Codex) for code review
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Codex Review Adapter for Clawdbot

Usage: $(basename "$0") <workdir> <base_branch> <output_file> [options]

Arguments:
  workdir       Working directory to review
  base_branch   Base branch to compare against
  output_file   Where to save the JSON output

Options:
  -m, --model MODEL       Model to use (default: gpt-5.2-codex)
  --timeout SECONDS       Timeout in seconds (default: 300)
  -q, --quiet             Suppress progress output

Examples:
  $(basename "$0") /path/to/worktree main review.json
  $(basename "$0") . develop output.json --model gpt-5.2-codex
EOF
}

# Default values
MODEL="${CODEX_MODEL:-gpt-5.2-codex}"
TIMEOUT=300
QUIET=false
WORKDIR=""
BASE_BRANCH=""
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -m|--model) MODEL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$WORKDIR" ]]; then
        WORKDIR="$1"
      elif [[ -z "$BASE_BRANCH" ]]; then
        BASE_BRANCH="$1"
      elif [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="$1"
      else
        echo "Unknown argument: $1"; usage; exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$WORKDIR" ]] && { echo "ERROR: workdir is required"; usage; exit 1; }
[[ -z "$BASE_BRANCH" ]] && { echo "ERROR: base_branch is required"; usage; exit 1; }
[[ -z "$OUTPUT_FILE" ]] && { echo "ERROR: output_file is required"; usage; exit 1; }

# Check if Codex is installed
if ! command -v codex &>/dev/null; then
  echo "ERROR: codex is not installed"
  echo "Install with: npm install -g @openai/codex-cli"
  exit 1
fi

# Note: Codex CLI uses its own built-in authentication (codex auth login)

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Change to working directory
cd "$WORKDIR"

[[ "$QUIET" == "false" ]] && echo "Running Codex review ($MODEL) against $BASE_BRANCH..."

# Build the review command
REVIEW_CMD="/review base-branch $BASE_BRANCH"

# Run Codex with timeout
RESULT=0
timeout "$TIMEOUT" codex exec \
  --model "$MODEL" \
  --json \
  "$REVIEW_CMD" \
  > "$OUTPUT_FILE" 2>&1 || RESULT=$?

# Check result
if [[ $RESULT -eq 124 ]]; then
  echo "ERROR: Codex review timed out after ${TIMEOUT}s"
  cat > "$OUTPUT_FILE" << 'EOF'
{
  "error": "timeout",
  "message": "Codex review timed out",
  "approved": false,
  "issues": [
    {
      "severity": "error",
      "message": "Review timed out - unable to complete analysis",
      "blocking": true
    }
  ]
}
EOF
  exit 1
elif [[ $RESULT -ne 0 ]]; then
  echo "WARNING: Codex exited with code $RESULT"
fi

# Validate JSON output
if ! jq empty "$OUTPUT_FILE" 2>/dev/null; then
  echo "WARNING: Invalid JSON output from Codex, wrapping..."
  CONTENT=$(cat "$OUTPUT_FILE")
  cat > "$OUTPUT_FILE" << EOF
{
  "raw_output": $(echo "$CONTENT" | jq -Rs .),
  "approved": false,
  "issues": [
    {
      "severity": "warning",
      "message": "Could not parse Codex output",
      "blocking": false
    }
  ]
}
EOF
fi

[[ "$QUIET" == "false" ]] && echo "Review saved to: $OUTPUT_FILE"

exit 0
