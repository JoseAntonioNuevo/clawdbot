---
name: orchestrator
description: |
  Intelligent Implementer Orchestrator - Use this skill when asked to implement
  coding tasks, fix bugs, add features, or make code changes to a project.
  This skill orchestrates OpenCode (GLM 4.7), Codex review (GPT-5.2-Codex),
  and Claude Code fallback (Opus 4.5) to complete tasks with code review.

  Triggers: "implement", "fix", "build", "create feature", "add", "code task",
  "run task on", "work on project", "orchestrate", "start task"
metadata:
  clawdbot:
    primaryEnv: ZAI_API_KEY
    requiredEnv:
      - ZAI_API_KEY
    requiredCli:
      - opencode
      - codex
      - claude
---

# Intelligent Implementer Orchestrator

You are the master orchestrator for automated coding tasks. When a user gives you a task to implement on a project, follow this workflow precisely.

## Prerequisites

Before starting, ensure:
1. Environment file exists: `~/.clawdbot-orchestrator.env` with ZAI_API_KEY
2. CLI tools are installed and authenticated:
   - `opencode` (run: `opencode auth login`)
   - `codex` (run: `codex auth login`)
   - `claude` (authenticates on first run)
   - `gh` (run: `gh auth login`)
   - `git`

Load environment:
```bash
source ~/.clawdbot-orchestrator.env
```

## Workflow Overview

```
USER REQUEST → Parse Task → Create Worktree → OpenCode Loop (max 80)
                                                    ↓
                                              Codex Review
                                                    ↓
                                         Approved? → Create PR → Notify Success
                                                    ↓ No
                                              Stuck? → Claude Loop (max 10)
                                                    ↓
                                         Approved? → Create PR → Notify Success
                                                    ↓ No (10 iterations)
                                              Notify Failure
```

---

## Step 1: Task Intake & Validation

### 1.1 Parse the Request

Extract from user's natural language request:
- **Project path**: Absolute path to the git repository
- **Task description**: What needs to be implemented/fixed
- **Base branch**: (optional, default from config or 'main')

### 1.2 Validate the Project

```bash
PROJECT_PATH="<extracted_project_path>"

# Navigate to project
cd "$PROJECT_PATH" || {
  echo "ERROR: Project path does not exist: $PROJECT_PATH"
  exit 1
}

# Verify it's a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository: $PROJECT_PATH"
  exit 1
fi

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
  echo "WARNING: Uncommitted changes detected in $PROJECT_PATH"
  # Options:
  # 1. Ask user to stash/commit
  # 2. Continue anyway (changes stay in main repo, not in worktree)
  # 3. Abort
fi

# Get default branch if not specified
BASE_BRANCH="${BASE_BRANCH:-$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')}"
BASE_BRANCH="${BASE_BRANCH:-main}"
```

### 1.3 Generate Identifiers

```bash
# Generate task ID: YYYYMMDD-HHMMSS-<8-char-hash>
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TASK_HASH=$(echo "$TASK_DESCRIPTION" | md5sum | cut -c1-8)
TASK_ID="${TIMESTAMP}-${TASK_HASH}"

# Generate branch name based on task (YOU decide this intelligently)
# Examples:
#   "fix login timeout bug" → ai/fix-login-timeout
#   "add user authentication" → ai/add-user-auth
#   "refactor database layer" → ai/refactor-db-layer
BRANCH_NAME="ai/<your-chosen-descriptive-name>"
```

---

## Step 2: Create Isolated Workspace

