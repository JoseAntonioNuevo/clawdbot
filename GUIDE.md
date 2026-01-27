# Clawdbot Intelligent Implementer - User Guide

A complete guide to using Clawdbot's AI-powered coding orchestrator.

## What is Intelligent Implementer?

Intelligent Implementer is an autonomous coding workflow that:

1. Takes your task description
2. Creates an isolated git worktree
3. Calls AI coding agents (Kimi K2, OpenCode, or Claude Code) to implement
4. Has Codex review the code
5. Creates a Pull Request
6. Sends you an email notification

**You describe what you want. Clawdbot orchestrates the AI agents to build it.**

---

## Quick Start

```bash
clawdbot agent --local --agent main --message "Implement [your task] in [project path]"
```

**Example:**
```bash
clawdbot agent --local --agent main --message "Implement a /health endpoint that returns {status: 'ok'} in /Users/jose/my-api-project"
```

---

## Prerequisites

### 1. Install Clawdbot

```bash
npm install -g clawdbot
```

### 2. Run Initial Setup

```bash
clawdbot onboard
```

### 3. Configure Environment Variables

Add these to `~/.clawdbot/clawdbot.json` under the `"env"` section:

```json
{
  "env": {
    "ZAI_API_KEY": "your-zai-key",
    "MOONSHOT_API_KEY": "your-moonshot-key",
    "RESEND_API_KEY": "your-resend-key",
    "NOTIFY_EMAIL_TO": "your@email.com",
    "WORKTREE_BASE": "~/ai-worktrees"
  }
}
```

