# Clawdbot Intelligent Implementer

An AI-powered orchestrator that automates coding tasks using a multi-agent pipeline with planning, implementation, and review phases.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CLAWDBOT (GLM 4.7)                               │
│                        Master Orchestrator                               │
│         Coordinates workflow, maintains context, manages state           │
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
│  │ • Creates    │      │ • Writes     │      │ • Approves   │          │
│  │   strategy   │      │   code       │      │   or rejects │          │
│  │ • Revises    │      │ • Runs       │      │              │          │
│  │   on failure │      │   tests      │      │              │          │
│  └──────────────┘      └──────────────┘      └──────┬───────┘          │
│         ▲                                           │                   │
│         │         NO (with full context)            │ YES               │
│         └───────────────────────────────────────────┤                   │
│                                                     ▼                   │
│                                              ┌──────────┐              │
│                                              │ CREATE   │              │
│                                              │   PR     │              │
│                                              └──────────┘              │
└─────────────────────────────────────────────────────────────────────────┘
```

## The Workflow

1. **Claude Code (Opus 4.5)** - The **Planner**
   - Analyzes the codebase and task requirements
   - Creates detailed implementation plans
   - Revises plans when previous attempts fail

2. **OpenCode (Kimi K2.5)** - The **Implementer**
   - Executes the plan step by step
   - Writes production-ready code
   - Runs tests to verify implementation

3. **Codex (GPT-5.2-Codex)** - The **Reviewer**
   - Reviews the implementation against the plan
   - Validates code correctness and completeness
   - Approves or rejects with detailed feedback

4. **Loop Until Approved**
   - If rejected, full context (task + all plans + implementations + feedback) goes back to Claude
   - Claude creates a revised plan addressing all issues
   - Kimi implements the new plan
   - Codex reviews again
   - Maximum 10 iterations

## Quick Start

### 1. Install Dependencies

```bash
./tools/install.sh

# Or manually:
brew install git jq gh node
npm install -g opencode-ai @openai/codex-cli @anthropic-ai/claude-code
```

### 2. Authenticate CLI Tools

```bash
# OpenCode (for Kimi K2.5)
opencode auth login

# Codex CLI (for GPT-5.2-Codex)
codex auth login

# Claude Code (authenticates on first run)
claude --version

# GitHub CLI
gh auth login
```

### 3. Configure Environment

```bash
cp config/env.template ~/.clawdbot-orchestrator.env
chmod 600 ~/.clawdbot-orchestrator.env
nano ~/.clawdbot-orchestrator.env
```

Add your API keys:
- `ZAI_API_KEY` - For GLM 4.7 (Clawdbot orchestrator)
- `MOONSHOT_API_KEY` - For Kimi K2.5 (optional, CLI handles auth)

### 4. Verify Setup

```bash
./tools/doctor.sh
```

### 5. Run a Task

```bash
clawdbot "implement 'add user authentication' on /path/to/my-project"
```

## Context Management

Every agent receives **full context** at every step:

```
logs/<project>/<task-id>/
├── context/
│   ├── original_task.md          # What the user asked for
│   ├── codebase_summary.md       # Analysis of the codebase
│   └── cumulative_context.md     # Growing context with all iterations
├── iterations/
│   ├── iter_001/
│   │   ├── claude_plan.md        # Claude's plan
│   │   ├── kimi_implementation.md # What Kimi did
│   │   ├── codex_review.json     # Codex's review
│   │   └── codex_feedback.md     # Human-readable feedback
│   ├── iter_002/
│   │   ├── claude_revised_plan.md # Revised plan
│   │   └── ...
│   └── ...
└── final/
    ├── success_report.md
    └── pr_description.md
```

When the loop repeats:
- Claude sees: original task + codebase + ALL previous plans + ALL implementations + ALL feedback
- Kimi sees: new plan + task + codebase + what failed before
- Codex sees: task + plan + implementation + test results

## Key Principles

1. **Context is King** - Every agent gets the full picture
2. **Nothing is Lost** - Every iteration is logged
3. **Clear Handoffs** - Each agent knows exactly what to do
4. **Cumulative Learning** - Later iterations build on earlier ones
5. **Fail Forward** - Each failure provides information for the next attempt

## Configuration

### Environment Variables

```bash
# Model API Keys
ZAI_API_KEY=...           # For GLM 4.7 (orchestrator)
MOONSHOT_API_KEY=...      # For Kimi K2.5 (optional)

# Notifications
TWILIO_ACCOUNT_SID=...    # WhatsApp via Twilio
CALLMEBOT_APIKEY=...      # WhatsApp via CallMeBot (free)
SENDGRID_API_KEY=...      # Email notifications

# Settings
MAX_ITERATIONS=10         # Max Claude→Kimi→Codex cycles
WORKTREE_BASE=~/ai-worktrees
AUTO_RUN_TESTS=true
```

## Directory Structure

```
/Users/jose/Documents/clawdbot/
├── skills/
│   ├── orchestrator/           # Main orchestration
│   │   ├── SKILL.md           # Workflow documentation
│   │   └── lib/
│   │       ├── build-claude-context.sh
│   │       ├── build-kimi-context.sh
│   │       ├── build-codex-context.sh
│   │       ├── claude-code.sh
│   │       ├── opencode.sh
│   │       ├── codex.sh
│   │       ├── analyze-codebase.sh
│   │       ├── capture-implementation.sh
│   │       └── update-cumulative-context.sh
│   ├── notify/                 # Notifications
│   └── pr-creator/             # PR creation
├── config/
│   ├── env.template
│   └── defaults.yaml
├── tools/
│   ├── doctor.sh
│   ├── install.sh
│   └── cleanup.sh
└── logs/                       # Task logs
```

## Troubleshooting

Run the doctor script:
```bash
./tools/doctor.sh
```

Check task logs:
```bash
cat logs/<project>/<task-id>/context/cumulative_context.md
```

## License

MIT License
