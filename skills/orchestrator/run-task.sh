#!/bin/bash
# ==============================================================================
# Clawdbot Intelligent Implementer - Main Orchestrator
# ==============================================================================
# Orchestrates the complete AI coding workflow:
#   1. Claude Code (Opus 4.5) - Planning
#   2. OpenCode (Kimi K2.5) - Implementation
#   3. Codex CLI (GPT-5.2-Codex) - Review
#   4. Notifications via Resend/Email
#
# Usage: ./run-task.sh --project /path/to/repo --task "Task description"
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CLAWDBOT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load environment
[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

# ==============================================================================
# CONFIGURATION DEFAULTS
# ==============================================================================
MAX_CLAUDE_ITERATIONS="${MAX_ITERATIONS:-10}"
MAX_OPENCODE_ITERATIONS=80
WORKTREE_BASE="${WORKTREE_BASE:-$HOME/ai-worktrees}"
DEFAULT_BASE_BRANCH="${DEFAULT_BASE_BRANCH:-main}"
AUTO_RUN_TESTS="${AUTO_RUN_TESTS:-true}"
LOG_BASE="${LOG_BASE:-$CLAWDBOT_ROOT/logs}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================================================
# USAGE
# ==============================================================================
usage() {
  cat << EOF
Clawdbot Intelligent Implementer - Main Orchestrator

Usage: $(basename "$0") [options]

Required:
  --project PATH        Path to the git repository
  --task DESCRIPTION    Task description (what to implement/fix)

Options:
  --base-branch BRANCH  Base branch for PR (default: main)
  --email EMAIL         Email for notifications
  --dry-run             Preview workflow without running AI tools or modifying git
                        (creates log files for debugging but no worktrees/commits)
  -q, --quiet           Suppress progress output
  -h, --help            Show this help

Environment Variables:
  MAX_ITERATIONS        Max Claude iterations (default: 10)
  WORKTREE_BASE         Where to create worktrees (default: ~/ai-worktrees)
  AUTO_RUN_TESTS        Run tests automatically (default: true)
  RESEND_API_KEY        For email notifications
  NOTIFY_EMAIL_TO       Default notification recipient

Examples:
  $(basename "$0") --project /path/to/myapp --task "Fix the login timeout bug"
  $(basename "$0") --project . --task "Add user authentication" --email me@example.com
EOF
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================
PROJECT_PATH=""
TASK_DESCRIPTION=""
BASE_BRANCH="$DEFAULT_BASE_BRANCH"
NOTIFY_EMAIL=""
DRY_RUN=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT_PATH="$2"; shift 2 ;;
    --task) TASK_DESCRIPTION="$2"; shift 2 ;;
    --base-branch) BASE_BRANCH="$2"; shift 2 ;;
    --email) NOTIFY_EMAIL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Validate required arguments
[[ -z "$PROJECT_PATH" ]] && { echo -e "${RED}ERROR: --project is required${NC}" >&2; usage >&2; exit 1; }
[[ -z "$TASK_DESCRIPTION" ]] && { echo -e "${RED}ERROR: --task is required${NC}" >&2; usage >&2; exit 1; }

# Resolve project path
PROJECT_PATH=$(cd "$PROJECT_PATH" 2>/dev/null && pwd) || {
  echo -e "${RED}ERROR: Project directory does not exist: $PROJECT_PATH${NC}" >&2
  exit 1
}

# Set notification email - export so notify.sh can use it
if [[ -n "$NOTIFY_EMAIL" ]]; then
  export NOTIFY_EMAIL_TO="$NOTIFY_EMAIL"
elif [[ -z "${NOTIFY_EMAIL_TO:-}" ]]; then
  NOTIFY_EMAIL_TO=""
fi

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================
preflight_check() {
  local missing=()

  # Required dependencies
  command -v git &>/dev/null || missing+=("git")
  command -v jq &>/dev/null || missing+=("jq")
  command -v gh &>/dev/null || missing+=("gh (GitHub CLI)")

  # Optional but needed for full functionality
  if [[ "$DRY_RUN" != "true" ]]; then
    command -v opencode &>/dev/null || missing+=("opencode")
    command -v codex &>/dev/null || missing+=("codex")
    command -v claude &>/dev/null || missing+=("claude")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}ERROR: Missing required dependencies:${NC}" >&2
    for dep in "${missing[@]}"; do
      echo -e "  ${RED}✗${NC} $dep" >&2
    done
    echo "" >&2
    echo "Run 'tools/doctor.sh' to check your setup." >&2
    exit 1
  fi
}

