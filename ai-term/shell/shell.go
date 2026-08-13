// Package shell spawns the user's real shell inside a PTY and streams
// its output, so ai-term can wrap the shell without replacing it.
//
// The shell keeps ECHO on and renders its own prompt line natively
// (editing, history, and completion stay 100% readline). ai-term only
// adds chrome: a status bar, a scrollback view, and (later) the AI
// panel. This is the "native line + chrome" design: like tmux, we
// multiplex the terminal, we do not replace the line editor.
//
// Idle detection: for bash we inject an OSC 133;A prompt marker into
// PROMPT_COMMAND. Every prompt prints the marker, so the wrapper knows
// the shell is idle. Busy is derived: any Enter the wrapper forwards
// means a command started, so the shell is busy until the next marker.
package shell

import (
	"os"
	"os/exec"
	"path/filepath"

	"github.com/creack/pty"
)

// Session is a shell running inside a PTY.
type Session struct {
	Cmd    *exec.Cmd
	Master *os.File
	Out    chan []byte // shell output chunks (closed on exit)
	done   chan struct{}
	Name   string // shell binary basename (e.g. "bash")
	Track  bool   // idle tracking active (bash only for now)
}

// Spawn starts the user's interactive shell in a fresh PTY.
func Spawn() (*Session, error) {
	shellPath := os.Getenv("SHELL")
	if shellPath == "" {
		shellPath = "bash"
	}
	base := filepath.Base(shellPath)

	args := []string{}
	if base == "bash" {
		args = append(args, "-i")
	}

	cmd := exec.Command(shellPath, args...)
	cmd.Env = os.Environ()

	sess := &Session{
		Out:  make(chan []byte, 64),
		done: make(chan struct{}),
		Name: base,
	}

	// Inject the OSC 133 prompt marker for idle detection (bash only).
	if base == "bash" {
		cmd.Env = injectPromptMarker(cmd.Env)
		sess.Track = true
	}

	master, err := pty.Start(cmd)
	if err != nil {
		return nil, err
	}
	sess.Cmd = cmd
	sess.Master = master

	go sess.readLoop()
	return sess, nil
}

// injectPromptMarker prepends an OSC 133;A marker to PROMPT_COMMAND so
// every prompt print tells the wrapper the shell is idle again.
func injectPromptMarker(env []string) []string {
	const marker = `printf '\033]133;A\007'`
	pc := ""
	for _, e := range env {
		if len(e) > len("PROMPT_COMMAND=") && e[:len("PROMPT_COMMAND=")] == "PROMPT_COMMAND=" {
			pc = e[len("PROMPT_COMMAND="):]
		}
	}
	combined := marker
	if pc != "" {
		combined = marker + "; " + pc
	}
	return append(env, "PROMPT_COMMAND="+combined)
}

func (s *Session) readLoop() {
	buf := make([]byte, 4096)
	for {
		n, err := s.Master.Read(buf)
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			select {
			case s.Out <- chunk:
			case <-s.done:
				return
			}
		}
		if err != nil {
			close(s.Out)
			return
		}
	}
}

// Write sends bytes to the shell's stdin.
func (s *Session) Write(b []byte) (int, error) {
	return s.Master.Write(b)
}

// Output returns the channel of shell output chunks (closed on exit).
func (s *Session) Output() <-chan []byte { return s.Out }

// TracksIdle reports whether idle/busy tracking is active for this
// shell (bash with injected prompt markers).
func (s *Session) TracksIdle() bool { return s.Track }

// ShellName returns the shell binary basename (e.g. "bash").
func (s *Session) ShellName() string { return s.Name }

// Resize resizes the PTY window.
func (s *Session) Resize(cols, rows uint16) error {
	return pty.Setsize(s.Master, &pty.Winsize{Cols: cols, Rows: rows})
}

// Close terminates the shell and releases the PTY.
func (s *Session) Close() {
	select {
	case <-s.done:
	default:
		close(s.done)
	}
	if s.Cmd.Process != nil {
		_ = s.Cmd.Process.Kill()
	}
	_ = s.Master.Close()
}