```bash
# Set paths
PROJECT_NAME=$(basename "$PROJECT_PATH")
WORKTREE_BASE="${WORKTREE_BASE:-$HOME/ai-worktrees}"
WORKTREE_PATH="$WORKTREE_BASE/$PROJECT_NAME/$TASK_ID"
CLAWDBOT_ROOT="/Users/jose/Documents/clawdbot"
LOG_DIR="$CLAWDBOT_ROOT/logs/$PROJECT_NAME/$TASK_ID"

# Create directories
mkdir -p "$(dirname "$WORKTREE_PATH")"
mkdir -p "$LOG_DIR"/{opencode,codex,claude}

# Create worktree with new branch
cd "$PROJECT_PATH"
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "origin/$BASE_BRANCH" 2>/dev/null || \
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"

# Initialize state file
cat > "$LOG_DIR/state.json" << EOF
{
  "task_id": "$TASK_ID",
  "project": "$PROJECT_PATH",
  "project_name": "$PROJECT_NAME",
  "task": "$TASK_DESCRIPTION",
  "branch": "$BRANCH_NAME",
  "base_branch": "$BASE_BRANCH",
  "worktree": "$WORKTREE_PATH",
  "log_dir": "$LOG_DIR",
  "status": "in_progress",
  "implementer": "opencode",
  "opencode_iterations": 0,
  "claude_iterations": 0,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "completed_at": null,
  "pr_url": null,
  "error": null
}
EOF

echo "Created worktree: $WORKTREE_PATH"
echo "Branch: $BRANCH_NAME"
echo "Logs: $LOG_DIR"
```

---

## Step 3: OpenCode Implementation Loop

Run up to 80 iterations of OpenCode + Codex review.

```bash
MAX_OPENCODE=${MAX_OPENCODE_ITERATIONS:-80}

for ITERATION in $(seq 1 $MAX_OPENCODE); do
  echo "=== OpenCode Iteration $ITERATION/$MAX_OPENCODE ==="

  # Build prompt for OpenCode
  PROMPT="TASK: $TASK_DESCRIPTION

WORKING DIRECTORY: $WORKTREE_PATH

IMPORTANT: Make changes to implement the task. After making changes, ensure the code compiles/runs correctly."

  # Add previous Codex feedback if iteration > 1
  if [[ $ITERATION -gt 1 && -f "$LOG_DIR/codex_feedback.md" ]]; then
    PROMPT="$PROMPT

PREVIOUS REVIEW FEEDBACK (must address):
$(cat "$LOG_DIR/codex_feedback.md")

Please address ALL the issues listed above."
  fi

  # Run OpenCode
  cd "$WORKTREE_PATH"
  ./lib/opencode.sh "$PROMPT" "$LOG_DIR/opencode/iter_${ITERATION}.json"

  # Capture diff
  git diff "$BASE_BRANCH"...HEAD > "$LOG_DIR/opencode/diff_${ITERATION}.txt" 2>/dev/null || true
  git diff --stat "$BASE_BRANCH"...HEAD > "$LOG_DIR/opencode/diff_stat_${ITERATION}.txt" 2>/dev/null || true

  # Run tests (if enabled)
  if [[ "${AUTO_RUN_TESTS:-true}" == "true" ]]; then
    ./lib/detect-tests.sh "$WORKTREE_PATH" > "$LOG_DIR/opencode/tests_${ITERATION}.txt" 2>&1 || true
  fi

  # Run Codex review
  ./lib/codex.sh "$WORKTREE_PATH" "$BASE_BRANCH" "$LOG_DIR/codex/review_${ITERATION}.json"

  # Check if approved
  APPROVAL=$(./lib/codex-approval.sh "$LOG_DIR/codex/review_${ITERATION}.json")

  if [[ "$APPROVAL" == "approved" ]]; then
    echo "✓ Codex approved at iteration $ITERATION"
    # Update state
    jq ".opencode_iterations = $ITERATION | .status = \"approved\"" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"
    # Go to Step 5: Create PR
    break
  fi

  # Extract feedback for next iteration
  ./lib/extract-feedback.sh "$LOG_DIR/codex/review_${ITERATION}.json" > "$LOG_DIR/codex_feedback.md"

  # Check if stuck
  STUCK_RESULT=$(./lib/stuck-detector.sh "$LOG_DIR")

  if [[ "$STUCK_RESULT" == "STUCK"* ]]; then
    echo "⚠ Detected stuck state after $ITERATION iterations"
    echo "$STUCK_RESULT" > "$LOG_DIR/stuck_reason.md"
    # Update state and go to Step 4: Escalate to Claude
    jq ".opencode_iterations = $ITERATION | .status = \"stuck\"" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"
    break
  fi

  # Update iteration count in state
  jq ".opencode_iterations = $ITERATION" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"
done

# If reached max iterations without approval
if [[ $ITERATION -eq $MAX_OPENCODE && "$APPROVAL" != "approved" ]]; then
  echo "⚠ Reached maximum OpenCode iterations ($MAX_OPENCODE)"
  jq ".status = \"max_iterations\"" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"
fi
```