# Run preflight checks
preflight_check

# ==============================================================================
# LOGGING HELPERS
# ==============================================================================
log() {
  [[ "$QUIET" == "false" ]] && echo -e "$1"
}

log_phase() {
  log ""
  log "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  log "${CYAN}  $1${NC}"
  log "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  log ""
}

log_step() {
  log "${BLUE}▶${NC} $1"
}

log_success() {
  log "${GREEN}✓${NC} $1"
}

log_warning() {
  log "${YELLOW}⚠${NC} $1"
}

log_error() {
  log "${RED}✗${NC} $1"
}

# ==============================================================================
# PHASE 1: INITIALIZATION
# ==============================================================================
initialize() {
  log_phase "PHASE 1: INITIALIZATION"

  # Validate git repository
  log_step "Validating project..."
  if [[ ! -d "$PROJECT_PATH/.git" ]]; then
    log_error "Not a git repository: $PROJECT_PATH"
    exit 1
  fi
  log_success "Project is a git repository"

  # Check for uncommitted changes
  cd "$PROJECT_PATH"
  if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
    log_warning "Project has uncommitted changes"
    log_warning "These won't be included in the worktree"
  fi

  # Generate task ID (portable hash for macOS and Linux)
  local task_hash
  if command -v md5 &>/dev/null; then
    task_hash=$(echo "$TASK_DESCRIPTION" | md5 | cut -c1-8)
  elif command -v md5sum &>/dev/null; then
    task_hash=$(echo "$TASK_DESCRIPTION" | md5sum | cut -c1-8)
  elif command -v shasum &>/dev/null; then
    task_hash=$(echo "$TASK_DESCRIPTION" | shasum -a 256 | cut -c1-8)
  else
    task_hash=$(printf '%08x' $RANDOM)
  fi
  TASK_ID="$(date +%Y%m%d-%H%M%S)-${task_hash}"
  log_success "Task ID: $TASK_ID"

  # Get project name
  PROJECT_NAME=$(basename "$PROJECT_PATH")
  log_success "Project: $PROJECT_NAME"

  # Create worktree
  log_step "Creating isolated worktree..."
  WORKTREE_PATH="$WORKTREE_BASE/$PROJECT_NAME/$TASK_ID"

  # Generate branch name
  BRANCH_NAME="ai/$(echo "$TASK_DESCRIPTION" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-40)"
  BRANCH_NAME="${BRANCH_NAME%-}"  # Remove trailing dash

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would create worktree at: $WORKTREE_PATH"
    log_warning "[DRY RUN] Would create branch: $BRANCH_NAME"
  else
    WORKTREE_PATH=$("$LIB_DIR/worktree.sh" create \
      --project "$PROJECT_PATH" \
      --branch "$BRANCH_NAME" \
      --task-id "$TASK_ID" \
      --base "$BASE_BRANCH")
  fi
  log_success "Worktree: $WORKTREE_PATH"
  log_success "Branch: $BRANCH_NAME"

  # Create log directory
  LOG_DIR="$LOG_BASE/$PROJECT_NAME/$TASK_ID"
  mkdir -p "$LOG_DIR"/{opencode,codex,claude,iterations}
  log_success "Logs: $LOG_DIR"

  # Initialize state file
  STATE_FILE="$LOG_DIR/state.json"
  cat > "$STATE_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "project": "$PROJECT_PATH",
  "project_name": "$PROJECT_NAME",
  "task": $(echo "$TASK_DESCRIPTION" | jq -Rs .),
  "branch": "$BRANCH_NAME",
  "worktree": "$WORKTREE_PATH",
  "base_branch": "$BASE_BRANCH",
  "status": "in_progress",
  "phase": "initializing",
  "claude_iterations": 0,
  "opencode_iterations": 0,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pr_url": null
}
EOF
  log_success "State initialized"

  # Save task description
  TASK_FILE="$LOG_DIR/task.md"
  echo "$TASK_DESCRIPTION" > "$TASK_FILE"

  # Analyze codebase
  log_step "Analyzing codebase..."
  CODEBASE_FILE="$LOG_DIR/codebase_summary.md"
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would analyze codebase"
  else
    "$LIB_DIR/analyze-codebase.sh" "$WORKTREE_PATH" > "$CODEBASE_FILE"
  fi
  log_success "Codebase analysis complete"

  log_success "Initialization complete"
}

