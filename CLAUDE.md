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
| Research & Planning | Claude Opus 4.5 | WebSearch best practices 2026, analyze codebase, create plan | Native web search |
| Implementation | Kimi K2.5 | Write code (only code, no tests/docs) | 76.8% SWE-bench |
| Tests & Docs | GLM-4.7 | Generate tests, JSDoc, docstrings, README | 84.9% LiveCodeBench |
| Code Review | Codex (GPT-5.2) | Review against plan, approve/reject | Structured JSON output |

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
3. **Claude Code researches** → WebSearch for 2026 best practices, analyzes codebase
4. **Claude Code plans** → Detailed implementation plan
5. **Kimi K2.5 implements** → Code only, following the plan
6. **GLM-4.7 generates** → Tests + documentation
7. **Codex reviews** → Approve or provide feedback
8. **Loop if needed** → Back to Kimi (code issues) or GLM (test issues)
9. **GPT-5.2 creates PR** → Clean, human-like (no AI mentions)
10. **GPT-5.2 notifies** → Email with full agent breakdown

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
            └── send-resend-email.sh    # Email via Resend
```

## Key Files

### `skills/intelligent-implementer/SKILL.md`

The orchestrator instructions (~475 lines). Clawdbot reads this and executes autonomously.

**Steps:**
- Step 0: Create worktree
- Step 1: Claude Code research & planning (WebSearch + Supabase MCP if applicable)
- Step 2: Kimi K2.5 implementation (code + migrations, no tests)
- Step 3: GLM-4.7 tests & documentation
- Step 4: Codex code review
- Step 5: Create PR + Send notification

**Critical Rules:**
- Orchestrator NEVER uses `edit` or `write` tools
- Claude Code MUST use WebSearch for 2026 best practices
- Claude Code queries Supabase MCP for live DB schema (if project uses Supabase)
- Kimi K2.5 writes code AND migration files (no tests, no docs)
- Migrations are created but NOT applied (reviewed in PR first)
- GLM-4.7 writes tests AND documentation
- PRs are clean (no AI/LLM mentions)
- Email contains full agent breakdown

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
- Which agent did what
- Iteration count
- Research highlights from Claude

## Iteration Limits

- **Kimi K2.5**: Unlimited iterations for code fixes
- **GLM-4.7**: Unlimited for test/doc fixes
- **Stuck detection**: 5 identical failures → escalate to Claude Code
- **Claude Code fallback**: Max 10 iterations
