#!/bin/bash

# Script to automatically add all changes and commit every 30 minutes,
# using an AI (Ollama) instance to generate commit messages based on git diff.
# Verbose output included.

OLLAMA_URL="http://192.168.0.160:11434/api/chat"
OLLAMA_MODEL="gemma3:latest"
OLLAMA_TEMP=1.0

echo "[$(date)] Starting auto-commit AI script."
echo "AI model: $OLLAMA_MODEL"
echo "Ollama endpoint: $OLLAMA_URL"

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

    # System and user prompts for Ollama
    SYSTEM_PROMPT="You are an assistant that writes concise and descriptive commit messages for git commits."
    USER_PROMPT="Analyze the following git diff and write a clear, brief commit message summarizing the changes:\n$diff_content"

    # Compose the JSON payload
    PAYLOAD=$(jq -nc --arg sys "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" --arg model "$OLLAMA_MODEL" --argjson temp $OLLAMA_TEMP '{
      model: $model,
      temperature: $temp,
      stream: false,
      messages: [
        {role: "system", content: $sys},
        {role: "user", content: $user}
      ]
    }')

    echo "[$(date)] Requesting AI commit message from Ollama..."

    # Make the API call and grab the output message
    COMMIT_MSG=$(curl -s "$OLLAMA_URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" | jq -r '.message.content')

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