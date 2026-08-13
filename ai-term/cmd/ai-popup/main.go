// ai-popup is the tmux display-popup front end for ai-term. It reuses
// the ai package (providers, context, prompt) and shows a small
// bubbletea panel: type a request, Enter to generate, Enter again to
// insert the command into the target tmux pane via `tmux send-keys -l`,
// Esc to dismiss.
//
// Typical binding (tmux.conf):
//
//	bind-key g display-popup -w 70% -h 30% -E \
//	  "ai-popup -t '#{pane_id}'"
//
// #{pane_id} expands to the pane that was current before the popup
// opened, so send-keys lands in the right place.
//
// When run outside tmux (no TMUX env), Enter prints the generated
// command to stdout instead of sending keys.
package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"

	"ai-term/ai"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type resultMsg struct {
	cmd string
	err error
}

type model struct {
	input    textinput.Model
	spinner  spinner.Model
	querying bool
	result   string
	err      string
	cancel   context.CancelFunc

	target string // tmux pane id, "" when not in tmux
	cfg    ai.Config
}

func initial(target string) model {
	in := textinput.New()
	in.Placeholder = "Describe the command…"
	in.Prompt = "❯ "
	in.Focus()

	sp := spinner.New()
	sp.Spinner = spinner.Dot
	sp.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))

	return model{
		input:   in,
		spinner: sp,
		target:  target,
		cfg:     ai.Load(),
	}
}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case resultMsg:
		m.querying = false
		if msg.err != nil {
			m.err = msg.err.Error()
			m.result = ""
		} else {
			m.result = msg.cmd
			m.err = ""
		}
		m.input.Focus()
		return m, nil

	case tea.KeyMsg:
		switch msg.Type {
		case tea.KeyCtrlC:
			if m.querying {
				m.cancel()
			}
			return m, tea.Quit

		case tea.KeyEsc:
			if m.querying {
				m.cancel()
			}
			return m, tea.Quit

		case tea.KeyEnter:
			switch {
			case m.querying:
				return m, nil
			case m.result != "":
				return m, deliver(m.result, m.target)
			default:
				q := strings.TrimSpace(m.input.Value())
				if q == "" {
					return m, nil
				}
				ctx, cancel := context.WithCancel(context.Background())
				m.cancel = cancel
				m.querying = true
				m.input.Blur()
				return m, tea.Batch(runQuery(ctx, m.cfg, q), m.spinner.Tick)
			}
		}
	}

	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

func runQuery(ctx context.Context, cfg ai.Config, query string) tea.Cmd {
	return func() tea.Msg {
		cmd, err := ai.Query(ctx, cfg, http.DefaultClient, query)
		return resultMsg{cmd: cmd, err: err}
	}
}

// deliver inserts the command into the tmux pane (or prints it when not
// in tmux) and quits.
func deliver(cmd, target string) tea.Cmd {
	return func() tea.Msg {
		cmd = strings.TrimRight(cmd, " \t\n")
		if cmd == "" {
			return tea.Quit()
		}
		if os.Getenv("TMUX") == "" {
			fmt.Println(cmd)
			return tea.Quit()
		}
		// -t must precede -l: everything after -l is typed literally.
		args := []string{"send-keys"}
		if target != "" {
			args = append(args, "-t", target)
		}
		args = append(args, "-l", cmd)
		out, err := exec.Command("tmux", args...).CombinedOutput()
		if err != nil {
			fmt.Fprintf(os.Stderr, "ai-popup: tmux send-keys failed: %v\n%s\n", err, out)
		}
		return tea.Quit()
	}
}

func (m model) View() string {
	status := "Enter: generate · Esc: close"
	content := m.input.View()

	switch {
	case m.querying:
		status = m.spinner.View() + " Querying…"
		content = ""
	case m.result != "":
		status = lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Render("✓ generated — Enter inserts · Esc discards")
		content = m.result
	case m.err != "":
		status = lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Render("✗ " + m.err)
		content = ""
	}

	provider := m.cfg.Provider
	if provider == "" {
		provider = "anthropic"
	}
	title := lipgloss.NewStyle().Bold(true).Render(" ai-term · " + provider + "/" + m.cfg.Model() + " ")
	return title + "\n" + " " + content + "\n " + status
}

func main() {
	target := flag.String("t", "", "tmux target pane (e.g. %0); defaults to the pane set in #{pane_id}")
	flag.Parse()

	p := tea.NewProgram(initial(*target), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "ai-popup: %v\n", err)
		os.Exit(1)
	}
}
