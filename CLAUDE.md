# Clawdbot - Intelligent Implementer

Clawdbot is an AI-powered coding orchestrator that automates software development tasks using multiple AI models working together.

## Quick Start

```bash
# Quick implementation command
implement megrowth "fix the speech-to-text streaming"
implement landing "add contact form"
implement . "add dark mode"

# General Clawdbot command with isolated sessions
cbot megrowth "any message"
cbot -v megrowth "with verbose output"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              GPT-5.2 ORCHESTRATOR (95% IFEval)                  │
│                                                                  │
│  Reads SKILL.md → Coordinates agents → Never writes code        │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Claude Code  │    │  Kimi K2.5   │    │   GLM-4.7    │
│ (Opus 4.5)   │    │              │    │              │
│              │    │ Implementation│   │ Tests & Docs │
│ Research &   │    │ (code only)  │    │              │
│ Planning     │    │              │    │              │
└──────────────┘    └──────────────┘    └──────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
                    ┌──────────────┐
                    │    Codex     │
                    │ Code Review  │
                    └──────────────┘
```

## Agent Roles

| Agent | Model | Task | Why |
|-------|-------|------|-----|
| Orchestrator | GPT-5.2 | Coordinate workflow | 95% instruction following |
| Research & Planning | Claude Opus 4.5 | Analyze codebase, WebSearch best practices 2026, create plan | Native web search |
| Implementation | Kimi K2.5 | Write code only | 76.8% SWE-bench |
| Tests & Docs | GLM-4.7 | Write tests, JSDoc, docstrings | 84.9% LiveCodeBench |
| Code Review | Codex (GPT-5.2) | Review against plan, approve/reject | Structured JSON output |

## Fallback Strategy

If Kimi K2.5 fails (rate limit, error, or no progress), Claude Code takes over implementation:

```
Kimi K2.5 fails (rate limit/error/timeout)
    ↓
Claude Code implements (using the plan from Step 1)
    ↓
Continue to GLM-4.7 (tests) as normal
```

**Rate limit indicators:**
- Output contains "rate limit", "429", "quota exceeded"
- Status file shows `ERROR:N`
- No file changes after 30+ minutes

## Branch Naming Conventions

Branches follow standard Git conventions based on task type:

| Task Type | Prefix | Example |
|-----------|--------|---------|
| New feature | `feature/` | `feature/add-dark-mode` |
| Bug fix | `fix/` | `fix/login-timeout` |
| Urgent fix | `hotfix/` | `hotfix/security-patch` |
| Refactor | `refactor/` | `refactor/auth-module` |
| Documentation | `docs/` | `docs/api-reference` |
| Performance | `perf/` | `perf/optimize-queries` |

## Workflow

1. **User requests task** → `implement megrowth "fix bug X"`
2. **GPT-5.2 creates worktree** → Branch: `fix/bug-x` (convention-based)
3. **Claude Code researches** → Analyzes codebase, WebSearch for 2026 best practices
4. **Claude Code plans** → Detailed implementation plan
5. **Kimi K2.5 implements** → Code only, following the plan
6. **GLM-4.7 tests & docs** → Write tests, JSDoc/docstrings
7. **Codex reviews** → Approve or provide feedback
8. **Loop if needed** → Back to Kimi (code) or GLM (tests)
9. **Build verification** → `lint`, `test`, `build` must ALL pass
10. **Loop if build fails** → Kimi (lint/build) or GLM (tests)
11. **GPT-5.2 creates PR** → Clean, human-like (no AI mentions)
12. **GPT-5.2 notifies** → Email with full agent breakdown

## CLI Commands

### `implement` - Quick Implementation

```bash
implement <project> "task description"
```

Examples:
```bash
implement megrowth "fix the speech-to-text streaming"
implement /Users/jose/my-api "add /health endpoint"
implement . "refactor auth module"
```

Features:
- Automatically uses intelligent-implementer skill
- Isolated session per project (no context mixing)
- Verbose output enabled by default

### `cbot` - General Clawdbot

