# Future Improvements & Features

> Ideas to advance bash-ai — from quick wins in the current bash port to
> the big one: a native terminal with built-in AI, so we stop fighting
> bash/readline entirely.

## Status (2026-08)

Built: `ai-term/` (Go + bubbletea), a PTY wrapper that keeps the shell's
native line editor and adds a status bar + AI panel (`Ctrl-G` →
query → bracketed-paste insert). Providers, context, and prompt are
ported from `lib-bash/` into `ai/` (net/http + JSON, no jq). A tmux
front end (`cmd/ai-popup`) opens the same UI in a `display-popup` and
inserts via `tmux send-keys -l`.

Two deliberate design decisions, recorded because they change the
original vision:

1. **Native-line + chrome, not a fully-owned input line.** The original
   vision said "own the input line" (Warp-style, ECHO off + own
   editor). That forfeits readline editing/history/completion and means
   reimplementing a line editor — months. MVP instead wraps the native
   line: shell keeps ECHO, we add chrome (status bar, AI panel) and
   insert via bracketed paste / `send-keys -l`. If a fully-owned line
   is ever wanted, it is a separate project.
2. **tmux integration via popup, not a fork.** Forking tmux would not
   solve the input-line problem anyway (tmux leaves the line editor to
   the shell inside each pane) and means maintaining a C fork. The
   `display-popup` route keeps tmux's terminal emulator and reuses the
   Go `ai/` package.

Known limitation: shell output colors are stripped in the wrapper's
screen model (rows stay plain so cursor math is exact — SGR bytes
previously consumed cells and corrupted the cursor, producing literal
`[0m`/`[4m` text). The model does handle readline's CSI ICH/DCH/ECH
(`\x1b[<n>@` etc.) for faithful mid-line edits.

## The Core Problem

The bash port is a series of compromises:

| zsh (native) | bash (workaround) |
|---|---|
| `zle` widgets hook Enter | `bind -x` callbacks desync readline's display |
| `print -z` pushes into the buffer | pending file + Ctrl-G |
| async spinner in the buffer | synchronous query, static indicator |
| `.accept-line` delegate | nothing — eval has no delegate |

Every display bug we fixed (eaten prompts, garbled lines, hidden queries)
traced back to one root cause: **bash does not let a third party own the
input line**. We always lose — readline redraws from its own internal
state and erases whatever we drew.

The endgame fix is not a better workaround. It is **owning the input line
ourselves**.

## Vision: A Native Terminal with Built-in AI

Instead of living inside bash's readline, ship a terminal wrapper that
owns the whole UI:

```
┌──────────────────────────────────────────┐
│ $ git status                             │  ← app-drawn history area
│ $ git add .                              │
│                                          │
│ ⠋ generating…  find . -type f -size +10M │  ← app-drawn input line
│                                          │    (spinner animates natively)
│ [1] find . -type f -size +10M            │  ← candidate menu (j/k + Enter)
│ [2] du -ah | sort -rh | head             │
└──────────────────────────────────────────┘
```

### Architecture (PTY wrapper, not a terminal emulator)

The sweet spot is a **shell wrapper**, not a from-scratch terminal:

1. Spawn the real shell (`bash`, `zsh`, `fish`) inside a PTY, in raw mode.
2. Render our own prompt + input line with a TUI framework.
3. Pass user input to the shell's stdin; stream the shell's output into
   a scrollback area.
4. Run AI queries as an async task in the app — spinner, cancellation,
   streaming all native.
5. Insert the generated command into *our* input buffer, fully editable
   with normal terminal keys (arrows, Ctrl-W, selection).
6. Optional: detect the shell prompt in the output stream to know when
   the shell is idle (prompt detection is a solved problem — ptyparser,
   shell-integration escape codes).

Because the app owns rendering, every fight disappears:
- async spinner while waiting
- command inserted in place (no `print -z` equivalent needed)
- Enter stays Enter; `# query` can work natively again
- Ctrl-C/streaming/cancellation all native
- multiline input, pasted code blocks — all normal

### Tech Options

| Stack | Why |
|---|---|
| Go + bubbletea (Charm) | fastest to MVP; bubbletea is built for this; single static binary |
| Rust + ratatui | if performance/embedded terminal matters later |
| Python + prompt_toolkit | quickest prototype; prompt_toolkit's `PromptSession` handles raw-mode input editing |

### Feature List (native terminal)

- [ ] Async generation with animated spinner and Ctrl-C cancellation
- [ ] In-place command insertion + arrow-key editing
- [ ] Multi-candidate picker (3 commands, j/k select, Enter accept)
- [ ] Streaming response display
- [ ] Query history + generated-command history (`Ctrl-R`-style)
- [ ] Risky command confirmation (`rm -rf`, `sudo`, destructive git ops)
- [ ] Per-project context (cwd, git, project type) sent automatically
- [ ] Shell-agnostic: works over bash, zsh, fish, nushell

### Scope Guardrails

- Do **not** build a full terminal emulator (Warp did; it took years).
  A wrapper keeps the real shell's semantics (aliases, jobs, completion,
  job control all untouched) and only replaces the line editor + UI.
- MVP first: wrapper + own input line + async AI + insert. Everything
  else is polish.

## Quick Wins for the Current bash-ai (before the terminal)

Smaller, shippable improvements while the wrapper is being built:

- [x] **PTY integration tests** (wrapper track): `go test ./...` covers
      providers (httptest), context, screen model, and panel logic.
- [ ] **Streaming**: `curl -N` + progressively display the command as it
      streams instead of one blocking wait.
- [ ] **Candidate picker**: request 2–3 commands in one call, render a
      small menu, let the user pick with j/k before inserting.
- [ ] **Query + command history**: persist recent queries/commands under
      `~/.config/bash-ai/history`; reuse via `Ctrl-R`-style search.
- [ ] **Risky command guard**: flag commands matching `rm -rf|:(){|sudo
      |git push -f|dd if=` and require a second Enter.
- [ ] **Project-aware prompt**: `BASH_AI_PROMPT_EXTEND` per-directory via
      `.bash-ai-prompt` files (like `.editorconfig`).
- [ ] **Key management**: load the API key from the OS keyring
      (`secret-tool`/`pass`/`keychain`) instead of a world-readable-able
      config file.
- [ ] **Provider ergonomics**: per-query `--model` override, `bash-ai
      --list-models`, cheap retry on rate-limit errors.
- [x] **Wrapper MVP** (supersedes the quick-win PTY work): shell in a
      PTY + status bar + AI panel (async query, spinner, cancellation,
      bracketed-paste insert, busy/idle detection). See `ai-term/`.

## How to Start the Terminal Project

1. Prototype the wrapper in a scratch repo (e.g. `go mod init ai-term`).
2. Goal 1: spawn `bash` in a PTY, stream its output to a scrollback
   panel, own the input line. No AI yet.
3. Goal 2: `Ctrl-G` in *our* input line calls Groq asynchronously,
   spinner animates, command inserts in place.
4. Goal 3: candidate picker + history.
5. When stable, embed as the default launcher: `exec ai-term`, falling
   back to plain bash when not interactive.

Everything learned in this repo (prompt shape, Groq params, reasoning
effort workaround, context building) transfers directly — only the
readline layer gets thrown away.
