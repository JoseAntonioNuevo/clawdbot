#!/bin/bash
# Output Normalizer for Clawdbot Orchestrator
# Uses AI to transform arbitrary outputs into expected JSON schemas
set -euo pipefail

[[ -f "$HOME/.clawdbot-orchestrator.env" ]] && source "$HOME/.clawdbot-orchestrator.env"

usage() {
  cat << EOF
Output Normalizer for Clawdbot

Uses AI to transform arbitrary model outputs into expected JSON schemas.
Handles cases where Codex or other models return unexpected formats.

Usage: $(basename "$0") [options]

Options:
  --input FILE          Input file with raw output to normalize
  --schema TYPE         Expected schema: codex-review|plan|implementation
  --output FILE         Where to write the normalized JSON
  --model MODEL         Model to use (default: uses opencode with Kimi)
  -q, --quiet           Suppress progress output
  -h, --help            Show this help

Schemas:
  codex-review    Normalize to code review JSON (approved, issues, etc.)
  plan            Normalize to implementation plan structure
  implementation  Normalize to implementation summary structure

Examples:
  $(basename "$0") --input raw_codex.txt --schema codex-review --output review.json
EOF
}

INPUT=""
SCHEMA=""
OUTPUT=""
MODEL="${NORMALIZER_MODEL:-moonshot/kimi-k2.5-preview}"
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --input) INPUT="$2"; shift 2 ;;
    --schema) SCHEMA="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$INPUT" ]] && { echo "ERROR: --input required" >&2; exit 1; }
[[ -z "$SCHEMA" ]] && { echo "ERROR: --schema required" >&2; exit 1; }
[[ -z "$OUTPUT" ]] && { echo "ERROR: --output required" >&2; exit 1; }
[[ ! -f "$INPUT" ]] && { echo "ERROR: Input file not found: $INPUT" >&2; exit 1; }

RAW_CONTENT=$(cat "$INPUT")

# First, try to parse as valid JSON matching our schema
try_parse_json() {
  local content="$1"
  local schema="$2"

  case "$schema" in
    codex-review)
      # Check if it's already valid JSON with required fields
      if echo "$content" | jq -e '.approved != null and .issues != null' > /dev/null 2>&1; then
        echo "$content" | jq '{
          approved: .approved,
          summary: (.summary // "No summary"),
          issues: (.issues // []),
          missing: (.missing // []),
          positives: (.positives // [])
        }'
        return 0
      fi
      ;;
  esac
  return 1
}

# Try direct parsing first
if try_parse_json "$RAW_CONTENT" "$SCHEMA" > "$OUTPUT" 2>/dev/null; then
  [[ "$QUIET" == "false" ]] && echo "Output already in expected format"
  exit 0
fi

[[ "$QUIET" == "false" ]] && echo "Normalizing output to $SCHEMA schema..."

mkdir -p "$(dirname "$OUTPUT")"

# Build schema-specific prompt
TARGET_SCHEMA=""
case "$SCHEMA" in
  codex-review)
    TARGET_SCHEMA='{
  "approved": boolean,
  "summary": "1-2 sentence overall assessment",
  "issues": [
    {
      "severity": "critical" | "major" | "minor",
      "blocking": boolean,
      "file": "path/to/file" | null,
      "line": number | null,
      "message": "Description of the issue",
      "suggestion": "How to fix it"
    }
  ],
  "missing": ["List of missing functionality"],
  "positives": ["List of things done well"]
}'
    RULES="
- Set approved=true ONLY if there are NO critical issues AND NO blocking issues
- If the input mentions any failures, errors, or problems, those are issues
- If the input says things like 'looks good', 'approved', 'LGTM' with no issues, set approved=true
- Extract ALL issues mentioned, categorize by severity
- If severity isn't clear: security/crash issues are critical, bugs are major, style is minor"
    ;;

  plan)
    TARGET_SCHEMA='{
  "summary": "Brief overview of the plan",
  "steps": [
    {
      "number": 1,
      "title": "Step title",
      "description": "What to do",
      "files": ["files to modify"],
      "code_snippets": ["key code if any"]
    }
  ],
  "files_to_modify": ["list of all files"],
  "testing": ["how to test"],
  "risks": ["potential issues"]
}'
    RULES="
- Extract all implementation steps in order
- Identify all files that need to be changed
- Include any code snippets or pseudocode mentioned
- Note any warnings or risks mentioned"
    ;;

  implementation)
    TARGET_SCHEMA='{
  "summary": "What was implemented",
  "approach": "How it was implemented",
  "files_changed": [
    {
      "path": "file path",
      "action": "created" | "modified" | "deleted",
      "description": "what changed"
    }
  ],
  "tests_run": boolean,
  "test_results": "pass" | "fail" | "unknown",
  "issues_encountered": ["any problems faced"]
}'
    RULES="
- Extract what was actually built/changed
- List all files that were modified
- Note if tests were run and their results
- Include any errors or issues encountered"
    ;;

  *)
    echo "ERROR: Unknown schema: $SCHEMA" >&2
    exit 1
    ;;
esac

# Create the normalization prompt
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << EOF
You are a JSON normalizer. Convert the following content into the exact JSON schema specified.