```bash
cbot <project> "message"
cbot -v <project> "message"  # verbose
```

Examples:
```bash
cbot megrowth "analyze the codebase structure"
cbot landing "what files handle routing?"
cbot -v clawdbot "review the SKILL.md"
```

Features:
- Isolated session per project
- Optional verbose flag
- Resolves project paths automatically

### Project Path Resolution

Both commands resolve paths in this order:
1. Exact path if directory exists
2. `/Users/jose/Documents/<name>`
3. `/Users/jose/Documents/growth/<name>`
4. `/Users/jose/<name>`

## Project Structure

```
clawdbot/
├── CLAUDE.md                           # This file
├── GUIDE.md                            # User guide
├── clawdbot.json                       # Project config
├── config/
│   └── env.template                    # Environment template
└── skills/
    └── intelligent-implementer/
        ├── SKILL.md                    # Orchestrator instructions
        └── lib/
            ├── worktree.sh             # Git worktree helper
            ├── send-resend-email.sh    # Email via Resend
            ├── run-claude.sh           # Claude CLI wrapper (with timeout)
            ├── run-kimi.sh             # Kimi CLI wrapper (with timeout)
            ├── run-opencode.sh         # OpenCode CLI wrapper (with timeout)
            ├── safe-kill.sh            # Prevents premature agent kills
            ├── checkpoint.sh           # Checkpoint save/load for resume
            └── retry-with-backoff.sh   # Retry wrapper for transient errors
```

## Key Files

### `skills/intelligent-implementer/SKILL.md`

The orchestrator instructions (~1000 lines). Clawdbot reads this and executes autonomously.

**Steps:**
- Step 0: Create worktree
- Step 1: Claude Code research & planning (WebSearch + Supabase MCP if applicable)
- Step 2: Kimi K2.5 implementation (code + migrations, no tests)
- Step 3: GLM-4.7 tests & documentation
- Step 4: Codex code review
- Step 5: Build verification (lint, test, build)
- Step 6: Create PR + Send notification

**Critical Rules (enforced in SKILL.md):**

1. **Orchestrator NEVER writes code** - No `edit` or `write` tools
2. **ALL 4 agents are MANDATORY** - Cannot skip any step:
   ```
   Claude Code → Kimi K2.5 → GLM-4.7 → Codex → Build → PR
   ```
   Even if tests pass or build succeeds, GLM-4.7 and Codex MUST still run.
3. **Use wrapper scripts** for coding agents (`lib/run-*.sh`)
4. **Never kill agents before 60 minutes** - Use `lib/safe-kill.sh`
5. **Poll every 3-5 minutes**, not seconds
6. **Check status files**, not stdout (`.<agent>-status.txt`)
7. Claude Code MUST use WebSearch for 2026 best practices
8. Claude Code queries Supabase MCP for live DB schema (if applicable)
9. Kimi K2.5 writes code AND migration files (no tests, no docs)
10. Migrations are created but NOT applied (reviewed in PR first)
11. GLM-4.7 writes tests AND documentation
12. PRs are clean (no AI/LLM mentions)
13. Email contains full agent breakdown

## Supabase Integration

If a project uses Supabase, Claude Code will:

1. **Detect Supabase** - Check package.json or .env for supabase references
2. **Query live schema** via MCP tools:
   - `list_tables` - Get all tables and columns
   - `execute_sql` - Query detailed schema info
   - `list_migrations` - See existing migrations
3. **Plan migrations** - Document needed DB changes in the plan
4. **Kimi creates migration files** - In `supabase/migrations/YYYYMMDDHHMMSS_name.sql`

**Migrations are NEVER auto-applied.** They are:
- Created as SQL files in the PR
- Reviewed by you before merging
- Applied manually after PR approval:
  ```bash
  supabase db push  # or supabase migration up
  ```

### Helper Scripts

**`lib/worktree.sh`** - Git worktree management:
```bash
worktree.sh create --project PATH --branch NAME --task-id ID --base main
worktree.sh remove --path WORKTREE_PATH
worktree.sh list --project PATH
```

