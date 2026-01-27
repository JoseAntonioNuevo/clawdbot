#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

echo "🦞 Clawdbot Intelligent Implementer - Installer"
echo "================================================"
echo ""

# Detect OS
OS="$(uname -s)"
case "$OS" in
  Darwin) PACKAGE_MANAGER="brew" ;;
  Linux)
    if command -v apt-get &>/dev/null; then
      PACKAGE_MANAGER="apt"
    elif command -v yum &>/dev/null; then
      PACKAGE_MANAGER="yum"
    else
      PACKAGE_MANAGER="unknown"
    fi
    ;;
  *) PACKAGE_MANAGER="unknown" ;;
esac

log "Detected OS: $OS (package manager: $PACKAGE_MANAGER)"

# Check/Install Homebrew (macOS)
if [[ "$OS" == "Darwin" ]]; then
  if ! command -v brew &>/dev/null; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    success "Homebrew installed"
  else
    success "Homebrew already installed"
  fi
fi

# Install system dependencies
log "Installing system dependencies..."

install_package() {
  local name="$1"
  local brew_name="${2:-$1}"

  if command -v "$name" &>/dev/null; then
    success "$name already installed"
    return 0
  fi

  case "$PACKAGE_MANAGER" in
    brew) brew install "$brew_name" 2>/dev/null || true ;;
    apt) sudo apt-get install -y "$name" 2>/dev/null || true ;;
    yum) sudo yum install -y "$name" 2>/dev/null || true ;;
    *)
      warn "Cannot auto-install $name. Please install manually."
      return 1
      ;;
  esac

  if command -v "$name" &>/dev/null; then
    success "$name installed"
  else
    error "Failed to install $name"
    return 1
  fi
}

install_package git
install_package jq
install_package gh
install_package node

# Install Clawdbot (if available)
log "Installing Clawdbot..."
if command -v clawdbot &>/dev/null; then
  success "Clawdbot already installed"
else
  if [[ "$PACKAGE_MANAGER" == "brew" ]]; then
    brew tap clawdbot/tap 2>/dev/null || true
    brew install clawdbot 2>/dev/null || warn "Clawdbot not available via brew (optional)"
  else
    warn "Clawdbot installation skipped (brew not available)"
  fi
fi

# Install Node.js CLI tools
log "Installing Node.js CLI tools..."

install_npm_package() {
  local name="$1"
  local package="$2"

  if command -v "$name" &>/dev/null; then
    success "$name already installed"
  else
    log "Installing $package..."
    npm install -g "$package" 2>/dev/null || {
      warn "Failed to install $package globally. Trying with sudo..."
      sudo npm install -g "$package" 2>/dev/null || error "Failed to install $package"
    }

    if command -v "$name" &>/dev/null; then
      success "$name installed"
    else
      error "Failed to install $name"
    fi
  fi
}

install_npm_package opencode opencode-ai
install_npm_package codex @openai/codex-cli
install_npm_package claude @anthropic-ai/claude-code

# Create directories
log "Creating directories..."

mkdir -p "$HOME/ai-worktrees"
success "Created: ~/ai-worktrees"

mkdir -p "$CLAWDBOT_ROOT/logs"
success "Created: $CLAWDBOT_ROOT/logs"

# Setup environment file
log "Setting up environment file..."

ENV_FILE="$HOME/.clawdbot-orchestrator.env"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$CLAWDBOT_ROOT/config/env.template" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  success "Created: $ENV_FILE"
  echo ""
  warn "IMPORTANT: Edit $ENV_FILE and add your API keys"
else
  success "Environment file already exists: $ENV_FILE"
fi

# Install Node.js dependencies
log "Installing Node.js dependencies..."

cd "$CLAWDBOT_ROOT"
if npm install 2>/dev/null; then
  success "Node.js dependencies installed"
else
  warn "Failed to install Node.js dependencies. Try: npm install"
fi

# Make scripts executable
log "Making scripts executable..."

chmod +x "$CLAWDBOT_ROOT/tools/"*.sh 2>/dev/null || true
chmod +x "$CLAWDBOT_ROOT/skills/"*/lib/*.sh 2>/dev/null || true
success "Scripts made executable"

# Create symlink for worktrees (optional)
if [[ ! -L "$CLAWDBOT_ROOT/worktrees" ]]; then
  ln -sf "$HOME/ai-worktrees" "$CLAWDBOT_ROOT/worktrees" 2>/dev/null || true
  success "Created symlink: $CLAWDBOT_ROOT/worktrees -> ~/ai-worktrees"
fi

# Summary
echo ""
echo "================================================"
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit ~/.clawdbot-orchestrator.env and add your API keys"
echo "  2. Run: gh auth login (if not already authenticated)"
echo "  3. Run: ./tools/doctor.sh to verify setup"
echo ""
echo "Then start using Clawdbot:"
echo "  clawdbot 'implement <task description> on <project path>'"
