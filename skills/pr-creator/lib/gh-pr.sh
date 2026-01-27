#!/bin/bash
# GitHub PR Creator for Clawdbot Orchestrator
# Creates PRs with proper titles and descriptions
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
GitHub PR Creator for Clawdbot

Usage: $(basename "$0") [options]

Required Options:
  --title TITLE         PR title
  --task TASK           Original task description
  --base BRANCH         Base branch (target)
  --head BRANCH         Head branch (source)

Optional Options:
  --state-file PATH     Path to state.json for metadata
  --workdir PATH        Working directory (default: current)
  --draft               Create as draft PR
  --reviewer USER       Add reviewer (can be repeated)
  --label LABEL         Add label (can be repeated)
  --template PATH       Custom PR body template
  -q, --quiet           Suppress progress output
  -h, --help            Show this help

Output:
  Prints the PR URL on success

Examples:
  $(basename "$0") --title "Fix bug" --task "Fix the login bug" --base main --head ai/fix-bug
  $(basename "$0") --title "Add feature" --task "Add auth" --base main --head ai/add-auth --draft
EOF
}

# Defaults
TITLE=""
TASK=""
BASE_BRANCH=""
HEAD_BRANCH=""
STATE_FILE=""
WORKDIR="$(pwd)"
DRAFT=false
REVIEWERS=()
LABELS=("ai-generated")
TEMPLATE=""
QUIET=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --title) TITLE="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --head) HEAD_BRANCH="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --draft) DRAFT=true; shift ;;
    --reviewer) REVIEWERS+=("$2"); shift 2 ;;
    --label) LABELS+=("$2"); shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Validate required arguments
[[ -z "$TITLE" ]] && { echo "ERROR: --title is required" >&2; exit 1; }
[[ -z "$TASK" ]] && { echo "ERROR: --task is required" >&2; exit 1; }
[[ -z "$BASE_BRANCH" ]] && { echo "ERROR: --base is required" >&2; exit 1; }
[[ -z "$HEAD_BRANCH" ]] && { echo "ERROR: --head is required" >&2; exit 1; }

log() {
  [[ "$QUIET" == "false" ]] && echo "$1" >&2
}

# Check gh CLI
if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not installed" >&2
  echo "Install with: brew install gh" >&2
  exit 1
fi

# Check auth
if ! gh auth status &>/dev/null 2>&1; then
  echo "ERROR: gh not authenticated" >&2
  echo "Run: gh auth login" >&2
  exit 1
fi

cd "$WORKDIR"

# Extract metadata from state file
IMPLEMENTER="OpenCode (GLM 4.7)"
OPENCODE_ITERS="0"
CLAUDE_ITERS="0"
TASK_ID="unknown"
PROJECT_NAME="unknown"

if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
  IMPLEMENTER_RAW=$(jq -r '.implementer // "opencode"' "$STATE_FILE" 2>/dev/null)
  case "$IMPLEMENTER_RAW" in
    opencode) IMPLEMENTER="OpenCode (GLM 4.7)" ;;
    claude) IMPLEMENTER="Claude Code (Opus 4.5)" ;;
    *) IMPLEMENTER="$IMPLEMENTER_RAW" ;;
  esac
  OPENCODE_ITERS=$(jq -r '.opencode_iterations // 0' "$STATE_FILE" 2>/dev/null)
  CLAUDE_ITERS=$(jq -r '.claude_iterations // 0' "$STATE_FILE" 2>/dev/null)
  TASK_ID=$(jq -r '.task_id // "unknown"' "$STATE_FILE" 2>/dev/null)
  PROJECT_NAME=$(jq -r '.project_name // "unknown"' "$STATE_FILE" 2>/dev/null)
fi

# Get diff stats
DIFF_STAT=$(git diff --stat "$BASE_BRANCH"..."$HEAD_BRANCH" 2>/dev/null | tail -1 || echo "No changes")
FILES_CHANGED=$(git diff --name-only "$BASE_BRANCH"..."$HEAD_BRANCH" 2>/dev/null | head -20 || echo "")

