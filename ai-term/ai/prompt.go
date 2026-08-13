package ai

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
)

var fenceRe = regexp.MustCompile("(?m)^```[a-zA-Z]*$")

// SystemPrompt builds the standardized system prompt with the given
// context. Port of _bash_ai_get_system_prompt from lib-bash/utils.bash.
func SystemPrompt(context string) string {
	base := `You are a bash command generator. Generate syntactically correct bash commands based on the user's natural language request.

IMPORTANT RULES:
1. Output ONLY the raw command - no explanations, no markdown, no backticks
2. For arguments containing spaces or special characters, use single quotes
3. Use double quotes only when variable expansion is needed
4. Properly escape special characters within quotes

Examples:
- echo 'Hello World!' (spaces require quotes)
- echo "Current user: $USER" (variable expansion needs double quotes)
- grep 'pattern with spaces' file.txt
- find . -name '*.txt' (glob patterns in quotes)`

	if promptExtend := os.Getenv("BASH_AI_PROMPT_EXTEND"); promptExtend != "" {
		base += "\n\n" + promptExtend
	}
	return fmt.Sprintf("%s\n\nContext:\n%s", base, context)
}

// cleanResult normalizes a model response into a single-line command:
// newlines are removed, trailing whitespace trimmed, and (for ollama)
// markdown code fences stripped. Port of the per-provider cleanup in
// the bash modules.
func cleanResult(s string, stripFences bool) string {
	if stripFences {
		s = fenceRe.ReplaceAllString(s, "")
	}
	s = strings.ReplaceAll(s, "\r", "")
	s = strings.ReplaceAll(s, "\n", "")
	return strings.TrimRight(s, " \t")
}

// errorMessage digs a human-readable error out of an API error
// response by checking the common shapes: {"error": {"message": ...}}
// and {"error": "..."}.
func errorMessage(body []byte) string {
	var m map[string]json.RawMessage
	if err := json.Unmarshal(body, &m); err != nil {
		return ""
	}
	rawErr, ok := m["error"]
	if !ok {
		return ""
	}
	var nested struct {
		Message string `json:"message"`
	}
	if err := json.Unmarshal(rawErr, &nested); err == nil && nested.Message != "" {
		return nested.Message
	}
	var flat string
	if err := json.Unmarshal(rawErr, &flat); err == nil && flat != "" {
		return flat
	}
	return ""
}
