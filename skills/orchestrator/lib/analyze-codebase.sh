#!/bin/bash
# Analyze Codebase for Context
# Creates a summary of the codebase structure and patterns
set -euo pipefail

WORKTREE="${1:-.}"

if [[ ! -d "$WORKTREE" ]]; then
  echo "ERROR: Directory not found: $WORKTREE" >&2
  exit 1
fi

cd "$WORKTREE"

{
  echo "# Codebase Analysis"
  echo ""
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  # Project type detection
  echo "## Project Type"
  echo ""

  if [[ -f "package.json" ]]; then
    echo "- **Type**: Node.js / JavaScript / TypeScript"
    if [[ -f "tsconfig.json" ]]; then
      echo "- **Language**: TypeScript"
    else
      echo "- **Language**: JavaScript"
    fi

    # Package manager
    if [[ -f "pnpm-lock.yaml" ]]; then
      echo "- **Package Manager**: pnpm"
    elif [[ -f "yarn.lock" ]]; then
      echo "- **Package Manager**: Yarn"
    elif [[ -f "bun.lockb" ]]; then
      echo "- **Package Manager**: Bun"
    else
      echo "- **Package Manager**: npm"
    fi

    # Framework detection
    if grep -q '"next"' package.json 2>/dev/null; then
      echo "- **Framework**: Next.js"
    elif grep -q '"react"' package.json 2>/dev/null; then
      echo "- **Framework**: React"
    elif grep -q '"vue"' package.json 2>/dev/null; then
      echo "- **Framework**: Vue"
    elif grep -q '"express"' package.json 2>/dev/null; then
      echo "- **Framework**: Express"
    fi
  elif [[ -f "requirements.txt" || -f "pyproject.toml" || -f "setup.py" ]]; then
    echo "- **Type**: Python"
    if [[ -f "pyproject.toml" ]]; then
      if grep -q "django" pyproject.toml 2>/dev/null; then
        echo "- **Framework**: Django"
      elif grep -q "fastapi" pyproject.toml 2>/dev/null; then
        echo "- **Framework**: FastAPI"
      elif grep -q "flask" pyproject.toml 2>/dev/null; then
        echo "- **Framework**: Flask"
      fi
    fi
  elif [[ -f "go.mod" ]]; then
    echo "- **Type**: Go"
  elif [[ -f "Cargo.toml" ]]; then
    echo "- **Type**: Rust"
  elif [[ -f "Gemfile" ]]; then
    echo "- **Type**: Ruby"
    if grep -q "rails" Gemfile 2>/dev/null; then
      echo "- **Framework**: Ruby on Rails"
    fi
  else
    echo "- **Type**: Unknown"
  fi
  echo ""

  # Directory structure
  echo "## Directory Structure"
  echo ""
  echo "\`\`\`"
  # Show top-level structure, excluding common noise
  find . -maxdepth 2 -type d \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    ! -path "*/dist/*" \
    ! -path "*/build/*" \
    ! -path "*/__pycache__/*" \
    ! -path "*/.next/*" \
    ! -path "*/coverage/*" \
    ! -name "node_modules" \
    ! -name ".git" \
    | head -50 | sort
  echo "\`\`\`"
  echo ""

  # Key files
  echo "## Key Files"
  echo ""

  # Entry points
  for f in "src/index.ts" "src/index.js" "src/main.ts" "src/main.js" \
           "index.ts" "index.js" "main.py" "app.py" "main.go" "src/main.rs"; do
    if [[ -f "$f" ]]; then
      echo "- **Entry Point**: \`$f\`"
    fi
  done

  # Config files
  for f in "package.json" "tsconfig.json" "pyproject.toml" "go.mod" "Cargo.toml"; do
    if [[ -f "$f" ]]; then
      echo "- **Config**: \`$f\`"
    fi
  done

  # Test files
  if [[ -d "tests" || -d "test" || -d "__tests__" || -d "spec" ]]; then
    TEST_DIR=$(ls -d tests test __tests__ spec 2>/dev/null | head -1)
    echo "- **Tests**: \`$TEST_DIR/\`"
  fi
  echo ""

  # Source files count
  echo "## Code Statistics"
  echo ""

  TS_COUNT=$(find . -name "*.ts" -o -name "*.tsx" 2>/dev/null | grep -v node_modules | grep -v ".d.ts" | wc -l | tr -d ' ')
  JS_COUNT=$(find . -name "*.js" -o -name "*.jsx" 2>/dev/null | grep -v node_modules | wc -l | tr -d ' ')
  PY_COUNT=$(find . -name "*.py" 2>/dev/null | grep -v __pycache__ | wc -l | tr -d ' ')
  GO_COUNT=$(find . -name "*.go" 2>/dev/null | wc -l | tr -d ' ')
  RS_COUNT=$(find . -name "*.rs" 2>/dev/null | wc -l | tr -d ' ')

  [[ $TS_COUNT -gt 0 ]] && echo "- TypeScript files: $TS_COUNT"
  [[ $JS_COUNT -gt 0 ]] && echo "- JavaScript files: $JS_COUNT"
  [[ $PY_COUNT -gt 0 ]] && echo "- Python files: $PY_COUNT"
  [[ $GO_COUNT -gt 0 ]] && echo "- Go files: $GO_COUNT"
  [[ $RS_COUNT -gt 0 ]] && echo "- Rust files: $RS_COUNT"
  echo ""

  # Dependencies (if package.json)
  if [[ -f "package.json" ]]; then
    echo "## Key Dependencies"
    echo ""
    echo "\`\`\`json"
    jq -r '.dependencies // {} | to_entries | .[:15] | from_entries' package.json 2>/dev/null || echo "{}"
    echo "\`\`\`"
    echo ""
  fi

  # README summary
  if [[ -f "README.md" ]]; then
    echo "## README Summary"
    echo ""
    head -50 README.md | sed 's/^/> /'
    echo ""
  fi

  # Recent git history
  echo "## Recent Changes"
  echo ""
  echo "\`\`\`"
  git log --oneline -10 2>/dev/null || echo "(Not a git repository)"
  echo "\`\`\`"

} 2>/dev/null

exit 0
