#!/bin/bash
# Git Worktree Management for Clawdbot Orchestrator
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../config/env.template" 2>/dev/null || true
[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

WORKTREE_BASE="${WORKTREE_BASE:-$HOME/ai-worktrees}"

usage() {
  cat << EOF
Git Worktree Management for Clawdbot

Usage: $(basename "$0") <command> [options]

Commands:
  create    Create a new worktree
  remove    Remove a worktree
  list      List all worktrees for a project
  cleanup   Clean up old worktrees

Create Options:
  -p, --project PATH     Project repository path (required)
  -b, --branch NAME      Branch name to create (required)
  -t, --task-id ID       Task ID for directory naming (required)
  --base BRANCH          Base branch (default: main)

Remove Options:
  -w, --worktree PATH    Worktree path to remove (required)
  --force                Force removal even with changes

Examples:
  $(basename "$0") create -p /path/to/repo -b ai/fix-bug -t 20240101-120000-abc123
  $(basename "$0") remove -w ~/ai-worktrees/myrepo/20240101-120000-abc123
  $(basename "$0") list -p /path/to/repo
EOF
}

create_worktree() {
  local project_path=""
  local branch_name=""
  local task_id=""
  local base_branch="main"

  while [[ $# -gt 0 ]]; do
    case $1 in
      -p|--project) project_path="$2"; shift 2 ;;
      -b|--branch) branch_name="$2"; shift 2 ;;
      -t|--task-id) task_id="$2"; shift 2 ;;
      --base) base_branch="$2"; shift 2 ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done

  [[ -z "$project_path" ]] && { echo "ERROR: --project is required"; exit 1; }
  [[ -z "$branch_name" ]] && { echo "ERROR: --branch is required"; exit 1; }
  [[ -z "$task_id" ]] && { echo "ERROR: --task-id is required"; exit 1; }

  # Validate project
  if [[ ! -d "$project_path/.git" ]]; then
    echo "ERROR: Not a git repository: $project_path"
    exit 1
  fi

  local project_name
  project_name=$(basename "$project_path")
  local worktree_path="$WORKTREE_BASE/$project_name/$task_id"

  # Create parent directory
  mkdir -p "$(dirname "$worktree_path")"

  # Fetch latest from remote
  cd "$project_path"
  git fetch origin "$base_branch" 2>/dev/null || true

  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    echo "WARNING: Branch $branch_name already exists, using existing branch"
    git worktree add "$worktree_path" "$branch_name"
  else
    # Create worktree with new branch from base
    if git show-ref --verify --quiet "refs/remotes/origin/$base_branch" 2>/dev/null; then
      git worktree add -b "$branch_name" "$worktree_path" "origin/$base_branch"
    else
      git worktree add -b "$branch_name" "$worktree_path" "$base_branch"
    fi
  fi

  echo "$worktree_path"
}

remove_worktree() {
  local worktree_path=""
  local force=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      -w|--worktree) worktree_path="$2"; shift 2 ;;
      --force) force=true; shift ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done

  [[ -z "$worktree_path" ]] && { echo "ERROR: --worktree is required"; exit 1; }

  if [[ ! -d "$worktree_path" ]]; then
    echo "WARNING: Worktree doesn't exist: $worktree_path"
    exit 0
  fi

  # Get the main repo path from the worktree
  if [[ -f "$worktree_path/.git" ]]; then
    local gitdir
    gitdir=$(grep "gitdir:" "$worktree_path/.git" | cut -d' ' -f2)
    if [[ -n "$gitdir" ]]; then
      local main_repo
      main_repo=$(dirname "$(dirname "$(dirname "$gitdir")")")

      if [[ -d "$main_repo/.git" ]]; then
        cd "$main_repo"

        # Get branch name before removing
        local branch
        branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

        # Remove worktree
        if [[ "$force" == "true" ]]; then
          git worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
        else
          git worktree remove "$worktree_path" 2>/dev/null || {
            echo "WARNING: Worktree has uncommitted changes. Use --force to remove anyway."
            exit 1
          }
        fi

        # Optionally delete branch (only if it starts with ai/)
        if [[ -n "$branch" && "$branch" == ai/* ]]; then
          git branch -D "$branch" 2>/dev/null || true
        fi

        echo "Removed worktree: $worktree_path"
        return 0
      fi
    fi
  fi

  # Fallback: just delete the directory
  rm -rf "$worktree_path"
  echo "Removed directory: $worktree_path"
}

list_worktrees() {
  local project_path=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -p|--project) project_path="$2"; shift 2 ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done

  [[ -z "$project_path" ]] && { echo "ERROR: --project is required"; exit 1; }

  local project_name
  project_name=$(basename "$project_path")
  local project_worktree_dir="$WORKTREE_BASE/$project_name"

  if [[ ! -d "$project_worktree_dir" ]]; then
    echo "No worktrees found for: $project_name"
    exit 0
  fi

  echo "Worktrees for $project_name:"
  echo "=============================="

  for worktree in "$project_worktree_dir"/*/; do
    if [[ -d "$worktree" ]]; then
      local task_id
      task_id=$(basename "$worktree")
      local branch="unknown"
      local status="unknown"

      if [[ -d "$worktree/.git" ]] || [[ -f "$worktree/.git" ]]; then
        branch=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
      fi

      # Check for state file
      local log_dir="/Users/jose/Documents/clawdbot/logs/$project_name/$task_id"
      if [[ -f "$log_dir/state.json" ]]; then
        status=$(jq -r '.status' "$log_dir/state.json" 2>/dev/null || echo "unknown")
      fi

      printf "  %-30s %-25s %s\n" "$task_id" "$branch" "[$status]"
    fi
  done
}

cleanup_worktrees() {
  local days=7
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      -d|--days) days="$2"; shift 2 ;;
      -n|--dry-run) dry_run=true; shift ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done

  echo "Cleaning up worktrees older than $days days..."

  find "$WORKTREE_BASE" -maxdepth 2 -mindepth 2 -type d -mtime +"$days" 2>/dev/null | while read -r worktree; do
    if [[ "$dry_run" == "true" ]]; then
      echo "Would remove: $worktree"
    else
      remove_worktree -w "$worktree" --force
    fi
  done
}

# Main
case "${1:-}" in
  create) shift; create_worktree "$@" ;;
  remove) shift; remove_worktree "$@" ;;
  list) shift; list_worktrees "$@" ;;
  cleanup) shift; cleanup_worktrees "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
