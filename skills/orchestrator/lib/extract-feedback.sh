#!/bin/bash
# Extract Feedback from Codex Review for Clawdbot Orchestrator
# Formats blocking issues as actionable feedback for the next iteration
set -euo pipefail

usage() {
  cat << EOF
Codex Feedback Extractor for Clawdbot

Usage: $(basename "$0") <review_json_file>

Arguments:
  review_json_file    Path to Codex review JSON output

Output:
  Markdown-formatted list of blocking issues to address

Examples:
  $(basename "$0") /path/to/review.json > feedback.md
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
  echo "Unable to parse review output. Please review the changes manually."
  exit 0
fi

# Check for error
if jq -e '.error' "$JSON_FILE" >/dev/null 2>&1; then
  ERROR_MSG=$(jq -r '.error // .message // "Unknown error"' "$JSON_FILE")
  echo "Review encountered an error: $ERROR_MSG"
  exit 0
fi

# Extract blocking/critical issues
BLOCKING_ISSUES=$(jq -r '
  [.issues[]? | select(.blocking == true or .severity == "critical" or .severity == "error")]
  | if length == 0 then empty else
    .[] | "- **[\(.severity // "issue")]** \(.message // .description // "No description")\n" +
    (if .file then "  - File: `\(.file)`" + (if .line then ":\(.line)" else "" end) + "\n" else "" end) +
    (if .suggestion then "  - Suggestion: \(.suggestion)\n" else "" end) +
    (if .code then "  - Code: `\(.code)`\n" else "" end)
  end
' "$JSON_FILE" 2>/dev/null)

# Extract warnings (non-blocking but important)
WARNINGS=$(jq -r '
  [.issues[]? | select(.severity == "warning" and .blocking != true)]
  | if length == 0 then empty else
    .[] | "- **[warning]** \(.message // .description // "No description")\n" +
    (if .file then "  - File: `\(.file)`" + (if .line then ":\(.line)" else "" end) + "\n" else "" end)
  end
' "$JSON_FILE" 2>/dev/null | head -20)

# Extract general summary if available
SUMMARY=$(jq -r '.summary // .message // empty' "$JSON_FILE" 2>/dev/null)

# Output formatted feedback
if [[ -n "$BLOCKING_ISSUES" ]]; then
  echo "## Blocking Issues (Must Fix)"
  echo ""
  echo "$BLOCKING_ISSUES"
  echo ""
fi

if [[ -n "$WARNINGS" ]]; then
  echo "## Warnings (Should Address)"
  echo ""
  echo "$WARNINGS"
  echo ""
fi

if [[ -n "$SUMMARY" && "$SUMMARY" != "null" ]]; then
  echo "## Summary"
  echo ""
  echo "$SUMMARY"
fi

# If no issues extracted, check for raw feedback
if [[ -z "$BLOCKING_ISSUES" && -z "$WARNINGS" ]]; then
  RAW=$(jq -r '.raw_output // .feedback // .comments // empty' "$JSON_FILE" 2>/dev/null)
  if [[ -n "$RAW" && "$RAW" != "null" ]]; then
    echo "## Review Feedback"
    echo ""
    echo "$RAW"
  else
    echo "No specific issues identified. Review may need manual inspection."
  fi
fi
