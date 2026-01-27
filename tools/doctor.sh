#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

FAILURES=0

echo "🦞 Clawdbot Intelligent Implementer - Doctor"
echo "============================================"
echo ""

# Check Git
echo "Checking Git..."
if command -v git &>/dev/null; then
  GIT_VERSION=$(git --version | awk '{print $3}')
  pass "Git installed: $GIT_VERSION"

  # Check worktree support
  if git worktree list &>/dev/null 2>&1; then
    pass "Git worktree support available"
  else
    fail "Git worktree not supported (need git >= 2.5)"
  fi
else
  fail "Git not installed"
fi

# Check Clawdbot
echo ""
echo "Checking Clawdbot..."
if command -v clawdbot &>/dev/null; then
  CB_VERSION=$(clawdbot --version 2>/dev/null || echo "unknown")
  pass "Clawdbot installed: $CB_VERSION"
else
  warn "Clawdbot not installed (optional if using CLI directly)"
  info "  Install: brew install clawdbot/tap/clawdbot"
fi

# Check OpenCode
echo ""
echo "Checking OpenCode..."
if command -v opencode &>/dev/null; then
  OC_VERSION=$(opencode --version 2>/dev/null || echo "unknown")
  pass "OpenCode installed: $OC_VERSION"

  # Check auth
  if opencode auth status &>/dev/null 2>&1; then
    pass "OpenCode authenticated"
  else
    warn "OpenCode not authenticated (run: opencode auth login)"
  fi
else
  fail "OpenCode not installed"
  info "  Install: npm install -g opencode-ai"
fi

# Check Codex CLI
echo ""
echo "Checking Codex CLI..."
if command -v codex &>/dev/null; then
  CODEX_VERSION=$(codex --version 2>/dev/null || echo "unknown")
  pass "Codex CLI installed: $CODEX_VERSION"

  if codex auth status &>/dev/null 2>&1; then
    pass "Codex authenticated"
  else
    warn "Codex not authenticated (run: codex auth login)"
  fi
else
  fail "Codex CLI not installed"
  info "  Install: npm install -g @openai/codex-cli"
fi

# Check Claude Code
echo ""
echo "Checking Claude Code..."
if command -v claude &>/dev/null; then
  CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
  pass "Claude Code installed: $CLAUDE_VERSION"
else
  fail "Claude Code not installed"
  info "  Install: npm install -g @anthropic-ai/claude-code"
fi

# Check GitHub CLI
echo ""
echo "Checking GitHub CLI..."
if command -v gh &>/dev/null; then
  GH_VERSION=$(gh --version | head -1)
  pass "GitHub CLI installed: $GH_VERSION"

  if gh auth status &>/dev/null 2>&1; then
    pass "GitHub CLI authenticated"
  else
    warn "GitHub CLI not authenticated (run: gh auth login)"
  fi
else
  fail "GitHub CLI not installed"
  info "  Install: brew install gh"
fi

# Check jq
echo ""
echo "Checking utilities..."
if command -v jq &>/dev/null; then
  pass "jq installed"
else
  fail "jq not installed"
  info "  Install: brew install jq"
fi

# Check Node.js
if command -v node &>/dev/null; then
  NODE_VERSION=$(node --version)
  pass "Node.js installed: $NODE_VERSION"

  # Check minimum version
  NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
  if [[ "$NODE_MAJOR" -ge 18 ]]; then
    pass "Node.js version >= 18"
  else
    warn "Node.js version < 18 (some features may not work)"
  fi
else
  fail "Node.js not installed"
  info "  Install: brew install node"
fi

# Check API Keys & CLI Authentication
echo ""
echo "Checking Configuration..."
ENV_FILE="$HOME/.clawdbot-orchestrator.env"

