// Package term is a minimal ANSI screen model used to display the
// wrapped shell's output. It is deliberately NOT a terminal emulator:
// it understands the escape sequences bash/zsh prompts and common
// commands emit (cursor moves, line/screen clears, SGR colors) and
// ignores the rest. Full-screen apps (vim, htop) will degrade.
//
// Content is kept as raw rows of text; SGR color sequences pass through
// untouched so colors survive our re-rendering.
package term

import (
	"fmt"
	"unicode/utf8"
)

const (
	stateNormal = iota
	stateESC
	stateCSI
	stateOSC
)

// Screen tracks shell output as a scrollable row buffer.
type Screen struct {
	rows    []string
	cursorR int
	cursorC int
	width   int
	height  int
	cap     int // maximum rows kept (scrollback)
	Idle    bool

	// MarkerSeq counts OSC 133;A prompts seen. Consumers use it to tell
	// "a fresh prompt arrived since I did X" apart from a stale flag.
	MarkerSeq int

	state int    // parse state, kept across Write calls (chunked reads)
	csi   []byte // pending CSI params
	osc   []byte // pending OSC payload
	oscST bool   // OSC was terminated by ST (ESC \)
}

// New creates a Screen. width/height are the visible viewport; cap is
// the total scrollback cap.
func New(width, height, cap int) *Screen {
	if width <= 0 {
		width = 80
	}
	if height <= 0 {
		height = 24
	}
	return &Screen{
		width:  width,
		height: height,
		cap:    cap,
		rows:   make([]string, 0, height),
	}
}

// Resize changes the viewport size, keeping existing rows.
func (s *Screen) Resize(width, height int) {
	if width > 0 {
		s.width = width
	}
	if height > 0 {
		s.height = height
	}
}

// Rows returns the row buffer.
func (s *Screen) Rows() []string { return s.rows }

// Write consumes a chunk of shell output, updating rows and state.
func (s *Screen) Write(b []byte) {
	for i := 0; i < len(b); i++ {
		c := b[i]
		switch s.state {
		case stateNormal:
			switch {
			case c == 0x1b:
				s.state = stateESC
			case c == '\r':
				s.cursorC = 0
			case c == '\n':
				s.cursorR++
				s.ensureRow()
			case c == '\b':
				if s.cursorC > 0 {
					s.cursorC--
				}
			case c == '\t':
				s.cursorC = (s.cursorC/8 + 1) * 8
				s.truncateRow()
			case c >= 0x20:
				r, size := utf8.DecodeRune(b[i:])
				if r == utf8.RuneError && size == 1 {
					s.writeByte(c)
				} else {
					s.writeRune(r)
					i += size - 1
				}
			}
		case stateESC:
			switch {
			case c == '[':
				s.state = stateCSI
				s.csi = s.csi[:0]
			case c == ']':
				s.state = stateOSC
				s.osc = s.osc[:0]
				s.oscST = false
			case c == '\\' && s.oscST:
				// ST (ESC \) terminator of an OSC sequence
				s.applyOSC(s.osc)
				s.osc = s.osc[:0]
				s.oscST = false
				s.state = stateNormal
			case c == '7':
				s.state = stateNormal
			case c == '8':
				s.state = stateNormal
			default:
				s.state = stateNormal
			}
		case stateCSI:
			if c >= 0x40 && c <= 0x7e {
				s.csi = append(s.csi, c)
				s.applyCSI(s.csi)
				s.csi = s.csi[:0]
				s.state = stateNormal
			} else {
				s.csi = append(s.csi, c)
			}
		case stateOSC:
			switch {
			case c == 0x07:
				s.applyOSC(s.osc)
				s.osc = s.osc[:0]
				s.state = stateNormal
			case c == 0x1b:
				s.oscST = true
				s.state = stateESC
			default:
				s.osc = append(s.osc, c)
			}
		}
	}
}

func (s *Screen) ensureRow() {
	for len(s.rows) <= s.cursorR {
		s.rows = append(s.rows, "")
	}
	if s.cursorR >= s.height {
		drop := s.cursorR - s.height + 1
		if drop > len(s.rows) {
			drop = len(s.rows)
		}
		s.rows = s.rows[drop:]
		s.cursorR -= drop
	}
	if len(s.rows) > s.cap {
		drop := len(s.rows) - s.cap
		s.rows = s.rows[drop:]
		s.cursorR -= drop
		if s.cursorR < 0 {
			s.cursorR = 0
		}
	}
}

