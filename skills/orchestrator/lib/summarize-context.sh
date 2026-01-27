#!/bin/bash
# Context Summarizer for Clawdbot Orchestrator
# Uses AI to intelligently summarize large contexts while preserving essential information
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Context Summarizer for Clawdbot

Uses AI to create intelligent summaries of large contexts, preserving
essential information while reducing token count.

Usage: $(basename "$0") [options]

Options:
  --input FILE          Input file to summarize
  --type TYPE           Type of content: diff|implementation|feedback|tests|codebase
  --output FILE         Where to write the summary
  --max-tokens N        Target max tokens for summary (default: 2000)
  --model MODEL         Model to use (default: uses opencode with Kimi)
  -q, --quiet           Suppress progress output
  -h, --help            Show this help

Types:
  diff            Summarize code changes (what was added/modified/deleted)
  implementation  Summarize what was implemented and how
  feedback        Summarize review feedback and issues
  tests           Summarize test results (pass/fail/errors)
  codebase        Summarize codebase structure and patterns

Examples:
  $(basename "$0") --input large_diff.txt --type diff --output summary.md
  $(basename "$0") --input iteration_001/ --type implementation --output impl_summary.md
EOF
}

INPUT=""
TYPE=""
OUTPUT=""
MAX_TOKENS=2000
MODEL="${SUMMARIZER_MODEL:-moonshot/kimi-k2.5-preview}"
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --input) INPUT="$2"; shift 2 ;;
    --type) TYPE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$INPUT" ]] && { echo "ERROR: --input required" >&2; exit 1; }
[[ -z "$TYPE" ]] && { echo "ERROR: --type required" >&2; exit 1; }
[[ -z "$OUTPUT" ]] && { echo "ERROR: --output required" >&2; exit 1; }

# Check if input exists
if [[ -f "$INPUT" ]]; then
  CONTENT=$(cat "$INPUT")
