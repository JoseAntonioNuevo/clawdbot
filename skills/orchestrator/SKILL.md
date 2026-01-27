---
name: orchestrator
description: |
  Intelligent Implementer Orchestrator - Use this skill when asked to implement
  coding tasks, fix bugs, add features, or make code changes to a project.

  Workflow: Claude Code (Plan) → OpenCode/Kimi (Implement) → Codex (Review) → Loop

  Triggers: "implement", "fix", "build", "create feature", "add", "code task",
  "run task on", "work on project", "orchestrate", "start task"
metadata:
  clawdbot:
    primaryEnv: ZAI_API_KEY
    requiredEnv:
      - ZAI_API_KEY
      - MOONSHOT_API_KEY
    requiredCli:
      - opencode
      - codex
      - claude
---

# Intelligent Implementer Orchestrator

You are the master orchestrator (powered by GLM 4.7) for automated coding tasks.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CLAWDBOT (GLM 4.7)                               │
│                        Master Orchestrator                               │
│   Coordinates the workflow, maintains context, manages iterations        │
└─────────────────────────────────────┬───────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           WORKFLOW LOOP                                  │
│                                                                          │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐          │
│  │  CLAUDE CODE │ ───▶ │   OPENCODE   │ ───▶ │  CODEX CLI   │          │
│  │   Opus 4.5   │      │   Kimi K2.5  │      │ GPT-5.2-Codex│          │
│  │              │      │              │      │              │          │
│  │   PLANNER    │      │ IMPLEMENTER  │      │   REVIEWER   │          │
│  │              │      │              │      │              │          │
│  │ • Analyzes   │      │ • Executes   │      │ • Validates  │          │
│  │   codebase   │      │   the plan   │      │   code       │          │
│  │ • Creates    │      │ • Writes     │      │ • Finds      │          │
│  │   strategy   │      │   code       │      │   issues     │          │
│  │ • Revises    │      │ • Runs       │      │ • Approves   │          │
│  │   on failure │      │   tests      │      │   or rejects │          │
│  └──────────────┘      └──────────────┘      └──────┬───────┘          │
│         ▲                                           │                   │
│         │                                           ▼                   │
│         │                                    ┌─────────────┐           │
│         │                                    │  APPROVED?  │           │
│         │                                    └──────┬──────┘           │
│         │                                           │                   │
│         │  ┌────────────────────────────────────────┤                   │
│         │  │ NO: Full context passed back:          │ YES               │
│         │  │ • Original task                        │                   │
│         │  │ • All previous plans                   ▼                   │
│         │  │ • What Kimi implemented          ┌──────────┐             │
│         │  │ • Current codebase state         │ CREATE   │             │
│         │  │ • Codex feedback & issues        │   PR     │             │
│         │  │ • Test results                   └──────────┘             │
│         │  │ • Iteration history                    │                   │
│         └──┘                                        ▼                   │
│                                               ┌──────────┐             │
│                                               │ NOTIFY   │             │
│                                               │ SUCCESS  │             │
│                                               └──────────┘             │
└─────────────────────────────────────────────────────────────────────────┘
```

## Context Management (CRITICAL)

Every agent MUST receive full context. The orchestrator maintains a cumulative context file that grows with each iteration.

### Context Structure

```
logs/<project>/<task-id>/
├── state.json                    # Current state and metadata
├── context/
│   ├── original_task.md          # Original task description
│   ├── codebase_summary.md       # Initial codebase analysis
│   └── cumulative_context.md     # Growing context file (THE KEY FILE)
├── iterations/
│   ├── iter_001/
│   │   ├── claude_plan.md        # Plan created by Claude
│   │   ├── kimi_implementation.md # What Kimi did (diff + explanation)
│   │   ├── codex_review.json     # Codex review results
│   │   └── codex_feedback.md     # Human-readable feedback
│   ├── iter_002/
│   │   ├── claude_revised_plan.md
│   │   ├── kimi_implementation.md
│   │   ├── codex_review.json
│   │   └── codex_feedback.md
│   └── ...
└── final/
    ├── success_report.md         # Or failure_report.md
    └── pr_description.md