---

## Step 4: Escalate to Claude Code

When OpenCode is stuck or reaches max iterations, escalate to Claude Code.

```bash
# Build comprehensive context
./lib/context-builder.sh \
  --project "$PROJECT_PATH" \
  --worktree "$WORKTREE_PATH" \
  --task "$TASK_DESCRIPTION" \
  --log-dir "$LOG_DIR" \
  --output "$LOG_DIR/full_context.md"

MAX_CLAUDE=${MAX_CLAUDE_ITERATIONS:-10}

for CLAUDE_ITER in $(seq 1 $MAX_CLAUDE); do
  echo "=== Claude Code Iteration $CLAUDE_ITER/$MAX_CLAUDE ==="

  CONTEXT=$(cat "$LOG_DIR/full_context.md")

  # Add current feedback
  if [[ -f "$LOG_DIR/codex_feedback.md" ]]; then
    CONTEXT="$CONTEXT

CURRENT BLOCKING ISSUES:
$(cat "$LOG_DIR/codex_feedback.md")"
  fi

  # Run Claude Code
  cd "$WORKTREE_PATH"
  ./lib/claude-code.sh "$CONTEXT" "$LOG_DIR/claude/iter_${CLAUDE_ITER}.json"

  # Run Codex review
  ./lib/codex.sh "$WORKTREE_PATH" "$BASE_BRANCH" "$LOG_DIR/codex/claude_review_${CLAUDE_ITER}.json"

  # Check if approved
  APPROVAL=$(./lib/codex-approval.sh "$LOG_DIR/codex/claude_review_${CLAUDE_ITER}.json")

  if [[ "$APPROVAL" == "approved" ]]; then
    echo "✓ Codex approved Claude's changes at iteration $CLAUDE_ITER"
    jq ".claude_iterations = $CLAUDE_ITER | .status = \"approved\" | .implementer = \"claude\"" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"
    break
  fi

  # Extract feedback
  ./lib/extract-feedback.sh "$LOG_DIR/codex/claude_review_${CLAUDE_ITER}.json" > "$LOG_DIR/codex_feedback.md"

  # Update state
  jq ".claude_iterations = $CLAUDE_ITER" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"
done

# If Claude also failed
if [[ $CLAUDE_ITER -eq $MAX_CLAUDE && "$APPROVAL" != "approved" ]]; then
  echo "✗ Claude Code also failed after $MAX_CLAUDE iterations"
  jq ".status = \"failed\"" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"
  # Go to Step 6: Failure notification
fi
```

---

## Step 5: Success - Create PR

```bash
cd "$WORKTREE_PATH"

# Stage and commit all changes
git add -A

# Generate commit message based on task and changes
COMMIT_MSG="$TASK_DESCRIPTION

Implemented by Clawdbot Intelligent Implementer
- Primary: OpenCode (GLM 4.7)
- Reviewer: Codex (GPT-5.2-Codex)
$(if [[ "$(jq -r '.implementer' "$LOG_DIR/state.json")" == "claude" ]]; then echo "- Fallback: Claude Code (Opus 4.5)"; fi)

Co-Authored-By: Clawdbot <noreply@clawd.bot>"

git commit -m "$COMMIT_MSG"

# Push branch
git push -u origin "$BRANCH_NAME"

# Generate PR title and body
PR_TITLE="<Generated based on task - imperative, under 70 chars>"
# Examples: "Fix login timeout issue", "Add JWT authentication", "Refactor database queries"

# Create PR
PR_URL=$(gh pr create \
  --title "$PR_TITLE" \
  --body "$(cat <<'PRBODY'
## Summary
<!-- 1-3 bullet points of key changes -->

## Task
> $TASK_DESCRIPTION

## Implementation Details
- **Implementer**: $(jq -r '.implementer' "$LOG_DIR/state.json" | sed 's/opencode/OpenCode (GLM 4.7)/; s/claude/Claude Code (Opus 4.5)/')
- **Iterations**: $(jq -r '.opencode_iterations' "$LOG_DIR/state.json") (OpenCode) + $(jq -r '.claude_iterations' "$LOG_DIR/state.json") (Claude)
- **Reviewer**: Codex (GPT-5.2-Codex)

## Test Results
<!-- Auto-detected test output -->

## Codex Review
Status: ✅ Approved

---
🦞 Generated by [Clawdbot Intelligent Implementer](https://github.com/clawdbot/clawdbot)
PRBODY
)" \
  --base "$BASE_BRANCH" \
  --head "$BRANCH_NAME" \
  2>/dev/null)

# Update state with PR URL
jq ".pr_url = \"$PR_URL\" | .status = \"completed\" | .completed_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"

echo "✓ PR created: $PR_URL"

# Send success notification
./lib/notify.sh success "$TASK_DESCRIPTION" "$PR_URL" "$LOG_DIR/state.json"
```