func (s *Screen) writeRune(r rune) {
	s.ensureRow()
	row := []rune(s.rows[s.cursorR])
	if s.cursorC < len(row) {
		row[s.cursorC] = r
	} else {
		for len(row) < s.cursorC {
			row = append(row, ' ')
		}
		row = append(row, r)
	}
	s.rows[s.cursorR] = string(row)
	s.cursorC++
	s.truncateRow()
}

func (s *Screen) writeByte(c byte) {
	if c < 0x20 {
		return
	}
	s.ensureRow()
	row := []byte(s.rows[s.cursorR])
	if s.cursorC < len(row) {
		row[s.cursorC] = c
	} else {
		for len(row) < s.cursorC {
			row = append(row, ' ')
		}
		row = append(row, c)
	}
	s.rows[s.cursorR] = string(row)
	s.cursorC++
	s.truncateRow()
}

func (s *Screen) truncateRow() {
	if s.cursorR < len(s.rows) && len(s.rows[s.cursorR]) > s.width {
		s.rows[s.cursorR] = s.rows[s.cursorR][:s.width]
		s.cursorC = s.width
	}
}

// applyCSI handles CSI final bytes. The raw sequence bytes are passed
// in so SGR color sequences can be embedded in the row content and
// reach the real terminal display.
func (s *Screen) applyCSI(csi []byte) {
	final := csi[len(csi)-1]
	params := string(csi[:len(csi)-1])

	count := func(def int) int {
		n := def
		if params != "" && params != "?" {
			fmt.Sscanf(params, "%d", &n)
		}
		if n < 1 {
			n = 1
		}
		return n
	}

	switch final {
	case 'm':
		// SGR: colors pass through by embedding the raw sequence.
		s.ensureRow()
		s.rows[s.cursorR] += "\x1b[" + params + "m"
	case 'K':
		if s.cursorR >= len(s.rows) {
			s.ensureRow()
		}
		row := []rune(s.rows[s.cursorR])
		switch params {
		case "", "0":
			if s.cursorC < len(row) {
				s.rows[s.cursorR] = string(row[:s.cursorC])
			}
		case "1":
			if s.cursorC <= len(row) {
				pad := make([]rune, s.cursorC)
				for i := range pad {
					pad[i] = ' '
				}
				s.rows[s.cursorR] = string(pad) + string(row[s.cursorC:])
			}
		case "2":
			s.rows[s.cursorR] = ""
		}
	case 'J':
		switch params {
		case "", "0":
			for r := s.cursorR + 1; r < len(s.rows); r++ {
				s.rows[r] = ""
			}
		case "1":
			for r := 0; r < s.cursorR; r++ {
				s.rows[r] = ""
			}
		case "2":
			s.rows = s.rows[:0]
			s.ensureRow()
			s.cursorR = 0
			s.cursorC = 0
		}
	case 'A':
		s.cursorR -= count(1)
		if s.cursorR < 0 {
			s.cursorR = 0
		}
	case 'B':
		s.cursorR += count(1)
		s.ensureRow()
	case 'C':
		s.cursorC += count(1)
	case 'D':
		s.cursorC -= count(1)
		if s.cursorC < 0 {
			s.cursorC = 0
		}
	case 'G':
		s.cursorC = count(1) - 1
		if s.cursorC < 0 {
			s.cursorC = 0
		}
	case 'H', 'f':
		row, col := 1, 1
		if params != "" {
			fmt.Sscanf(params, "%d;%d", &row, &col)
		}
		s.cursorR = row - 1
		s.cursorC = col - 1
		if s.cursorR < 0 {
			s.cursorR = 0
		}
		if s.cursorC < 0 {
			s.cursorC = 0
		}
		s.ensureRow()
	}
}

// applyOSC handles OSC sequences. OSC 133;A marks the shell as idle
// (prompt shown); OSC 133;B marks busy. Everything else is dropped.
func (s *Screen) applyOSC(osc []byte) {
	switch string(osc) {
	case "133;A":
		s.Idle = true
		s.MarkerSeq++
	case "133;B":
		s.Idle = false
	}
}
