// Package term is a minimal ANSI screen model used to display the
// wrapped shell's output. It is deliberately NOT a terminal emulator:
// it understands the escape sequences bash/zsh prompts and common
// commands emit (cursor moves, line/screen clears) and ignores the
// rest. Full-screen apps (vim, htop) will degrade.
//
// Rows are kept as plain text: SGR color sequences are stripped on
// ingestion so that cursor math is exact (sequence bytes consume zero
// cells). The cost is that shell output loses its colors; the ai-term
// chrome (status bar, panel) is styled by lipgloss independently.
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
	cursorC int // column in runes
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
			case c == '\b' || c == 0x7f:
				if s.cursorC > 0 {
					s.cursorC--
				}
			case c == '\t':
				s.cursorC = (s.cursorC/8 + 1) * 8
				s.truncateRow()
			case c >= 0x20:
				r, size := utf8.DecodeRune(b[i:])
				if r != utf8.RuneError || size > 1 {
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
	s.trimToHeight()
}

// trimToHeight drops overflow rows from the top (scrolling) and caps
// the buffer at the scrollback limit.
func (s *Screen) trimToHeight() {
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

// writeRune inserts r at the cursor. Overwrites existing content; pads
// with spaces if the cursor is beyond the row end.
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

// truncateRow cuts the current row to the screen width (rune-aware so
// multi-byte characters are never split).
func (s *Screen) truncateRow() {
	if s.cursorR >= len(s.rows) {
		return
	}
	row := []rune(s.rows[s.cursorR])
	if len(row) > s.width {
		s.rows[s.cursorR] = string(row[:s.width])
		s.cursorC = s.width
	}
}

// applyCSI handles CSI final bytes. Cursor moves and erases are
// applied; everything else (SGR colors, mode sets) is dropped so rows
// stay plain text.
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
	case 'm', 'h', 'l':
		// SGR color / mode-set: dropped to keep rows plain.
	case '@':
		// ICH: insert n spaces at the cursor, shifting the rest right.
		s.ensureRow()
		row := []rune(s.rows[s.cursorR])
		n := count(1)
		if s.cursorC <= len(row) {
			pad := make([]rune, n)
			for i := range pad {
				pad[i] = ' '
			}
			s.rows[s.cursorR] = string(row[:s.cursorC]) + string(pad) + string(row[s.cursorC:])
		}
		s.truncateRow()
	case 'P':
		// DCH: delete n chars at the cursor, shifting the rest left.
		s.ensureRow()
		row := []rune(s.rows[s.cursorR])
		n := count(1)
		end := s.cursorC + n
		if end > len(row) {
			end = len(row)
		}
		s.rows[s.cursorR] = string(row[:s.cursorC]) + string(row[end:])
	case 'X':
		// ECH: erase n chars at the cursor (fill with spaces).
		s.ensureRow()
		row := []rune(s.rows[s.cursorR])
		n := count(1)
		for i := 0; i < n && s.cursorC+i < len(row); i++ {
			row[s.cursorC+i] = ' '
		}
		s.rows[s.cursorR] = string(row)
	case 'L':
		// IL: insert n blank rows at the cursor, shifting down.
		n := count(1)
		blank := make([]string, n)
		for i := range blank {
			blank[i] = ""
		}
		if s.cursorR < len(s.rows) {
			rows := append([]string{}, s.rows[:s.cursorR]...)
			rows = append(rows, blank...)
			s.rows = append(rows, s.rows[s.cursorR:]...)
			s.cursorR += n
		}
		s.trimToHeight()
	case 'M':
		// DL: delete n rows at the cursor, shifting up.
		n := count(1)
		end := s.cursorR + n
		if end > len(s.rows) {
			end = len(s.rows)
		}
		s.rows = append(s.rows[:s.cursorR], s.rows[end:]...)
		s.trimToHeight()
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