```

### Cumulative Context Format

The `cumulative_context.md` file is rebuilt after each iteration:

```markdown
# Task Context - Iteration N

## Original Task
<original task description>

## Codebase Overview
<summary of relevant files, architecture, patterns>

## Iteration History

### Iteration 1
#### Plan (Claude Code)
<plan details>

#### Implementation (Kimi K2.5)
<what was implemented, files changed, approach taken>

#### Review (Codex)
<review results, issues found, feedback>

### Iteration 2
#### Plan (Claude Code) - REVISION
<revised plan addressing previous issues>
<why the previous approach didn't work>
<new strategy>

#### Implementation (Kimi K2.5)
...

#### Review (Codex)
...

## Current State
- Files modified: <list>
- Tests status: <pass/fail details>
- Outstanding issues: <from latest Codex review>

## What Needs to Happen Next
<clear direction for the next agent>
```

---

## Prerequisites

1. Environment file: `~/.clawdbot-orchestrator.env`
   - `ZAI_API_KEY` - For Clawdbot orchestrator (GLM 4.7)
   - `MOONSHOT_API_KEY` - For OpenCode/Kimi K2.5

2. CLI tools authenticated:
   - `opencode` → `opencode auth login` (uses Moonshot/Kimi)
   - `codex` → `codex auth login`
   - `claude` → authenticates on first run
   - `gh` → `gh auth login`

---

## Workflow Steps

### Step 1: Task Intake & Setup

```bash
source ~/.clawdbot-orchestrator.env

# Validate project
cd "$PROJECT_PATH"
git rev-parse --git-dir > /dev/null 2>&1 || exit 1

# Generate identifiers
TASK_ID="$(date +%Y%m%d-%H%M%S)-$(echo "$TASK" | md5sum | cut -c1-8)"
BRANCH_NAME="ai/<descriptive-name>"  # YOU decide based on task

# Create worktree
WORKTREE_PATH="$WORKTREE_BASE/$PROJECT_NAME/$TASK_ID"
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"

# Initialize context structure
LOG_DIR="$CLAWDBOT_ROOT/logs/$PROJECT_NAME/$TASK_ID"
mkdir -p "$LOG_DIR"/{context,iterations,final}

# Save original task
echo "$TASK_DESCRIPTION" > "$LOG_DIR/context/original_task.md"

# Build initial codebase summary
./lib/analyze-codebase.sh "$WORKTREE_PATH" > "$LOG_DIR/context/codebase_summary.md"