elif [[ -d "$INPUT" ]]; then
  # Directory - concatenate relevant files with proper newlines
  CONTENT=""
  for f in "$INPUT"/*.md "$INPUT"/*.txt "$INPUT"/*.json; do
    if [[ -f "$f" ]]; then
      CONTENT="${CONTENT}"$'\n\n'"--- File: $f ---"$'\n'"$(cat "$f")"
    fi
  done
else
  echo "ERROR: Input not found: $INPUT" >&2
  exit 1
fi

# Check content size - if small enough, just copy
CONTENT_SIZE=${#CONTENT}
if [[ $CONTENT_SIZE -lt 4000 ]]; then
  [[ "$QUIET" == "false" ]] && echo "Content is small ($CONTENT_SIZE chars), copying as-is"
  echo "$CONTENT" > "$OUTPUT"
  exit 0
fi

[[ "$QUIET" == "false" ]] && echo "Summarizing $TYPE content ($CONTENT_SIZE chars)..."

mkdir -p "$(dirname "$OUTPUT")"

# Build type-specific prompt
SYSTEM_PROMPT=""
case "$TYPE" in
  diff)
    SYSTEM_PROMPT="You are a code change summarizer. Analyze this diff and create a structured summary.

Output format:
## Files Changed
- List each file with (added/modified/deleted) status

## Key Changes
1. [Most important change with brief explanation]
2. [Second most important change]
...

## Code Patterns
- New functions/classes added
- Functions modified
- Dependencies changed

## Potential Issues
- Any obvious bugs or concerns in the changes

Keep the summary concise but preserve ALL important details about WHAT changed and WHY it matters."
    ;;

  implementation)
    SYSTEM_PROMPT="You are an implementation summarizer. Analyze what was implemented and create a structured summary.

Output format:
## Approach Taken
[1-2 sentences describing the implementation approach]

## What Was Built
- [Key component 1]
- [Key component 2]
...

## Files Created/Modified
- List with brief description of changes

## Technical Decisions
- Any notable decisions or patterns used

## Current State
- What works
- What doesn't work (if applicable)

Preserve the essential details that would help understand what was done."
    ;;

  feedback)
    SYSTEM_PROMPT="You are a feedback summarizer. Analyze this code review feedback and create a structured summary.

Output format:
## Overall Verdict
[Approved/Rejected with one-line reason]

## Critical Issues (must fix)
1. [Issue description] - File: X, Line: Y
   - How to fix: [suggestion]

## Major Issues
1. [Issue description]
   - How to fix: [suggestion]

## Minor Issues
- [List briefly]

## Missing Functionality
- [What wasn't implemented that should have been]

## What Was Done Well
- [Positive feedback]

Preserve ALL critical and blocking issues with their exact locations and fix suggestions."
    ;;

  tests)
    SYSTEM_PROMPT="You are a test results summarizer. Analyze these test results and create a structured summary.

Output format:
## Test Summary
- Total: X tests
- Passed: Y
- Failed: Z
- Skipped: W

## Failed Tests
1. [Test name]
   - Error: [brief error description]
   - File: [if available]

2. [Test name]
   ...

## Error Patterns
- [Common patterns in failures if any]

## Recommendations
- [What needs to be fixed to make tests pass]

Focus on the failures and what's needed to fix them."
    ;;

  codebase)
    SYSTEM_PROMPT="You are a codebase summarizer. Analyze this codebase information and create a structured summary.

Output format:
## Project Type
[Language, framework, purpose]

## Key Directories
- [dir]: [purpose]

## Important Files
- [file]: [purpose]

## Dependencies
- [Key dependencies relevant to implementation]

## Patterns & Conventions
- [Coding patterns used]
- [Naming conventions]

## Entry Points
- [Where to start for different tasks]

Focus on information that would help someone implement new features."
    ;;

  *)
    SYSTEM_PROMPT="Summarize the following content, preserving all essential information while being concise. Structure your output clearly with headers and bullet points."
    ;;
esac

# Create prompt file
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << EOF
$SYSTEM_PROMPT

Target length: approximately $MAX_TOKENS tokens (be concise but complete).

---

CONTENT TO SUMMARIZE:

$CONTENT
EOF

# Run summarization using OpenCode (Kimi)
TEMP_OUTPUT=$(mktemp)

if command -v opencode &>/dev/null; then
  # Use stdin to avoid ARG_MAX limits with large contexts
  PROMPT_SIZE=$(wc -c < "$PROMPT_FILE")
  RUN_SUCCESS=false

  # Try stdin first (preferred for large prompts)
  if timeout 120 opencode run -m "$MODEL" --allowedTools "" -q - < "$PROMPT_FILE" > "$TEMP_OUTPUT" 2>&1; then
    RUN_SUCCESS=true
  # Try --prompt-file if available
  elif timeout 120 opencode run -m "$MODEL" --allowedTools "" -q --prompt-file "$PROMPT_FILE" > "$TEMP_OUTPUT" 2>&1; then
    RUN_SUCCESS=true
  # Last resort: direct argument (check size first)
  elif [[ $PROMPT_SIZE -lt 100000 ]]; then
    timeout 120 opencode run -m "$MODEL" --allowedTools "" -q "$(cat "$PROMPT_FILE")" > "$TEMP_OUTPUT" 2>&1 || true
    RUN_SUCCESS=true
  fi
else
  # Fallback: just truncate intelligently (use CONTENT, not INPUT which may be a directory)
  echo "WARNING: opencode not available, using simple truncation" >&2
  head -c 8000 <<< "$CONTENT" > "$OUTPUT"
  echo "" >> "$OUTPUT"
  echo "[... content truncated for context management ...]" >> "$OUTPUT"
  rm -f "$PROMPT_FILE"
  exit 0
fi

rm -f "$PROMPT_FILE"

# Extract the summary from output
if [[ -s "$TEMP_OUTPUT" ]]; then
  # Try to extract just the text content (remove JSON wrapper if present)
  if jq -e '.result' "$TEMP_OUTPUT" > /dev/null 2>&1; then
    jq -r '.result' "$TEMP_OUTPUT" > "$OUTPUT"
  elif jq -e '.content' "$TEMP_OUTPUT" > /dev/null 2>&1; then
    jq -r '.content' "$TEMP_OUTPUT" > "$OUTPUT"
  else
    # Just use the output as-is
    cat "$TEMP_OUTPUT" > "$OUTPUT"
  fi
else
  # Fallback if summarization failed
  echo "WARNING: Summarization failed, using truncated content" >&2
  head -c 8000 <<< "$CONTENT" > "$OUTPUT"
  echo "" >> "$OUTPUT"
  echo "[... content truncated ...]" >> "$OUTPUT"
fi

rm -f "$TEMP_OUTPUT"

[[ "$QUIET" == "false" ]] && echo "Summary written to: $OUTPUT"
[[ "$QUIET" == "false" ]] && echo "Original: $CONTENT_SIZE chars → Summary: $(wc -c < "$OUTPUT") chars"