**`lib/send-resend-email.sh`** - Email notifications:
```bash
send-resend-email.sh --to EMAIL --subject "Subject" --body "Body"
```

**`lib/run-claude.sh`** - Claude CLI wrapper with file-based output:
```bash
run-claude.sh <working-dir> <prompt> [allowed-tools]
# Example:
run-claude.sh /path/to/worktree "Analyze this codebase" "Bash,Read,Glob,Grep,WebSearch"
# Output: .claude-output.txt, .claude-status.txt
```

**`lib/run-kimi.sh`** - Kimi CLI wrapper with file-based output:
```bash
run-kimi.sh <working-dir> <prompt>
# Output: .kimi-output.txt, .kimi-status.txt
```

**`lib/run-opencode.sh`** - OpenCode CLI wrapper with file-based output:
```bash
run-opencode.sh <working-dir> <model> <prompt>
# Example:
run-opencode.sh /path/to/worktree "zai-coding-plan/glm-4.7" "Write tests"
# Output: .opencode-output.txt, .opencode-status.txt
```

**File-based output system:**
Clawdbot's `exec` tool doesn't capture stdout properly from background processes. The wrappers now write output to files:
- Status file (`.<agent>-status.txt`): Contains status value (see below)
- Output file (`.<agent>-output.txt`): Contains the agent's full output
- PID file (`.<agent>-pid.txt`): Contains the process ID while running

**Status values:**
| Status | Meaning | Retryable? |
|--------|---------|------------|
| `RUNNING` | Agent still working | N/A |
| `COMPLETED` | Agent finished successfully | N/A |
| `ERROR:<code>` | Agent failed with exit code | Check output |
| `TIMEOUT:NO_ACTIVITY` | No output for 30 minutes | Yes |
| `TIMEOUT:MAX_TIME` | Exceeded 60 minute maximum | Yes |

To check if an agent is done:
```bash
cat /path/to/worktree/.claude-status.txt  # Returns status value
```

**`lib/safe-kill.sh`** - Prevents premature agent kills:
```bash
safe-kill.sh <pid> [min-seconds]
# Example:
safe-kill.sh 12345        # Default: Won't kill until 60 min (3600s) elapsed
safe-kill.sh 12345 3600   # Explicit: 1 hour minimum
```

GPT-5.2 tends to kill agents prematurely (after seconds instead of waiting). This wrapper enforces the minimum wait time at the system level - it will BLOCK kill attempts before the minimum time (default: 1 hour) has elapsed.

**`lib/checkpoint.sh`** - Checkpoint management for resume capability:
```bash
# Initialize checkpoint for a new task
checkpoint.sh init <worktree> <task_id> <project> [description]

# Save checkpoint before each step
checkpoint.sh save <worktree> <step> <status> [data_json]

# Mark step as completed
checkpoint.sh complete-step <worktree> <step>

# Load checkpoint (returns JSON)
checkpoint.sh load <worktree>

# Get current step number
checkpoint.sh get-step <worktree>

# Increment iteration counter
checkpoint.sh increment <worktree> <counter_name>

# Get counter value
checkpoint.sh get-counter <worktree> <counter_name>
```

Enables workflow resume after orchestrator crashes. Checkpoint file: `<worktree>/.checkpoint.json`

**`lib/retry-with-backoff.sh`** - Retry wrapper for transient errors:
```bash
retry-with-backoff.sh [options] <command>
# Options:
#   --max-retries N     Maximum attempts (default: 3)
#   --initial-delay N   Initial delay in seconds (default: 5)
#   --max-delay N       Max delay cap in seconds (default: 300)
#   --status-file F     File to check for rate limit indicators

# Example:
retry-with-backoff.sh --max-retries 3 -- curl https://api.example.com
```

Automatically retries on transient errors (timeouts, rate limits, network issues) with exponential backoff.