# ==============================================================================
# UPDATE STATE HELPER
# ==============================================================================
update_state() {
  local key="$1"
  local value="$2"
  local temp_file=$(mktemp)
  jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$STATE_FILE" > "$temp_file" && mv "$temp_file" "$STATE_FILE"
}

update_state_num() {
  local key="$1"
  local value="$2"
  local temp_file=$(mktemp)
  jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$STATE_FILE" > "$temp_file" && mv "$temp_file" "$STATE_FILE"
}

# ==============================================================================
# PHASE 2: PLANNING (Claude Code)
# ==============================================================================
run_claude_planning() {
  local iteration=$1
  log_step "Running Claude Code (Opus 4.5) planning - Iteration $iteration..."

  update_state "phase" "planning"

  ITER_DIR="$LOG_DIR/iterations/iter_$(printf '%03d' $iteration)"
  mkdir -p "$ITER_DIR"

  # Build context for Claude
  local context_file="$ITER_DIR/claude_context.md"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would build Claude context"
  else
    "$LIB_DIR/build-claude-context.sh" \
      --task "$TASK_FILE" \
      --codebase "$CODEBASE_FILE" \
      --worktree "$WORKTREE_PATH" \
      --iteration "$iteration" \
      --history "$LOG_DIR/iterations" \
      --base-branch "$BASE_BRANCH" \
      --output "$context_file"
  fi

  # Run Claude Code
  local plan_file="$ITER_DIR/claude_plan.md"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would run Claude Code for planning"
    echo "# Mock Plan for $TASK_DESCRIPTION" > "$plan_file"
  else
    "$LIB_DIR/claude-code.sh" \
      --mode plan \
      --context "$context_file" \
      --workdir "$WORKTREE_PATH" \
      --output "$plan_file" \
      ${QUIET:+"-q"} || {
        log_error "Claude Code planning failed"
        return 1
      }
  fi

  log_success "Plan created: $plan_file"

  # Copy plan to latest location
  cp "$plan_file" "$LOG_DIR/claude/plan_iter_${iteration}.md"

  update_state_num "claude_iterations" "$iteration"
}

# ==============================================================================
# PHASE 3: IMPLEMENTATION (OpenCode/Kimi)
# ==============================================================================
run_opencode_implementation() {
  local claude_iteration=$1
  local opencode_iteration=$2
  log_step "Running OpenCode (Kimi K2.5) implementation - Claude:$claude_iteration, OpenCode:$opencode_iteration..."

  update_state "phase" "implementing"

  ITER_DIR="$LOG_DIR/iterations/iter_$(printf '%03d' $claude_iteration)"
  local plan_file="$ITER_DIR/claude_plan.md"

  # Build context for Kimi
  local context_file="$LOG_DIR/opencode/context_${claude_iteration}_${opencode_iteration}.md"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would build Kimi context"
  else
    "$LIB_DIR/build-kimi-context.sh" \
      --plan "$plan_file" \
      --task "$TASK_FILE" \
      --codebase "$CODEBASE_FILE" \
      --iteration "$opencode_iteration" \
      --history "$LOG_DIR/iterations" \
      --output "$context_file"
  fi

  # Run OpenCode
  local output_file="$LOG_DIR/opencode/iter_${claude_iteration}_${opencode_iteration}.json"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would run OpenCode for implementation"
    echo '{"status": "mock"}' > "$output_file"
  else
    "$LIB_DIR/opencode.sh" \
      --context "$context_file" \
      --workdir "$WORKTREE_PATH" \
      --output "$output_file" \
      ${QUIET:+"-q"} || {
        log_warning "OpenCode returned non-zero exit code"
      }
  fi

  update_state_num "opencode_iterations" "$opencode_iteration"

  # Capture the implementation diff
  if [[ "$DRY_RUN" != "true" && -d "$WORKTREE_PATH" ]]; then
    cd "$WORKTREE_PATH"
    git diff "$BASE_BRANCH"...HEAD > "$LOG_DIR/opencode/diff_${claude_iteration}_${opencode_iteration}.txt" 2>/dev/null || true
  fi

  log_success "Implementation iteration complete"
}

