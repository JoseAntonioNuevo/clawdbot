#!/bin/bash
# Codex CLI Adapter for Clawdbot Orchestrator
# Runs Codex (GPT-5.2-Codex) for code review WITH FULL CONTEXT
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Codex Review Adapter for Clawdbot (GPT-5.2-Codex Reviewer)

Usage: $(basename "$0") [options]

Options:
  --context FILE        Path to context file (built by build-codex-context.sh)
  --workdir PATH        Working directory (default: current)
  --base BRANCH         Base branch for diff comparison
  --output FILE         Where to save the JSON output
  -m, --model MODEL     Model to use (default: gpt-5.2-codex)
  --timeout SECONDS     Timeout in seconds (default: 600)
  -q, --quiet           Suppress progress output
  -h, --help            Show this help

The --context file should contain the full review context including:
- Original task
- Implementation plan
- What was implemented
- Code diff
- Test results

Examples:
  $(basename "$0") --context codex_context.md --workdir /path/to/repo --base main --output review.json
EOF
}

# Default values
MODEL="${CODEX_MODEL:-gpt-5.2-codex}"
TIMEOUT=600
QUIET=false
CONTEXT_FILE=""
WORKDIR="$(pwd)"
BASE_BRANCH="main"
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --context) CONTEXT_FILE="$2"; shift 2 ;;
    -w|--workdir) WORKDIR="$2"; shift 2 ;;
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    -m|--model) MODEL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      # Legacy positional args: <workdir> <base_branch> <output_file>
      if [[ -z "$WORKDIR" || "$WORKDIR" == "$(pwd)" ]] && [[ -d "$1" ]]; then
        WORKDIR="$1"
      elif [[ "$BASE_BRANCH" == "main" ]] && [[ ! -f "$1" ]]; then
        BASE_BRANCH="$1"
      elif [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="$1"
      else
        echo "Unknown argument: $1" >&2; usage >&2; exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$OUTPUT_FILE" ]] && { echo "ERROR: --output required" >&2; usage >&2; exit 1; }

# Create output directory if needed (do this early so we can write error JSON)
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Helper to write structured error JSON
write_error_json() {
  local message="$1"
  local suggestion="$2"
  cat > "$OUTPUT_FILE" << EOF
{
  "approved": false,
  "summary": "$message",
  "issues": [
    {
      "severity": "critical",
      "blocking": true,
      "file": null,
      "line": null,
      "message": "$message",
      "suggestion": "$suggestion"
    }
  ],
  "missing": [],
  "positives": []
}
EOF
}

# Check if Codex is installed
if ! command -v codex &>/dev/null; then
  echo "ERROR: codex is not installed" >&2
  echo "Install with: npm install -g @openai/codex-cli" >&2
  write_error_json "Codex CLI is not installed" "Install with: npm install -g @openai/codex-cli"
  exit 1
fi

# Change to working directory
cd "$WORKDIR"

[[ "$QUIET" == "false" ]] && echo "Running Codex review ($MODEL) in $WORKDIR..."

# Build the full review prompt
REVIEW_PROMPT=""

if [[ -n "$CONTEXT_FILE" ]]; then
  # Context file was explicitly provided - it MUST exist
  if [[ ! -f "$CONTEXT_FILE" ]]; then
    echo "ERROR: Context file specified but not found: $CONTEXT_FILE" >&2
    echo "Full context is required for orchestrator runs." >&2
    write_error_json "Context file not found: $CONTEXT_FILE" "Ensure the context file exists before running Codex review"
    exit 1
  fi
  if [[ ! -r "$CONTEXT_FILE" ]]; then
    echo "ERROR: Context file not readable: $CONTEXT_FILE" >&2
    write_error_json "Context file not readable: $CONTEXT_FILE" "Check file permissions on the context file"
    exit 1
  fi
  [[ "$QUIET" == "false" ]] && echo "Using context from: $CONTEXT_FILE"
  REVIEW_PROMPT=$(cat "$CONTEXT_FILE")
else
  # No context file - only allowed for standalone/manual runs
  [[ "$QUIET" == "false" ]] && echo "WARNING: No context file provided, building basic review context..."
  [[ "$QUIET" == "false" ]] && echo "For orchestrator runs, use --context to provide full context."

  # Build basic context from git diff
  DIFF_STAT=$(git diff --stat "$BASE_BRANCH"...HEAD 2>/dev/null || echo "Unable to get diff stats")
  DIFF_CONTENT=$(git diff "$BASE_BRANCH"...HEAD 2>/dev/null || echo "Unable to get diff")

  REVIEW_PROMPT="# Code Review Request

## Changes to Review

### Files Changed
\`\`\`
$DIFF_STAT
\`\`\`

### Full Diff
\`\`\`diff
$DIFF_CONTENT
\`\`\`

## Review Criteria

1. Is the code correct and complete?
2. Are there any bugs or issues?
3. Do tests pass (if applicable)?
4. Is the code clean and maintainable?
5. Are there any security concerns?
"
fi

# Add JSON response format instructions
FULL_PROMPT="$REVIEW_PROMPT

---

## REQUIRED RESPONSE FORMAT

You MUST respond with valid JSON in this exact structure:

\`\`\`json
{
  \"approved\": boolean,
  \"summary\": \"1-2 sentence overall assessment\",
  \"issues\": [
    {
      \"severity\": \"critical\" | \"major\" | \"minor\",
      \"blocking\": boolean,
      \"file\": \"path/to/file.ts\",
      \"line\": number | null,
      \"message\": \"Description of the issue\",
      \"suggestion\": \"How to fix it\"
    }
  ],
  \"missing\": [\"List of missing functionality from the plan\"],
  \"positives\": [\"List of things done well\"]
}
\`\`\`

RULES:
- Set \"approved\": true ONLY if there are ZERO critical issues AND ZERO blocking issues
- If any tests fail, that is a blocking issue
- Be specific about file paths and line numbers
- Provide actionable suggestions for every issue
- If the implementation doesn't match the plan, list what's missing

Respond with ONLY the JSON, no other text."

# Create temp file for the prompt (avoids ARG_MAX limits)
PROMPT_FILE=$(mktemp)
echo "$FULL_PROMPT" > "$PROMPT_FILE"

# Run Codex with the full context
# Use stdin to avoid ARG_MAX limits with large contexts
RESULT=0
TEMP_OUTPUT=$(mktemp)

[[ "$QUIET" == "false" ]] && echo "Sending review request to Codex..."

# Try stdin first (preferred for large prompts), fall back to file arg
if timeout "$TIMEOUT" codex exec --model "$MODEL" - < "$PROMPT_FILE" > "$TEMP_OUTPUT" 2>&1; then
  RESULT=0
elif timeout "$TIMEOUT" codex exec --model "$MODEL" --prompt-file "$PROMPT_FILE" > "$TEMP_OUTPUT" 2>&1; then
  RESULT=0
else
  # Last resort: direct argument (may fail for very large contexts)
  PROMPT_SIZE=$(wc -c < "$PROMPT_FILE")
  if [[ $PROMPT_SIZE -gt 100000 ]]; then
    echo "ERROR: Prompt too large ($PROMPT_SIZE bytes) and codex doesn't support stdin/file input" >&2
    # Write error JSON so downstream steps can continue
    cat > "$OUTPUT_FILE" << EOF
{
  "approved": false,
  "summary": "Prompt too large ($PROMPT_SIZE bytes) - codex CLI doesn't support stdin or file input",
  "issues": [
    {
      "severity": "critical",
      "blocking": true,
      "file": null,
      "line": null,
      "message": "Review context exceeded maximum size for codex CLI",
      "suggestion": "Reduce context size or upgrade codex CLI to support stdin/file input"
    }
  ],
  "missing": [],
  "positives": []
}
EOF
    rm -f "$PROMPT_FILE" "$TEMP_OUTPUT"
    exit 1
  fi
  timeout "$TIMEOUT" codex exec --model "$MODEL" "$(cat "$PROMPT_FILE")" > "$TEMP_OUTPUT" 2>&1 || RESULT=$?
fi

rm -f "$PROMPT_FILE"

# Check result
if [[ $RESULT -eq 124 ]]; then
  echo "ERROR: Codex review timed out after ${TIMEOUT}s" >&2
  cat > "$OUTPUT_FILE" << EOF
{
  "approved": false,
  "summary": "Review timed out after ${TIMEOUT}s",
  "issues": [{"severity": "critical", "blocking": true, "file": null, "line": null, "message": "Review process timed out", "suggestion": "Try again or simplify the review scope"}],
  "missing": [],
  "positives": []
}
EOF
  rm -f "$TEMP_OUTPUT"
  exit 1
elif [[ $RESULT -ne 0 ]]; then
  echo "WARNING: Codex exited with code $RESULT" >&2
fi

# Process output - extract and validate JSON
if [[ -f "$TEMP_OUTPUT" && -s "$TEMP_OUTPUT" ]]; then
  # Try to parse as JSON directly
  if jq -e . "$TEMP_OUTPUT" > /dev/null 2>&1; then
    # Valid JSON - normalize structure
    jq '{
      approved: (.approved // false),
      summary: (.summary // "No summary provided"),
      issues: (.issues // []),
      missing: (.missing // []),
      positives: (.positives // [])
    }' "$TEMP_OUTPUT" > "$OUTPUT_FILE"
  else
    # Try to extract JSON from mixed output (between first { and last })
    JSON_EXTRACTED=$(mktemp)

    # Try multiple extraction strategies
    # 1. Look for ```json ... ``` blocks
    if grep -q '```json' "$TEMP_OUTPUT"; then
      sed -n '/```json/,/```/p' "$TEMP_OUTPUT" | sed '1d;$d' > "$JSON_EXTRACTED"
    # 2. Look for { ... } pattern
    elif grep -q '{' "$TEMP_OUTPUT"; then
      # Get content between first { and last }
      awk '/{/{p=1} p; /}/{if(p) exit}' "$TEMP_OUTPUT" > "$JSON_EXTRACTED"
    fi

    # Validate extracted JSON
    if [[ -s "$JSON_EXTRACTED" ]] && jq -e . "$JSON_EXTRACTED" > /dev/null 2>&1; then
      jq '{
        approved: (.approved // false),
        summary: (.summary // "No summary provided"),
        issues: (.issues // []),
        missing: (.missing // []),
        positives: (.positives // [])
      }' "$JSON_EXTRACTED" > "$OUTPUT_FILE"
    else
      # Failed to extract valid JSON - try AI-powered normalization
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      NORMALIZER="$SCRIPT_DIR/normalize-output.sh"

      if [[ -x "$NORMALIZER" ]]; then
        [[ "$QUIET" == "false" ]] && echo "JSON extraction failed, using AI normalizer..."
        "$NORMALIZER" \
          --input "$TEMP_OUTPUT" \
          --schema codex-review \
          --output "$OUTPUT_FILE" \
          ${QUIET:+"-q"} || {
            # Normalizer failed - create error response
            RAW_OUTPUT=$(cat "$TEMP_OUTPUT" | head -500 | jq -Rs .)
            cat > "$OUTPUT_FILE" << EOF
{
  "approved": false,
  "summary": "Failed to parse and normalize Codex response",
  "issues": [
    {
      "severity": "critical",
      "blocking": true,
      "file": null,
      "line": null,
      "message": "Codex output was not valid JSON and normalization failed",
      "suggestion": "Check Codex configuration or retry"
    }
  ],
  "missing": [],
  "positives": [],
  "_raw_output": $RAW_OUTPUT
}
EOF
        }
      else
        # No normalizer available - create error response
        RAW_OUTPUT=$(cat "$TEMP_OUTPUT" | head -500 | jq -Rs .)
        cat > "$OUTPUT_FILE" << EOF
{
  "approved": false,
  "summary": "Failed to parse Codex response as JSON",
  "issues": [
    {
      "severity": "critical",
      "blocking": true,
      "file": null,
      "line": null,
      "message": "Codex output was not valid JSON",
      "suggestion": "Check Codex configuration or retry"
    }
  ],
  "missing": [],
  "positives": [],
  "_raw_output": $RAW_OUTPUT
}
EOF
      fi
    fi

    rm -f "$JSON_EXTRACTED"
  fi
else
  # Empty output
  cat > "$OUTPUT_FILE" << EOF
{
  "approved": false,
  "summary": "Codex returned empty output",
  "issues": [{"severity": "critical", "blocking": true, "file": null, "line": null, "message": "No response from Codex", "suggestion": "Check Codex authentication and try again"}],
  "missing": [],
  "positives": []
}
EOF
fi

rm -f "$TEMP_OUTPUT"

[[ "$QUIET" == "false" ]] && echo "Review saved to: $OUTPUT_FILE"

# Show quick summary
if [[ "$QUIET" == "false" ]]; then
  APPROVED=$(jq -r '.approved // false' "$OUTPUT_FILE" 2>/dev/null || echo "false")
  SUMMARY=$(jq -r '.summary // "No summary"' "$OUTPUT_FILE" 2>/dev/null || echo "Parse error")
  ISSUE_COUNT=$(jq -r '.issues | length' "$OUTPUT_FILE" 2>/dev/null || echo "?")
  echo "---"
  echo "Approved: $APPROVED"
  echo "Issues: $ISSUE_COUNT"
  echo "Summary: $SUMMARY"
fi

exit 0
