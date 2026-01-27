#!/bin/bash
# Codex Approval Parser for Clawdbot Orchestrator
# Parses Codex review JSON to determine approval status
set -euo pipefail

usage() {
  cat << EOF
Codex Approval Parser for Clawdbot

Usage: $(basename "$0") <review_json_file>

Arguments:
  review_json_file    Path to Codex review JSON output

Output:
  approved    - Review passed, no blocking issues
  rejected    - Review failed, has blocking issues

Exit codes:
  0 - Approved
  1 - Rejected or error

Examples:
  $(basename "$0") /path/to/review.json
  if [ "\$($(basename "$0") review.json)" == "approved" ]; then echo "Good!"; fi
EOF
}

JSON_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$JSON_FILE" ]]; then
        JSON_FILE="$1"
      else
        echo "Unknown argument: $1" >&2; usage >&2; exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$JSON_FILE" ]] && { echo "ERROR: review_json_file is required" >&2; usage >&2; exit 1; }
[[ ! -f "$JSON_FILE" ]] && { echo "ERROR: file not found: $JSON_FILE" >&2; exit 1; }

# Check if valid JSON
if ! jq empty "$JSON_FILE" 2>/dev/null; then
  echo "ERROR: invalid JSON in $JSON_FILE" >&2
  echo "rejected"
  exit 1
fi

# Check for explicit approval field
if jq -e '.approved == true' "$JSON_FILE" >/dev/null 2>&1; then
  echo "approved"
  exit 0
fi

# Check for explicit rejection
if jq -e '.approved == false' "$JSON_FILE" >/dev/null 2>&1; then
  echo "rejected"
  exit 1
fi

# Check for critical issues
CRITICAL=$(jq '[.issues[]? | select(.severity == "critical" or .severity == "error")] | length' "$JSON_FILE" 2>/dev/null || echo "0")

# Check for blocking issues
BLOCKING=$(jq '[.issues[]? | select(.blocking == true)] | length' "$JSON_FILE" 2>/dev/null || echo "0")

# Check for error in output
if jq -e '.error' "$JSON_FILE" >/dev/null 2>&1; then
  echo "rejected"
  exit 1
fi

# Decision logic
if [[ "$CRITICAL" == "0" && "$BLOCKING" == "0" ]]; then
  # No critical or blocking issues - approved
  echo "approved"
  exit 0
else
  # Has critical or blocking issues - rejected
  echo "rejected"
  exit 1
fi