# ==============================================================================
# PHASE 4: TESTING
# ==============================================================================
run_tests() {
  local claude_iteration=$1
  local opencode_iteration=$2
  log_step "Running tests..."

  update_state "phase" "testing"

  local test_output="$LOG_DIR/opencode/tests_${claude_iteration}_${opencode_iteration}.txt"

  if [[ "$AUTO_RUN_TESTS" != "true" ]]; then
    echo "Tests skipped (AUTO_RUN_TESTS=false)" > "$test_output"
    log_warning "Tests skipped"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would run tests"
    echo "Tests would run here" > "$test_output"
    return 0
  fi

  "$LIB_DIR/detect-tests.sh" "$WORKTREE_PATH" > "$test_output" 2>&1 || {
    log_warning "Some tests failed"
  }

  log_success "Tests complete"
}

# ==============================================================================
# PHASE 5: CODE REVIEW (Codex)
# ==============================================================================
run_codex_review() {
  local claude_iteration=$1
  local opencode_iteration=$2
  log_step "Running Codex (GPT-5.2-Codex) code review..."

  update_state "phase" "reviewing"

  ITER_DIR="$LOG_DIR/iterations/iter_$(printf '%03d' $claude_iteration)"

  # Build context for Codex
  local context_file="$LOG_DIR/codex/context_${claude_iteration}_${opencode_iteration}.md"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would build Codex context"
  else
    "$LIB_DIR/build-codex-context.sh" \
      --task "$TASK_FILE" \
      --plan "$ITER_DIR/claude_plan.md" \
      --worktree "$WORKTREE_PATH" \
      --base-branch "$BASE_BRANCH" \
      --test-results "$LOG_DIR/opencode/tests_${claude_iteration}_${opencode_iteration}.txt" \
      --output "$context_file" 2>/dev/null || true
  fi

  # Run Codex review
  local review_file="$LOG_DIR/codex/review_${claude_iteration}_${opencode_iteration}.json"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would run Codex review"
    echo '{"approved": false, "summary": "Mock review"}' > "$review_file"
  else
    "$LIB_DIR/codex.sh" \
      --context "$context_file" \
      --workdir "$WORKTREE_PATH" \
      --base "$BASE_BRANCH" \
      --output "$review_file" \
      ${QUIET:+"-q"} || {
        log_warning "Codex review returned non-zero"
      }
  fi

  # Copy to iteration directory for history
  cp "$review_file" "$ITER_DIR/codex_review.json"

  # Extract feedback for next iteration
  "$LIB_DIR/extract-feedback.sh" "$review_file" > "$ITER_DIR/codex_feedback.md" 2>/dev/null || true

  log_success "Review complete: $review_file"
}

# ==============================================================================
# CHECK APPROVAL
# ==============================================================================
check_approval() {
  local claude_iteration=$1
  local opencode_iteration=$2

  local review_file="$LOG_DIR/codex/review_${claude_iteration}_${opencode_iteration}.json"

  if [[ ! -f "$review_file" ]]; then
    return 1
  fi

  local result
  result=$("$LIB_DIR/codex-approval.sh" "$review_file" 2>/dev/null) || true

  if [[ "$result" == "approved" ]]; then
    log_success "Codex APPROVED the implementation!"
    return 0
  else
    local summary
    summary=$(jq -r '.summary // "No summary"' "$review_file" 2>/dev/null || echo "Unknown")
    log_warning "Codex REJECTED: $summary"
    return 1
  fi
}

# ==============================================================================
# CHECK IF STUCK
# ==============================================================================
check_stuck() {
  local result
  result=$("$LIB_DIR/stuck-detector.sh" "$LOG_DIR" 2>/dev/null) || true

  if [[ "$result" == "STUCK"* ]]; then
    log_warning "Stuck detected - escalating to Claude"
    return 0
  fi
  return 1
}

