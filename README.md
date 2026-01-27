# Clawdbot Intelligent Implementer

An AI-powered orchestrator that automates coding tasks using multiple AI agents with built-in code review.

## Overview

Clawdbot orchestrates the entire coding workflow:

1. **Receives** task requests via CLI, WhatsApp, or other channels
2. **Creates** isolated git worktrees for safe development
3. **Implements** using OpenCode + GLM 4.7 (max 80 iterations)
4. **Reviews** using Codex CLI + GPT-5.2-Codex (after each iteration)
5. **Falls back** to Claude Code + Opus 4.5 when stuck (max 10 iterations)
6. **Creates** PRs with proper titles and descriptions
7. **Notifies** via WhatsApp/email when done or failed

```
┌────────────────────────────────────────────────────────────────────────┐
│                          USER (You)                                    │
│   Commands via: WhatsApp / Telegram / Discord / Slack / CLI            │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    CLAWDBOT (GLM 4.7 Powered)                          │
│                    Master Orchestrator                                  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────────────┐
        │                           │                                   │
        ▼                           ▼                                   ▼
┌───────────────┐          ┌───────────────┐                  ┌───────────────┐
│   OPENCODE    │          │   CODEX CLI   │                  │  CLAUDE CODE  │
│   GLM 4.7     │          │ GPT-5.2-Codex │                  │   Opus 4.5    │
│  Implementer  │          │   Reviewer    │                  │   Fallback    │
│  Max 80 iter  │          │   Unlimited   │                  │  Max 10 iter  │
└───────────────┘          └───────────────┘                  └───────────────┘
```

## Quick Start

### 1. Install Dependencies

```bash
# Run the install script
./tools/install.sh

# Or manually:
brew install git jq gh node
npm install -g opencode-ai @openai/codex-cli @anthropic-ai/claude-code
```

### 2. Authenticate CLI Tools

Each CLI tool uses its own built-in authentication:

```bash
# OpenCode (GLM 4.7)
opencode auth login

# Codex CLI (GPT-5.2-Codex)
codex auth login

# Claude Code (Opus 4.5) - authenticates on first run
claude --version

# GitHub CLI
gh auth login
```

### 3. Configure Environment

```bash
# Copy template to home directory
cp config/env.template ~/.clawdbot-orchestrator.env
chmod 600 ~/.clawdbot-orchestrator.env

# Edit and add your API key
nano ~/.clawdbot-orchestrator.env
```

Required:
- `ZAI_API_KEY` - For GLM 4.7 (Clawdbot orchestrator)

Optional (for notifications):
- Twilio credentials for WhatsApp
- SendGrid API key for email

### 4. Verify Setup

```bash
./tools/doctor.sh
```

### 5. Run a Task

```bash
# Via Clawdbot CLI
clawdbot "implement 'add user authentication' on /path/to/my-project"

# Or using the orchestrator skill directly
clawdbot orchestrate --project /path/to/repo --task "Fix the login timeout bug"
```

## Directory Structure

```
/Users/jose/Documents/clawdbot/
├── README.md                    # This file
├── package.json                 # Node.js dependencies
├── clawdbot.json               # Workspace configuration
│
├── config/
│   ├── env.template            # Environment template
│   └── defaults.yaml           # Default settings
│
├── gateway/
│   └── config.yaml             # Gateway settings (WhatsApp, etc.)
│
├── skills/
│   ├── orchestrator/           # Main orchestration skill
│   │   ├── SKILL.md           # Skill definition
│   │   └── lib/               # Helper scripts
│   │       ├── worktree.sh    # Git worktree management
│   │       ├── opencode.sh    # OpenCode adapter
│   │       ├── codex.sh       # Codex adapter
│   │       ├── claude-code.sh # Claude Code adapter
│   │       ├── stuck-detector.sh
│   │       ├── context-builder.sh
│   │       ├── detect-tests.sh
│   │       ├── codex-approval.sh
│   │       ├── extract-feedback.sh
│   │       └── notify.sh
│   │
│   ├── notify/                 # Notification skill
│   │   ├── SKILL.md
│   │   └── lib/
│   │       ├── whatsapp.js
│   │       └── email.js
│   │
│   └── pr-creator/             # PR creation skill
│       ├── SKILL.md
│       └── lib/
│           └── gh-pr.sh
│
├── tools/
│   ├── doctor.sh              # Setup validator
│   ├── install.sh             # Dependency installer
│   └── cleanup.sh             # Cleanup utility
│
├── logs/                       # Task logs (auto-created)
│   └── <project>/<task-id>/
│       ├── state.json
│       ├── opencode/
│       ├── codex/
│       └── claude/
│
└── worktrees/                  # Symlink to ~/ai-worktrees
```

## Configuration

### Environment Variables

Edit `~/.clawdbot-orchestrator.env`:

