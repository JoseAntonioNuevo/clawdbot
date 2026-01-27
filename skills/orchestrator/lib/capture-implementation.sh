#!/bin/bash
# Capture Implementation Details
# Records what was implemented for context in reviews and future iterations
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Capture Implementation Details

Usage: $(basename "$0") [options]

Required:
  --worktree PATH       Path to worktree
  --base BRANCH         Base branch for diff
  --output FILE         Where to write the summary

Optional:
  --redact              Redact potential secrets from output (default: true)
  --no-redact           Disable redaction
  --exclude PATTERN     Exclude files matching pattern (can be repeated)

Examples:
  $(basename "$0") --worktree /path/to/worktree --base main --output impl.md
  $(basename "$0") --worktree /path --base main --output impl.md --exclude "*.env"
EOF
}

# Default sensitive file patterns to exclude from full content display
SENSITIVE_PATTERNS=(
  "*.env"
  "*.env.*"
  ".env*"
  "*credentials*"
  "*secret*"
  "*.pem"
  "*.key"
  "*.p12"
  "*.pfx"
  "*password*"
  "*.secrets"
  "config/secrets*"
)

# Redact potential secrets from content
# Compatible with both BSD sed (macOS) and GNU sed (Linux)
redact_secrets() {
  local content="$1"
  # Use a quote character class that works on BSD sed: [\"'] using $'...' syntax
  # \047 is octal for single quote
  local SQ=$'\047'  # Single quote character

  echo "$content" | sed -E \
    -e "s/(api[_-]?key|apikey|secret|password|token|auth|credential|private[_-]?key)[\"${SQ}]?[[:space:]]*[:=][[:space:]]*[\"${SQ}]?[A-Za-z0-9_-]{8,}[\"${SQ}]?/\1=<REDACTED>/gi" \
    -e "s/(Bearer|Basic)[[:space:]]+[A-Za-z0-9_.-]{20,}/(AUTH) <REDACTED>/gi" \
    -e 's/ghp_[A-Za-z0-9]{36}/ghp_<REDACTED>/g' \
    -e 's/sk-[A-Za-z0-9]{32,}/sk-<REDACTED>/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/xox_<REDACTED>/g' \
    -e "s/[\"${SQ}][A-Za-z0-9_-]{20,}[\"${SQ}]([[:space:]]*[,}])/\"<REDACTED>\"\1/g"
}

# Check if file matches sensitive patterns
is_sensitive_file() {
  local file="$1"
  local basename=$(basename "$file")
  for pattern in "${SENSITIVE_PATTERNS[@]}" "${EXCLUDE_PATTERNS[@]}"; do
    if [[ "$basename" == $pattern ]] || [[ "$file" == $pattern ]]; then
      return 0
    fi
  done
  return 1
}

WORKTREE=""
BASE_BRANCH=""
OUTPUT=""
REDACT=true
EXCLUDE_PATTERNS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --worktree) WORKTREE="$2"; shift 2 ;;
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --redact) REDACT=true; shift ;;
    --no-redact) REDACT=false; shift ;;
    --exclude) EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$WORKTREE" ]] && { echo "ERROR: --worktree required" >&2; exit 1; }