---

## Step 6: Failure - Notify User

```bash
# Generate failure report
cat > "$LOG_DIR/failure_report.md" << EOF
# Task Failed: $TASK_DESCRIPTION

## Summary
- OpenCode iterations: $(jq -r '.opencode_iterations' "$LOG_DIR/state.json")
- Claude Code iterations: $(jq -r '.claude_iterations' "$LOG_DIR/state.json")
- Final status: $(jq -r '.status' "$LOG_DIR/state.json")

## Last Blocking Issues
$(cat "$LOG_DIR/codex_feedback.md" 2>/dev/null || echo "No feedback available")

## Stuck Reason
$(cat "$LOG_DIR/stuck_reason.md" 2>/dev/null || echo "Max iterations reached")

## Files Modified
$(cd "$WORKTREE_PATH" && git diff --stat "$BASE_BRANCH"...HEAD 2>/dev/null || echo "No changes")

## Suggested Next Steps
1. Review the code at: $WORKTREE_PATH
2. Check logs at: $LOG_DIR
3. Manually address the blocking issues
4. Re-run the task or complete manually

## Resources
- Worktree: $WORKTREE_PATH
- Branch: $BRANCH_NAME
- Logs: $LOG_DIR
EOF

# Update state
jq ".status = \"failed\" | .completed_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"

# Send failure notification
./lib/notify.sh failure "$TASK_DESCRIPTION" "$LOG_DIR/failure_report.md" "$LOG_DIR/state.json"

echo "✗ Task failed. Report: $LOG_DIR/failure_report.md"
```

---

## Helper Scripts Reference

| Script | Purpose |
|--------|---------|
| `lib/worktree.sh` | Git worktree management |
| `lib/opencode.sh` | Run OpenCode with proper arguments |
| `lib/codex.sh` | Run Codex review |
| `lib/claude-code.sh` | Run Claude Code |
| `lib/stuck-detector.sh` | Detect if implementation is stuck |
| `lib/context-builder.sh` | Build context for Claude escalation |
| `lib/detect-tests.sh` | Auto-detect and run tests |
| `lib/codex-approval.sh` | Parse Codex approval status |
| `lib/extract-feedback.sh` | Extract feedback from Codex review |
| `lib/notify.sh` | Send notifications |

---

## State Machine

```
┌─────────┐
│ pending │
└────┬────┘
     │ start
     ▼
┌──────────────┐
│ in_progress  │
└──────┬───────┘
       │
       ├── opencode loop ──┬── approved ───┐
       │                   │               │
       │                   └── stuck ──────┤
       │                                   │
       │                                   ▼
       │                         ┌─────────────────┐
       │                         │ claude_fallback │
       │                         └────────┬────────┘
       │                                  │
       │               ┌── approved ──────┤
       │               │                  │
       │               │      ┌── failed ─┘
       │               │      │
       ▼               ▼      ▼
┌───────────┐    ┌──────────┐
│ completed │    │  failed  │
└───────────┘    └──────────┘
```
