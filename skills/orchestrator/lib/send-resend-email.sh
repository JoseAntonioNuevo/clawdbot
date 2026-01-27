#!/bin/bash
# Send Email via Resend API for Clawdbot Orchestrator
# Simple, modern email delivery using Resend (https://resend.com)
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Send Email via Resend API

Usage: $(basename "$0") --to EMAIL --subject SUBJECT --body BODY [options]

Options:
  --to EMAIL          Recipient email address (required)
  --subject SUBJECT   Email subject (required)
  --body BODY         Email body - plain text or HTML (required)
  --html              Treat body as HTML (default: auto-detect)
  --from EMAIL        Sender email (default: \$RESEND_FROM or onboarding@resend.dev)
  -q, --quiet         Suppress output
  -h, --help          Show this help

Environment Variables:
  RESEND_API_KEY      Resend API key (required) - get from https://resend.com/api-keys
  RESEND_FROM         Default sender email (optional)

Examples:
  $(basename "$0") --to user@example.com --subject "Test" --body "Hello!"
  $(basename "$0") --to user@example.com --subject "Report" --body "<h1>HTML</h1>" --html
EOF
}

TO=""
SUBJECT=""
BODY=""
IS_HTML=""
FROM="${RESEND_FROM:-onboarding@resend.dev}"
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --to) TO="$2"; shift 2 ;;
    --subject) SUBJECT="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --html) IS_HTML=true; shift ;;
    --from) FROM="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Validate required params
[[ -z "$TO" ]] && { echo "ERROR: --to is required" >&2; exit 1; }
[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required" >&2; exit 1; }
[[ -z "$BODY" ]] && { echo "ERROR: --body is required" >&2; exit 1; }

# Check API key
if [[ -z "${RESEND_API_KEY:-}" ]]; then
  echo "ERROR: RESEND_API_KEY environment variable is not set" >&2
  echo "Get your API key from: https://resend.com/api-keys" >&2
  exit 1
fi

# Auto-detect HTML if not specified
if [[ -z "$IS_HTML" ]]; then
  if [[ "$BODY" == *"<"*">"* ]]; then
    IS_HTML=true
  else
    IS_HTML=false
  fi
fi

# Build JSON payload
# Use jq to properly escape strings for JSON
if [[ "$IS_HTML" == "true" ]]; then
  PAYLOAD=$(jq -n \
    --arg from "$FROM" \
    --arg to "$TO" \
    --arg subject "$SUBJECT" \
    --arg html "$BODY" \
    '{from: $from, to: [$to], subject: $subject, html: $html}')
else
  PAYLOAD=$(jq -n \
    --arg from "$FROM" \
    --arg to "$TO" \
    --arg subject "$SUBJECT" \
    --arg text "$BODY" \
    '{from: $from, to: [$to], subject: $subject, text: $text}')
fi

[[ "$QUIET" == "false" ]] && echo "Sending email via Resend to: $TO"

# Send via Resend API with proper error handling
CURL_ERROR_FILE=$(mktemp)
RESPONSE=$(curl -s -w "\n%{http_code}" \
  --connect-timeout 10 \
  --max-time 30 \
  -X POST "https://api.resend.com/emails" \
  -H "Authorization: Bearer $RESEND_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  2>"$CURL_ERROR_FILE") || {
    CURL_EXIT=$?
    CURL_ERROR=$(cat "$CURL_ERROR_FILE")
    rm -f "$CURL_ERROR_FILE"
    echo "ERROR: curl failed (exit code $CURL_EXIT)" >&2
    [[ -n "$CURL_ERROR" ]] && echo "Details: $CURL_ERROR" >&2
    echo "Check your network connection and try again." >&2
    exit 1
  }
rm -f "$CURL_ERROR_FILE"

# Extract HTTP status code (last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY_RESPONSE=$(echo "$RESPONSE" | sed '$d')

# Validate HTTP code is numeric
if ! [[ "$HTTP_CODE" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Invalid HTTP response" >&2
  echo "Response: $RESPONSE" >&2
  exit 1
fi

# Check response
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
  [[ "$QUIET" == "false" ]] && echo "Email sent successfully!"
  [[ "$QUIET" == "false" ]] && echo "Response: $BODY_RESPONSE"
  exit 0
else
  echo "ERROR: Failed to send email (HTTP $HTTP_CODE)" >&2
  echo "Response: $BODY_RESPONSE" >&2
  exit 1
fi