**Why wrappers are used:**
1. **PTY creation via expect** - CLIs hang when spawned from processes without a controlling terminal (like clawdbot gateway). The wrappers use `/usr/bin/expect` to create a pseudo-terminal.
2. **File-based output capture** - Clawdbot's exec doesn't capture stdout properly from background processes. Output goes to `.claude-output.txt` etc.
3. **Terminal code cleanup** - Removes ANSI escape sequences from output.
4. **Timeout monitoring** - Detects stuck agents (no activity for 30 min) and enforces max runtime (60 min).
5. **safe-kill wrapper** prevents premature agent kills.

**System requirements:**
- `/usr/bin/expect` must be available (standard on macOS)
- `jq` for checkpoint JSON manipulation

## Environment Variables

In `~/.clawdbot/clawdbot.json` under `"env"`:

```json
{
  "env": {
    "OPENAI_API_KEY": "sk-...",
    "MOONSHOT_API_KEY": "sk-kimi-...",
    "ZAI_API_KEY": "...",
    "RESEND_API_KEY": "re_...",
    "NOTIFY_EMAIL_TO": "you@example.com",
    "WORKTREE_BASE": "/Users/jose/ai-worktrees"
  }
}
```

## CLI Tools Required

- `git` - Version control
- `gh` - GitHub CLI (PR creation)
- `claude` - Claude Code CLI (research & planning)
- `kimi` - Kimi CLI (implementation)
- `opencode` - OpenCode CLI (GLM-4.7 for tests, fallback for Kimi)
- `codex` - Codex CLI (code review)

## Session Isolation

Each project gets its own isolated session:
- `implement megrowth "..."` → session: `megrowth`
- `implement landing "..."` → session: `landing`
- No context mixing between projects

To clear a session:
```bash
rm -rf ~/.clawdbot/agents/main/sessions/*
```

## PR and Commit Policy

PRs and commits are **clean** - no mentions of:
- AI, LLM, agents
- Clawdbot, Claude, Kimi, GPT
- Co-Authored-By AI

The email notification (private to you) contains:
- Which agents ACTUALLY ran (verified via status files)
- ⚠️ markers for any skipped agents
- Iteration count
- Research highlights from Claude

**Honest Reporting:** Email only lists agents that ran. If GPT-5.2 skips an agent, it must be marked as `⚠️ SKIPPED` in the email rather than falsely claiming it ran.

## Mandatory Agent Chain

The orchestrator MUST use all 4 agents in order. This is enforced via:

1. **RULE 4 in SKILL.md** - Explicit "YOU MUST USE ALL 4 AGENTS (NO SKIPPING)"
2. **Checkpoint before PR** - Checklist requiring all status files verified
3. **Forbidden Actions table** - Skipping GLM-4.7 or Codex is explicitly forbidden

**Why this matters:** GPT-5.2 was observed skipping GLM-4.7 and Codex steps when existing tests passed, going straight to PR creation. The new rules prevent this.

**Verification checkpoint (before PR):**
```
□ Claude Code - .claude-status.txt = COMPLETED
□ Kimi K2.5 - .kimi-status.txt = COMPLETED
□ GLM-4.7 - .opencode-status.txt = COMPLETED
□ Codex - returned JSON with "approved": true
```

**Verification command (orchestrator must run this):**
```bash
cd WORKTREE && echo "=== Agent Status ===" && \
  echo -n "Claude: "; cat .claude-status.txt 2>/dev/null || echo "NOT RUN"; \
  echo -n "Kimi: "; cat .kimi-status.txt 2>/dev/null || echo "NOT RUN"; \
  echo -n "GLM-4.7: "; cat .opencode-status.txt 2>/dev/null || echo "NOT RUN"
```

If ANY shows "NOT RUN" → orchestrator must go back and run the missing agent.

## Codex Approval Loop (Critical)

**PR creation is BLOCKED until Codex returns `approved: true`.**

The orchestrator follows a **hybrid approach** based on issue severity:

### Full Loop (for serious issues)
Triggered when:
- Any issue has `severity: "high"`
- `plan_compliance: "none"`
- Same issues repeat 2+ times (stuck)

Flow:
```
Codex rejects → Claude analyzes + creates NEW plan → Kimi → GLM-4.7 → Codex
```

