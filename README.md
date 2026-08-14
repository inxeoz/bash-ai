# zsh-ai

> Ask your shell for the command you meant to write.

<img src="https://img.shields.io/github/v/release/matheusml/zsh-ai?label=version&color=yellow" alt="Version"> <img src="https://img.shields.io/badge/runtime-zsh-blue" alt="zsh runtime"> <img src="https://img.shields.io/badge/jq-optional-lightgrey" alt="jq optional"> <img src="https://img.shields.io/github/license/matheusml/zsh-ai?color=lightgrey" alt="License">

The hard part of the terminal usually is not knowing what to do. It is remembering the exact flags, quoting, and pipeline shape.

`zsh-ai` turns a zsh comment into a command. Type `#`, describe the job, press Enter, and the generated command appears in your prompt.

```bash
$ # find files larger than 100mb changed this week
$ find . -type f -size +100M -mtime -7
```

It does not run the command for you. You read it first, edit it if needed, then press Enter again.

## Why This Is Different

Most command help breaks your flow: search result, forum thread, copied snippet, little edits, fingers crossed.

`zsh-ai` stays on the command line. It sends useful context with your request, including project type, nearby files, git state, and OS. That means "run tests" can become the right command for the directory you are already in.

It is also small by design: zsh plus `curl` and `perl`, no Node runtime, no Python runtime. `jq` is optional.

## Install

```bash
brew install matheusml/zsh-ai/zsh-ai
```

Add this to `~/.zshrc`, with the API key above the `source` line:

```bash
export ANTHROPIC_API_KEY="your-key-here"
source $(brew --prefix)/share/zsh-ai/zsh-ai.plugin.zsh
```

Keep API keys out of public dotfiles.

Reload your shell:

```bash
source ~/.zshrc
```

Then try:

```bash
# summarize disk usage for this folder
```

Prefer a local model on your machine?

```bash
ollama pull llama3.2
export ZSH_AI_PROVIDER="ollama"
```

Put the Ollama provider line above the `zsh-ai` source line.

Full setup lives in [INSTALL.md](INSTALL.md).

## Usage

### Comment Syntax

Type `#`, describe the job, then press Enter.

