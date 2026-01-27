#!/bin/bash
# Notification Dispatcher for Clawdbot Orchestrator
# Routes notifications to WhatsApp, email, or other channels
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Notification Dispatcher for Clawdbot

Usage: $(basename "$0") <type> <task> <data> [state_file]

Arguments:
  type        Notification type: success, failure, progress
  task        Task description
  data        PR URL (success), report path (failure), or message (progress)
  state_file  Optional path to state.json for additional info

Options:
  --channel CHANNEL   Force specific channel: whatsapp, email, discord
  -q, --quiet         Suppress output
  -h, --help          Show this help

Environment Variables:
  TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_WHATSAPP_FROM, NOTIFY_WHATSAPP_TO
  CALLMEBOT_PHONE, CALLMEBOT_APIKEY
  SENDGRID_API_KEY, NOTIFY_EMAIL_TO, NOTIFY_EMAIL_FROM

Examples:
  $(basename "$0") success "Fix login bug" "https://github.com/user/repo/pull/123"
  $(basename "$0") failure "Add auth" /path/to/report.md /path/to/state.json
EOF
}

TYPE=""
TASK=""
DATA=""
STATE_FILE=""
CHANNEL=""
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --channel) CHANNEL="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$TYPE" ]]; then
        TYPE="$1"
      elif [[ -z "$TASK" ]]; then
        TASK="$1"
      elif [[ -z "$DATA" ]]; then
        DATA="$1"
      elif [[ -z "$STATE_FILE" ]]; then
        STATE_FILE="$1"
      else
        echo "Unknown argument: $1" >&2; usage >&2; exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$TYPE" ]] && { echo "ERROR: type is required" >&2; exit 1; }
[[ -z "$TASK" ]] && { echo "ERROR: task is required" >&2; exit 1; }
[[ -z "$DATA" ]] && { echo "ERROR: data is required" >&2; exit 1; }

log() {
  [[ "$QUIET" == "false" ]] && echo "$1"
}

# Get additional info from state file
PROJECT_NAME="unknown"
BRANCH_NAME="unknown"
OPENCODE_ITERS="0"
CLAUDE_ITERS="0"

if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
  PROJECT_NAME=$(jq -r '.project_name // "unknown"' "$STATE_FILE" 2>/dev/null)
  BRANCH_NAME=$(jq -r '.branch // "unknown"' "$STATE_FILE" 2>/dev/null)
  OPENCODE_ITERS=$(jq -r '.opencode_iterations // 0' "$STATE_FILE" 2>/dev/null)
  CLAUDE_ITERS=$(jq -r '.claude_iterations // 0' "$STATE_FILE" 2>/dev/null)
fi

# Build message based on type
build_message() {
  case "$TYPE" in
    success)
      cat << EOF
🦞 CLAWDBOT TASK COMPLETE

✅ Task: ${TASK}
📁 Project: ${PROJECT_NAME}
🔀 PR: ${DATA}

Iterations: ${OPENCODE_ITERS} (OpenCode) + ${CLAUDE_ITERS} (Claude)
Status: Codex Approved ✓

View PR: ${DATA}
EOF
      ;;
    failure)
      local failure_summary=""
      if [[ -f "$DATA" ]]; then
        failure_summary=$(head -20 "$DATA" | grep -v "^#" | head -10)
      fi
      cat << EOF
🦞 CLAWDBOT TASK FAILED

❌ Task: ${TASK}
📁 Project: ${PROJECT_NAME}
🔀 Branch: ${BRANCH_NAME}

Iterations: ${OPENCODE_ITERS} (OpenCode) + ${CLAUDE_ITERS} (Claude)
Status: Could not resolve all issues

${failure_summary:+Summary:
$failure_summary}

Manual review required.
EOF
      ;;
    progress)
      cat << EOF
🦞 CLAWDBOT PROGRESS UPDATE

📁 Project: ${PROJECT_NAME}
🔄 Task: ${TASK}

Current iteration: ${OPENCODE_ITERS}
Status: ${DATA}
EOF
      ;;
    *)
      echo "Unknown notification type: $TYPE" >&2
      exit 1
      ;;
  esac
}

MESSAGE=$(build_message)

# Send via Twilio WhatsApp
send_twilio_whatsapp() {
  if [[ -z "${TWILIO_ACCOUNT_SID:-}" || -z "${TWILIO_AUTH_TOKEN:-}" ]]; then
    return 1
  fi

  log "Sending via Twilio WhatsApp..."

  curl -s -X POST "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json" \
    --data-urlencode "Body=${MESSAGE}" \
    --data-urlencode "From=${TWILIO_WHATSAPP_FROM:-whatsapp:+14155238886}" \
    --data-urlencode "To=${NOTIFY_WHATSAPP_TO}" \
    -u "${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}" \
    > /dev/null 2>&1

  return $?
}

# Send via CallMeBot WhatsApp (free)
send_callmebot_whatsapp() {
  if [[ -z "${CALLMEBOT_PHONE:-}" || -z "${CALLMEBOT_APIKEY:-}" ]]; then
    return 1
  fi

  log "Sending via CallMeBot WhatsApp..."

  # URL encode the message
  ENCODED_MSG=$(echo "$MESSAGE" | jq -sRr @uri)

  curl -s "https://api.callmebot.com/whatsapp.php?phone=${CALLMEBOT_PHONE}&text=${ENCODED_MSG}&apikey=${CALLMEBOT_APIKEY}" \
    > /dev/null 2>&1

  return $?
}

# Send via SendGrid email
send_sendgrid_email() {
  if [[ -z "${SENDGRID_API_KEY:-}" || -z "${NOTIFY_EMAIL_TO:-}" ]]; then
    return 1
  fi

  log "Sending via SendGrid email..."

  local subject=""
  case "$TYPE" in
    success) subject="✅ Clawdbot: Task Complete - ${TASK:0:50}" ;;
    failure) subject="❌ Clawdbot: Task Failed - ${TASK:0:50}" ;;
    progress) subject="🔄 Clawdbot: Progress Update - ${TASK:0:50}" ;;
  esac

  # Use Node.js script for email
  node "$CLAWDBOT_ROOT/skills/notify/lib/email.js" \
    --to "$NOTIFY_EMAIL_TO" \
    --from "${NOTIFY_EMAIL_FROM:-clawdbot@noreply.local}" \
    --subject "$subject" \
    --body "$MESSAGE" \
    2>/dev/null

  return $?
}

# Determine channel and send
send_notification() {
  local sent=false

  # If specific channel requested
  if [[ -n "$CHANNEL" ]]; then
    case "$CHANNEL" in
      whatsapp)
        send_twilio_whatsapp && sent=true
        [[ "$sent" == "false" ]] && send_callmebot_whatsapp && sent=true
        ;;
      email)
        send_sendgrid_email && sent=true
        ;;
      *)
        echo "Unknown channel: $CHANNEL" >&2
        return 1
        ;;
    esac
  else
    # Try in order of preference
    send_twilio_whatsapp && sent=true
    [[ "$sent" == "false" ]] && send_callmebot_whatsapp && sent=true
    [[ "$sent" == "false" ]] && send_sendgrid_email && sent=true
  fi

  if [[ "$sent" == "true" ]]; then
    log "Notification sent successfully"
    return 0
  else
    log "WARNING: No notification channel available or all failed"
    log "Message content:"
    log "$MESSAGE"
    return 1
  fi
}

# Main
send_notification