# Initialize state
cat > "$LOG_DIR/state.json" << EOF
{
  "task_id": "$TASK_ID",
  "project": "$PROJECT_PATH",
  "task": "$TASK_DESCRIPTION",
  "branch": "$BRANCH_NAME",
  "worktree": "$WORKTREE_PATH",
  "status": "in_progress",
  "current_iteration": 0,
  "max_iterations": 10,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

### Step 2: Main Loop

```bash
MAX_ITERATIONS=10

for ITERATION in $(seq 1 $MAX_ITERATIONS); do
  echo "═══════════════════════════════════════════════════════════"
  echo "  ITERATION $ITERATION / $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════════"

  ITER_DIR="$LOG_DIR/iterations/iter_$(printf '%03d' $ITERATION)"
  mkdir -p "$ITER_DIR"

  # ─────────────────────────────────────────────────────────────
  # PHASE 1: CLAUDE CODE - CREATE/REVISE PLAN
  # ─────────────────────────────────────────────────────────────

  echo "▶ Phase 1: Claude Code (Opus 4.5) - Planning..."

  # Build full context for Claude
  ./lib/build-claude-context.sh \
    --task "$LOG_DIR/context/original_task.md" \
    --codebase "$LOG_DIR/context/codebase_summary.md" \
    --history "$LOG_DIR/iterations" \
    --worktree "$WORKTREE_PATH" \
    --iteration "$ITERATION" \
    --output "$ITER_DIR/claude_input_context.md"

  # Run Claude Code for planning
  ./lib/claude-code.sh \
    --mode plan \
    --context "$ITER_DIR/claude_input_context.md" \
    --workdir "$WORKTREE_PATH" \
    --output "$ITER_DIR/claude_plan.md"

  # ─────────────────────────────────────────────────────────────
  # PHASE 2: OPENCODE/KIMI - IMPLEMENT THE PLAN
  # ─────────────────────────────────────────────────────────────

  echo "▶ Phase 2: OpenCode (Kimi K2.5) - Implementing..."

  # Build context for Kimi (includes the plan)
  ./lib/build-kimi-context.sh \
    --plan "$ITER_DIR/claude_plan.md" \
    --task "$LOG_DIR/context/original_task.md" \
    --codebase "$LOG_DIR/context/codebase_summary.md" \
    --history "$LOG_DIR/iterations" \
    --iteration "$ITERATION" \
    --output "$ITER_DIR/kimi_input_context.md"

  # Run OpenCode with Kimi K2.5
  ./lib/opencode.sh \
    --context "$ITER_DIR/kimi_input_context.md" \
    --workdir "$WORKTREE_PATH" \
    --output "$ITER_DIR/kimi_output.json"

  # Capture what Kimi did
  ./lib/capture-implementation.sh \
    --worktree "$WORKTREE_PATH" \
    --base "$BASE_BRANCH" \
    --output "$ITER_DIR/kimi_implementation.md"

  # Run tests
  ./lib/detect-tests.sh "$WORKTREE_PATH" > "$ITER_DIR/test_results.txt" 2>&1 || true

  # ─────────────────────────────────────────────────────────────
  # PHASE 3: CODEX - REVIEW THE IMPLEMENTATION
  # ─────────────────────────────────────────────────────────────

  echo "▶ Phase 3: Codex (GPT-5.2-Codex) - Reviewing..."

  # Build context for Codex
  ./lib/build-codex-context.sh \
    --task "$LOG_DIR/context/original_task.md" \
    --plan "$ITER_DIR/claude_plan.md" \
    --implementation "$ITER_DIR/kimi_implementation.md" \
    --tests "$ITER_DIR/test_results.txt" \
    --worktree "$WORKTREE_PATH" \
    --base "$BASE_BRANCH" \
    --output "$ITER_DIR/codex_input_context.md"

  # Run Codex review
  ./lib/codex.sh \
    --context "$ITER_DIR/codex_input_context.md" \
    --workdir "$WORKTREE_PATH" \
    --base "$BASE_BRANCH" \
    --output "$ITER_DIR/codex_review.json"

  # Extract human-readable feedback
  ./lib/extract-feedback.sh "$ITER_DIR/codex_review.json" > "$ITER_DIR/codex_feedback.md"

  # ─────────────────────────────────────────────────────────────
  # PHASE 4: CHECK APPROVAL
  # ─────────────────────────────────────────────────────────────

  APPROVAL=$(./lib/codex-approval.sh "$ITER_DIR/codex_review.json")

  if [[ "$APPROVAL" == "approved" ]]; then
    echo "✅ APPROVED at iteration $ITERATION"

    # Update cumulative context with success
    ./lib/update-cumulative-context.sh \
      --log-dir "$LOG_DIR" \
      --iteration "$ITERATION" \
      --status "approved"

    # Go to PR creation
    break
  fi

  echo "❌ Not approved. Preparing context for next iteration..."

  # Update cumulative context with failure details
  ./lib/update-cumulative-context.sh \
    --log-dir "$LOG_DIR" \
    --iteration "$ITERATION" \
    --status "rejected" \
    --feedback "$ITER_DIR/codex_feedback.md"

  # Update state
  jq ".current_iteration = $ITERATION" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" \
    && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"

done
```

### Step 3: Create PR (on success)

```bash
if [[ "$APPROVAL" == "approved" ]]; then
  cd "$WORKTREE_PATH"

  # Stage and commit
  git add -A
  git commit -m "$(cat <<EOF
$TASK_DESCRIPTION

Implemented via Clawdbot Intelligent Implementer
- Planner: Claude Code (Opus 4.5)
- Implementer: OpenCode (Kimi K2.5)
- Reviewer: Codex (GPT-5.2-Codex)
- Iterations: $ITERATION

Co-Authored-By: Clawdbot <noreply@clawd.bot>
EOF
)"

  # Push and create PR
  git push -u origin "$BRANCH_NAME"

  # Generate PR description from context
  ./lib/generate-pr-description.sh \
    --log-dir "$LOG_DIR" \
    --output "$LOG_DIR/final/pr_description.md"

  PR_URL=$(gh pr create \
    --title "<Generated title based on task>" \
    --body "$(cat "$LOG_DIR/final/pr_description.md")" \
    --base "$BASE_BRANCH")

  # Update state and notify
  jq ".status = \"completed\" | .pr_url = \"$PR_URL\"" "$LOG_DIR/state.json" > "$LOG_DIR/state.tmp" \
    && mv "$LOG_DIR/state.tmp" "$LOG_DIR/state.json"

  ./lib/notify.sh success "$TASK_DESCRIPTION" "$PR_URL" "$LOG_DIR/state.json"

else
  # Max iterations reached without approval
  ./lib/generate-failure-report.sh --log-dir "$LOG_DIR" --output "$LOG_DIR/final/failure_report.md"
  ./lib/notify.sh failure "$TASK_DESCRIPTION" "$LOG_DIR/final/failure_report.md" "$LOG_DIR/state.json"
fi
```

---

## Context Building Scripts

### build-claude-context.sh

Builds the full context for Claude Code to create or revise a plan:

```markdown
# Context for Claude Code - Iteration {N}

## Your Role
You are the PLANNER. Analyze the codebase and create a detailed implementation plan.
{If iteration > 1: You are REVISING the plan based on what didn't work.}

## Original Task
{content of original_task.md}

## Codebase Overview
{content of codebase_summary.md}

## Current State of the Code
{git diff showing current changes}
{list of modified files}

{If iteration > 1:}
## Previous Iterations

### Iteration 1
**Plan you created:**
{previous plan}

**What Kimi implemented:**
{implementation details}

**Why Codex rejected it:**
{feedback and issues}

### Iteration 2
...

## What You Need To Do Now
1. Analyze what went wrong in previous attempts
2. Consider the Codex feedback carefully
3. Create a REVISED plan that addresses all issues
4. Be specific about what needs to change

## Output Format
Provide a detailed plan with:
- Step-by-step implementation instructions
- Files to create/modify
- Code snippets or pseudocode
- Expected test cases
- Potential pitfalls to avoid
```

### build-kimi-context.sh

Builds the context for OpenCode/Kimi to implement the plan:

```markdown
# Context for Kimi K2.5 - Implementation

## Your Role
You are the IMPLEMENTER. Execute the plan created by Claude Code.

## The Plan to Implement
{content of claude_plan.md}

## Original Task
{content of original_task.md}

## Codebase Overview
{content of codebase_summary.md}

{If iteration > 1:}
## Previous Attempts
You tried before and it didn't pass review. Here's what happened:

### What you did:
{previous implementation}

### Why it was rejected:
{Codex feedback}

### The new plan addresses this by:
{relevant parts of new plan}

## Instructions
1. Follow the plan step by step
2. Write clean, working code
3. Run tests after implementation
4. Make sure all plan items are addressed
```

### build-codex-context.sh

Builds the context for Codex to review:

```markdown
# Code Review Request

## Original Task
{content of original_task.md}

## Implementation Plan
{content of claude_plan.md}

## What Was Implemented
{content of kimi_implementation.md}

## Code Changes
{git diff}

## Test Results
{content of test_results.txt}

## Review Criteria
1. Does the implementation match the plan?
2. Does it fulfill the original task?
3. Is the code correct and complete?
4. Do all tests pass?
5. Are there any bugs or issues?
6. Is the code clean and maintainable?

## Your Response
Provide structured JSON with:
- approved: boolean
- issues: array of {severity, file, line, message, suggestion}
- summary: overall assessment
```

---

## Key Principles

1. **Context is King**: Every agent gets the FULL picture - task, history, code, feedback
2. **Nothing is Lost**: Every iteration is logged and available for analysis
3. **Clear Handoffs**: Each agent knows exactly what it needs to do
4. **Cumulative Learning**: Later iterations build on earlier ones
5. **Fail Forward**: Each failure provides information for the next attempt
