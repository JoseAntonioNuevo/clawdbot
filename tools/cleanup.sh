#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Default values
WORKTREE_BASE="${WORKTREE_BASE:-$HOME/ai-worktrees}"
LOGS_DIR="$CLAWDBOT_ROOT/logs"
DRY_RUN=false
DAYS=7
CLEAN_LOGS=false
CLEAN_WORKTREES=false
CLEAN_MERGED=false
CLEAN_ALL=false

usage() {
  cat << EOF
🦞 Clawdbot Cleanup Utility

Usage: $(basename "$0") [OPTIONS]

Options:
  -d, --days DAYS       Clean items older than DAYS days (default: 7)
  -w, --worktrees       Clean old worktrees
  -l, --logs            Clean old logs
  -m, --merged          Clean worktrees for merged PRs
  -a, --all             Clean everything (worktrees + logs + merged)
  -n, --dry-run         Show what would be deleted without deleting
  -h, --help            Show this help message

Examples:
  $(basename "$0") --worktrees --days 14    # Clean worktrees older than 14 days
  $(basename "$0") --merged                  # Clean worktrees for merged PRs
  $(basename "$0") --all --dry-run          # Show what would be cleaned
  $(basename "$0") -a -d 30                  # Clean everything older than 30 days
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--days)
      DAYS="$2"
      shift 2
      ;;
    -w|--worktrees)
      CLEAN_WORKTREES=true
      shift
      ;;
    -l|--logs)
      CLEAN_LOGS=true
      shift
      ;;
    -m|--merged)
      CLEAN_MERGED=true
      shift
      ;;
    -a|--all)
      CLEAN_ALL=true
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# If --all, enable everything
if [[ "$CLEAN_ALL" == "true" ]]; then
  CLEAN_WORKTREES=true
  CLEAN_LOGS=true
  CLEAN_MERGED=true
fi

# If nothing specified, show usage
if [[ "$CLEAN_WORKTREES" == "false" && "$CLEAN_LOGS" == "false" && "$CLEAN_MERGED" == "false" ]]; then
  usage
  exit 0
fi