```bash
# Model API Key (Required)
ZAI_API_KEY=your-zai-api-key

# NOTE: OpenCode, Codex, and Claude Code use their own CLI authentication
# Make sure you've run: opencode auth login, codex auth login, etc.

# WhatsApp Notifications (Twilio)
TWILIO_ACCOUNT_SID=ACxxxxx
TWILIO_AUTH_TOKEN=xxxxx
TWILIO_WHATSAPP_FROM=whatsapp:+14155238886
NOTIFY_WHATSAPP_TO=whatsapp:+1XXXXXXXXXX

# OR WhatsApp (CallMeBot - Free)
CALLMEBOT_PHONE=+1XXXXXXXXXX
CALLMEBOT_APIKEY=xxxxx

# Email Notifications (SendGrid)
SENDGRID_API_KEY=SG.xxxxx
NOTIFY_EMAIL_TO=your@email.com
NOTIFY_EMAIL_FROM=clawdbot@yourdomain.com

# Orchestrator Settings
WORKTREE_BASE=~/ai-worktrees
MAX_OPENCODE_ITERATIONS=80
MAX_CLAUDE_ITERATIONS=10
STUCK_DETECTION_WINDOW=5
AUTO_RUN_TESTS=true
```

### Default Settings

See `config/defaults.yaml` for all configurable options.

## Usage

### Basic Commands

```bash
# Implement a feature
clawdbot "implement 'add dark mode toggle' on /path/to/frontend"

# Fix a bug
clawdbot "fix the memory leak in the WebSocket handler on /path/to/server"

# Refactor code
clawdbot "refactor the database layer for better performance on /path/to/api"
```

### Manual Orchestration

```bash
# Step 1: Create worktree
./skills/orchestrator/lib/worktree.sh create \
  -p /path/to/repo \
  -b ai/my-feature \
  -t $(date +%Y%m%d-%H%M%S)-abc123 \
  --base main

# Step 2: Run implementation (handled by orchestrator)
# Step 3: Create PR (handled by orchestrator)
```

### Cleanup

```bash
# Clean worktrees older than 7 days
./tools/cleanup.sh --worktrees --days 7

# Clean worktrees for merged PRs
./tools/cleanup.sh --merged

# Clean everything (dry run first)
./tools/cleanup.sh --all --dry-run
./tools/cleanup.sh --all
```

## Workflow Details

### 1. Task Intake

When you give Clawdbot a task:
- Parses the project path and task description
- Validates the git repository
- Generates a task ID and branch name

### 2. Workspace Creation

Creates an isolated environment:
- Git worktree with a new branch (e.g., `ai/fix-login-timeout`)
- Log directory for tracking iterations
- State file for progress tracking

### 3. Implementation Loop

OpenCode (GLM 4.7) runs up to 80 iterations:
1. Receives task + previous feedback
2. Makes code changes
3. Codex reviews the changes
4. If approved → Create PR
5. If stuck → Escalate to Claude Code
6. Otherwise → Continue with feedback

### 4. Stuck Detection

Detects when implementation is stuck:
- Same blocking issues repeated 5+ times
- Code diff not meaningfully changing
- Same test failures persisting
- Identical output from implementer

### 5. Claude Code Fallback

When stuck, Claude Code (Opus 4.5) takes over:
- Receives full context of what was tried
- Has up to 10 iterations to resolve issues
- If still failing → Report failure

### 6. PR Creation

On success:
- Commits changes with proper message
- Pushes branch to remote
- Creates PR with detailed description
- Sends success notification

### 7. Notifications

Sends alerts via configured channels:
- WhatsApp (Twilio or CallMeBot)
- Email (SendGrid)
- Includes task summary, PR URL, and iteration count

## Logs

Each task creates logs at `logs/<project>/<task-id>/`:

```
logs/my-project/20240115-143022-a1b2c3d4/
├── state.json              # Current state and metadata
├── opencode/
│   ├── iter_1.json        # OpenCode iteration outputs
│   ├── iter_2.json
│   ├── diff_1.txt         # Code diffs
│   └── tests_1.txt        # Test results
├── codex/
│   ├── review_1.json      # Codex review outputs
│   └── review_2.json
├── claude/
│   └── iter_1.json        # Claude Code outputs (if escalated)
├── codex_feedback.md       # Current blocking issues
├── stuck_reason.md         # Why stuck (if applicable)
└── full_context.md         # Context for Claude escalation
```

## Troubleshooting

### Common Issues

**"OpenCode not installed"**
```bash
npm install -g opencode-ai
```

**"Codex not authenticated"**
```bash
codex auth login
```

**"gh not authenticated"**
```bash
gh auth login
```

**"ZAI_API_KEY not set"**
```bash
# Edit ~/.clawdbot-orchestrator.env and add your API key
nano ~/.clawdbot-orchestrator.env
```

### Debug Mode

Run doctor to diagnose issues:
```bash
./tools/doctor.sh
```

Check logs for a specific task:
```bash
cat logs/<project>/<task-id>/state.json | jq .
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a PR

## License

MIT License - see LICENSE file for details.

---

🦞 **Clawdbot** - Intelligent Implementer Orchestrator
