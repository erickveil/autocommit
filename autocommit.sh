#!/bin/bash

# Script to automatically add all changes and commit every 30 minutes,
# using Ollama to generate commit messages based on git diff.
# Verbose output; NO jq dependency.

OLLAMA_URL="http://192.168.0.160:11434/api/chat"
OLLAMA_MODEL="gemma3:latest"
OLLAMA_TEMP="1.0"

echo "[$(date)] Starting auto-commit AI script."
echo "AI model: $OLLAMA_MODEL"
echo "Ollama endpoint: $OLLAMA_URL"

# Function to escape double quotes and backslashes in the diff
escape_for_json() {
    # Replace backslash with double-backslash, then double quote with escaped quote
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
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
        echo "No changes detected for commit message generation."
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

    echo "[$(date)] Requesting AI commit message from Ollama..."

    # Make the API call and grab the output message
    RESPONSE=$(curl -s "$OLLAMA_URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")

    # Extract the message content from the JSON response
    # This assumes the response contains: "content": "your message here"
    COMMIT_MSG=$(echo "$RESPONSE" | grep -o '"content":"[^"]*"' | head -n 1 | sed 's/"content":"//;s/"$//')

    # Fallback if empty
    if [ -z "$COMMIT_MSG" ]; then
        echo "AI did not generate a commit message. Using fallback."
        COMMIT_MSG="Automated commit"
    fi

    echo "[$(date)] Generated commit message: $COMMIT_MSG"
    echo "$COMMIT_MSG"
}

# Function to add and commit all changes
auto_commit() {
    echo "[$(date)] Running: git add -A"
    git add -A

    echo "[$(date)] Checking for staged changes..."
    if ! git diff --cached --quiet; then
        COMMIT_MSG=$(generate_commit_message)
        echo "[$(date)] Changes detected. Committing..."
        git commit -m "$COMMIT_MSG"
        echo "[$(date)] Commit successful."
    else
        echo "[$(date)] No changes to commit."
    fi
}

# Initial commit when script is run
auto_commit

# Loop to commit every 30 minutes
while true; do
    echo "[$(date)] Sleeping for 30 minutes..."
    sleep 1800  # 30 minutes
    auto_commit
done
