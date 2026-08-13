package tui

import (
	"strings"
	"testing"

	"ai-term/ai"
	"ai-term/shell"

	tea "github.com/charmbracelet/bubbletea"
)

// fakeSession records writes and reports a fixed idle/busy state.
type fakeSession struct {
	writes   []byte
	idle     bool
	tracks   bool
	outputCh chan []byte
}

func newFakeSession(tracks bool) *fakeSession {
	return &fakeSession{
		idle:     true,
		tracks:   tracks,
		outputCh: make(chan []byte, 16),
	}
}

func (f *fakeSession) Write(b []byte) (int, error) {
	f.writes = append(f.writes, b...)
	return len(b), nil
}

func (f *fakeSession) Resize(cols, rows uint16) error { return nil }
func (f *fakeSession) Output() <-chan []byte          { return f.outputCh }
func (f *fakeSession) TracksIdle() bool               { return f.tracks }
func (f *fakeSession) ShellName() string              { return "fake" }

func testModel(f *fakeSession) Model {
	base := New(&shell.Session{}, ai.Load())
	m := Model{
		sess:      f,
		screen:    base.screen,
		cfg:       ai.Load(),
		width:     80,
		height:    24,
		aiInput:   base.aiInput,
		aiSpinner: base.aiSpinner,
	}
	return m
}

func keyMsg(k tea.KeyType) tea.KeyMsg { return tea.KeyMsg{Type: k} }

func update(m Model, msg tea.Msg) Model {
	mm, _ := m.Update(msg)
	return mm.(Model)
}

func TestCtrlGOpenAIPanel(t *testing.T) {
	m := update(testModel(newFakeSession(true)), keyMsg(tea.KeyCtrlG))
	if !m.aiMode {
		t.Fatal("expected AI panel to open on Ctrl-G")
	}
	if !m.aiInput.Focused() {
		t.Fatal("expected input to be focused")
	}
}

func TestPanelTypingStaysInInput(t *testing.T) {
	f := newFakeSession(true)
	m := update(testModel(f), keyMsg(tea.KeyCtrlG))

	// Type "list files" into the panel: must NOT reach the shell.
	for _, r := range "list files" {
		m = update(m, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
	}
	if len(f.writes) != 0 {
		t.Fatalf("panel typing leaked to shell: %q", f.writes)
	}
	if got := m.aiInput.Value(); got != "list files" {
		t.Fatalf("input value = %q, want %q", got, "list files")
	}
}

func TestEscClosesPanel(t *testing.T) {
	m := update(testModel(newFakeSession(true)), keyMsg(tea.KeyCtrlG))
	m = update(m, keyMsg(tea.KeyEsc))
	if m.aiMode {
		t.Fatal("expected panel to close on Esc")
	}
	if m.aiInput.Focused() {
		t.Fatal("expected input blurred after close")
	}
}

func TestInsertResultWritesBracketedPaste(t *testing.T) {
	f := newFakeSession(true)
	m := update(testModel(f), keyMsg(tea.KeyCtrlG))
	m.aiResult = "ls -la"

	m = update(m, keyMsg(tea.KeyEnter))

	if string(f.writes) != "\x1b[200~ls -la\x1b[201~" {
		t.Fatalf("writes = %q, want bracketed paste of ls -la", f.writes)
	}
	if m.aiMode {
		t.Fatal("expected panel to close after insert")
	}
}

func TestInsertBlockedWhileBusy(t *testing.T) {
	f := newFakeSession(true)
	m := update(testModel(f), keyMsg(tea.KeyCtrlG))
	m.aiResult = "rm -rf /"
	m.busy = true

	m = update(m, keyMsg(tea.KeyEnter))

	if len(f.writes) != 0 {
		t.Fatalf("busy insert wrote to shell: %q", f.writes)
	}
	if !m.aiMode {
		t.Fatal("expected panel to stay open while busy")
	}
	if !strings.Contains(m.aiError, "busy") {
		t.Fatalf("expected busy hint, got %q", m.aiError)
	}
}

func TestEnterForwardsToShellOutsidePanel(t *testing.T) {
	f := newFakeSession(true)
	m := update(testModel(f), keyMsg(tea.KeyEnter))
	if !strings.Contains(string(f.writes), "\r") {
		t.Fatalf("expected Enter forwarded to shell, got %q", f.writes)
	}
	if !m.busy {
		t.Fatal("expected busy after Enter with tracking shell")
	}
}

func TestNormalKeysPassThrough(t *testing.T) {
	f := newFakeSession(true)
	update(testModel(f), tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'e', 'c', 'h', 'o'}})
	if string(f.writes) != "echo" {
		t.Fatalf("writes = %q, want echo", f.writes)
	}
}

func TestQueryErrorShownInPanel(t *testing.T) {
	m := update(testModel(newFakeSession(true)), keyMsg(tea.KeyCtrlG))
	m.aiQuerying = true
	m = update(m, aiResultMsg{err: errMock})
	if m.aiQuerying {
		t.Fatal("expected querying to end")
	}
	if m.aiError == "" {
		t.Fatal("expected error message")
	}
}

func TestShellOutputClearsBusyOnFreshMarker(t *testing.T) {
	f := newFakeSession(true)
	m := update(testModel(f), keyMsg(tea.KeyEnter))

	// Regression: after Enter, the echo of the typed line must NOT clear
	// busy just because an old marker flag is still set. Busy clears only
	// when a fresh 133;A prompt marker arrives.
	m = update(m, shellOutputMsg{data: []byte("sleep 3; echo x\r\n")})
	if !m.busy {
		t.Fatal("command echo cleared busy without a fresh marker")
	}
	m = update(m, shellOutputMsg{data: []byte("\x1b]133;A\x07")})
	if m.busy {
		t.Fatal("fresh marker did not clear busy")
	}
}

var errMock = errString("boom")

type errString string

func (e errString) Error() string { return string(e) }