if [[ -f "$ENV_FILE" ]]; then
  pass "Environment file exists: $ENV_FILE"

  # Check permissions (macOS vs Linux)
  if [[ "$(uname)" == "Darwin" ]]; then
    PERMS=$(stat -f "%OLp" "$ENV_FILE" 2>/dev/null || echo "unknown")
  else
    PERMS=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || echo "unknown")
  fi

  if [[ "$PERMS" == "600" ]]; then
    pass "Environment file permissions correct (600)"
  else
    warn "Environment file permissions should be 600 (current: $PERMS)"
    info "  Fix: chmod 600 $ENV_FILE"
  fi

  # Source and check keys
  set +u
  source "$ENV_FILE"
  set -u

  # Only ZAI_API_KEY is required - CLIs handle their own auth
  [[ -n "${ZAI_API_KEY:-}" ]] && pass "ZAI_API_KEY set" || fail "ZAI_API_KEY not set"

  # Check at least one notification method
  if [[ -n "${TWILIO_ACCOUNT_SID:-}" && -n "${TWILIO_AUTH_TOKEN:-}" ]]; then
    pass "Twilio WhatsApp configured"
  elif [[ -n "${CALLMEBOT_APIKEY:-}" && -n "${CALLMEBOT_PHONE:-}" ]]; then
    pass "CallMeBot WhatsApp configured"
  elif [[ -n "${SENDGRID_API_KEY:-}" ]]; then
    pass "SendGrid email configured"
  else
    warn "No notification method configured"
    info "  Configure Twilio, CallMeBot, or SendGrid in $ENV_FILE"
  fi
else
  warn "Environment file not found: $ENV_FILE"
  info "  Create from template: cp config/env.template ~/.clawdbot-orchestrator.env"
  info "  Then: chmod 600 ~/.clawdbot-orchestrator.env"
fi

# CLI Authentication Summary
echo ""
echo "CLI Authentication Status..."
info "OpenCode, Codex, and Claude Code use their own built-in authentication."
info "Make sure each CLI is logged in (checked above)."

# Check worktree directory
echo ""
echo "Checking directories..."
WORKTREE_BASE="${WORKTREE_BASE:-$HOME/ai-worktrees}"
if [[ -d "$WORKTREE_BASE" ]]; then
  pass "Worktree directory exists: $WORKTREE_BASE"

  # Check disk space
  if command -v df &>/dev/null; then
    AVAIL=$(df -h "$WORKTREE_BASE" | tail -1 | awk '{print $4}')
    info "Available space: $AVAIL"
  fi
else
  warn "Worktree directory doesn't exist (will be created): $WORKTREE_BASE"
  info "  Create: mkdir -p $WORKTREE_BASE"
fi

# Check logs directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$CLAWDBOT_ROOT/logs"

if [[ -d "$LOGS_DIR" ]]; then
  pass "Logs directory exists: $LOGS_DIR"
else
  warn "Logs directory doesn't exist (will be created): $LOGS_DIR"
fi

# Check Node dependencies
echo ""
echo "Checking Node.js dependencies..."
if [[ -f "$CLAWDBOT_ROOT/package.json" ]]; then
  if [[ -d "$CLAWDBOT_ROOT/node_modules" ]]; then
    pass "Node modules installed"

    # Check specific packages
    if [[ -d "$CLAWDBOT_ROOT/node_modules/twilio" ]]; then
      pass "twilio package installed"
    else
      warn "twilio package not installed (run: npm install)"
    fi

    if [[ -d "$CLAWDBOT_ROOT/node_modules/@sendgrid" ]]; then
      pass "@sendgrid/mail package installed"
    else
      warn "@sendgrid/mail package not installed (run: npm install)"
    fi
  else
    warn "Node modules not installed"
    info "  Run: cd $CLAWDBOT_ROOT && npm install"
  fi
fi

# Summary
echo ""
echo "============================================"
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}All checks passed!${NC}"
  echo ""
  echo "You're ready to use Clawdbot Intelligent Implementer."
  echo "Run: clawdbot 'implement <task> on <project>'"
  exit 0
else
  echo -e "${RED}$FAILURES check(s) failed${NC}"
  echo ""
  echo "Please fix the issues above before using Clawdbot."
  exit 1
fi