The trigger is configurable, and the inline hook can be turned off entirely if you
only want the `zsh-ai "..."` command — see [Configuration](#configuration).

<img src="https://github.com/user-attachments/assets/eff46629-855c-41eb-9de3-a53040bd2654" alt="zsh-ai comment syntax demo" width="520">

```bash
$ # show what is using port 3000
$ lsof -i :3000

$ # show commits on this branch that are not on main
$ git log main..HEAD --oneline
```

### Direct Command

<img src="https://github.com/user-attachments/assets/e58f0b99-68bf-45a5-87b9-ba7f925ddc87" alt="zsh-ai direct command demo" width="520">

```bash
$ zsh-ai "find large files modified this week"
$ find . -type f -size +50M -mtime -7
```

The command is pushed into your prompt with `print -z`, ready to edit or run.

## Configuration

Switch providers with `ZSH_AI_PROVIDER`:

```bash
export ZSH_AI_PROVIDER="openai"
export OPENAI_API_KEY="your-key-here"
```

OpenAI-compatible endpoints can also pass provider-specific reasoning controls:

```bash
export ZSH_AI_OPENAI_REASONING_EFFORT="none"
```

Add command preferences without replacing the built-in quoting rules:

```bash
export ZSH_AI_PROMPT_EXTEND="Prefer rg over grep, fd over find, and bat over cat."
```

Change the inline trigger, or disable the comment hook altogether (handy when you
paste code blocks that start with `#` comments):

```bash
# Use ,, instead of "# " to start a query
export ZSH_AI_TRIGGER=",,"

# Disable the inline hook entirely; only `zsh-ai "..."` stays active
export ZSH_AI_COMMENT_HOOK="false"
```

## Docs

- [Installation](INSTALL.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md)

## bash-ai (bash port)

`bash-ai.plugin.bash` + `lib-bash/` are a port of this plugin for bash.
Source it from `~/.bashrc` instead of the zsh plugin. All config
variables are `BASH_AI_*` instead of `ZSH_AI_*`.

The port does **not** intercept Enter: normal commands keep 100% native
readline display (intercepting Enter in bash desyncs readline's cursor
tracking and eats prompt renders). Instead, `Ctrl-G` ("generate") turns
the current line into a query:

```bash
$ show top 5 largest files here     # type, then press Ctrl-G
$ find . -type f -printf '%s %p\n' | sort -nr | head -5   # command replaces the line
```

### Answer mode (Ctrl-F)

Ctrl-F ("find") is for questions, not commands. Type a question and press
Ctrl-F: the answer — with properly formatted, multi-line code examples —
is printed to the terminal, and the prompt redraws below it.

```bash
$ show me a python example of reading a csv   # type, then press Ctrl-F
```

Answer mode searches the web for free:

- **Gemini provider**: real Google Search via the API's built-in
  `googleSearch` grounding (free tier, no extra key).
- **Every other provider**: DuckDuckGo results (no API key) are fetched
  and fed to the model as context; if DuckDuckGo serves its bot
  challenge, results automatically fall back to Bing.

If search fails or is disabled, the model still answers from its own
knowledge. Configure it:

```bash
# auto (default) | gemini | ddg | off
export BASH_AI_SEARCH_BACKEND="auto"

# Max DuckDuckGo results fed to the model
export BASH_AI_SEARCH_MAX_RESULTS="5"

# Token budget for answer-mode responses
export BASH_AI_ANSWER_MAX_TOKENS="4096"

# Ctrl-F is readline's forward-char; move the answer key if you use it
export BASH_AI_ANSWER_KEY="\C-t"

# Render answers through a terminal markdown renderer when one is
# installed (glow/mdcat/bat), else print raw text
export BASH_AI_MARKDOWN_RENDERER="auto"   # auto | off | glow | mdcat | bat
# glow color scheme: "auto" follows the system theme, or force it
export BASH_AI_MARKDOWN_THEME="auto"      # auto | light | dark
```

`bash-ai-answer "question"` is the direct-command equivalent (prints the
answer, no pending file). Install a renderer for prettier output:

```bash
brew install glow        # or: sudo apt install glow
```

```bash
# bash-ai — any OpenAI-compatible endpoint works (Groq, LM Studio, ...)
export BASH_AI_PROVIDER="openai"
export BASH_AI_OPENAI_URL="https://api.groq.com/openai/v1/chat/completions"
export BASH_AI_OPENAI_MODEL="openai/gpt-oss-20b"
export BASH_AI_OPENAI_API_KEY="your-key-here"
# Groq's gpt-oss models burn the whole token budget on hidden reasoning
# and return empty content; low keeps reasoning short enough to answer
export BASH_AI_OPENAI_REASONING_EFFORT="low"
source ~/path/to/bash-ai.plugin.bash
```

`bash-ai "query"` prints the generated command and stages it; pressing
Ctrl-G on an empty line inserts it into the prompt (bash has no
`print -z`). A `,, query` alias is a handy shorthand.

## ai-term (PTY wrapper)

`ai-term/` is a Go program that wraps your real shell in a PTY and
renders it inside a TUI: the shell keeps its native readline line
(editing, history, completion all untouched), and ai-term adds a status
bar (provider/model, idle/busy) plus an AI panel.

```bash
cd ai-term && go build -o ai-term .
./ai-term                      # replaces your shell; exit with `exit`
```

- `Ctrl-G` opens the AI panel: type a request, Enter to generate
  (animated spinner, Esc/Ctrl-C to cancel), Enter again to insert the
  command into the shell line via bracketed paste — fully editable.
- Insert is refused while the shell is busy (idle detection via OSC
  133 prompt markers, injected for bash).
- Same `BASH_AI_*` env vars as the plugins; providers ported to
  `net/http` + JSON (no `jq` needed).
- Known limitation: shell output colors are stripped (the mini screen
  model keeps rows plain so cursor math stays exact); vim/htop-style
  full-screen apps degrade.

### tmux-ai (popup front end)

Prefer tmux? Use `ai-popup` instead of running ai-term as your shell —
tmux keeps its full terminal emulator (vim/htop fine) and the popup
panel reuses the same provider code:

```bash
cd ai-term && go build -o ai-popup ./cmd/ai-popup
```

Add to `~/.tmux.conf` (see `ai-term/tmux-ai.tmux`):

```tmux
bind-key -T prefix g display-popup -w 70% -h 30% -E \
  "/path/to/ai-popup -t '#{pane_id}'"
```

`prefix + g` opens the popup; the generated command is typed into the
pane that was current before the popup (`tmux send-keys -l`), so it
lands in the shell's own line. Outside tmux, ai-popup prints the
command instead. Same `BASH_AI_*` config, same providers.