# ==============================================================================
# REFORMULATE CONTEXT FOR NEW CLAUDE ITERATION
# ==============================================================================
reformulate_context() {
  local iteration=$1
  log_step "Reformulating context for Claude iteration $((iteration + 1))..."

  update_state "phase" "reformulating"

  ITER_DIR="$LOG_DIR/iterations/iter_$(printf '%03d' $iteration)"

  local reformulated="$LOG_DIR/claude/reformulated_for_iter_$((iteration + 1)).md"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would reformulate context"
  else
    "$LIB_DIR/reformulate-context.sh" \
      --task "$TASK_FILE" \
      --plan "$ITER_DIR/claude_plan.md" \
      --codex-feedback "$ITER_DIR/codex_review.json" \
      --test-results "$LOG_DIR/opencode/tests_${iteration}_*.txt" \
      --history "$LOG_DIR/iterations" \
      --iteration "$iteration" \
      --output "$reformulated" \
      ${QUIET:+"-q"} || true
  fi

  log_success "Context reformulated"
}

# ==============================================================================
# SUCCESS: CREATE PR
# ==============================================================================
create_pr() {
  log_phase "SUCCESS: CREATING PULL REQUEST"

  update_state "phase" "creating_pr"
  update_state "status" "completed"

  # Generate PR title
  local pr_title
  pr_title=$("$LIB_DIR/generate-pr-title.sh" "$TASK_DESCRIPTION")
  log_step "PR Title: $pr_title"

  local claude_iters opencode_iters
  claude_iters=$(jq -r '.claude_iterations' "$STATE_FILE" 2>/dev/null || echo "?")
  opencode_iters=$(jq -r '.opencode_iterations' "$STATE_FILE" 2>/dev/null || echo "?")

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would commit and create PR"
    PR_URL="https://github.com/example/pr/123"
  else
    cd "$WORKTREE_PATH"

    # Commit changes
    log_step "Committing changes..."
    git add -A
    git commit -m "$(cat <<EOF
$pr_title

Task: $TASK_DESCRIPTION

Implementation Stats:
- Claude iterations: $claude_iters
- OpenCode iterations: $opencode_iters
- Status: Codex Approved

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
Co-Authored-By: Kimi K2.5 <noreply@moonshot.ai>
Co-Authored-By: Clawdbot <noreply@clawdbot.ai>
EOF
)" || log_warning "Commit failed (maybe no changes?)"

    # Push branch
    log_step "Pushing branch..."
    git push -u origin "$BRANCH_NAME" || {
      log_error "Failed to push branch"
      return 1
    }

    # Create PR
    log_step "Creating pull request..."
    PR_URL=$(gh pr create \
      --title "$pr_title" \
      --body "$(cat <<EOF
## Summary

$TASK_DESCRIPTION

## Implementation

This PR was automatically generated by **Clawdbot Intelligent Implementer**.

### Stats
- **Claude iterations**: $claude_iters (planning)
- **OpenCode iterations**: $opencode_iters (implementation)
- **Reviewer**: Codex (GPT-5.2-Codex)
- **Status**: Approved

### Files Changed
\`\`\`
$(git diff --stat "$BASE_BRANCH"...HEAD)
\`\`\`

---
Generated by [Clawdbot](https://github.com/clawdbot/clawdbot) Intelligent Implementer
EOF
)" --json url --jq '.url' 2>/dev/null) || {
      # Try without JSON output
      PR_URL=$(gh pr create \
        --title "$pr_title" \
        --body "Task: $TASK_DESCRIPTION - Generated by Clawdbot" 2>/dev/null | grep -oE 'https://github.com/[^ ]+') || {
          log_error "Failed to create PR"
          PR_URL="PR creation failed"
        }
    }
  fi

  log_success "PR Created: $PR_URL"

  # Update state with PR URL
  update_state "pr_url" "$PR_URL"

  # Send success notification
  send_notification "success" "$PR_URL"
}

# ==============================================================================
# FAILURE: GENERATE REPORT
# ==============================================================================
handle_failure() {
  log_phase "TASK FAILED"

  update_state "phase" "failed"
  update_state "status" "failed"

  # Generate failure report
  local report_file="$LOG_DIR/failure_report.md"
  "$LIB_DIR/generate-failure-report.sh" \
    --task "$TASK_DESCRIPTION" \
    --log-dir "$LOG_DIR" \
    --state-file "$STATE_FILE" \
    --output "$report_file"

  log_error "Task failed after maximum iterations"
  log_error "Failure report: $report_file"
  log_error "Worktree preserved at: $WORKTREE_PATH"
  log_error "Logs at: $LOG_DIR"

  # Send failure notification
  send_notification "failure" "$report_file"
}

# ==============================================================================
# NOTIFICATIONS
# ==============================================================================
send_notification() {
  local type="$1"
  local data="$2"

  # Check if any notification method is configured
  # Let notify.sh handle the actual channel selection
  if [[ -z "${NOTIFY_EMAIL_TO:-}" && \
        -z "${RESEND_API_KEY:-}" && \
        -z "${SENDGRID_API_KEY:-}" && \
        -z "${TWILIO_ACCOUNT_SID:-}" && \
        -z "${CALLMEBOT_APIKEY:-}" ]]; then
    log_warning "No notification method configured"
    return 0
  fi

  log_step "Sending $type notification..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would send $type notification"
    return 0
  fi

  "$LIB_DIR/notify.sh" "$type" "$TASK_DESCRIPTION" "$data" "$STATE_FILE" ${QUIET:+"-q"} || {
    log_warning "Failed to send notification"
  }
}

# ==============================================================================
# MAIN ORCHESTRATION LOOP
# ==============================================================================
main() {
  log ""
  log "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  log "${CYAN}║         CLAWDBOT INTELLIGENT IMPLEMENTER                         ║${NC}"
  log "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  log ""
  log "Task: $TASK_DESCRIPTION"
  log "Project: $PROJECT_PATH"
  log ""

  # Phase 1: Initialize
  initialize

  # Main loop
  local claude_iteration=1
  local total_opencode_iterations=0
  local approved=false

  while [[ $claude_iteration -le $MAX_CLAUDE_ITERATIONS ]]; do
    log_phase "CLAUDE ITERATION $claude_iteration of $MAX_CLAUDE_ITERATIONS"

    # Phase 2: Planning
    run_claude_planning $claude_iteration || {
      log_error "Planning failed"
      handle_failure
      exit 1
    }

    # Phase 3+4+5: Implementation loop
    local opencode_iteration=1
    local stuck=false

    while [[ $opencode_iteration -le $MAX_OPENCODE_ITERATIONS && $total_opencode_iterations -lt $MAX_OPENCODE_ITERATIONS ]]; do
      log ""
      log "${BLUE}--- OpenCode Iteration $opencode_iteration ---${NC}"

      # Implementation
      run_opencode_implementation $claude_iteration $opencode_iteration

      # Tests
      run_tests $claude_iteration $opencode_iteration

      # Review
      run_codex_review $claude_iteration $opencode_iteration

      # Check approval
      if check_approval $claude_iteration $opencode_iteration; then
        approved=true
        break
      fi

      # Check if stuck
      if check_stuck; then
        stuck=true
        log_warning "Implementation stuck - need new plan from Claude"
        break
      fi

      ((opencode_iteration++))
      ((total_opencode_iterations++))
    done

    if [[ "$approved" == "true" ]]; then
      break
    fi

    if [[ "$stuck" == "true" || $opencode_iteration -gt $MAX_OPENCODE_ITERATIONS ]]; then
      log_warning "Escalating to Claude for new plan..."
      reformulate_context $claude_iteration
    fi

    ((claude_iteration++))
  done

  # Result
  if [[ "$approved" == "true" ]]; then
    create_pr
    log ""
    log "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    log "${GREEN}  TASK COMPLETED SUCCESSFULLY!${NC}"
    log "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    log ""
    exit 0
  else
    handle_failure
    log ""
    log "${RED}═══════════════════════════════════════════════════════════════${NC}"
    log "${RED}  TASK FAILED - Maximum iterations reached${NC}"
    log "${RED}═══════════════════════════════════════════════════════════════${NC}"
    log ""
    exit 1
  fi
}

# ==============================================================================
# RUN
# ==============================================================================
main