echo "🦞 Clawdbot Cleanup Utility"
echo "==========================="
echo ""
[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN MODE - nothing will be deleted"
echo ""

TOTAL_FREED=0

# Clean old worktrees
if [[ "$CLEAN_WORKTREES" == "true" ]]; then
  log "Cleaning worktrees older than $DAYS days..."

  if [[ -d "$WORKTREE_BASE" ]]; then
    # Find old worktree directories
    OLD_WORKTREES=$(find "$WORKTREE_BASE" -maxdepth 2 -mindepth 2 -type d -mtime +"$DAYS" 2>/dev/null || true)

    if [[ -n "$OLD_WORKTREES" ]]; then
      echo "$OLD_WORKTREES" | while read -r worktree; do
        if [[ -n "$worktree" ]]; then
          SIZE=$(du -sh "$worktree" 2>/dev/null | cut -f1)
          if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would remove: $worktree ($SIZE)"
          else
            # Find the original repo and remove worktree properly
            if [[ -f "$worktree/.git" ]]; then
              GITDIR=$(cat "$worktree/.git" | grep "gitdir:" | cut -d' ' -f2)
              if [[ -n "$GITDIR" ]]; then
                MAIN_REPO=$(dirname "$(dirname "$(dirname "$GITDIR")")")
                if [[ -d "$MAIN_REPO/.git" ]]; then
                  git -C "$MAIN_REPO" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
                else
                  rm -rf "$worktree"
                fi
              else
                rm -rf "$worktree"
              fi
            else
              rm -rf "$worktree"
            fi
            echo "  Removed: $worktree ($SIZE)"
          fi
        fi
      done
      success "Old worktrees cleanup complete"
    else
      success "No old worktrees to clean"
    fi
  else
    warn "Worktree directory not found: $WORKTREE_BASE"
  fi
fi

# Clean worktrees for merged PRs
if [[ "$CLEAN_MERGED" == "true" ]]; then
  log "Cleaning worktrees for merged PRs..."

  if [[ -d "$WORKTREE_BASE" ]]; then
    # Iterate through project directories
    for project_dir in "$WORKTREE_BASE"/*/; do
      if [[ -d "$project_dir" ]]; then
        for worktree in "$project_dir"*/; do
          if [[ -d "$worktree" && -f "$worktree/.git" ]]; then
            # Get the branch name
            BRANCH=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

            if [[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]]; then
              # Check if there's a merged PR for this branch
              PR_STATE=$(gh pr view "$BRANCH" --json state -q '.state' 2>/dev/null || true)

              if [[ "$PR_STATE" == "MERGED" || "$PR_STATE" == "CLOSED" ]]; then
                SIZE=$(du -sh "$worktree" 2>/dev/null | cut -f1)
                if [[ "$DRY_RUN" == "true" ]]; then
                  echo "  Would remove (PR $PR_STATE): $worktree ($SIZE)"
                else
                  # Find original repo and remove properly
                  GITDIR=$(cat "$worktree/.git" | grep "gitdir:" | cut -d' ' -f2)
                  if [[ -n "$GITDIR" ]]; then
                    MAIN_REPO=$(dirname "$(dirname "$(dirname "$GITDIR")")")
                    if [[ -d "$MAIN_REPO/.git" ]]; then
                      # Also delete the branch
                      git -C "$MAIN_REPO" worktree remove --force "$worktree" 2>/dev/null || true
                      git -C "$MAIN_REPO" branch -D "$BRANCH" 2>/dev/null || true
                    fi
                  fi
                  rm -rf "$worktree" 2>/dev/null || true
                  echo "  Removed (PR $PR_STATE): $worktree ($SIZE)"
                fi
              fi
            fi
          fi
        done
      fi
    done
    success "Merged PR worktrees cleanup complete"
  fi
fi

# Clean old logs
if [[ "$CLEAN_LOGS" == "true" ]]; then
  log "Cleaning logs older than $DAYS days..."

  if [[ -d "$LOGS_DIR" ]]; then
    # Find old log directories
    OLD_LOGS=$(find "$LOGS_DIR" -maxdepth 2 -mindepth 2 -type d -mtime +"$DAYS" 2>/dev/null || true)

    if [[ -n "$OLD_LOGS" ]]; then
      echo "$OLD_LOGS" | while read -r logdir; do
        if [[ -n "$logdir" ]]; then
          SIZE=$(du -sh "$logdir" 2>/dev/null | cut -f1)
          if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would remove: $logdir ($SIZE)"
          else
            rm -rf "$logdir"
            echo "  Removed: $logdir ($SIZE)"
          fi
        fi
      done
      success "Old logs cleanup complete"
    else
      success "No old logs to clean"
    fi
  else
    warn "Logs directory not found: $LOGS_DIR"
  fi
fi

# Clean empty directories
log "Cleaning empty directories..."
find "$WORKTREE_BASE" -type d -empty -delete 2>/dev/null || true
find "$LOGS_DIR" -type d -empty -delete 2>/dev/null || true
success "Empty directories cleaned"

# Summary
echo ""
echo "==========================="
if [[ "$DRY_RUN" == "true" ]]; then
  warn "DRY RUN COMPLETE - no files were deleted"
  echo "Remove --dry-run flag to actually delete files"
else
  success "Cleanup complete!"
fi

# Show current disk usage
if [[ -d "$WORKTREE_BASE" ]]; then
  WORKTREE_SIZE=$(du -sh "$WORKTREE_BASE" 2>/dev/null | cut -f1)
  echo "Current worktree usage: $WORKTREE_SIZE"
fi

if [[ -d "$LOGS_DIR" ]]; then
  LOGS_SIZE=$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1)
  echo "Current logs usage: $LOGS_SIZE"
fi