TARGET JSON SCHEMA:
\`\`\`json
$TARGET_SCHEMA
\`\`\`

RULES:
$RULES

IMPORTANT:
- Output ONLY valid JSON, nothing else
- Do not include markdown code blocks in your response
- If information is missing, use reasonable defaults (null, empty arrays, etc.)
- Preserve all important information from the input

---

CONTENT TO NORMALIZE:

$RAW_CONTENT
EOF

# Run normalization
TEMP_OUTPUT=$(mktemp)

if command -v opencode &>/dev/null; then
  # Use stdin to avoid ARG_MAX limits with large contexts
  PROMPT_SIZE=$(wc -c < "$PROMPT_FILE")
  RUN_SUCCESS=false

  # Try stdin first (preferred for large prompts)
  if timeout 60 opencode run -m "$MODEL" --allowedTools "" -q - < "$PROMPT_FILE" > "$TEMP_OUTPUT" 2>&1; then
    RUN_SUCCESS=true
  # Try --prompt-file if available
  elif timeout 60 opencode run -m "$MODEL" --allowedTools "" -q --prompt-file "$PROMPT_FILE" > "$TEMP_OUTPUT" 2>&1; then
    RUN_SUCCESS=true
  # Last resort: direct argument (check size first)
  elif [[ $PROMPT_SIZE -lt 100000 ]]; then
    if timeout 60 opencode run -m "$MODEL" --allowedTools "" -q "$(cat "$PROMPT_FILE")" > "$TEMP_OUTPUT" 2>&1; then
      RUN_SUCCESS=true
    fi
    # RUN_SUCCESS stays false if command failed
  fi
else
  echo "ERROR: opencode not available for normalization" >&2
  rm -f "$PROMPT_FILE"
  # Create a fallback error response
  case "$SCHEMA" in
    codex-review)
      cat > "$OUTPUT" << 'FALLBACK'
{
  "approved": false,
  "summary": "Could not normalize output - manual review required",
  "issues": [{"severity": "critical", "blocking": true, "message": "Output normalization failed"}],
  "missing": [],
  "positives": []
}
FALLBACK
      ;;
    *)
      echo '{"error": "normalization_failed"}' > "$OUTPUT"
      ;;
  esac
  exit 1
fi

rm -f "$PROMPT_FILE"

# Check if normalization command was successful
if [[ "$RUN_SUCCESS" != "true" ]]; then
  [[ "$QUIET" == "false" ]] && echo "WARNING: Normalization command failed, creating error response"
  case "$SCHEMA" in
    codex-review)
      cat > "$OUTPUT" << 'EOF'
{
  "approved": false,
  "summary": "Normalization command failed",
  "issues": [{"severity": "critical", "blocking": true, "message": "OpenCode normalization command failed"}],
  "missing": [],
  "positives": []
}
EOF
      ;;
    *)
      echo '{"error": "normalization_command_failed"}' > "$OUTPUT"
      ;;
  esac
  rm -f "$TEMP_OUTPUT"
  exit 1
fi

# Extract JSON from the response
if [[ -s "$TEMP_OUTPUT" ]]; then
  # Try multiple extraction methods

  # Method 1: Direct JSON parse
  if jq -e . "$TEMP_OUTPUT" > /dev/null 2>&1; then
    cat "$TEMP_OUTPUT" > "$OUTPUT"
  # Method 2: Extract from opencode JSON wrapper
  elif jq -e '.result' "$TEMP_OUTPUT" > /dev/null 2>&1; then
    EXTRACTED=$(jq -r '.result' "$TEMP_OUTPUT")
    if echo "$EXTRACTED" | jq -e . > /dev/null 2>&1; then
      echo "$EXTRACTED" > "$OUTPUT"
    else
      # Result is text, try to find JSON in it
      echo "$EXTRACTED" | grep -o '{.*}' | head -1 > "$OUTPUT" 2>/dev/null || echo "$EXTRACTED" > "$OUTPUT"
    fi
  # Method 3: Find JSON block in output
  elif grep -q '{' "$TEMP_OUTPUT"; then
    # Extract everything between first { and last }
    sed -n '/{/,/}/p' "$TEMP_OUTPUT" > "$OUTPUT"
  else
    # Last resort - copy as-is
    cat "$TEMP_OUTPUT" > "$OUTPUT"
  fi

  # Validate final output
  if ! jq -e . "$OUTPUT" > /dev/null 2>&1; then
    [[ "$QUIET" == "false" ]] && echo "WARNING: Could not produce valid JSON, creating error response"
    case "$SCHEMA" in
      codex-review)
        cat > "$OUTPUT" << EOF
{
  "approved": false,
  "summary": "Output normalization produced invalid JSON",
  "issues": [{"severity": "critical", "blocking": true, "message": "Failed to normalize Codex output to expected schema"}],
  "missing": [],
  "positives": [],
  "_raw": $(jq -Rs . "$TEMP_OUTPUT")
}
EOF
        ;;
      *)
        echo '{"error": "invalid_json", "_raw": '"$(jq -Rs . "$TEMP_OUTPUT")"'}' > "$OUTPUT"
        ;;
    esac
  fi
else
  echo "ERROR: No output from normalizer" >&2
  case "$SCHEMA" in
    codex-review)
      cat > "$OUTPUT" << 'EOF'
{
  "approved": false,
  "summary": "Normalizer returned empty output",
  "issues": [{"severity": "critical", "blocking": true, "message": "Empty normalizer response"}],
  "missing": [],
  "positives": []
}
EOF
      ;;
    *)
      echo '{"error": "empty_response"}' > "$OUTPUT"
      ;;
  esac
fi

rm -f "$TEMP_OUTPUT"

[[ "$QUIET" == "false" ]] && echo "Normalized output written to: $OUTPUT"
