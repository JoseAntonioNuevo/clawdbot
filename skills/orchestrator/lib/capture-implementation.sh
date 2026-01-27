#!/bin/bash
# Capture Implementation Details
# Records what was implemented for context in reviews and future iterations
set -euo pipefail

usage() {
  cat << EOF
Capture Implementation Details

Usage: $(basename "$0") [options]

Required:
  --worktree PATH       Path to worktree
  --base BRANCH         Base branch for diff
  --output FILE         Where to write the summary

Examples:
  $(basename "$0") --worktree /path/to/worktree --base main --output impl.md
EOF
}

WORKTREE=""
BASE_BRANCH=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --worktree) WORKTREE="$2"; shift 2 ;;
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
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

  # Show the actual changes per file (FULL - no truncation)
  echo "## Changes Detail"
  echo ""

  if [[ -n "$CHANGED_FILES" ]]; then
    while IFS= read -r file; do
      if [[ -n "$file" ]]; then
        echo "### \`$file\`"
        echo ""
        echo "\`\`\`diff"
        git diff "$BASE_BRANCH"...HEAD -- "$file" 2>/dev/null || echo "(diff not available)"
        echo "\`\`\`"
        echo ""
      fi
    done <<< "$CHANGED_FILES"
  fi

  # Show deleted files content (what was removed)
  if [[ -n "$DELETED_FILES" ]]; then
    echo "## Deleted Files"
    echo ""
    echo "> These files were deleted during implementation"
    echo ""
    while IFS= read -r file; do
      if [[ -n "$file" ]]; then
        echo "### \`$file\` (DELETED)"
        echo ""
        echo "\`\`\`diff"
        git show "$BASE_BRANCH:$file" 2>/dev/null | head -50 || echo "(content not available)"
        echo "\`\`\`"
        echo ""
      fi
    done <<< "$DELETED_FILES"
  fi

  # New files content (show full content for new files)
  echo "## New Files Content"
  echo ""

  if [[ -n "$CHANGED_FILES" ]]; then
    while IFS= read -r file; do
      if [[ -n "$file" && -f "$file" ]]; then
        # Check if file is new
        if ! git show "$BASE_BRANCH:$file" &>/dev/null 2>&1; then
          echo "### \`$file\` (new)"
          echo ""

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
          cat "$file"
          echo "\`\`\`"
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