### Quick Fix (for minor issues)
Triggered when:
- All issues `severity: "low"` or `"medium"`
- `plan_compliance: "full"` or `"partial"`

Flow:
```
Codex rejects → Kimi/GLM fixes directly → Codex reviews again
```

### Loop Logic
```
WHILE approved != true AND iterations < 10:
    Run Codex review

    IF approved == true:
        EXIT → Build Verification → PR

    IF severity HIGH or plan_compliance NONE or stuck:
        → Claude (new plan) → Kimi → GLM → Codex
    ELSE:
        → Kimi/GLM quick fix → Codex

IF iterations >= 10:
    Send failure notification
```

**Why this matters:** GPT-5.2 was observed creating PRs before Codex finished, or even when Codex said `approved: false`. The hybrid approach ensures serious issues get proper analysis from Claude while minor issues can be fixed quickly.

## Build Verification Loop

**Even after Codex approves, build/test/lint must pass before PR.**

If any verification fails, it triggers a full loop back to Claude:

```
Build/Test/Lint FAILS
    ↓
Claude analyzes failure → creates fix plan
    ↓
Kimi implements fix
    ↓
GLM-4.7 updates tests (if needed)
    ↓
Codex reviews (must approve again)
    ↓
Build Verification again
    ↓
REPEAT until ALL pass
```

**Script availability:**
| Check | Required? | If not configured |
|-------|-----------|-------------------|
| `lint` | Optional | Skip, continue |
| `test` | Optional | Skip, continue |
| `build` | **MANDATORY** | Error - all projects need build |

**Max iterations:** 10 build-fix cycles before failure notification.

## Iteration Limits

- **Kimi K2.5**: Unlimited iterations for code fixes
- **GLM-4.7**: Unlimited for test/doc fixes
- **Stuck detection**: 2 identical failures → escalate to Claude Code
- **Claude Code fallback**: Max 10 iterations

## Resilience Features

Clawdbot includes built-in resilience to handle failures gracefully:

### 1. Timeout Detection

Wrapper scripts monitor agent activity and detect stuck processes:
- **No-activity timeout (30 min)**: If output file isn't modified for 30 minutes, agent is considered stuck
- **Max-time timeout (60 min)**: Hard limit on agent runtime

Status file will show `TIMEOUT:NO_ACTIVITY` or `TIMEOUT:MAX_TIME` when triggered.

### 2. Retry with Backoff

Transient errors are automatically retried:
- Rate limits (429, "quota exceeded")
- Timeouts and connection errors
- Service unavailable (503)

Retry behavior:
- Max 3 retries per step
- Exponential backoff: 5s → 10s → 20s → ... (capped at 5 min)
- Permanent errors fail immediately without retry

### 3. Checkpoint-Based Resume

Workflow state is saved before each step:
- Checkpoint file: `<worktree>/.checkpoint.json`
- If orchestrator crashes, next run can resume from last checkpoint
- Tracks: current step, completed steps, iteration counts

Checkpoint format:
```json
{
  "version": 1,
  "task_id": "20260128-220810",
  "project": "megrowth",
  "current_step": 3,
  "completed_steps": [0, 1, 2],
  "iteration_counts": {
    "codex_review": 0,
    "build_fix": 0
  }
}
```

### 4. Fallback Strategy

When primary agents fail:
- **Kimi fails** → Claude Code implements (same plan)
- **GLM-4.7 fails** → Claude Code writes tests
- **Rate limits** → Retry up to 3 times, then fallback

### Recovery Workflow

```
Agent starts
    │
    ├─► COMPLETED → Next step
    │
    ├─► TIMEOUT:* → Retry (up to 3x)
    │       │
    │       └─► Max retries → Fallback agent
    │
    └─► ERROR:* → Check if retryable
            │
            ├─► Rate limit/network → Retry
            │
            └─► Other error → Fallback agent
```

### Resume After Crash

If orchestrator dies mid-workflow:
1. Worktree and checkpoint file remain
2. Re-run `implement project "same task"`
3. Orchestrator detects existing checkpoint
4. Resumes from last completed step
