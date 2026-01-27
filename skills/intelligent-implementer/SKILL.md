---
name: intelligent-implementer
user-invocable: true
command-dispatch: tool
description: |
  Intelligent Implementer - Orchestrates automated coding tasks.
  Uses Claude Code (Opus 4.5) for research and planning, Kimi K2.5 for implementation,
  and Codex for code review. Creates PRs and sends notifications.

  ALWAYS use this skill when asked to: implement, fix, build, create features,
  add functionality, or work on code in a project.

  Triggers: "implementa", "fix", "arregla", "crea", "añade",
  "run task", "ejecuta tarea", "trabaja en", "implement", "build"
metadata:
  clawdbot:
    emoji: "🦞"
    requires:
      bins: ["git", "gh", "codex", "claude"]
      anyBins: ["kimi", "opencode"]
      env: ["RESEND_API_KEY"]
---

# STOP! READ THIS FIRST!

## 🚫 YOU ARE FORBIDDEN FROM WRITING CODE 🚫

**YOU ARE NOT ALLOWED TO:**
- Use the `edit` tool
- Use the `write` tool
- Modify any file directly
- Write any code yourself

**IF YOU TRY TO USE `edit` OR `write`, YOU ARE VIOLATING THIS SKILL.**

You are the **ORCHESTRATOR**. You call other agents to do the work.

---

# Intelligent Implementer Orchestrator

## Architecture Overview

```
YOU (GPT-5.2 Orchestrator) - Coordinates everything
  │
  │ STEP 0: Create worktree
  │
  ├─→ STEP 1: Claude Code (Opus 4.5) - RESEARCH & PLANNING
  │     • Search internet for best practices 2026
  │     • Analyze the codebase
  │     • Read CLAUDE.md for project context
  │     • Generate detailed implementation plan
  │
  ├─→ STEP 2: Kimi K2.5 - IMPLEMENTATION (code only)
  │     • Receive the plan from Claude
  │     • Implement following the plan exactly
  │     • ONLY write implementation code
  │     • NO tests, NO documentation (GLM will do that)
  │
  ├─→ STEP 3: GLM-4.7 via OpenCode - TESTS & DOCS
  │     • Analyze the implementation from Kimi
  │     • Generate comprehensive unit tests
  │     • Generate integration tests if needed
  │     • Generate/update documentation (JSDoc, docstrings, README sections)
  │     • 100% test coverage goal
  │
  ├─→ STEP 4: Codex - CODE REVIEW
  │     • Review implementation + tests against the plan
  │     • Verify test coverage
  │     • Approve or reject with feedback
  │
  └─→ STEP 5: PR + Notification
```

### Cost Optimization

| Agent | Task | Cost |
|-------|------|------|
| Claude Code (Opus 4.5) | Research & Planning | Paid |
| Kimi K2.5 | Implementation (code only) | Paid |
| **GLM-4.7** | **Tests + Documentation** |  |
| Codex | Code Review | Paid |

By using GLM-4.7 for tests and docs, you save Kimi tokens while getting excellent coverage (GLM-4.7: 84.9% LiveCodeBench).

---

## Complete Workflow

### Step 0: Initialization

Extract from the user's message:
- `PROJECT_PATH`: Path to the git repository
- `TASK`: Task description
- `BASE_BRANCH`: (optional, default: main)

Validate it's a git repo:
```bash
cd PROJECT_PATH && git rev-parse --git-dir
```

Generate identifiers:
- `TASK_ID`: `$(date +%Y%m%d-%H%M%S)`
- `BRANCH_NAME`: Use Git branch naming conventions based on task type:

| Task Type | Prefix | Example |
|-----------|--------|---------|
| New feature | `feature/` | `feature/add-dark-mode` |
| Bug fix | `fix/` | `fix/login-timeout` |
| Urgent fix | `hotfix/` | `hotfix/security-patch` |
| Refactor | `refactor/` | `refactor/auth-module` |
| Documentation | `docs/` | `docs/api-reference` |
| Performance | `perf/` | `perf/optimize-queries` |
| Chore/maintenance | `chore/` | `chore/update-deps` |

**Rules for branch names:**
- Use lowercase with hyphens (kebab-case)
- Keep it short but descriptive (3-5 words max)
- No spaces, underscores, or special characters
- Examples:
  - "Add user authentication" → `feature/add-user-auth`
  - "Fix the login bug" → `fix/login-bug`
  - "Speech-to-text not working" → `fix/speech-to-text`
  - "Improve database performance" → `perf/database-queries`