[[ -z "$BASE_BRANCH" ]] && { echo "ERROR: --base required" >&2; exit 1; }
[[ -z "$OUTPUT" ]] && { echo "ERROR: --output required" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"

cd "$WORKTREE"

{
  echo "# Implementation Summary"
  echo ""
  echo "Captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  # Files changed
  echo "## Files Changed"
  echo ""
  echo "\`\`\`"
  git diff --stat "$BASE_BRANCH"...HEAD 2>/dev/null || echo "(No changes)"
  echo "\`\`\`"
  echo ""

  # List of all file changes (including deleted/renamed)
  echo "## File Changes"
  echo ""

  # Get detailed file status (Added, Modified, Deleted, Renamed)
  FILE_STATUS=$(git diff --name-status "$BASE_BRANCH"...HEAD 2>/dev/null || echo "")

  if [[ -n "$FILE_STATUS" ]]; then
    echo "| Status | File |"
    echo "|--------|------|"
    while IFS=$'\t' read -r status file renamed_to; do
      if [[ -n "$status" ]]; then
        case "$status" in
          A) echo "| Created | \`$file\` |" ;;
          M) echo "| Modified | \`$file\` |" ;;
          D) echo "| **Deleted** | \`$file\` |" ;;
          R*) echo "| Renamed | \`$file\` → \`$renamed_to\` |" ;;
          C*) echo "| Copied | \`$file\` → \`$renamed_to\` |" ;;
          *) echo "| $status | \`$file\` |" ;;
        esac
      fi
    done <<< "$FILE_STATUS"
  else
    echo "(No files changed)"
  fi
  echo ""

  # Get list of changed files for further processing
  CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null || echo "")

  # Also get deleted files
  DELETED_FILES=$(git diff --name-only --diff-filter=D "$BASE_BRANCH"...HEAD 2>/dev/null || echo "")
  echo ""

  # Show the actual changes per file (with optional redaction)
  echo "## Changes Detail"
  echo ""

  if [[ -n "$CHANGED_FILES" ]]; then
    while IFS= read -r file; do
      if [[ -n "$file" ]]; then
        echo "### \`$file\`"
        echo ""

        # Check if file is sensitive
        if is_sensitive_file "$file"; then
          echo "> **REDACTED**: This file matches a sensitive pattern and content is not shown."
          echo ""
          echo "\`\`\`"
          echo "(sensitive file - content redacted for security)"
          echo "\`\`\`"
        else
          echo "\`\`\`diff"
          DIFF_CONTENT=$(git diff "$BASE_BRANCH"...HEAD -- "$file" 2>/dev/null || echo "(diff not available)")
          if [[ "$REDACT" == "true" ]]; then
            redact_secrets "$DIFF_CONTENT"
          else
            echo "$DIFF_CONTENT"
          fi
          echo "\`\`\`"
        fi
        echo ""
      fi
    done <<< "$CHANGED_FILES"
  fi

  # Show deleted files content (what was removed) - with redaction
  if [[ -n "$DELETED_FILES" ]]; then
    echo "## Deleted Files"
    echo ""
    echo "> These files were deleted during implementation"
    echo ""
    while IFS= read -r file; do
      if [[ -n "$file" ]]; then
        echo "### \`$file\` (DELETED)"
        echo ""

        # Check if deleted file was sensitive
        if is_sensitive_file "$file"; then
          echo "> **REDACTED**: This deleted file matches a sensitive pattern."
          echo ""
          echo "\`\`\`"
          echo "(sensitive file - content redacted for security)"
          echo "\`\`\`"
        else
          echo "\`\`\`diff"
          DELETED_CONTENT=$(git show "$BASE_BRANCH:$file" 2>/dev/null | head -50 || echo "(content not available)")
          if [[ "$REDACT" == "true" ]]; then
            redact_secrets "$DELETED_CONTENT"
          else
            echo "$DELETED_CONTENT"
          fi
          echo "\`\`\`"
        fi
        echo ""
      fi
    done <<< "$DELETED_FILES"
  fi

  # New files content (show full content for new files, with redaction)
  echo "## New Files Content"
  echo ""

  if [[ -n "$CHANGED_FILES" ]]; then
    while IFS= read -r file; do
      if [[ -n "$file" && -f "$file" ]]; then
        # Check if file is new
        if ! git show "$BASE_BRANCH:$file" &>/dev/null 2>&1; then
          echo "### \`$file\` (new)"
          echo ""

          # Check if file is sensitive
          if is_sensitive_file "$file"; then
            echo "> **REDACTED**: This file matches a sensitive pattern and content is not shown."
            echo ""
            echo "\`\`\`"
            echo "(sensitive file - content redacted for security)"
            echo "\`\`\`"
          else
            # Detect language for syntax highlighting
            EXT="${file##*.}"
            case "$EXT" in
              ts|tsx) LANG="typescript" ;;
              js|jsx) LANG="javascript" ;;
              py) LANG="python" ;;
              go) LANG="go" ;;
              rs) LANG="rust" ;;
              rb) LANG="ruby" ;;
              sh|bash) LANG="bash" ;;
              json) LANG="json" ;;
              yaml|yml) LANG="yaml" ;;
              md) LANG="markdown" ;;
              *) LANG="" ;;
            esac

            echo "\`\`\`$LANG"
            FILE_CONTENT=$(cat "$file")
            if [[ "$REDACT" == "true" ]]; then
              redact_secrets "$FILE_CONTENT"
            else
              echo "$FILE_CONTENT"
            fi
            echo "\`\`\`"
          fi
          echo ""
        fi
      fi
    done <<< "$CHANGED_FILES"
  fi

  # Commits made
  echo "## Commits"
  echo ""
  echo "\`\`\`"
  git log "$BASE_BRANCH"...HEAD --oneline 2>/dev/null || echo "(No commits)"
  echo "\`\`\`"

} > "$OUTPUT"

echo "Implementation captured to: $OUTPUT"
