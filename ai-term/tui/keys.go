package tui

import tea "github.com/charmbracelet/bubbletea"

// keyBytes converts a bubbletea KeyMsg back into the raw terminal byte
// sequence to forward to the shell. This is the mirror of readline's
// key parsing: runes pass through as UTF-8, named keys become their
// escape sequences.
func keyBytes(msg tea.KeyMsg) []byte {
	if msg.Type == tea.KeyRunes && len(msg.Runes) > 0 {
		return []byte(string(msg.Runes))
	}

	switch msg.Type {
	case tea.KeyEnter:
		return []byte{'\r'}
	case tea.KeyTab:
		return []byte{'\t'}
	case tea.KeyBackspace:
		return []byte{'\x7f'}
	case tea.KeySpace:
		return []byte{' '}
	case tea.KeyEsc:
		return []byte{'\x1b'}
	case tea.KeyDelete:
		return []byte("\x1b[3~")
	case tea.KeyUp:
		return []byte("\x1b[A")
	case tea.KeyDown:
		return []byte("\x1b[B")
	case tea.KeyRight:
		return []byte("\x1b[C")
	case tea.KeyLeft:
		return []byte("\x1b[D")
	case tea.KeyHome:
		return []byte("\x1b[H")
	case tea.KeyEnd:
		return []byte("\x1b[F")
	case tea.KeyPgUp:
		return []byte("\x1b[5~")
	case tea.KeyPgDown:
		return []byte("\x1b[6~")
	case tea.KeyCtrlAt:
		return []byte{0x00}
	case tea.KeyCtrlBackslash:
		return []byte{0x1c}
	case tea.KeyCtrlCloseBracket:
		return []byte{0x1d}
	case tea.KeyCtrlUnderscore:
		return []byte{0x1f}
	}

	if code, ok := ctrlCodes[msg.Type]; ok {
		return []byte{code}
	}
	return nil
}

// ctrlCodes maps bubbletea's KeyCtrlX types to their control bytes.
var ctrlCodes = map[tea.KeyType]byte{
	tea.KeyCtrlA: 0x01,
	tea.KeyCtrlB: 0x02,
	tea.KeyCtrlC: 0x03,
	tea.KeyCtrlD: 0x04,
	tea.KeyCtrlE: 0x05,
	tea.KeyCtrlF: 0x06,
	tea.KeyCtrlG: 0x07,
	tea.KeyCtrlH: 0x08,
	tea.KeyCtrlI: 0x09,
	tea.KeyCtrlJ: 0x0a,
	tea.KeyCtrlK: 0x0b,
	tea.KeyCtrlL: 0x0c,
	tea.KeyCtrlM: 0x0d,
	tea.KeyCtrlN: 0x0e,
	tea.KeyCtrlO: 0x0f,
	tea.KeyCtrlP: 0x10,
	tea.KeyCtrlQ: 0x11,
	tea.KeyCtrlR: 0x12,
	tea.KeyCtrlS: 0x13,
	tea.KeyCtrlT: 0x14,
	tea.KeyCtrlU: 0x15,
	tea.KeyCtrlV: 0x16,
	tea.KeyCtrlW: 0x17,
	tea.KeyCtrlX: 0x18,
	tea.KeyCtrlY: 0x19,
	tea.KeyCtrlZ: 0x1a,
}