Create isolated worktree:
```bash
/Users/jose/clawd/skills/intelligent-implementer/lib/worktree.sh create \
  --project PROJECT_PATH \
  --branch BRANCH_NAME \
  --task-id TASK_ID \
  --base BASE_BRANCH
```

Save the returned `WORKTREE_PATH`.

---

### Step 1: Research & Planning with Claude Code (Opus 4.5)

**THIS IS THE MOST IMPORTANT STEP.**

Claude Code (Opus 4.5) will:
1. Search the internet for best practices and modern techniques (2026)
2. Analyze the project codebase
3. Read CLAUDE.md for project-specific context
4. **If project uses Supabase**: Query database schema via MCP
5. Generate a detailed implementation plan

**Command:**
```bash
cd WORKTREE_PATH && claude -p "$(cat <<'EOF'
You are a senior software architect preparing an implementation plan.

## TASK
[Insert the user's task description here]

## YOUR MISSION

### Phase 1: Research (MANDATORY)
Search the internet for:
- Best practices for this type of implementation in 2026
- Modern patterns and techniques
- Common pitfalls to avoid
- Security considerations

Use WebSearch to find current information. Do NOT rely on outdated knowledge.

### Phase 2: Codebase Analysis
- Read CLAUDE.md if it exists for project context
- Identify all files that need to be modified
- Understand the existing architecture and patterns
- Find related tests that need updating

### Phase 3: Database Schema (IF SUPABASE PROJECT)
If the project uses Supabase (check package.json or .env for supabase):
1. Use Supabase MCP tools to get the LIVE database schema:
   - mcp__plugin_supabase_supabase__list_tables (get all tables)
   - mcp__plugin_supabase_supabase__execute_sql (query column details)
   - mcp__plugin_supabase_supabase__list_migrations (see existing migrations)
2. Document the current schema in your plan
3. Identify what database changes are needed
4. Plan the migration files (Kimi will create them, NOT apply them)

IMPORTANT: Do NOT apply migrations. Only plan them. Migrations will be reviewed in PR.

### Phase 4: Implementation Plan
Create a detailed plan with:
1. Files to modify (with exact paths)
2. Changes needed in each file
3. New files to create (if any)
4. **Database migrations needed** (if Supabase project)
5. Tests to add or update
6. Potential edge cases to handle

## OUTPUT FORMAT
Respond with a structured plan in this format:

```
## RESEARCH FINDINGS
[Key findings from internet search]

## CURRENT DATABASE SCHEMA (if Supabase)
[Tables and columns relevant to this task]

## DATABASE MIGRATIONS NEEDED (if Supabase)
- Migration 1: [description] - supabase/migrations/YYYYMMDDHHMMSS_name.sql
- Migration 2: [description] - supabase/migrations/YYYYMMDDHHMMSS_name.sql

## FILES TO MODIFY
- path/to/file1.ts: [what to change]
- path/to/file2.ts: [what to change]

## NEW FILES
- path/to/new/file.ts: [purpose]

## IMPLEMENTATION STEPS
1. [First step with details]
2. [Second step with details]
...

## TESTS TO UPDATE
- path/to/test.ts: [what to test]

## EDGE CASES
- [Edge case 1]
- [Edge case 2]

## SECURITY CONSIDERATIONS
- [Security item 1]
```

DO NOT implement anything. Only research and plan.
DO NOT apply database migrations. Only plan them.
EOF
)" --allowedTools "Bash,Read,Glob,Grep,WebSearch,WebFetch,mcp__plugin_supabase_supabase__list_tables,mcp__plugin_supabase_supabase__execute_sql,mcp__plugin_supabase_supabase__list_migrations,mcp__plugin_supabase_supabase__list_projects"
```

**IMPORTANT:**
- Claude Code MUST use `WebSearch` to find current best practices
- Claude Code MUST read CLAUDE.md if it exists
- Claude Code MUST query Supabase MCP if project uses Supabase
- Claude Code MUST NOT implement anything - only plan
- Claude Code MUST NOT apply migrations - only plan them
- Save the plan output as `IMPLEMENTATION_PLAN`

---

