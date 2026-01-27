#!/bin/bash
# Test Auto-Detection and Runner for Clawdbot Orchestrator
# Detects the project's test framework and runs tests
set -euo pipefail

usage() {
  cat << EOF
Test Detector and Runner for Clawdbot

Usage: $(basename "$0") <project_path> [options]

Arguments:
  project_path    Path to the project to test

Options:
  --timeout SECONDS   Timeout for test execution (default: 300)
  --dry-run           Just detect tests, don't run them
  -q, --quiet         Suppress progress output
  -h, --help          Show this help

Examples:
  $(basename "$0") /path/to/project
  $(basename "$0") . --dry-run
  $(basename "$0") /path/to/project --timeout 600
EOF
}

PROJECT_PATH=""
TIMEOUT=300
DRY_RUN=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$PROJECT_PATH" ]]; then
        PROJECT_PATH="$1"
      else
        echo "Unknown argument: $1"; usage; exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$PROJECT_PATH" ]] && { echo "ERROR: project_path is required"; usage; exit 1; }
[[ ! -d "$PROJECT_PATH" ]] && { echo "ERROR: directory not found: $PROJECT_PATH"; exit 1; }

cd "$PROJECT_PATH"

log() {
  [[ "$QUIET" == "false" ]] && echo "$1"
}

# Detection functions
detect_node() {
  [[ -f "package.json" ]]
}

detect_python() {
  [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]] || [[ -f "Pipfile" ]]
}

detect_go() {
  [[ -f "go.mod" ]]
}

detect_rust() {
  [[ -f "Cargo.toml" ]]
}

detect_ruby() {
  [[ -f "Gemfile" ]]
}

detect_java_maven() {
  [[ -f "pom.xml" ]]
}

detect_java_gradle() {
  [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]
}

# Get test command
get_test_command() {
  # Node.js projects
  if detect_node; then
    if [[ -f "package.json" ]]; then
      # Check for test script
      if jq -e '.scripts.test' package.json > /dev/null 2>&1; then
        local test_script
        test_script=$(jq -r '.scripts.test' package.json)
        if [[ "$test_script" != "null" && "$test_script" != *"no test"* && "$test_script" != *"Error"* ]]; then
          # Determine package manager
          if [[ -f "pnpm-lock.yaml" ]]; then
            echo "pnpm test"
          elif [[ -f "yarn.lock" ]]; then
            echo "yarn test"
          elif [[ -f "bun.lockb" ]]; then
            echo "bun test"
          else
            echo "npm test"
          fi
          return 0
        fi
      fi
    fi
  fi

  # Python projects
  if detect_python; then
    if [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]] || [[ -d "tests" ]]; then
      if command -v pytest &>/dev/null; then
        echo "pytest"
        return 0
      elif command -v python3 &>/dev/null; then
        echo "python3 -m pytest"
        return 0
      fi
    fi
    # Fallback to unittest
    if [[ -d "tests" ]] || [[ -d "test" ]]; then
      echo "python3 -m unittest discover"
      return 0
    fi
  fi

  # Go projects
  if detect_go; then
    echo "go test ./..."
    return 0
  fi

  # Rust projects
  if detect_rust; then
    echo "cargo test"
    return 0
  fi

  # Ruby projects
  if detect_ruby; then
    if [[ -f "Rakefile" ]] && grep -q "rspec" Gemfile 2>/dev/null; then
      echo "bundle exec rspec"
      return 0
    elif [[ -d "test" ]]; then
      echo "bundle exec rake test"
      return 0
    fi
  fi

  # Java Maven
  if detect_java_maven; then
    echo "mvn test"
    return 0
  fi

  # Java Gradle
  if detect_java_gradle; then
    if [[ -f "gradlew" ]]; then
      echo "./gradlew test"
    else
      echo "gradle test"
    fi
    return 0
  fi

  # Check for Makefile with test target
  if [[ -f "Makefile" ]]; then
    if grep -q "^test:" Makefile; then
      echo "make test"
      return 0
    fi
  fi

  # No tests detected
  return 1
}

# Main
log "Detecting test framework in $PROJECT_PATH..."

TEST_CMD=""
if TEST_CMD=$(get_test_command); then
  log "Detected test command: $TEST_CMD"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "TEST_COMMAND=$TEST_CMD"
    exit 0
  fi

  log "Running tests (timeout: ${TIMEOUT}s)..."
  echo "========================================"
  echo "Test Command: $TEST_CMD"
  echo "========================================"

  RESULT=0
  timeout "$TIMEOUT" bash -c "$TEST_CMD" 2>&1 || RESULT=$?

  echo "========================================"
  if [[ $RESULT -eq 0 ]]; then
    echo "Tests PASSED"
  elif [[ $RESULT -eq 124 ]]; then
    echo "Tests TIMED OUT after ${TIMEOUT}s"
  else
    echo "Tests FAILED (exit code: $RESULT)"
  fi
  echo "========================================"

  exit $RESULT
else
  log "No test framework detected"
  echo "NO_TESTS_FOUND"
  exit 0
fi
