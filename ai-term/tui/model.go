// Package tui is the bubbletea UI for ai-term: a scrollback view of the
// wrapped shell's output, a status bar, and the AI panel. Normal input
// passes through to the shell so its native line editor stays in charge.
package tui

import (
	"context"
	"net/http"
	"strings"

	"ai-term/ai"
	"ai-term/shell"
	"ai-term/term"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type shellOutputMsg struct {
	data []byte
}

type shellExitedMsg struct{}

type aiResultMsg struct {
	cmd string
	err error
}

// aiPanelStyle marks the panel area.
var aiPanelStyle = lipgloss.NewStyle().Border(lipgloss.RoundedBorder(), false, false, true, false)

// Model is the bubbletea state for ai-term.
type Model struct {
	sess   *shell.Session
	screen *term.Screen
	busy   bool
	cfg    ai.Config

	markerAtBusy int // MarkerSeq when the current command started

	// AI panel state
	aiMode     bool
	aiInput    textinput.Model
	aiSpinner  spinner.Model
	aiQuerying bool
	aiResult   string
	aiError    string
	aiCancel   context.CancelFunc

	width  int
	height int
}

// New builds the model around a spawned shell session.
func New(s *shell.Session, cfg ai.Config) Model {
	input := textinput.New()
	input.Placeholder = "Describe the command…"
	input.Prompt = "❯ "

	sp := spinner.New()
	sp.Spinner = spinner.Dot
	sp.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))

	return Model{
		sess:      s,
		screen:    term.New(80, 24, 2000),
		cfg:       cfg,
		aiInput:   input,
		aiSpinner: sp,
	}
}

func (m Model) Init() tea.Cmd {
	return waitForShell(m.sess.Out)
}

func waitForShell(ch <-chan []byte) tea.Cmd {
	return func() tea.Msg {
		chunk, ok := <-ch
		if !ok {
			return shellExitedMsg{}
		}
		return shellOutputMsg{data: chunk}
	}
}

// runAIQuery issues the query asynchronously; cancellation happens via
// the context.
func runAIQuery(ctx context.Context, cfg ai.Config, query string) tea.Cmd {
	return func() tea.Msg {
		cmd, err := ai.Query(ctx, cfg, http.DefaultClient, query)
		return aiResultMsg{cmd: cmd, err: err}
	}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case shellOutputMsg:
		m.screen.Write(msg.data)
		// Busy clears only when a FRESH prompt marker arrives (not a
		// stale one from before the command started).
		if m.busy && m.screen.MarkerSeq != m.markerAtBusy {
			m.busy = false
		}
		return m, waitForShell(m.sess.Out)

	case shellExitedMsg:
		return m, tea.Quit

	case aiResultMsg:
		m.aiQuerying = false
		if msg.err != nil {
			m.aiError = msg.err.Error()
			m.aiResult = ""
		} else {
			m.aiResult = msg.cmd
			m.aiError = ""
		}
		m.aiInput.Focus()
		return m, nil

	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.screen.Resize(msg.Width, msg.Height)
		_ = m.sess.Resize(uint16(msg.Width), uint16(msg.Height))
		return m, nil

	case tea.KeyMsg:
		if m.aiMode {
			return m.aiKey(msg)
		}
		return m.handleKey(msg)
	}
	return m, nil
}

// ---- normal (pass-through) mode ----

// handleKey routes keys: Ctrl-G opens the AI panel; everything else
// passes through to the shell's stdin untouched.
func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if msg.Type == tea.KeyCtrlG {
		m.aiMode = true
		m.aiInput.Focus()
		m.aiResult = ""
		m.aiError = ""
		return m, nil
	}
	bytes := keyBytes(msg)
	if len(bytes) == 0 {
		return m, nil
	}
	if _, err := m.sess.Write(bytes); err != nil {
		return m, tea.Quit
	}
	// A command just started; idle returns at the next 133;A marker.
	// Real Enter sends \r (KeyEnter); pasted input can send \n (KeyCtrlJ).
	if (msg.Type == tea.KeyEnter || msg.Type == tea.KeyCtrlJ) && m.sess.Track {
		m.busy = true
		m.markerAtBusy = m.screen.MarkerSeq
	}
	return m, nil
}

// ---- AI panel mode ----

