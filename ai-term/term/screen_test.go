package term

import (
	"strings"
	"testing"
)

func feed(s *Screen, parts ...string) {
	for _, p := range parts {
		s.Write([]byte(p))
	}
}

func TestSGRStripped(t *testing.T) {
	s := New(80, 24, 200)
	feed(s, "\x1b[1;36mhello\x1b[0m")

	rows := s.Rows()
	if len(rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(rows))
	}
	if rows[0] != "hello" {
		t.Errorf("row = %q, want plain %q", rows[0], "hello")
	}
}

// Regression: bash redraws the prompt on every keystroke (\r + prompt +
// line). SGR bytes must consume zero cells, so the typed text lands
// exactly after the prompt instead of overwriting escape bytes (which
// previously produced literal "[1;36m" text and garbled lines).
func TestPromptRedrawCursorAlignment(t *testing.T) {
	s := New(80, 24, 200)

	// First draw: colored prompt, then the user types "ls".
	feed(s, "\x1b[1;36m/tmp\x1b[0m ❯ ", "l", "s")
	// bash redraws the whole line after each keystroke
	feed(s, "\r\x1b[1;36m/tmp\x1b[0m ❯ ls", "\r\x1b[1;36m/tmp\x1b[0m ❯ ls")

	rows := s.Rows()
	if len(rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(rows))
	}
	if rows[0] != "/tmp ❯ ls" {
		t.Errorf("row = %q, want %q", rows[0], "/tmp ❯ ls")
	}
}

func TestTypeThenBackspace(t *testing.T) {
	s := New(80, 24, 200)
	// \x7f alone moves the cursor back; readline then redraws the line.
	feed(s, "$ ", "echo", "\x7f")
	if s.Rows()[0] != "$ echo" {
		t.Errorf("row = %q, want %q (cursor moved, char remains)", s.Rows()[0], "$ echo")
	}
	// readline redraw: \r + new line + erase-to-EOL
	feed(s, "\r$ ech\x1b[K")
	if s.Rows()[0] != "$ ech" {
		t.Errorf("row = %q, want %q after redraw", s.Rows()[0], "$ ech")
	}
}

func TestTypeOverwritesPreviousContent(t *testing.T) {
	s := New(80, 24, 200)
	feed(s, "abcdef")
	feed(s, "\rXY")

	rows := s.Rows()
	if rows[0] != "XYcdef" {
		t.Errorf("row = %q, want %q", rows[0], "XYcdef")
	}
}

func TestEraseToEndOfLine(t *testing.T) {
	s := New(80, 24, 200)
	feed(s, "abcdef", "\rXY\x1b[K")

	rows := s.Rows()
	if rows[0] != "XY" {
		t.Errorf("row = %q, want %q", rows[0], "XY")
	}
}

func TestNewlineScrolling(t *testing.T) {
	s := New(10, 3, 100)
	for i := 0; i < 5; i++ {
		feed(s, "line"+string(rune('0'+i)), "\r\n")
	}

	rows := s.Rows()
	if len(rows) != 3 {
		t.Fatalf("rows = %d, want 3 (height-capped)", len(rows))
	}
	got := strings.Join(rows, "|")
	if got != "line3|line4|" {
		t.Errorf("scrolled content = %q (trailing blank = cursor row)", got)
	}
}

func TestCursorMoves(t *testing.T) {
	s := New(80, 24, 200)
	feed(s, "abcdef", "\x1b[2D", "X")

	if s.Rows()[0] != "abcdXf" {
		t.Errorf("row = %q, want %q", s.Rows()[0], "abcdXf")
	}
}

func TestOSCMarkers(t *testing.T) {
	s := New(80, 24, 200)
	feed(s, "\x1b]133;A\x07")
	if !s.Idle {
		t.Error("want idle after 133;A")
	}
	if s.MarkerSeq != 1 {
		t.Errorf("MarkerSeq = %d, want 1", s.MarkerSeq)
	}
	feed(s, "x", "\x1b]133;B\x07")
	if s.Idle {
		t.Error("want busy after 133;B")
	}
	feed(s, "\x1b]133;A\x1b\\") // ST-terminated marker
	if s.MarkerSeq != 2 {
		t.Errorf("MarkerSeq = %d, want 2 (ST terminator)", s.MarkerSeq)
	}
}

// Escape sequences split across chunks must still parse.
func TestSplitEscapeAcrossChunks(t *testing.T) {
	s := New(80, 24, 200)
	feed(s, "ab\x1b[1;3", "6mcd\x1b[", "0m")
	if s.Rows()[0] != "abcd" {
		t.Errorf("row = %q, want %q", s.Rows()[0], "abcd")
	}
}

func TestWideCharsNotSplitByTruncate(t *testing.T) {
	s := New(5, 3, 100)
	feed(s, "一二三四五六七八")
	rows := s.Rows()
	if len(rows[0]) > 5*3 {
		t.Errorf("row wider than 5 runes: %q", rows[0])
	}
	_ = rows
}

// Regression: bash/readline uses CSI ICH (\x1b[<n>@) when editing mid-
// line. Captured live from bash: "git status", 6×Left, "git add -A && ".
// The inserted text must shift the tail right, not overwrite it.
func TestReadlineInsertCharacters(t *testing.T) {
	s := New(80, 24, 200)
	feed(s,
		"git", " ", "status", // typed line
		"\b", "\b\b\b\b\b", // 6×Left
		"\x1b[3@git",      // ICH 3 + "git"
		"\x1b[8@ add -A ", // ICH 8 + " add -A "
		"\x1b[3@&& ",      // ICH 3 + "&& "
	)
	if got := s.Rows()[0]; got != "git git add -A && status" {
		t.Errorf("row = %q, want %q", got, "git git add -A && status")
	}
}

func TestReadlineDeleteCharacters(t *testing.T) {
	s := New(80, 24, 200)
	feed(s, "abcdef", "\x1b[2D", "\x1b[2P")
	if got := s.Rows()[0]; got != "abcd" {
		t.Errorf("row = %q, want %q", got, "abcd")
	}
}
