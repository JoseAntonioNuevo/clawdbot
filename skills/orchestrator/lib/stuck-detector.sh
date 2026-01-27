#!/bin/bash
# Stuck Detection Logic for Clawdbot Orchestrator
# Detects when the implementation loop is making no progress
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

WINDOW=${STUCK_DETECTION_WINDOW:-5}

usage() {
  cat << EOF
Stuck Detector for Clawdbot

Usage: $(basename "$0") <log_dir> [options]

Arguments:
  log_dir       Directory containing iteration logs

Options:
  -w, --window N      Number of iterations to analyze (default: 5)
  -v, --verbose       Show detailed analysis
  -h, --help          Show this help

Output:
  STUCK
  <reason 1>
  <reason 2>
  ...

  OR

  NOT_STUCK

Examples:
  $(basename "$0") /path/to/logs
  $(basename "$0") /path/to/logs --window 3 --verbose
EOF
}

VERBOSE=false
LOG_DIR=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -w|--window) WINDOW="$2"; shift 2 ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$LOG_DIR" ]]; then
        LOG_DIR="$1"
      else
        echo "Unknown argument: $1"; usage; exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$LOG_DIR" ]] && { echo "ERROR: log_dir is required"; usage; exit 1; }
[[ ! -d "$LOG_DIR" ]] && { echo "ERROR: log directory not found: $LOG_DIR"; exit 1; }

REASONS=()

log_verbose() {
  [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] $1" >&2
}

# Check 1: Same blocking issues repeated N times
check_repeated_issues() {
  log_verbose "Checking for repeated blocking issues..."

  local reviews
  reviews=($(ls -t "$LOG_DIR/codex/review_"*.json 2>/dev/null | head -n "$WINDOW"))

  if [[ ${#reviews[@]} -lt $WINDOW ]]; then
    log_verbose "Not enough reviews yet (${#reviews[@]} < $WINDOW)"
    return 1
  fi

  local prev_sig=""
  local repeats=0

  for r in "${reviews[@]}"; do
    # Extract a signature of blocking issues
    local sig
    sig=$(jq -r '[.issues[]? | select(.blocking == true or .severity == "critical") | "\(.file // ""):\(.line // ""):\(.code // .message // "")"] | sort | join("|")' "$r" 2>/dev/null || echo "")

    log_verbose "Review $r signature: ${sig:0:100}..."

    if [[ "$sig" == "$prev_sig" && -n "$sig" ]]; then
      ((repeats++))
      log_verbose "Repeat #$repeats detected"
    fi
    prev_sig="$sig"
  done

  if [[ $repeats -ge $((WINDOW - 1)) ]]; then
    log_verbose "Same blocking issues repeated $repeats times"
    return 0
  fi

  return 1
}

# Check 2: Diff not meaningfully changing
check_stale_diff() {
  log_verbose "Checking for stale diffs..."

  local diffs
  diffs=($(ls -t "$LOG_DIR/opencode/diff_"*.txt 2>/dev/null | head -n "$WINDOW"))

  if [[ ${#diffs[@]} -lt $WINDOW ]]; then
    log_verbose "Not enough diffs yet (${#diffs[@]} < $WINDOW)"
    return 1
  fi

  local hashes=()
  for d in "${diffs[@]}"; do
    local hash
    if [[ "$(uname)" == "Darwin" ]]; then
      hash=$(md5 -q "$d" 2>/dev/null || echo "empty")
    else
      hash=$(md5sum "$d" 2>/dev/null | cut -d' ' -f1 || echo "empty")
    fi
    hashes+=("$hash")
    log_verbose "Diff $d hash: $hash"
  done

  local unique
  unique=$(printf '%s\n' "${hashes[@]}" | sort -u | wc -l | tr -d ' ')

  log_verbose "Unique diff hashes: $unique out of $WINDOW"

  if [[ $unique -le 2 ]]; then
    return 0
  fi

  return 1
}

# Check 3: Same test failures persisting
check_stale_tests() {
  log_verbose "Checking for stale test failures..."

  local tests
  tests=($(ls -t "$LOG_DIR/opencode/tests_"*.txt 2>/dev/null | head -n "$WINDOW"))

  if [[ ${#tests[@]} -lt $WINDOW ]]; then
    log_verbose "Not enough test runs yet (${#tests[@]} < $WINDOW)"
    return 1
  fi

  local prev_failures=""
  local repeats=0

  for t in "${tests[@]}"; do
    # Extract failure lines and hash them
    local failures
    if [[ "$(uname)" == "Darwin" ]]; then
      failures=$(grep -iE "(FAIL|ERROR|failed|FAILED|error:|AssertionError)" "$t" 2>/dev/null | sort | md5 -q || echo "")
    else
      failures=$(grep -iE "(FAIL|ERROR|failed|FAILED|error:|AssertionError)" "$t" 2>/dev/null | sort | md5sum | cut -d' ' -f1 || echo "")
    fi

    log_verbose "Test $t failure hash: ${failures:0:32}"

    if [[ "$failures" == "$prev_failures" && -n "$failures" ]]; then
      ((repeats++))
      log_verbose "Same failures repeat #$repeats"
    fi
    prev_failures="$failures"
  done

  if [[ $repeats -ge $((WINDOW - 1)) ]]; then
    log_verbose "Same test failures repeated $repeats times"
    return 0
  fi

  return 1
}

# Check 4: OpenCode giving up or producing same output
check_same_output() {
  log_verbose "Checking for identical OpenCode outputs..."

  local outputs
  outputs=($(ls -t "$LOG_DIR/opencode/iter_"*.json 2>/dev/null | head -n "$WINDOW"))

  if [[ ${#outputs[@]} -lt $WINDOW ]]; then
    return 1
  fi

  local prev_hash=""
  local repeats=0

  for o in "${outputs[@]}"; do
    # Hash the output content (excluding timestamps and IDs)
    local hash
    if [[ "$(uname)" == "Darwin" ]]; then
      hash=$(jq -S 'del(.timestamp, .id, .created_at)' "$o" 2>/dev/null | md5 -q || echo "empty")
    else
      hash=$(jq -S 'del(.timestamp, .id, .created_at)' "$o" 2>/dev/null | md5sum | cut -d' ' -f1 || echo "empty")
    fi

    if [[ "$hash" == "$prev_hash" && "$hash" != "empty" ]]; then
      ((repeats++))
    fi
    prev_hash="$hash"
  done

  if [[ $repeats -ge $((WINDOW - 1)) ]]; then
    return 0
  fi

  return 1
}

# Main detection
STUCK=false

if check_repeated_issues; then
  REASONS+=("Same blocking issues repeated across $WINDOW iterations")
  STUCK=true
fi

if check_stale_diff; then
  REASONS+=("Code diff not meaningfully changing across $WINDOW iterations")
  STUCK=true
fi

if check_stale_tests; then
  REASONS+=("Same test failures persisting across $WINDOW iterations")
  STUCK=true
fi

if check_same_output; then
  REASONS+=("OpenCode producing identical output across $WINDOW iterations")
  STUCK=true
fi

# Output result
if [[ "$STUCK" == "true" ]]; then
  echo "STUCK"
  printf '%s\n' "${REASONS[@]}"
  exit 0
else
  echo "NOT_STUCK"
  exit 1
fi
