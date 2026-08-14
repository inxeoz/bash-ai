#!/usr/bin/env bash

# setup.sh - installs bash-ai:
#   1. clones the repo into ~/.config/bash-ai/repo
#   2. creates ~/.config/bash-ai/config.sh pointing at the clone
#   3. wires the source line into ~/.bashrc (idempotent)
#
# Usage: ./setup.sh [repo-url] [install-dir]
#   repo-url     git URL to clone (default: this repo's origin)
#   install-dir  install dir (default: ~/.config/bash-ai)

set -euo pipefail

DEFAULT_URL="$(git -C "$(dirname "$0")" remote get-url origin 2>/dev/null || true)"
DEFAULT_URL="${DEFAULT_URL:-git@github.com:inxeoz/bash-ai.git}"

REPO_URL="${1:-$DEFAULT_URL}"
CONFIG_DIR="${2:-$HOME/.config/bash-ai}"
REPO_DIR="$CONFIG_DIR/repo"
CONFIG_FILE="$CONFIG_DIR/config.sh"
BASHRC="$HOME/.bashrc"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

say "bash-ai setup"
echo "    repo:  $REPO_URL"
echo "    into:  $CONFIG_DIR"

# --- 1. Clone (or update) the repo -------------------------------------
if [[ -d "$REPO_DIR/.git" ]]; then
    say "repo already cloned at $REPO_DIR, updating..."
    git -C "$REPO_DIR" pull --ff-only 2>/dev/null || echo "    (update skipped: uncommitted changes or no network)"
else
    mkdir -p "$CONFIG_DIR"
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi

# --- 2. Create config.sh ------------------------------------------------
if [[ -f "$CONFIG_FILE" ]]; then
    say "config.sh already exists, updating its plugin source line"
    if grep -q 'bash-ai.plugin.bash' "$CONFIG_FILE"; then
        sed -i "s|source .*bash-ai\.plugin\.bash.*$|source \"$REPO_DIR/bash-ai.plugin.bash\"|" "$CONFIG_FILE"
    else
        printf '\n# bash-ai plugin (added by setup.sh)\nsource "%s"\n' "$REPO_DIR/bash-ai.plugin.bash" >> "$CONFIG_FILE"
    fi
    chmod 600 "$CONFIG_FILE"
else
    say "creating $CONFIG_FILE"
    printf 'Groq API key (gsk-...), or leave empty for a placeholder: '
    read -r -s api_key
    printf '\n'

    if [[ -n "$api_key" ]]; then
        key_line="export BASH_AI_OPENAI_API_KEY=\"$api_key\""
    else
        key_line='export BASH_AI_OPENAI_API_KEY="your-key-here"'
    fi

    cat > "$CONFIG_FILE" <<EOF
#!/usr/bin/env bash

# bash-ai - single-file config, aliases, and plugin load.
# Sourced from ~/.bashrc with: source $CONFIG_FILE
#
# Contains the API key, so keep this file private (chmod 600).

# --- Provider (Groq, OpenAI-compatible) -------------------------------
export BASH_AI_PROVIDER="openai"
export BASH_AI_OPENAI_URL="https://api.groq.com/openai/v1/chat/completions"
export BASH_AI_OPENAI_MODEL="openai/gpt-oss-20b"
export BASH_AI_OPENAI_REASONING_EFFORT="low"  # gpt-oss burns the token budget on hidden reasoning otherwise
$key_line

# --- Usage --------------------------------------------------------------
# Two ways to generate a command:
#   1. Type a request and press Ctrl-G     (replaces the line, no prefix needed)
#   2. ,, query                            (alias -> bash-ai -> Ctrl-G to insert)
# Normal commands are never intercepted - bash keeps its native display.
alias ,,='bash-ai '

# Optional extras
# export BASH_AI_PROMPT_EXTEND="Prefer rg over grep, fd over find, bat over cat."

# --- Load the plugin ---------------------------------------------------
source "$REPO_DIR/bash-ai.plugin.bash"
EOF
    chmod 600 "$CONFIG_FILE"
fi

# --- 3. Wire into ~/.bashrc ---------------------------------------------
MARKER="# bash-ai - config lives in $CONFIG_FILE"
if [[ -f "$BASHRC" ]] && grep -qF "$MARKER" "$BASHRC"; then
    say "~/.bashrc already wired, skipping"
else
    mkdir -p "$(dirname "$BASHRC")"
    printf '\n%s\nsource %s\n' "$MARKER" "$CONFIG_FILE" >> "$BASHRC"
    say "added to ~/.bashrc"
fi

say "done. Open a new terminal or run: source $BASHRC"
