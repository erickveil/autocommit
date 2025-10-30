#!/bin/bash

# Script to automatically add all changes and commit every 30 minutes,
# using Ollama to generate commit messages based on git diff.
# Verbose output; NO jq dependency.
# Add -v for extra verbosity to show commands being run.

OLLAMA_URL="http://192.168.0.160:11434/api/chat"
OLLAMA_MODEL="gemma3:latest"
OLLAMA_TEMP="1.0"

VERBOSE=0
if [ "$1" = "-v" ]; then
    VERBOSE=1
    shift
fi

log() {
    echo "[$(date)] $*"
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
if [ "$VERBOSE" -eq 1 ]; then
    log "Verbose mode enabled."
fi

# Function to escape double quotes, backslashes, and newlines for JSON
escape_for_json() {
    echo "$1" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g'
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

    # Compose prompts
    SYSTEM_PROMPT="You are an assistant that writes concise and descriptive commit messages for git commits."
    USER_PROMPT="Analyze the following git diff and write a clear, brief commit message summarizing the changes:\n$diff_content"

    # Escape prompts for JSON
    SYSTEM_PROMPT_ESCAPED=$(escape_for_json "$SYSTEM_PROMPT")
    USER_PROMPT_ESCAPED=$(escape_for_json "$USER_PROMPT")

    # Manually build JSON payload
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

    # Make the API call and grab the output message
    RESPONSE=$(curl -s "$OLLAMA_URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")

    if [ "$VERBOSE" -eq 1 ]; then
        log "Ollama raw response: $RESPONSE"
    fi

    # Extract the message content from the JSON response
    COMMIT_MSG=$(echo "$RESPONSE" | grep -o '"content":"[^"]*"' | head -n 1 | sed 's/"content":"//;s/"$//')

    # Fallback if empty
    if [ -z "$COMMIT_MSG" ]; then
        log "AI did not generate a commit message. Using fallback."
        COMMIT_MSG="Automated commit"
    fi

    log "Generated commit message: $COMMIT_MSG"
    echo "$COMMIT_MSG"
}

# Function to add and commit all changes
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

# Initial commit when script is run
auto_commit

# Loop to commit every 30 minutes
while true; do
    log "Sleeping for 30 minutes..."
    sleep 1800  # 30 minutes
    auto_commit
done