**Where to get API keys:**
- `ZAI_API_KEY`: [Z.AI Platform](https://z.ai) - Powers Clawdbot (GLM 4.7)
- `MOONSHOT_API_KEY`: [Moonshot AI](https://platform.moonshot.ai) - Powers Kimi K2
- `RESEND_API_KEY`: [Resend](https://resend.com) - For email notifications

### 4. Install Required CLI Tools

```bash
# Kimi CLI (primary implementer)
pip install kimi-cli

# OpenCode (fallback implementer)
npm install -g opencode

# Codex (code reviewer)
npm install -g @openai/codex

# GitHub CLI (for PR creation)
brew install gh
gh auth login

# Claude Code (last resort fallback)
npm install -g @anthropic-ai/claude-code
```

### 5. Link the Skills

```bash
# Create symlink to skills in Clawdbot workspace
ln -sf /path/to/clawdbot/skills ~/clawd/skills
```

### 6. Verify Setup

```bash
clawdbot skills check
```

You should see `intelligent-implementer` as "Ready".

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 CLAWDBOT (GLM 4.7)                          │
│                 THE ORCHESTRATOR                            │
│                                                             │
│  Reads task → Coordinates agents → Creates PR → Notifies   │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Kimi CLI   │    │   OpenCode   │    │ Claude Code  │
│   (Primary)  │    │  (Fallback)  │    │(Last Resort) │
│              │    │              │    │              │
│ Kimi K2 model│    │ Multi-model  │    │ Opus 4.5     │
└──────────────┘    └──────────────┘    └──────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
                    ┌──────────────┐
                    │  Codex CLI   │
                    │  (Reviewer)  │
                    └──────────────┘
```

### Workflow Steps

| Step | Action | Description |
|------|--------|-------------|
| 1 | **Initialize** | Create isolated git worktree with new branch |
| 2 | **Plan** | Analyze codebase and plan implementation |
| 3 | **Implement** | Call Kimi CLI (or fallbacks) to write code |
| 4 | **Review** | Call Codex to review the changes |
| 5 | **Iterate** | If rejected, loop back to step 3 with feedback |
| 6 | **Commit** | Stage and commit changes |
| 7 | **Push** | Push branch to remote |
| 8 | **PR** | Create Pull Request on GitHub |
| 9 | **Notify** | Send email notification with results |

### Agent Fallback Chain

```
Kimi CLI (default)
    │
    └─→ fails/hangs → OpenCode
                          │
                          └─→ fails/hangs → Claude Code
                                                │
                                                └─→ fails → Report error
```

---

## Usage Examples

### Basic Implementation

```bash
clawdbot agent --local --agent main --message "Implement a logout button in the header in /path/to/project"
```

### Bug Fix

```bash
clawdbot agent --local --agent main --message "Fix the login timeout bug - users are getting logged out after 5 minutes instead of 30 in /path/to/project"
```

### Feature with Details

```bash
clawdbot agent --local --agent main --message "Implement dark mode toggle in /path/to/project. Should: 1) Add toggle button in settings, 2) Store preference in localStorage, 3) Apply theme via CSS variables"
```

### Using Explicit Skill Invocation

```bash
clawdbot agent --local --agent main --message "Use the intelligent-implementer skill to add form validation to the signup form in /path/to/project"
```

---

## Project Requirements

For the workflow to complete successfully, your project must:

1. **Be a git repository**
   ```bash
   cd /your/project && git rev-parse --git-dir  # Should return ".git"
   ```

2. **Have a GitHub remote**
   ```bash
   git remote -v  # Should show origin with github.com URL
   ```

3. **Have a clean state** (recommended)
   ```bash
   git status  # Ideally no uncommitted changes
   ```

4. **Have a CLAUDE.md file** (highly recommended)

   Create a `CLAUDE.md` in your project root with:
   - Project architecture overview
   - Tech stack and dependencies
   - Coding standards and conventions
   - File structure explanation
   - Important patterns to follow

   **Why?** When Claude Code is used as a fallback implementer, it reads this file automatically to understand your project context. This leads to much better code that follows your existing patterns.

   Example structure:
   ```markdown
   # Project Name

   ## Architecture
   [How the project is structured]

   ## Tech Stack
   - Framework: Next.js 14
   - Styling: Tailwind CSS
   - Database: PostgreSQL

   ## Coding Standards
   - Use TypeScript strict mode
   - Components in PascalCase
   - Hooks prefixed with "use"

   ## File Structure
   src/
   ├── components/   # React components
   ├── hooks/        # Custom hooks
   └── utils/        # Helper functions
   ```

---

## Monitoring Progress

### Real-time Output

All progress is displayed in the terminal:
- Workflow steps being executed
- Which agent is currently working
- Review results from Codex
- PR URL when complete

### Email Notification

After completion, you'll receive an email with:
- Task summary
- PR link
- Implementation details
- Number of iterations

---

## Troubleshooting

### Skill Not Found

```bash
# Check if skill is recognized
clawdbot skills info intelligent-implementer

# If not found, ensure skills are linked
ln -sf /path/to/clawdbot/skills ~/clawd/skills
```

### Agent Hangs

If an agent takes too long (>60s), Clawdbot automatically tries the next one in the chain. If all fail, you'll get an error notification.

### PR Creation Fails

Ensure:
1. GitHub CLI is authenticated: `gh auth status`
2. Project has GitHub remote: `git remote -v`
3. You have push access to the repo

### Missing Environment Variables

```bash
# Check what's configured
cat ~/.clawdbot/clawdbot.json | jq '.env'

# Add missing variables
clawdbot config set env.RESEND_API_KEY "your-key"
```

---

## Configuration

### Skill Location

```
~/clawd/skills/intelligent-implementer/
├── SKILL.md                 # Main skill instructions
└── lib/
    ├── worktree.sh          # Git worktree helper
    └── send-resend-email.sh # Email notification helper
```

### Customizing the Workflow

Edit `~/clawd/skills/intelligent-implementer/SKILL.md` to:
- Change iteration limits
- Modify agent preferences
- Customize PR templates
- Adjust notification format

---

## Security Notes

- **Worktrees are isolated**: Changes happen in a separate directory, not your main repo
- **Review before merge**: PRs are created for review, not auto-merged
- **API keys are local**: Stored in your `~/.clawdbot/clawdbot.json`, not transmitted
- **Exec approvals**: Configure in `~/.clawdbot/exec-approvals.json` for command restrictions

---

## File Structure

```
clawdbot/
├── CLAUDE.md                    # Project documentation
├── GUIDE.md                     # This guide
├── clawdbot.json                # Project configuration
├── config/
│   └── env.template             # Environment template
└── skills/
    └── intelligent-implementer/
        ├── SKILL.md             # Orchestrator instructions
        └── lib/
            ├── worktree.sh      # Git worktree operations
            └── send-resend-email.sh  # Email via Resend
```

---

## Support

- **Clawdbot Issues**: https://github.com/moltbot/clawdbot/issues
- **Documentation**: https://docs.clawd.bot
- **Skills Directory**: https://clawdhub.com

---

## Quick Reference

```bash
# Run a task
clawdbot agent --local --agent main --message "Implement X in /path"

# Check skill status
clawdbot skills info intelligent-implementer

# View available skills
clawdbot skills list

# Check configuration
clawdbot config get env
```
