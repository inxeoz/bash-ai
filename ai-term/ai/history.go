package ai

import (
	"os"
	"path/filepath"
	"strings"
)

// HistoryFile returns the path of the query/command history file.
func HistoryFile() string {
	if f := os.Getenv("AI_TERM_HISTORY_FILE"); f != "" {
		return f
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = os.Getenv("HOME")
	}
	return filepath.Join(dir, "ai-term", "history")
}

// HistoryAdd appends one "query<TAB>command" entry.
func HistoryAdd(query, cmd string) {
	cmd = strings.TrimRight(cmd, " \t\n")
	if cmd == "" {
		return
	}
	f := HistoryFile()
	if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
		return
	}
	line := strings.ReplaceAll(query, "\t", " ") + "\t" + cmd + "\n"
	fh, err := os.OpenFile(f, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer fh.Close()
	fh.WriteString(line)
}

// HistoryQueries returns the most recent queries, oldest first, capped
// at n entries.
func HistoryQueries(n int) []string {
	if n <= 0 {
		n = 10
	}
	data, err := os.ReadFile(HistoryFile())
	if err != nil {
		return nil
	}
	var queries []string
	for _, line := range strings.Split(string(data), "\n") {
		if tab := strings.IndexByte(line, '\t'); tab > 0 {
			queries = append(queries, line[:tab])
		}
	}
	if len(queries) > n {
		queries = queries[len(queries)-n:]
	}
	return queries
}
