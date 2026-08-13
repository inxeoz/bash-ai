// ai-term wraps the user's real shell in a PTY and renders it inside a
// TUI, so AI assistance (and, later, streaming, candidates, history)
// can live natively around the shell instead of fighting readline.
//
// Build: go build -o ai-term .   Run: ./ai-term  (must be a TTY)
package main

import (
	"fmt"
	"os"

	"ai-term/ai"
	"ai-term/shell"
	"ai-term/tui"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	if fi, err := os.Stdin.Stat(); err != nil || fi.Mode()&os.ModeCharDevice == 0 {
		fmt.Fprintln(os.Stderr, "ai-term: needs an interactive terminal")
		os.Exit(1)
	}

	sess, err := shell.Spawn()
	if err != nil {
		fmt.Fprintf(os.Stderr, "ai-term: %v\n", err)
		os.Exit(1)
	}
	defer sess.Close()

	p := tea.NewProgram(tui.New(sess, ai.Load()), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "ai-term: %v\n", err)
		os.Exit(1)
	}
}
