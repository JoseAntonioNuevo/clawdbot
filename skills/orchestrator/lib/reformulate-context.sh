#!/bin/bash
# Context Reformulator for Clawdbot Orchestrator
# Uses GLM 4.7 to intelligently reformulate context for Claude (Planner)
# Creates a concise, focused prompt from all available context
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Context Reformulator for Clawdbot (GLM 4.7)

Takes all context from a failed iteration and creates a clean, concise
prompt for Claude Code to create a revised plan.

Usage: $(basename "$0") [options]

Required:
  --task FILE             Original task description
  --iteration N           Current iteration number
  --output FILE           Where to write the reformulated prompt

Context inputs (at least codex-feedback required):
  --plan FILE             Claude's plan from this iteration
  --implementation FILE   What Kimi implemented (diff/summary)
  --codex-feedback FILE   Codex review feedback (why it failed)
  --test-results FILE     Test output (if available)
  --history DIR           Previous iterations directory

Optional:
  --codebase FILE         Codebase summary (included if small)
  --model MODEL           Model to use (default: zai/glm-4.7)
  --max-output N          Target max tokens for output (default: 4000)
  -q, --quiet             Suppress progress output
  -h, --help              Show this help

Examples:
  $(basename "$0") --task task.md --plan plan.md --implementation impl.md \\
    --codex-feedback feedback.json --iteration 2 --output claude_prompt.md
EOF
}

# Default values
MODEL="${REFORMULATOR_MODEL:-zai/glm-4.7}"
MAX_OUTPUT=4000
QUIET=false
TASK_FILE=""
PLAN_FILE=""
IMPL_FILE=""
CODEX_FEEDBACK=""
TEST_RESULTS=""
HISTORY_DIR=""
CODEBASE_FILE=""
ITERATION=1
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --task) TASK_FILE="$2"; shift 2 ;;
    --plan) PLAN_FILE="$2"; shift 2 ;;
    --implementation) IMPL_FILE="$2"; shift 2 ;;
    --codex-feedback) CODEX_FEEDBACK="$2"; shift 2 ;;
    --test-results) TEST_RESULTS="$2"; shift 2 ;;
    --history) HISTORY_DIR="$2"; shift 2 ;;
    --codebase) CODEBASE_FILE="$2"; shift 2 ;;
    --iteration) ITERATION="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --max-output) MAX_OUTPUT="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Validation
