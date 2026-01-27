#!/bin/bash
# Generate PR Title from Task Description for Clawdbot Orchestrator
# Creates concise, conventional PR titles from natural language tasks
set -euo pipefail

usage() {
  cat << EOF
Generate PR Title from Task Description

Usage: $(basename "$0") <task_description>
       echo "task description" | $(basename "$0")

Arguments:
  task_description    Natural language task description

Output:
  A concise PR title (max 70 characters)

Examples:
  $(basename "$0") "El transcriptor no funciona, arréglalo"
  # Output: Fix transcriptor functionality

  $(basename "$0") "Add user authentication with JWT"
  # Output: Add user authentication with JWT

  $(basename "$0") "Update the login flow to handle errors better"
  # Output: Update login flow error handling
EOF
}

# Read task from argument or stdin
TASK=""
if [[ $# -gt 0 ]]; then
  case $1 in
    -h|--help) usage; exit 0 ;;
    *) TASK="$1" ;;
  esac
else
  # Read from stdin
  TASK=$(cat)
fi

[[ -z "$TASK" ]] && { echo "ERROR: task description required" >&2; usage >&2; exit 1; }

# Lowercase for pattern matching
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')

# Determine prefix based on action words
# Use lowercase for matching, then strip from lowercase version
PREFIX=""
CLEANED_LOWER=""

# Spanish and English patterns (work with lowercase for portability)
if [[ "$TASK_LOWER" =~ ^(fix|arregla|corrige|repara|soluciona)[[:space:]]* ]]; then
  PREFIX="Fix"
  CLEANED_LOWER=$(echo "$TASK_LOWER" | sed -E 's/^(fix|arregla|corrige|repara|soluciona)[[:space:]]*//')
elif [[ "$TASK_LOWER" =~ ^(add|añade|agrega|crea|implement|implementa)[[:space:]]* ]]; then
  PREFIX="Add"
  CLEANED_LOWER=$(echo "$TASK_LOWER" | sed -E 's/^(add|añade|agrega|crea|implement|implementa)[[:space:]]*//')
elif [[ "$TASK_LOWER" =~ ^(update|actualiza|mejora|modifica)[[:space:]]* ]]; then
  PREFIX="Update"
  CLEANED_LOWER=$(echo "$TASK_LOWER" | sed -E 's/^(update|actualiza|mejora|modifica)[[:space:]]*//')
elif [[ "$TASK_LOWER" =~ ^(remove|elimina|borra|quita|delete)[[:space:]]* ]]; then
  PREFIX="Remove"
  CLEANED_LOWER=$(echo "$TASK_LOWER" | sed -E 's/^(remove|elimina|borra|quita|delete)[[:space:]]*//')
elif [[ "$TASK_LOWER" =~ ^(refactor|refactoriza|reorganiza)[[:space:]]* ]]; then
  PREFIX="Refactor"
  CLEANED_LOWER=$(echo "$TASK_LOWER" | sed -E 's/^(refactor|refactoriza|reorganiza)[[:space:]]*//')
elif [[ "$TASK_LOWER" =~ (no[[:space:]]+(funciona|works|working)|broken|roto|bug|error) ]]; then
  # Implicit fix: "X no funciona" or "X is broken"
  PREFIX="Fix"
  CLEANED_LOWER=$(echo "$TASK_LOWER" | sed -E 's/[[:space:]]*(no[[:space:]]+(funciona|works|working)|is[[:space:]]+(broken|not[[:space:]]+working)).*//')
else
  # Default: use task as-is
  PREFIX=""
  CLEANED_LOWER="$TASK_LOWER"
fi

# Clean up the task description (all lowercase operations for portability)
CLEANED_LOWER=$(echo "$CLEANED_LOWER" | sed -E '
  s/^(el|la|los|las|the|a|an)[[:space:]]+//
  s/[,.:;!?]+$//
  s/[[:space:]]+/ /g
')

# Use cleaned lowercase version
CLEANED_TASK="$CLEANED_LOWER"

# Capitalize first letter of cleaned task
CLEANED_TASK="$(echo "${CLEANED_TASK:0:1}" | tr '[:lower:]' '[:upper:]')${CLEANED_TASK:1}"

# Build title
if [[ -n "$PREFIX" ]]; then
  TITLE="$PREFIX $CLEANED_TASK"
else
  TITLE="$CLEANED_TASK"
fi

# Remove extra spaces
TITLE=$(echo "$TITLE" | tr -s ' ')

# Truncate to 70 characters
if [[ ${#TITLE} -gt 70 ]]; then
  TITLE="${TITLE:0:67}..."
fi

echo "$TITLE"