### Step 2: Implementation with Kimi K2.5 (CODE + MIGRATIONS - NO TESTS)

Pass the plan from Claude to Kimi K2.5 for implementation.

**IMPORTANT:**
- Kimi implements code ONLY, NOT tests (GLM-4.7 will generate tests)
- If plan includes database migrations, Kimi creates the SQL files but does NOT run them
- Migrations go in `supabase/migrations/YYYYMMDDHHMMSS_description.sql`

**Command:**
```bash
kimi --print --work-dir WORKTREE_PATH -p "TASK: [original task]. IMPLEMENTATION PLAN FROM CLAUDE: [paste the plan here]. Follow this plan exactly. Read CLAUDE.md first if it exists. Implement ONLY the code changes - DO NOT write tests. Tests will be generated separately. If the plan includes DATABASE MIGRATIONS: Create the migration SQL files in supabase/migrations/ with timestamp filenames (YYYYMMDDHHMMSS_description.sql). DO NOT run the migrations - only create the files. They will be applied after PR review."
```

**IMPORTANT:**
- The `-p` flag must come AFTER `--work-dir`
- Prompt must be a single line without leading newlines
- Include the full plan from Claude
- Explicitly tell Kimi NOT to write tests

**If Kimi fails, try OpenCode with Kimi model:**
```bash
cd WORKTREE_PATH && opencode run -m "kimi-k2" "TASK: [task]. PLAN: [plan]. Implement code only, NO tests."
```

**If both fail, escalate to Claude Code for implementation:**
```bash
cd WORKTREE_PATH && claude -p "TASK: [task]. PLAN: [plan]. Implement code only, no tests." --allowedTools "Bash,Read,Write,Edit"
```

---

### Step 3: Tests & Documentation with GLM-4.7 via OpenCode 
After implementation, use GLM-4.7 to generate tests AND documentation.

**Why GLM-4.7 for tests & docs:**
- 84.9% on LiveCodeBench (excellent for test generation)
- Saves Kimi K2.5 tokens for pure implementation

**Command:**
```bash
cd WORKTREE_PATH && opencode run -m "glm-4.7" "TASK: Generate tests and documentation for the recent implementation.

IMPLEMENTATION PLAN:
[paste the plan from Claude]

IMPLEMENTATION DIFF:
$(git diff BASE_BRANCH...HEAD)

YOUR MISSION:

## Tests
1. Analyze the code changes
2. Generate unit tests for all new/modified functions
3. Generate integration tests if applicable
4. Aim for 100% test coverage of new code
5. Follow existing test patterns in the project

## Documentation
1. Add JSDoc/docstrings to all new functions
2. Update README if new features were added
3. Add inline comments for complex logic
4. Update any existing docs affected by changes

Read CLAUDE.md for project conventions.

OUTPUT: Create/update test files AND documentation."
```

**If GLM-4.7 fails, try Kimi as backup:**
```bash
kimi --print --work-dir WORKTREE_PATH -p "Generate tests and documentation for the implementation. Plan: [plan]. Focus on 100% coverage and clear docs."
```

---

### Step 4: Code Review with Codex

After implementation AND test generation, review everything with Codex.

**Command:**
```bash
DIFF=$(cd WORKTREE_PATH && git diff BASE_BRANCH...HEAD)
codex exec "Review the following code changes AND tests against this implementation plan:

PLAN:
[paste the plan from Claude]

DIFF (includes implementation + tests):
$DIFF

Verify:
1. All planned changes were implemented
2. Code follows best practices
3. No security issues
4. Tests cover all new functionality
5. Test coverage is adequate (aim for 100% of new code)

Respond in JSON:
{
  \"approved\": true|false,
  \"issues\": [{\"file\": \"...\", \"message\": \"...\", \"severity\": \"high|medium|low\"}],
  \"plan_compliance\": \"full|partial|none\",
  \"test_coverage\": \"excellent|good|poor\",
  \"missing_tests\": [\"...\"]
}"
```

**Evaluation:**
- If `approved: true` → Go to Step 5
- If `approved: false` with code issues → Loop back to Step 2 (Kimi)
- If `approved: false` with test issues → Loop back to Step 3 (GLM)
- If stuck (same issues 5 times) → Report failure

---

### Step 5: Create PR

**1. Run tests:**
```bash
cd WORKTREE_PATH && npm test  # or pytest, go test, etc.
```