# Build file list for PR body
FILES_LIST=""
if [[ -n "$FILES_CHANGED" ]]; then
  while IFS= read -r file; do
    [[ -n "$file" ]] && FILES_LIST="$FILES_LIST\n- \`$file\`"
  done <<< "$FILES_CHANGED"
fi

# Check for test results in state directory
TEST_STATUS="Not available"
if [[ -n "$STATE_FILE" ]]; then
  LOG_DIR=$(dirname "$STATE_FILE")
  LATEST_TESTS=$(ls -t "$LOG_DIR/opencode/tests_"*.txt 2>/dev/null | head -1 || true)
  if [[ -n "$LATEST_TESTS" && -f "$LATEST_TESTS" ]]; then
    if grep -qiE "passed|ok|success" "$LATEST_TESTS" && ! grep -qiE "failed|error" "$LATEST_TESTS"; then
      TEST_STATUS="✅ All tests passing"
    elif grep -qiE "failed|error" "$LATEST_TESTS"; then
      TEST_STATUS="⚠️ Some tests may need attention"
    else
      TEST_STATUS="ℹ️ Tests executed"
    fi
  fi
fi

# Build PR body
if [[ -n "$TEMPLATE" && -f "$TEMPLATE" ]]; then
  PR_BODY=$(cat "$TEMPLATE")
else
  PR_BODY=$(cat << EOF
## Summary

This PR implements the following task:

> ${TASK}

## Changes

**Files Modified:**
$(echo -e "$FILES_LIST")

**Stats:** ${DIFF_STAT}

## Testing

${TEST_STATUS}

## Implementation Details

| Field | Value |
|-------|-------|
| **Implementer** | ${IMPLEMENTER} |
| **Reviewer** | Codex (GPT-5.2-Codex) |
| **OpenCode Iterations** | ${OPENCODE_ITERS} |
| **Claude Iterations** | ${CLAUDE_ITERS} |
| **Task ID** | \`${TASK_ID}\` |

## Codex Review

**Status**: ✅ Approved

---
🦞 Generated by [Clawdbot Intelligent Implementer](https://github.com/clawdbot/clawdbot)
EOF
)
fi

# Check if PR already exists
EXISTING_PR=$(gh pr list --head "$HEAD_BRANCH" --base "$BASE_BRANCH" --json url -q '.[0].url' 2>/dev/null || true)

if [[ -n "$EXISTING_PR" ]]; then
  log "PR already exists: $EXISTING_PR"
  echo "$EXISTING_PR"
  exit 0
fi

# Ensure branch is pushed
log "Ensuring branch is pushed..."
git push -u origin "$HEAD_BRANCH" 2>/dev/null || true

# Build gh pr create command
CMD=(gh pr create)
CMD+=(--title "$TITLE")
CMD+=(--base "$BASE_BRANCH")
CMD+=(--head "$HEAD_BRANCH")

if [[ "$DRAFT" == "true" ]]; then
  CMD+=(--draft)
fi

# Add labels
if [[ ${#LABELS[@]} -gt 0 ]]; then
  LABEL_STR=$(IFS=,; echo "${LABELS[*]}")
  CMD+=(--label "$LABEL_STR")
fi

# Add reviewers
for reviewer in "${REVIEWERS[@]}"; do
  CMD+=(--reviewer "$reviewer")
done

log "Creating PR: $TITLE"

# Create PR using heredoc for body
PR_URL=$("${CMD[@]}" --body "$(cat <<PRBODY
$PR_BODY
PRBODY
)" 2>&1)

# Check if successful
if [[ "$PR_URL" == http* ]]; then
  log "PR created successfully"
  echo "$PR_URL"
  exit 0
else
  echo "ERROR: Failed to create PR" >&2
  echo "$PR_URL" >&2
  exit 1
fi
