# Clawdbot - Intelligent Implementer

Clawdbot is an AI-powered coding orchestrator that automates software development tasks using multiple AI models working together.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                 CLAWDBOT (GLM 4.7) - THE BRAIN                  │
│                                                                  │
│  Reads SKILL.md → Understands workflow → Executes step by step  │
│                                                                  │
│  Native capabilities:                                            │
│  • Execute bash commands (git, gh, etc.)                        │
│  • Read/write files                                              │
│  • Call OpenCode, Codex, Claude directly                        │
│  • Evaluate results and make decisions                          │
│  • Generate content (PR titles, descriptions, emails)           │
│  • Maintain task state in context                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              MINIMAL HELPERS (2 scripts)                        │
├─────────────────────────────────────────────────────────────────┤
│ worktree.sh        │ Create/remove git worktrees safely         │
│ send-resend-email.sh │ Send email via Resend API                │
└─────────────────────────────────────────────────────────────────┘
```

## Core Principle

> Clawdbot (GLM 4.7) IS the orchestrator. It doesn't need scripts to tell it what to do.
> It only needs clear instructions (SKILL.md) and minimal helpers for atomic operations.

## Workflow

1. **User requests task** → "Implement X in project Y"
2. **Clawdbot creates worktree** → Isolated git branch for work
3. **Clawdbot calls Kimi K2.5** → Primary implementer via OpenCode
4. **Clawdbot calls Codex** → Code review (GPT-5.2-Codex)
5. **Clawdbot evaluates** → Reads JSON directly, decides next step
6. **Loop or escalate** → If stuck, escalates to Claude Code (Opus 4.5)
7. **Clawdbot creates PR** → Generates title/description itself
8. **Clawdbot notifies** → Sends email summary it writes

## Project Structure

```
clawdbot/
├── CLAUDE.md                      # This file - project documentation
├── clawdbot.json                  # Configuration: models, tools, settings
├── config/
│   └── env.template               # Environment variables template
└── skills/
    └── orchestrator/
        ├── SKILL.md               # THE BRAIN - orchestrator instructions
        └── lib/
            ├── worktree.sh        # Git worktree helper (create/remove/list)
            └── send-resend-email.sh # Email via Resend API
```

## Key Files

### `skills/orchestrator/SKILL.md`
The heart of the system (~250 lines). Contains instructions that Clawdbot follows to orchestrate tasks. Clawdbot reads this and executes the workflow autonomously.

**Key sections:**
- Step 1: Initialization (validate repo, create worktree)
- Step 2: Planning (mental plan, no file needed)
- Step 3: Implementation Loop (Kimi + Codex, max 80 iterations)
- Step 3.5: Escalation to Claude Code (max 10 iterations)
- Step 4: Create PR (Clawdbot generates all content)
- Step 5: Notification (email via Resend)
- Step 6: Failure handling

### `skills/orchestrator/lib/worktree.sh`
Git worktree management. Atomic operations only:
- `create` - Create isolated worktree with new branch
- `remove` - Remove worktree (with safety checks)
- `list` - List worktrees for a project
- `cleanup` - Remove old worktrees

### `skills/orchestrator/lib/send-resend-email.sh`
Email delivery via Resend API:
- `--to` - Recipient email
- `--subject` - Email subject
- `--body` - Email body (text or HTML)

### `clawdbot.json`
Configuration file defining:
- **models**: Default GLM 4.7, ZAI provider
- **tools**: opencode (Kimi), codex, claude
- **skills**: Load from ./skills directory
- **settings**: Iteration limits, worktree base, etc.

## Environment Variables

Required in `~/.clawdbot-orchestrator.env`:

```bash
# For Clawdbot orchestrator (GLM 4.7)
ZAI_API_KEY=your-zai-key

# For OpenCode/Kimi K2.5
MOONSHOT_API_KEY=your-moonshot-key

# For email notifications
RESEND_API_KEY=your-resend-key
RESEND_FROM=noreply@yourdomain.com
NOTIFY_EMAIL_TO=you@example.com

# Worktree location
WORKTREE_BASE=~/ai-worktrees
```

## CLI Tools Required

- `git` - Version control
- `gh` - GitHub CLI (for PR creation)
- `kimi` - Kimi CLI (primary implementer - Kimi K2) **RECOMMENDED**
- `opencode` - OpenCode CLI (alternative implementer - supports multiple models)
- `codex` - Codex CLI (code reviewer)
- `claude` - Claude Code CLI (fallback implementer - Opus 4.5)

### Kimi CLI vs OpenCode

| Tool | Use Case | Stability |
|------|----------|-----------|
| **Kimi CLI** | Default for Kimi K2 tasks | ✅ More stable, native client |
| **OpenCode** | Alternative/multi-model | ⚠️ May hang on some tasks |

The skill uses Kimi CLI by default and falls back to OpenCode if needed.

## Design Decisions

### Why Clawdbot is the Brain (not scripts)

**Before**: 21+ bash scripts (700+ lines each) with embedded Python for JSON parsing, complex context building, etc.

**After**: 3 files total. Clawdbot (GLM 4.7) handles:
- Decision making
- Context management (in its own context window)
- Content generation (PR titles, emails, summaries)
- Evaluation of results (reads JSON directly)
- Escalation logic

### Why Minimal Helpers

Only two atomic helpers remain:
1. **worktree.sh** - Git worktree operations are shell-native and have safety requirements
2. **send-resend-email.sh** - HTTP API call with proper error handling

Everything else Clawdbot does directly via its native capabilities.

### Stuck Detection

Clawdbot detects stuck conditions by observing:
- Same Codex issues appearing 5 times consecutively
- Diff not changing significantly between iterations
- Tests failing the same way repeatedly

When stuck → Escalates to Claude Code with full context.

## Usage Examples

```
User: "Implement a /health endpoint in /path/to/api"

Clawdbot:
1. Creates worktree: ai/add-health-endpoint
2. Calls Kimi: "Create /health endpoint returning {status: 'ok'}"
3. Codex reviews: approved: true
4. Creates PR: "Add /health endpoint for service monitoring"
5. Sends email: "✅ Added /health endpoint - PR #42 ready for review"
```

```
User: "Fix the login timeout bug in /path/to/app"

Clawdbot:
1. Analyzes code, finds login location
2. Creates worktree: ai/fix-login-timeout
3. Calls Kimi with specific bug context
4. Codex rejects: "Doesn't handle network errors"
5. Calls Kimi again with feedback
6. Codex approves
7. Creates PR: "Fix login timeout by adding retry logic"
8. Sends email explaining what caused bug and how it was fixed
```

## Iteration Limits

- **Kimi K2.5**: Max 80 iterations (primary implementer)
- **Claude Code**: Max 10 iterations (fallback for stuck situations)
- **Stuck detection window**: 5 identical failures triggers escalation
