package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	OLLAMA_URL   = "http://192.168.0.160:11434/api/chat"
	OLLAMA_MODEL = "gemma3:latest"
	OLLAMA_TEMP  = 1.0
	MAX_DIFF_LEN = 8000
)

var (
	verbose     = false
	intervalMin = 30
)

func logf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "[%s] %s\n", time.Now().Format("Mon Jan 02 15:04:05 MST 2006"), fmt.Sprintf(format, args...))
}

func runCmdCapture(cmd string, args ...string) (string, error) {
	if verbose {
		logf("Running command: %s %s", cmd, strings.Join(args, " "))
	}
	c := exec.Command(cmd, args...)
	out, err := c.CombinedOutput()
	return string(out), err
}

func collapseWhitespace(s string) string {
	// strings.Fields splits on any whitespace and removes extras
	return strings.Join(strings.Fields(s), " ")
}

func getDiff() (string, error) {
	out, err := runCmdCapture("git", "diff", "--cached")
	if err != nil {
		// it's okay if git diff --cached returns non-zero when there's content; we'll treat empty output specially
	}
	if strings.TrimSpace(out) == "" {
		out, err = runCmdCapture("git", "diff")
	}
	return out, err
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

type msgItem struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}
type ollamaPayload struct {
	Model       string    `json:"model"`
	Temperature float64   `json:"temperature"`
	Stream      bool      `json:"stream"`
	Messages    []msgItem `json:"messages"`
}

type ollamaResponse struct {
	Error   string `json:"error"`
	Message struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	} `json:"message"`
}

func getAICommitMessage(diff string) (string, error) {
	// Clean and truncate diff before sending:
	cleanDiff := collapseWhitespace(diff)
	cleanDiff = truncate(cleanDiff, MAX_DIFF_LEN)

	systemPrompt := "You are an assistant that writes concise and descriptive commit messages for git commits."
	userPrompt := "Analyze the following git diff and write a clear, brief commit message summarizing the changes. Start the commit with an appropriate emoji representing the change made instead of using a prefix like 'feat' or 'fix': " + cleanDiff

	payload := ollamaPayload{
		Model:       OLLAMA_MODEL,
		Temperature: OLLAMA_TEMP,
		Stream:      false,
		Messages: []msgItem{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	if verbose {
		logf("Payload size: %d bytes", len(data))
		// do not print entire payload when large
	}

	req, err := http.NewRequest("POST", OLLAMA_URL, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	if verbose {
		logf("Ollama raw response: %s", string(body))
	}

	var or ollamaResponse
	if err := json.Unmarshal(body, &or); err != nil {
		// fallback: try to find "content":"..." using crude search (single-line)
		// but prefer to surface the parsing error
		return "", fmt.Errorf("failed to parse Ollama response: %w", err)
	}
	if or.Error != "" {
		return "", fmt.Errorf("Ollama error: %s", or.Error)
	}
	commitMsg := or.Message.Content
	// Ollama may return escaped newline sequences (\n). Convert them to real newlines:
	commitMsg = strings.ReplaceAll(commitMsg, `\n`, "\n")
	commitMsg = strings.TrimSpace(commitMsg)
	return commitMsg, nil
}

func autoCommit() {
	// stage everything
	if _, err := runCmdCapture("git", "add", "-A"); err != nil {
		logf("git add error: %v", err)
		// continue; maybe nothing to add
	}

	// check for staged changes
	_, err := exec.Command("git", "diff", "--cached", "--quiet").CombinedOutput()
	if err == nil {
		logf("No changes to commit.")
		return
	}

	diff, err := getDiff()
	if err != nil {
		logf("git diff error: %v", err)
		// still try to proceed if diff contains something
	}
	if strings.TrimSpace(diff) == "" {
		logf("No changes detected for commit message generation.")
		return
	}

	commitMsg, err := getAICommitMessage(diff)
	if err != nil || commitMsg == "" {
		logf("AI did not generate a valid commit message (%v). Using fallback.", err)
		commitMsg = "Automated commit"
	}
	logf("Generated commit message:\n%s", commitMsg)

	// git commit -m "<msg>" supports multiline strings as single argument
	if out, err := runCmdCapture("git", "commit", "-m", commitMsg); err != nil {
		logf("git commit error: %v\n%s", err, out)
	} else {
		logf("Commit successful.\n%s", out)
	}
}

func main() {
	// parse CLI args
	for i := 1; i < len(os.Args); i++ {
		switch os.Args[i] {
		case "-v":
			verbose = true
		case "-i":
			if i+1 < len(os.Args) {
				fmt.Sscanf(os.Args[i+1], "%d", &intervalMin)
				i++
			}
		}
	}

	logf("Starting auto-commit AI program.")
	logf("AI model: %s", OLLAMA_MODEL)
	logf("Ollama endpoint: %s", OLLAMA_URL)
	logf("Commit interval: %d minute(s)", intervalMin)
	logf("Max diff length sent to Ollama: %d characters", MAX_DIFF_LEN)
	if verbose {
		logf("Verbose mode enabled.")
	}

	autoCommit()
	for {
		logf("Sleeping for %d minute(s)...", intervalMin)
		time.Sleep(time.Duration(intervalMin) * time.Minute)
		autoCommit()
	}
}