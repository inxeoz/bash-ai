# bash-ai

> Ask your shell for the command you meant to write.

<img src="https://img.shields.io/badge/runtime-bash-blue" alt="bash runtime"> <img src="https://img.shields.io/badge/jq-optional-lightgrey" alt="jq optional"> <img src="https://img.shields.io/github/license/inxeoz/bash-ai?color=lightgrey" alt="License">

The hard part of the terminal usually is not knowing what to do. It is remembering the exact flags, quoting, and pipeline shape.

`bash-ai` turns natural language into shell commands. Type a request and press Ctrl-G, and the generated command replaces your prompt line.

```bash
$ show top 5 largest files here     # type, then press Ctrl-G
$ find . -type f -printf '%s %p\n' | sort -nr | head -5
```

It does not run the command for you. You read it first, edit it if needed, then press Enter.

## Why This Is Different

Most command help breaks your flow: search result, forum thread, copied snippet, little edits, fingers crossed.

`bash-ai` stays on the command line. It sends useful context with your request, including project type, nearby files, git state, and OS. That means "run tests" can become the right command for the directory you are already in.

It is also small by design: bash plus `curl` and `perl`, no Node runtime, no Python runtime. `jq` is optional.

## Install

One-shot install:

```bash
./setup.sh                      # clones into ~/.config/bash-ai/repo,
                                # creates ~/.config/bash-ai/config.sh,
                                # wires source line into ~/.bashrc
```

Or manual — add to `~/.bashrc` above the source line:

```bash
export BASH_AI_PROVIDER="openai"
export BASH_AI_OPENAI_URL="https://api.groq.com/openai/v1/chat/completions"
export BASH_AI_OPENAI_MODEL="openai/gpt-oss-20b"
export BASH_AI_OPENAI_API_KEY="your-key-here"
export BASH_AI_OPENAI_REASONING_EFFORT="low"
source ~/path/to/bash-ai.plugin.bash
```

Keep API keys out of public dotfiles. Reload:

```bash
source ~/.bashrc
```

## Usage

### Ctrl-G (generate command)

Type a request on an empty prompt, press `Ctrl-G`. The current line is sent as a query and replaced with the generated command.

```bash
$ show what is using port 3000   # press Ctrl-G
$ lsof -i :3000
```

### Ctrl-F (answer mode)

`Ctrl-F` is for questions, not commands. Type a question and press `Ctrl-F`: the answer is printed to the terminal with properly formatted code examples.

```bash
$ show me a python example of reading a csv   # press Ctrl-F
```

### Direct commands

```bash
$ bash-ai "find large files modified this week"
$ bash-ai-answer "how to read a csv in python"
$ bash-ai-reset   # clear conversation memory
```

`bash-ai "query"` prints the command and stages it; pressing `Ctrl-G` on an empty line inserts it. `,, query` is a handy alias when you add `alias ,,='bash-ai '` in your config.

Answer mode searches the web for free:

- **Gemini provider**: real Google Search via the API's built-in `googleSearch` grounding.
- **Every other provider**: DuckDuckGo results (no API key) fed to the model; falls back to Bing on bot challenge.

## Configuration

Switch providers with `BASH_AI_PROVIDER`:

```bash
export BASH_AI_PROVIDER="openai"
export OPENAI_API_KEY="your-key-here"
```

Add command preferences without replacing the built-in quoting rules:

```bash
export BASH_AI_PROMPT_EXTEND="Prefer rg over grep, fd over find, and bat over cat."
```

Answer mode options:

```bash
export BASH_AI_SEARCH_BACKEND="auto"          # auto | gemini | ddg | off
export BASH_AI_SEARCH_MAX_RESULTS="5"
export BASH_AI_ANSWER_MAX_TOKENS="4096"
export BASH_AI_ANSWER_KEY="\C-t"              # rebind if you use Ctrl-F for forward-char
export BASH_AI_MARKDOWN_RENDERER="auto"       # auto | off | glow | mdcat | bat
export BASH_AI_MARKDOWN_THEME="auto"          # auto | light | dark
export BASH_AI_CONVERSATION_TURNS="6"         # 0 disables
```