[[ -z "$TASK_FILE" ]] && { echo "ERROR: --task required" >&2; exit 1; }
[[ -z "$CODEX_FEEDBACK" ]] && { echo "ERROR: --codex-feedback required" >&2; exit 1; }
[[ -z "$OUTPUT" ]] && { echo "ERROR: --output required" >&2; exit 1; }
[[ ! -f "$TASK_FILE" ]] && { echo "ERROR: Task file not found: $TASK_FILE" >&2; exit 1; }
[[ ! -f "$CODEX_FEEDBACK" ]] && { echo "ERROR: Codex feedback not found: $CODEX_FEEDBACK" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"

[[ "$QUIET" == "false" ]] && echo "Reformulating context for iteration $((ITERATION + 1)) using GLM 4.7..."

# ============================================================================
# GATHER ALL CONTEXT
# ============================================================================

TASK_CONTENT=$(cat "$TASK_FILE")

# Get Codex feedback (handle both JSON and markdown)
if jq -e . "$CODEX_FEEDBACK" > /dev/null 2>&1; then
  # JSON format - extract readable feedback
  FEEDBACK_CONTENT=$(jq -r '
    "## Codex Verdict: " + (if .approved then "APPROVED" else "REJECTED" end) + "\n\n" +
    "### Summary\n" + (.summary // "No summary") + "\n\n" +
    "### Blocking Issues\n" +
    (if (.issues | length) > 0 then
      (.issues | map(select(.blocking == true or .severity == "critical")) |
       if length > 0 then
         map("- **[\(.severity)]** \(.message)\n  File: \(.file // "N/A"):\(.line // "N/A")\n  Fix: \(.suggestion // "N/A")") | join("\n")
       else "None" end)
    else "None" end) + "\n\n" +
    "### Other Issues\n" +
    (if (.issues | length) > 0 then
      (.issues | map(select(.blocking != true and .severity != "critical")) |
       if length > 0 then
         map("- [\(.severity)] \(.message)") | join("\n")
       else "None" end)
    else "None" end) + "\n\n" +
    "### Missing Functionality\n" +
    (if (.missing | length) > 0 then (.missing | map("- " + .) | join("\n")) else "None reported" end)
  ' "$CODEX_FEEDBACK" 2>/dev/null) || FEEDBACK_CONTENT=$(cat "$CODEX_FEEDBACK")
else
  FEEDBACK_CONTENT=$(cat "$CODEX_FEEDBACK")
fi

# Get plan if available
PLAN_CONTENT=""
if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
  PLAN_CONTENT=$(cat "$PLAN_FILE")
fi

# Get implementation details if available
IMPL_CONTENT=""
if [[ -n "$IMPL_FILE" && -f "$IMPL_FILE" ]]; then
  IMPL_CONTENT=$(cat "$IMPL_FILE")
fi

# Get test results if available
TEST_CONTENT=""
if [[ -n "$TEST_RESULTS" && -f "$TEST_RESULTS" ]]; then
  TEST_CONTENT=$(cat "$TEST_RESULTS")
fi

# Get codebase summary if available and not too large
CODEBASE_CONTENT=""
if [[ -n "$CODEBASE_FILE" && -f "$CODEBASE_FILE" ]]; then
  CODEBASE_SIZE=$(wc -c < "$CODEBASE_FILE")
  if [[ $CODEBASE_SIZE -lt 10000 ]]; then
    CODEBASE_CONTENT=$(cat "$CODEBASE_FILE")
  fi
fi

# Gather previous iterations summary if available
HISTORY_SUMMARY=""
if [[ $ITERATION -gt 1 && -n "$HISTORY_DIR" && -d "$HISTORY_DIR" ]]; then
  HISTORY_SUMMARY="### Previous Attempts Summary\n\n"
  for i in $(seq 1 $((ITERATION - 1))); do
    ITER_DIR="$HISTORY_DIR/iter_$(printf '%03d' $i)"
    if [[ -d "$ITER_DIR" ]]; then
      HISTORY_SUMMARY+="**Iteration $i**: "
      if [[ -f "$ITER_DIR/codex_review.json" ]]; then
        ITER_SUMMARY=$(jq -r '.summary // "No summary"' "$ITER_DIR/codex_review.json" 2>/dev/null || echo "Failed")
        HISTORY_SUMMARY+="$ITER_SUMMARY\n"
      else
        HISTORY_SUMMARY+="No review data\n"
      fi
    fi
  done
  HISTORY_SUMMARY+="\n"
fi

# ============================================================================
# BUILD THE REFORMULATION PROMPT FOR GLM 4.7
# ============================================================================

REFORMULATION_PROMPT=$(cat << 'PROMPT_TEMPLATE'
You are a **Context Reformulator** for an AI coding orchestration system.

Your job is to take all the context from a failed implementation iteration and create a **clean, concise, and actionable prompt** for Claude Code (the Planner AI) to create a revised implementation plan.

## Your Goals

1. **Synthesize** - Combine all information into a coherent narrative
2. **Prioritize** - Focus on what's BLOCKING approval (critical issues first)
3. **Be Actionable** - Claude needs to understand exactly what to fix
4. **Be Concise** - Remove redundancy, keep only what matters
5. **Preserve Essential Details** - File paths, line numbers, specific errors

## Output Format

Generate a prompt for Claude Code in this structure:

```markdown
# Revised Implementation Request - Iteration N

## Task
[1-2 sentence summary of the original task]

## What Was Tried
[Brief summary of the approach taken - what worked, what didn't]

## Why It Failed (Codex Feedback)
### Critical/Blocking Issues (MUST FIX)
[List with file:line references and specific fix suggestions]

### Other Issues
[Brief list of non-blocking issues]

## What the New Plan Must Address
1. [Specific thing to fix/change]
2. [Another specific thing]
...

## Constraints
- [Any technical constraints discovered]
- [Dependencies or patterns to follow]

## Files Involved
- `path/to/file.ts` - [what needs to change]
```

## Rules

- Target length: ~$MAX_OUTPUT_TOKENS tokens (be concise but complete)
- NEVER lose critical information (blocking issues, file paths, error messages)
- If tests failed, include the specific failure reasons
- If something was partially working, mention what worked
- Use bullet points and headers for clarity
- The output should be a PROMPT that Claude can directly use

---

## INPUT CONTEXT TO REFORMULATE

PROMPT_TEMPLATE
)

# Replace placeholder
REFORMULATION_PROMPT="${REFORMULATION_PROMPT//\$MAX_OUTPUT_TOKENS/$MAX_OUTPUT}"

# Add the actual context
REFORMULATION_PROMPT+="
### Original Task
$TASK_CONTENT

"

if [[ -n "$PLAN_CONTENT" ]]; then
  REFORMULATION_PROMPT+="### Plan That Was Executed
$PLAN_CONTENT

"
fi

if [[ -n "$IMPL_CONTENT" ]]; then
  REFORMULATION_PROMPT+="### What Was Implemented
$IMPL_CONTENT

"
fi

REFORMULATION_PROMPT+="### Codex Review Feedback
$FEEDBACK_CONTENT

"

if [[ -n "$TEST_CONTENT" ]]; then
  REFORMULATION_PROMPT+="### Test Results
\`\`\`
$TEST_CONTENT
\`\`\`

"
fi

if [[ -n "$HISTORY_SUMMARY" ]]; then
  REFORMULATION_PROMPT+="$HISTORY_SUMMARY"
fi

if [[ -n "$CODEBASE_CONTENT" ]]; then
  REFORMULATION_PROMPT+="### Codebase Context
$CODEBASE_CONTENT

"
fi

REFORMULATION_PROMPT+="
---

Now generate the reformulated prompt for Claude Code. Remember:
- This is iteration $ITERATION, so the next will be iteration $((ITERATION + 1))
- Focus on what MUST change to pass the review
- Be concise but don't lose critical details
"

# ============================================================================
# RUN GLM 4.7 REFORMULATION
# ============================================================================

PROMPT_FILE=$(mktemp)
echo "$REFORMULATION_PROMPT" > "$PROMPT_FILE"

TEMP_OUTPUT=$(mktemp)

[[ "$QUIET" == "false" ]] && echo "Sending to GLM 4.7 for reformulation..."

# Check for opencode
if ! command -v opencode &>/dev/null; then
  echo "ERROR: opencode not available for reformulation" >&2
  echo "Falling back to direct context concatenation..." >&2

  # Fallback: create a basic prompt without AI reformulation
  cat > "$OUTPUT" << EOF
# Revised Implementation Request - Iteration $((ITERATION + 1))

## Task
$TASK_CONTENT

## Previous Attempt Failed

$FEEDBACK_CONTENT

## What Must Change
Address all blocking issues listed above.

## Files to Review
Check the implementation and fix the identified issues.
EOF

  rm -f "$PROMPT_FILE"
  exit 0
fi

# Run GLM 4.7 with interleaved thinking for better quality
timeout 120 opencode run \
  -m "$MODEL" \
  --allowedTools "" \
  -q \
  "$(cat "$PROMPT_FILE")" \
  > "$TEMP_OUTPUT" 2>&1 || {
    echo "WARNING: GLM 4.7 reformulation failed, using fallback" >&2
    cat > "$OUTPUT" << EOF
# Revised Implementation Request - Iteration $((ITERATION + 1))

## Task
$TASK_CONTENT

## Why Previous Attempt Failed
$FEEDBACK_CONTENT

## Required Changes
Address all issues identified by Codex above.
EOF
    rm -f "$PROMPT_FILE" "$TEMP_OUTPUT"
    exit 0
  }

rm -f "$PROMPT_FILE"

# ============================================================================
# EXTRACT AND SAVE OUTPUT
# ============================================================================

if [[ -s "$TEMP_OUTPUT" ]]; then
  # Try to extract text from JSON wrapper if present
  if jq -e '.result' "$TEMP_OUTPUT" > /dev/null 2>&1; then
    jq -r '.result' "$TEMP_OUTPUT" > "$OUTPUT"
  elif jq -e '.content' "$TEMP_OUTPUT" > /dev/null 2>&1; then
    jq -r '.content' "$TEMP_OUTPUT" > "$OUTPUT"
  elif jq -e '.choices[0].message.content' "$TEMP_OUTPUT" > /dev/null 2>&1; then
    jq -r '.choices[0].message.content' "$TEMP_OUTPUT" > "$OUTPUT"
  else
    # Use as-is (probably plain text)
    cat "$TEMP_OUTPUT" > "$OUTPUT"
  fi

  # Clean up any markdown code blocks wrapping the entire output
  if head -1 "$OUTPUT" | grep -q '^```'; then
    # Remove first and last lines if they're code fences
    sed -i.bak '1{/^```/d}; ${/^```/d}' "$OUTPUT" 2>/dev/null || \
    sed '1{/^```/d}; ${/^```/d}' "$OUTPUT" > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
    rm -f "$OUTPUT.bak"
  fi
else
  echo "ERROR: No output from GLM 4.7" >&2
  # Create minimal fallback
  cat > "$OUTPUT" << EOF
# Revised Implementation Request - Iteration $((ITERATION + 1))

## Task
$TASK_CONTENT

## Issues to Fix
$FEEDBACK_CONTENT
EOF
fi

rm -f "$TEMP_OUTPUT"

# Report stats
if [[ "$QUIET" == "false" ]]; then
  INPUT_SIZE=$((${#TASK_CONTENT} + ${#PLAN_CONTENT} + ${#IMPL_CONTENT} + ${#FEEDBACK_CONTENT} + ${#TEST_CONTENT}))
  OUTPUT_SIZE=$(wc -c < "$OUTPUT")
  echo "Reformulation complete:"
  echo "  Input context: $INPUT_SIZE chars"
  echo "  Output prompt: $OUTPUT_SIZE chars"
  echo "  Compression: $(( (INPUT_SIZE - OUTPUT_SIZE) * 100 / INPUT_SIZE ))%"
  echo "  Saved to: $OUTPUT"
fi
