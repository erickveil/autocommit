#!/bin/bash

# Script to automatically add all changes and commit at a set interval,
# using Ollama to generate commit messages based on git diff.
# Verbose output; NO jq dependency.
# Usage:
#   ./auto-commit-ai.sh [-v] [-i INTERVAL_MINUTES]
#   -v: verbose output (shows commands being run)
#   -i: set interval in minutes between automated commits (default: 30)

OLLAMA_URL="http://192.168.0.160:11434/api/chat"
OLLAMA_MODEL="gemma3:latest"
OLLAMA_TEMP="1.0"
DEFAULT_INTERVAL_MINUTES=30
MAX_DIFF_CHARS=8000  # Maximum number of characters from git diff sent to Ollama

# Parse options
VERBOSE=0
INTERVAL_MINUTES=$DEFAULT_INTERVAL_MINUTES

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v)
            VERBOSE=1
            shift
            ;;
        -i)
            shift
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                INTERVAL_MINUTES=$1
                shift
            else
                echo "Error: -i requires an integer argument (number of minutes)" >&2
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 [-v] [-i INTERVAL_MINUTES]" >&2
            exit 1
            ;;
    esac
done

log() {
    echo "[$(date)] $*" >&2
}

run_cmd() {
    if [ "$VERBOSE" -eq 1 ]; then
        log "Running command: $*"
    fi
    eval "$@"
}

log "Starting auto-commit AI script."
log "AI model: $OLLAMA_MODEL"
log "Ollama endpoint: $OLLAMA_URL"
log "Commit interval: $INTERVAL_MINUTES minute(s)"
log "Max diff length sent to Ollama: $MAX_DIFF_CHARS characters"
if [ "$VERBOSE" -eq 1 ]; then
    log "Verbose mode enabled."
fi

# Escape double quotes, backslashes, and newlines for JSON
escape_for_json() {
    echo "$1" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g'
}

# Truncate the diff content to a safe length (max $MAX_DIFF_CHARS characters)
truncate_diff() {
    # Usage: truncate_diff "$diff_content"
    # awk substr() counts bytes, not characters, but is safe for ASCII.
    echo "$1" | awk -v max="$MAX_DIFF_CHARS" '{out=out $0 "\n"} END {print substr(out,1,max)}'
}

# Function to get an AI-generated commit message based on git diff
generate_commit_message() {
    local diff_content
    diff_content=$(git diff --cached)

    # If no staged diff, try unstaged diff
    if [ -z "$diff_content" ]; then
        diff_content=$(git diff)
    fi

    # If still empty, fallback message
    if [ -z "$diff_content" ]; then
        log "No changes detected for commit message generation."
        echo "Automated commit"
        return
    fi

    # Truncate diff to MAX_DIFF_CHARS characters max
    diff_content=$(truncate_diff "$diff_content")

    # Compose prompts
    SYSTEM_PROMPT="You are an assistant that writes concise and descriptive commit messages for git commits."
    USER_PROMPT="Analyze the following git diff and write a clear, brief commit message summarizing the changes. Start the commit with an appropriate emoji representing the change made instead of using a prefix like 'feat' or 'fix':\\n$diff_content"

    # Escape prompts for JSON
    SYSTEM_PROMPT_ESCAPED=$(escape_for_json "$SYSTEM_PROMPT")
    USER_PROMPT_ESCAPED=$(escape_for_json "$USER_PROMPT")

    # Build JSON payload
    read -r -d '' PAYLOAD <<EOF
{
  "model": "$OLLAMA_MODEL",
  "temperature": $OLLAMA_TEMP,
  "stream": false,
  "messages": [
    {"role": "system", "content": "$SYSTEM_PROMPT_ESCAPED"},
    {"role": "user", "content": "$USER_PROMPT_ESCAPED"}
  ]
}
EOF

    log "Requesting AI commit message from Ollama..."
    if [ "$VERBOSE" -eq 1 ]; then
        log "curl -s \"$OLLAMA_URL\" -H \"Content-Type: application/json\" -d \"\$PAYLOAD\""
        log "Payload: $PAYLOAD"
    fi

    RESPONSE=$(curl -s "$OLLAMA_URL" -H "Content-Type: application/json" -d "$PAYLOAD")
    # If there's an error in the response, print it even if not in verbose mode
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"error":"[^"]*"' | sed 's/"error":"//;s/"$//')
    if [ -n "$ERROR_MSG" ]; then
        log "Ollama error: $ERROR_MSG"
    fi
    if [ "$VERBOSE" -eq 1 ]; then
        log "Ollama raw response: $RESPONSE"
    fi

    # Extract message.content using sed (inside the "message" object)
    COMMIT_MSG=$(echo "$RESPONSE" | sed -n 's/.*"message":{[^}]*"content":"\([^"]*\)".*/\1/p')

    # Convert literal \n to actual newlines
    COMMIT_MSG=$(echo "$COMMIT_MSG" | sed 's/\\n/\
/g')

    if [ -z "$COMMIT_MSG" ]; then
        log "AI did not generate a commit message. Using fallback."
        COMMIT_MSG="Automated commit"
    fi

    log "Generated commit message: $COMMIT_MSG"
    echo "$COMMIT_MSG"
}

auto_commit() {
    run_cmd "git add -A"

    log "Checking for staged changes..."
    if ! git diff --cached --quiet; then
        COMMIT_MSG=$(generate_commit_message)
        log "Changes detected. Committing..."
        run_cmd "git commit -m \"\$COMMIT_MSG\""
        log "Commit successful."
    else
        log "No changes to commit."
    fi
}

auto_commit

while true; do
    log "Sleeping for $INTERVAL_MINUTES minute(s)..."
    sleep $((INTERVAL_MINUTES * 60))
    auto_commit
done