func (m Model) aiKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyEsc, tea.KeyCtrlG:
		return m.closeAIPanel(), nil

	case tea.KeyCtrlC:
		if m.aiQuerying {
			m.cancelQuery()
			m.aiError = "cancelled"
			return m, nil
		}
		return m.closeAIPanel(), nil

	case tea.KeyEnter:
		switch {
		case m.aiQuerying:
			return m, nil // query in flight; ignore Enter
		case m.aiResult != "":
			m, cmd := m.insertResult()
			return m, cmd
		default:
			query := strings.TrimSpace(m.aiInput.Value())
			if query == "" {
				return m, nil
			}
			ctx, cancel := context.WithCancel(context.Background())
			m.aiCancel = cancel
			m.aiQuerying = true
			m.aiResult = ""
			m.aiError = ""
			m.aiInput.Blur()
			return m, tea.Batch(runAIQuery(ctx, m.cfg, query), m.aiSpinner.Tick)
		}
	}

	var cmd tea.Cmd
	m.aiInput, cmd = m.aiInput.Update(msg)
	return m, cmd
}

// insertResult pastes the generated command into the shell's native
// input line via bracketed paste, then closes the panel.
func (m Model) insertResult() (tea.Model, tea.Cmd) {
	if m.busy {
		m.aiError = "Shell is busy — wait for the prompt, then press Enter again"
		return m, nil
	}
	cmd := strings.TrimRight(m.aiResult, " \t\n")
	if cmd != "" {
		// Bracketed paste: readline treats the content literally and
		// renders it as text in the prompt, fully editable. No \r: the
		// user reviews and presses Enter themselves (native flow).
		if _, err := m.sess.Write([]byte("\x1b[200~" + cmd + "\x1b[201~")); err != nil {
			return m, tea.Quit
		}
	}
	return m.closeAIPanel(), nil
}

func (m Model) cancelQuery() {
	if m.aiCancel != nil {
		m.aiCancel()
		m.aiCancel = nil
	}
	m.aiQuerying = false
}

func (m Model) closeAIPanel() Model {
	m.cancelQuery()
	m.aiMode = false
	m.aiInput.Blur()
	return m
}

// ---- rendering ----

func (m Model) View() string {
	if m.height <= 1 {
		return ""
	}

	panelLines := 0
	panel := ""
	if m.aiMode {
		panel = m.aiPanel()
		panelLines = strings.Count(panel, "\n") + 1
	}
	barLines := 1
	bodyH := m.height - 1 - panelLines
	if bodyH < 0 {
		bodyH = 0
	}

	rows := m.screen.Rows()
	start := len(rows) - bodyH
	if start < 0 {
		start = 0
	}
	visible := rows[start:]
	body := strings.Join(visible, "\n")
	missing := bodyH - len(visible)
	if missing > 0 {
		body += strings.Repeat("\n", missing)
	}

	_ = barLines
	return body + panel + m.statusBar()
}

// aiPanel renders the input line and result/error/status area.
func (m Model) aiPanel() string {
	status := "Enter: generate · Esc: close"
	content := m.aiInput.View()

	switch {
	case m.aiQuerying:
		status = m.aiSpinner.View() + " Querying…"
		content = ""
	case m.aiResult != "":
		status = lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Render("✓ generated — Enter inserts · Esc discards")
		content = m.aiResult
	case m.aiError != "":
		status = lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Render("✗ " + m.aiError)
		content = ""
	}

	if m.busy {
		status += " · shell busy (insert waits)"
	}

	if m.width > 0 {
		if len(content) > m.width-2 {
			content = content[:m.width-2]
		}
		if len(status) > m.width-2 {
			status = status[:m.width-2]
		}
	}

	panel := " " + content + "\n " + status
	return aiPanelStyle.Render(panel)
}

func (m Model) statusBar() string {
	state := "idle"
	if m.busy {
		state = "busy"
	}
	name := "shell"
	if m.sess.Name != "" {
		name = m.sess.Name
	}
	model := ""
	if m.cfg.Provider != "" {
		model = " · " + m.cfg.Provider
		if m.cfg.Model() != "" {
			model += "/" + m.cfg.Model()
		}
	}
	text := " ai-term | " + name + model + " | " + state
	bar := lipgloss.NewStyle().Reverse(true).Padding(0, 1).Render(text)
	return "\n" + bar
}