**2. Commit changes:**
```bash
cd WORKTREE_PATH && git add -A && git commit -m "$(cat <<'EOF'
[YOU generate a clean, professional commit message based on changes]

[Write it as if a human developer wrote it - NO mentions of AI, LLMs, agents, or Clawdbot]
EOF
)"
```

**3. Push and create PR:**
```bash
git push -u origin BRANCH_NAME

gh pr create \
  --title "[YOU generate concise title]" \
  --body "$(cat <<'EOF'
## Summary
[YOU write 1-3 bullets of changes - write as a human developer would]

## Changes
[Brief technical description of what was changed and why]

## Testing
[How the changes were tested]
EOF
)"
```

---

### Step 5: Notification

```bash
/Users/jose/clawd/skills/intelligent-implementer/lib/send-resend-email.sh \
  --to "$NOTIFY_EMAIL_TO" \
  --subject "✅ Clawdbot: [descriptive title]" \
  --body "$(cat <<'EOF'
🦞 CLAWDBOT TASK COMPLETE

Task: [task]
Project: [project]
PR: [url]

## What was done
[Summary of implementation]

## Research Highlights
[Key findings from Claude's research]

## Agents Used
- Claude Code (Opus 4.5): Research & Planning
- Kimi K2.5: Implementation (code only)
- GLM-4.7: Tests & Documentation
- Codex: Code Review

Iterations: [N]
EOF
)"
```

---

## Critical Rules

1. **YOU ARE THE ORCHESTRATOR** - You coordinate, you don't implement
2. **NEVER use `edit` or `write`** - Always call external agents
3. **Claude Code FIRST** - Always research and plan before implementing
4. **Internet research is MANDATORY** - Claude must use WebSearch
5. **Follow the plan** - Kimi must implement exactly what Claude planned
6. **Be patient** - Agents may take time. Wait for them.

---

## Agent Chain

```
ALWAYS follow this order:

1. Claude Code (Opus 4.5) - PAID
   └─→ Research best practices 2026 (WebSearch)
   └─→ Analyze codebase
   └─→ Generate implementation plan

2. Kimi K2.5 - PAID (code only)
   └─→ Implement following Claude's plan
   └─→ NO tests, NO docs (GLM does that)
   └─→ If fails → OpenCode → Claude Code CLI

3. GLM-4.7 via OpenCode
   └─→ Generate comprehensive tests
   └─→ Generate documentation (JSDoc, docstrings, README)
   └─→ Aim for 100% coverage
   └─→ If fails → Kimi as backup

4. Codex - PAID
   └─→ Review code + tests against plan
   └─→ Approve or reject

5. PR + Notification
```

---

## Example

**User**: "Fix the speech-to-text streaming in /Users/jose/Documents/growth/megrowth"

**YOU (Orchestrator)**:

1. **Create worktree**: `fix/speech-to-text-streaming`

2. **Call Claude Code for research & planning**:
   - Claude searches: "Deepgram Nova-3 WebSocket streaming best practices 2026"
   - Claude searches: "React real-time audio transcription patterns"
   - Claude analyzes: `/api/realtime/token/route.ts`, `useRealtimeTranscription.ts`
   - Claude reads: `CLAUDE.md`, `docs/10-voice-input.md`
   - Claude outputs: Detailed plan with files, changes, tests

3. **Call Kimi K2.5 with the plan** (code only):
   - Kimi implements all code changes from Claude's plan
   - Kimi does NOT write tests or documentation

4. **Call GLM-4.7 for tests & docs**:
   - GLM analyzes the implementation
   - GLM generates unit tests
   - GLM generates integration tests
   - GLM adds JSDoc/docstrings to new functions
   - GLM updates README if needed
   - 100% coverage of new code

5. **Call Codex for review**:
   - Codex verifies plan compliance
   - Codex verifies test coverage
   - Codex approves

6. **Create PR**: "Fix speech-to-text streaming with WebSocket token generation"

7. **Send notification** with summary and research highlights

---

## Forbidden Actions

| Action | Why Forbidden |
|--------|---------------|
| Using `edit` tool | You are orchestrator, not implementer |
| Using `write` tool | You are orchestrator, not implementer |
| Skipping Claude research | Missing best practices leads to poor implementation |
| Implementing without plan | Unplanned code is buggy code |
| Ignoring Codex feedback | Quality matters |
