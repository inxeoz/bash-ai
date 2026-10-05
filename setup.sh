#!/usr/bin/env bash

# setup.sh - installs bash-ai:
#   1. clones the repo into ~/.config/bash-ai/repo
#   2. prints the block to paste into ~/.bashrc (never edits your rc file)
#
# Config is just env vars, so there is no config file to generate.
#
# Usage: ./setup.sh [options] [repo-url] [install-dir]
#   repo-url     git URL to clone (default: this repo's origin)
#   install-dir  install dir (default: ~/.config/bash-ai)
#
# Options:
#       --remove, --uninstall       print what to delete to uninstall
#   -h, --help                      show help

set -euo pipefail

DEFAULT_URL="$(git -C "$(dirname "$0")" remote get-url origin 2>/dev/null || true)"
DEFAULT_URL="${DEFAULT_URL:-git@github.com:inxeoz/bash-ai.git}"

# --- parse options -------------------------------------------------------
REMOVE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove|--uninstall)
            REMOVE=true; shift ;;
        -h|--help)
            cat <<'HELP_EOF'
Usage: ./setup.sh [options] [repo-url] [install-dir]

Options:
      --remove, --uninstall       print what to delete to uninstall
  -h, --help                      show help

Examples:
  ./setup.sh                      # install / update, print the ~/.bashrc block
  ./setup.sh --remove             # print the uninstall steps
  ./setup.sh <repo-url> <dir>     # install from a custom URL / location
HELP_EOF
            exit 0
            ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; echo "Try: ./setup.sh --help" >&2; exit 1 ;;
        *) break ;;
    esac
done

REPO_URL="${1:-$DEFAULT_URL}"
CONFIG_DIR="${2:-$HOME/.config/bash-ai}"
REPO_DIR="$CONFIG_DIR/repo"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# --- 0. Handle --remove --------------------------------------------------
if [[ "$REMOVE" == true ]]; then
    say "nothing to automate - delete these yourself:"
    echo "    1. the bash-ai block in $HOME/.bashrc (source line + alias)"
    echo "    2. rm -rf $CONFIG_DIR"
    echo "    (older installs also have $CONFIG_DIR/config.sh - delete it too)"
    exit 0
fi

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

# --- 2. Print the ~/.bashrc block ----------------------------------------
# Nothing is written to your rc or config: the plugin reads plain env vars,
# so the block below is the whole configuration.
printf 'Groq API key (gsk-...), or leave empty to set it later: '
read -r -s api_key || api_key=""
printf '\n'

if [[ -n "$api_key" ]]; then
    key_line="export GROQ_API_KEY=\"$api_key\""
else
    key_line='export GROQ_API_KEY="gsk-..."  # TODO: paste your key'
fi

cat <<EOF

# bash-ai - add this block to ~/.bashrc, then: source ~/.bashrc
#
# Two ways to generate a command:
#   1. Type a request and press Ctrl-G     (replaces the line, no prefix needed)
#   2. ,, query                            (alias -> bash-ai -> Ctrl-G to insert)
# Normal commands are never intercepted - bash keeps its native display.

export BASH_AI_PROVIDER="groq"
export BASH_AI_GROQ_REASONING_EFFORT="low"  # gpt-oss burns the token budget on hidden reasoning otherwise
$key_line

alias ,,='bash-ai '

# Optional extras
# export BASH_AI_PROMPT_EXTEND="Prefer rg over grep, fd over find, bat over cat."

source "$REPO_DIR/bash-ai.plugin.bash"

EOF

# --- 3. Verify setup ----------------------------------------------------
say "verifying setup..."

# dependencies
for cmd in curl bash perl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $cmd found"
    else
        echo "  ✗ $cmd missing"
    fi
done || true
if command -v jq >/dev/null 2>&1; then
    echo "  ✓ jq found (optional)"
else
    echo "  · jq not found (optional)"
fi || true

# plugin loads
if bash -c "source \"$REPO_DIR/bash-ai.plugin.bash\" && _bash_ai_validate_config" >/dev/null 2>&1; then
    echo "  ✓ plugin loads"
else
    echo "  ✗ plugin failed to load or config invalid" || true
fi || true

[[ -n "$api_key" ]] || echo "  ! no API key given - set GROQ_API_KEY in ~/.bashrc"

echo '  next: paste the block into ~/.bashrc, then: source ~/.bashrc'
echo '        bash-ai "list files by size"'
