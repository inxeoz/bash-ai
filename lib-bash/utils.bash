#!/usr/bin/env bash

# Hardened curl wrapper fallback (config.bash also defines this; keep in
# sync). Tests that source only utils still get the wrapper.
if ! declare -F _bash_ai_curl >/dev/null 2>&1; then
_bash_ai_curl() {
    curl -sN --connect-timeout 5 --max-time 60 --retry 2 --retry-delay 1 "$@"
}
fi

# Utility functions for bash-ai

# Function to get the standardized system prompt for all providers
# mode: "command" (Ctrl-G, single-line commands) or "answer" (Ctrl-H,
# explanations + properly formatted multi-line code examples)
_bash_ai_get_system_prompt() {
    local context="$1"
    local mode="${2:-command}"
    local base_prompt=""

    if [[ "$mode" == "answer" ]]; then
        base_prompt="You are a helpful terminal assistant. Answer the user's question with a clear explanation and, when relevant, properly formatted code examples.\n\nIMPORTANT RULES:\n1. Use fenced code blocks (like \`\`\`python ... \`\`\`) for code examples\n2. Preserve indentation and spacing exactly - proper formatting matters more than brevity\n3. Prefer working, idiomatic examples the user can paste and run\n4. If web search results are included in the user's message, use them as the primary source and cite their URLs\n5. If a previous conversation is included in the user's message, it is context: interpret the current question as a follow-up to it\n6. Answer in plain text outside code blocks"
    else
        base_prompt="You are a bash command generator. Generate syntactically correct bash commands based on the user's natural language request.\n\nIMPORTANT RULES:\n1. Output ONLY the raw command - no explanations, no markdown, no backticks\n2. For arguments containing spaces or special characters, use single quotes\n3. Use double quotes only when variable expansion is needed\n4. Properly escape special characters within quotes\n\nExamples:\n- echo 'Hello World!' (spaces require quotes)\n- echo \"Current user: \$USER\" (variable expansion needs double quotes)\n- grep 'pattern with spaces' file.txt\n- find . -name '*.txt' (glob patterns in quotes)"
    fi

    # %b interprets the \n escapes in the prompt constants; %s keeps
    # user/context data literal (bash's echo does not interpret escapes)
    printf '%b' "$base_prompt"

    # Add custom prompt extension if provided
    if [[ -n "$BASH_AI_PROMPT_EXTEND" ]]; then
        printf '\n\n%b' "$BASH_AI_PROMPT_EXTEND"
    fi

    printf '\n\nContext:\n%s' "$context"
}

# Function to properly escape strings for JSON
_bash_ai_escape_json() {
    # Use printf and perl for reliable JSON escaping
    printf '%s' "$1" | perl -0777 -pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g; s/\f/\\f/g; s/\x08/\\b/g; s/[\x00-\x07\x0B\x0E-\x1F]//g'
}

# Resolve the glow color scheme. BASH_AI_MARKDOWN_THEME:
# "light"/"dark" = fixed scheme; anything else ("auto" default) = follow
# the system theme: the active Omarchy theme's light.mode marker, then
# the GTK color-scheme (gsettings); falls back to dark when undetectable.
_bash_ai_resolve_markdown_theme() {
    local theme="${BASH_AI_MARKDOWN_THEME:-auto}"
    if [[ "$theme" == "light" || "$theme" == "dark" ]]; then
        printf '%s' "$theme"
        return 0
    fi

    # Omarchy marks light themes with a light.mode file in the active theme
    if [[ -f "$HOME/.config/omarchy/current/theme/light.mode" ]]; then
        printf 'light'
        return 0
    fi
    if [[ -d "$HOME/.config/omarchy/current/theme" ]]; then
        printf 'dark'
        return 0
    fi

    # GTK color-scheme fallback (GNOME/GTK desktops)
    if command -v gsettings &>/dev/null; then
        local scheme
        scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
        if [[ "$scheme" == *"prefer-light"* ]]; then
            printf 'light'
            return 0
        fi
    fi

    printf 'dark'
}

# Render markdown answers through a terminal renderer when one is
# available; print the raw text otherwise. BASH_AI_MARKDOWN_RENDERER:
# "auto" (default) = first of glow/mdcat/bat found in PATH, else raw;
# a command name = use that command (raw when not installed); "off" = raw.
_bash_ai_render_markdown() {
    local text="$1"
    local renderer="${BASH_AI_MARKDOWN_RENDERER:-auto}"
    local cmd=""

    if [[ "$renderer" == "auto" ]]; then
        local candidate
        for candidate in glow mdcat bat; do
            if command -v "$candidate" &>/dev/null; then
                cmd="$candidate"
                break
            fi
        done
    elif [[ "$renderer" != "off" ]] && [[ -n "$renderer" ]]; then
        command -v "$renderer" &>/dev/null && cmd="$renderer"
    fi

    if [[ -z "$cmd" ]]; then
        printf '%s' "$text"
        return 0
    fi

    case "$cmd" in
        glow)
            # BASH_AI_MARKDOWN_THEME: "light" -> glow -s light,
            # "dark" -> glow -s dark, "auto" -> follow the system theme.
            local theme
            theme="$(_bash_ai_resolve_markdown_theme)"
            printf '%s\n' "$text" | glow -s "$theme" -
            ;;
        mdcat)
            printf '%s\n' "$text" | mdcat
            ;;
        bat)
            printf '%s\n' "$text" | bat --language=markdown --style=plain
            ;;
        *)
            printf '%s\n' "$text" | "$cmd"
            ;;
    esac
}

# Print the separator line that frames an answer: between the search
# query and the result, and between the result and the next prompt.
# (printf -- is needed: a format starting with "-" would be parsed as an option)
_bash_ai_print_separator() {
    printf -- '-------------------------------\n'
}

# --- Answer-mode conversation memory -------------------------------------
# The last BASH_AI_CONVERSATION_TURNS Q/A pairs are stored in
# BASH_AI_CONVERSATION_FILE (one block per turn, separated by a marker
# line) and fed back to the model, so follow-up questions keep context.
_bash_ai_conv_file() {
    printf '%s' "${BASH_AI_CONVERSATION_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/bash-ai/conversation.log}"
}

# Append one Q/A turn and keep only the most recent BASH_AI_CONVERSATION_TURNS.
_bash_ai_conv_append() {
    local q="$1" a="$2"
    local n="${BASH_AI_CONVERSATION_TURNS:-6}"
    [[ "$n" == "0" ]] && return 0
    local file
    file="$(_bash_ai_conv_file)"
    mkdir -p "$(dirname "$file")" 2>/dev/null

    printf 'User: %s\nAssistant: %s\n\n==== bash-ai turn ====\n' "$q" "$a" >> "$file"

    # Trim the file to the newest n turns
    N="$n" perl -0777 -i -e '
        my $n = $ENV{N};
        my $s = <>;
        my @t = split /\n==== bash-ai turn ====\n/, $s;
        pop @t if @t && $t[-1] eq "";
        @t = @t[-$n..-1] if @t > $n;
        print join("\n==== bash-ai turn ====\n", @t), "\n==== bash-ai turn ====\n" if @t;
    ' "$file"
}

# Read the stored turns back as a prompt block ("" when empty/disabled).
_bash_ai_conv_context() {
    local n="${BASH_AI_CONVERSATION_TURNS:-6}"
    [[ "$n" == "0" ]] && return 0
    local file
    file="$(_bash_ai_conv_file)"
    [[ -s "$file" ]] || return 0

    N="$n" perl -0777 -e '
        my $n = $ENV{N};
        my $s = <STDIN>;
        my @t = split /\n==== bash-ai turn ====\n/, $s;
        pop @t if @t && $t[-1] eq "";
        @t = @t[-$n..-1] if @t > $n;
        print "Previous conversation:\n\n" if @t;
        for my $t (@t) { print "$t\n" }
    ' < "$file"
}

# PROMPT_COMMAND hook: the conversation only carries between consecutive
# searches. If the command that just completed was not an answer-mode
# search (bash-ai-answer), the stored conversation is cleared so the next
# search starts fresh. Consecutive Ctrl-F answers never run a command, so
# PROMPT_COMMAND does not fire between them and the thread survives.
_bash_ai_conv_keep_or_clear() {
    [[ "${BASH_AI_CONVERSATION_TURNS:-6}" != "0" ]] || return 0
    case "$(history 1 2>/dev/null)" in
        *bash-ai-answer*) return 0 ;;
    esac
    rm -f "$(_bash_ai_conv_file)"
}

# The last stored user question; used to give follow-up web searches
# thread context ("" when the conversation is empty).
_bash_ai_conv_last_question() {
    local file
    file="$(_bash_ai_conv_file)"
    [[ -s "$file" ]] || return 0
    tail -n 100 "$file" | grep '^User: ' | tail -1 | sed 's/^User: //'
}

# Clear the stored conversation (starts a fresh chat).
bash-ai-reset() {
    rm -f "$(_bash_ai_conv_file)"
    echo "bash-ai: conversation cleared"
}

# Main query function that routes to the appropriate provider
# mode: "command" (default) or "answer"
_bash_ai_query() {
    local query="$1"
    local mode="${2:-command}"
    local backend=""

    # Answer mode: feed back previous Q/A turns so follow-up questions
    # keep conversation context, and prepend web search results to the
    # query. When a conversation exists, the search query combines the
    # last question with the current one so results stay on-topic
    # ("what was the old cap" searches as "cap of india what was the old
    # cap"). The Gemini backend grounds inline (and "off" disables search).
    if [[ "$mode" == "answer" ]]; then
        backend="$(_bash_ai_resolve_search_backend)"
        if [[ "$backend" != "gemini" ]]; then
            local search_query="$query"
            local last_q
            last_q="$(_bash_ai_conv_last_question)"
            if [[ -n "$last_q" && "$last_q" != "$query" ]]; then
                search_query="$last_q $query"
            fi
            local search_ctx
            search_ctx="$(_bash_ai_web_search "$search_query")"
            if [[ -n "$search_ctx" ]]; then
                query=$(printf '%s\n\n%s' "$query" "$search_ctx")
            fi
        fi
        local conv_ctx
        conv_ctx="$(_bash_ai_conv_context)"
        if [[ -n "$conv_ctx" ]]; then
            query=$(printf '%s\n\n%s' "$conv_ctx" "$query")
        fi
    fi

    if [[ "$BASH_AI_PROVIDER" == "ollama" ]]; then
        # The check prints its own user-facing error when Ollama is unreachable
        _bash_ai_check_ollama || return 1
        _bash_ai_query_ollama "$query" "$mode"
    elif [[ "$BASH_AI_PROVIDER" == "gemini" ]]; then
        _bash_ai_query_gemini "$query" "$mode" "$backend"
    elif [[ "$BASH_AI_PROVIDER" == "openai" ]]; then
        _bash_ai_query_openai "$query" "$mode"
    elif [[ "$BASH_AI_PROVIDER" == "qwen" ]]; then
        _bash_ai_query_qwen "$query" "$mode"
    elif [[ "$BASH_AI_PROVIDER" == "grok" ]]; then
        _bash_ai_query_grok "$query" "$mode"
    elif [[ "$BASH_AI_PROVIDER" == "groq" ]]; then
        _bash_ai_query_groq "$query" "$mode"
    elif [[ "$BASH_AI_PROVIDER" == "mistral" ]]; then
        _bash_ai_query_mistral "$query" "$mode"
    elif [[ "$BASH_AI_PROVIDER" == "custom" ]]; then
        _bash_ai_query_custom "$query" "$mode"
    else
        _bash_ai_query_anthropic "$query" "$mode"
    fi
}

_bash_ai_version() {
    local v="0.5.0"
    if [[ -n "${_BASH_AI_PLUGIN_DIR:-}" && -f "${_BASH_AI_PLUGIN_DIR}/VERSION" ]]; then
        v="$(cat "${_BASH_AI_PLUGIN_DIR}/VERSION" 2>/dev/null | tr -d ' \r\n')"
        [[ -z "$v" ]] && v="0.5.0"
    elif [[ -f "VERSION" ]]; then
        v="$(cat VERSION 2>/dev/null | tr -d ' \r\n')"
        [[ -z "$v" ]] && v="0.5.0"
    elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/../VERSION" ]]; then
        v="$(cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null | tr -d ' \r\n')"
        [[ -z "$v" ]] && v="0.5.0"
    fi
    echo "bash-ai $v"
}

_bash_ai_usage() {
    echo "Usage: bash-ai \"your natural language command\""
    echo "Example: bash-ai \"find all python files modified today\""
    echo ""
    echo "Options:"
    echo "  --help     Show this help"
    echo "  --version  Show version"
    echo "  --status   Show configuration status"
    echo ""
    echo "Answers (web search + code examples): bash-ai-answer \"your question\""
    echo ""
    echo "Current provider: $BASH_AI_PROVIDER"
    if [[ "$BASH_AI_PROVIDER" == "ollama" ]]; then
        echo "Ollama model: $BASH_AI_OLLAMA_MODEL"
    elif [[ "$BASH_AI_PROVIDER" == "gemini" ]]; then
        echo "Gemini model: $BASH_AI_GEMINI_MODEL"
    elif [[ "$BASH_AI_PROVIDER" == "openai" ]]; then
        echo "OpenAI model: $BASH_AI_OPENAI_MODEL"
    elif [[ "$BASH_AI_PROVIDER" == "qwen" ]]; then
        echo "Qwen model: $BASH_AI_QWEN_MODEL"
    elif [[ "$BASH_AI_PROVIDER" == "grok" ]]; then
        echo "Grok model: $BASH_AI_GROK_MODEL"
    elif [[ "$BASH_AI_PROVIDER" == "groq" ]]; then
        echo "Groq model: $BASH_AI_GROQ_MODEL"
    elif [[ "$BASH_AI_PROVIDER" == "mistral" ]]; then
        echo "Mistral model: $BASH_AI_MISTRAL_MODEL"
    fi
}

_bash_ai_status() {
    echo "bash-ai status"
    echo "  provider: $BASH_AI_PROVIDER"
    case "$BASH_AI_PROVIDER" in
        ollama) echo "  model: $BASH_AI_OLLAMA_MODEL"; echo "  url: $BASH_AI_OLLAMA_URL" ;;
        gemini) echo "  model: $BASH_AI_GEMINI_MODEL"; echo "  url: https://generativelanguage.googleapis.com" ;;
        openai) echo "  model: $BASH_AI_OPENAI_MODEL"; echo "  url: $BASH_AI_OPENAI_URL" ;;
        qwen) echo "  model: $BASH_AI_QWEN_MODEL"; echo "  url: $BASH_AI_QWEN_URL" ;;
        grok) echo "  model: $BASH_AI_GROK_MODEL"; echo "  url: $BASH_AI_GROK_URL" ;;
        groq) echo "  model: $BASH_AI_GROQ_MODEL"; echo "  url: $BASH_AI_GROQ_URL" ;;
        mistral) echo "  model: $BASH_AI_MISTRAL_MODEL"; echo "  url: $BASH_AI_MISTRAL_URL" ;;
        *) echo "  model: $BASH_AI_ANTHROPIC_MODEL"; echo "  url: $BASH_AI_ANTHROPIC_URL" ;;
    esac
    local key_status="missing"
    case "$BASH_AI_PROVIDER" in
        anthropic) [[ -n "${ANTHROPIC_API_KEY:-}" ]] && key_status="***set" ;;
        gemini) [[ -n "${GEMINI_API_KEY:-}" ]] && key_status="***set" ;;
        openai) [[ -n "${OPENAI_API_KEY:-}" || -n "${BASH_AI_OPENAI_API_KEY:-}" ]] && key_status="***set" ;;
        qwen) [[ -n "${QWEN_API_KEY:-}" ]] && key_status="***set" ;;
        grok) [[ -n "${XAI_API_KEY:-}" ]] && key_status="***set" ;;
        groq) [[ -n "${GROQ_API_KEY:-}" || -n "${BASH_AI_GROQ_API_KEY:-}" ]] && key_status="***set" ;;
        mistral) [[ -n "${MISTRAL_API_KEY:-}" ]] && key_status="***set" ;;
        ollama) key_status="n/a (local)" ;;
        custom) key_status="n/a (custom)" ;;
    esac
    echo "  api_key: $key_status"
    local t
    for t in curl perl jq; do
        if command -v "$t" >/dev/null 2>&1; then
            echo "  $t: found ($(command -v "$t"))"
        else
            echo "  $t: missing"
        fi
    done
    if [[ -s "${BASH_AI_PENDING_FILE:-/tmp/bash-ai-pending}" ]]; then
        echo "  pending: exists (${BASH_AI_PENDING_FILE})"
    else
        echo "  pending: none (${BASH_AI_PENDING_FILE:-/tmp/bash-ai-pending})"
    fi
    local cf
    cf="$(_bash_ai_conv_file)"
    if [[ -s "$cf" ]]; then
        echo "  conversation: exists ($cf, $(wc -l < "$cf" 2>/dev/null | tr -d ' ') lines)"
    else
        echo "  conversation: none ($cf)"
    fi
    local global_toml="${XDG_CONFIG_HOME:-$HOME/.config}/bash-ai/config.toml"
    local proj_toml1="./config.toml"
    local proj_toml2="./bash-ai.toml"
    if [[ -f "$global_toml" ]]; then
        echo "  config.toml (global): exists ($global_toml)"
    else
        echo "  config.toml (global): missing ($global_toml)"
    fi
    if [[ -f "$proj_toml2" ]]; then
        echo "  config.toml (project): exists ($proj_toml2)"
    elif [[ -f "$proj_toml1" ]]; then
        echo "  config.toml (project): exists ($proj_toml1)"
    else
        echo "  config.toml (project): missing (./config.toml or ./bash-ai.toml)"
    fi
}

# Direct command: bash-ai "find large files modified this week"
# Bash cannot push text into the prompt from a plain function, so the
# generated command is staged in a pending file; pressing Ctrl-G on an
# empty line inserts it (handled by the Ctrl-G hook in widget.bash).
bash-ai() {
    case "${1:-}" in
        --version|-v) _bash_ai_version; return 0 ;;
        --status) _bash_ai_status; return 0 ;;
        --help|-h) _bash_ai_usage; return 0 ;;
    esac
    if [[ $# -eq 0 ]]; then
        _bash_ai_usage
        return 1
    fi

    local query="$*"

    # Run the query synchronously. A background job from an interactive
    # bash prints a job spec ([1] pid) even with job control off, so the
    # progress indicator is static rather than animated.
    printf '\r⠋ Querying…'
    local cmd
    cmd="$(_bash_ai_query "$query" 2>/dev/null)"
    local exit_code=$?
    printf '\r\033[K'

    if (( exit_code == 0 )) && [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
        # Stage the command atomically; the Ctrl-G hook inserts it on an empty line.
        # The status line is green; the model's command stays uncolored.
        local _bash_ai_tmp
        _bash_ai_tmp=$(mktemp "${BASH_AI_PENDING_FILE}.tmp.XXXXXX")
        printf '%s\n' "$cmd" > "$_bash_ai_tmp" && mv -f "$_bash_ai_tmp" "$BASH_AI_PENDING_FILE"
        printf '\033[32mCommand ready. Press Ctrl-G to insert:\033[0m\n'
        echo "$cmd"
    else
        echo ""
        printf '\033[31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
        printf '\033[31m❌ Failed to generate command\033[0m\n'
        if [[ -n "$cmd" ]]; then
            printf '\033[31m%s\033[0m\n' "$cmd"
        fi
        printf '\033[31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
        echo ""
        return 1
    fi
}

# Direct answer command: bash-ai-answer "show me a python csv example"
# Runs in answer mode (web search + multi-line formatted code) and prints
# the result directly - the terminal equivalent of the Ctrl-H widget.
bash-ai-answer() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: bash-ai-answer \"your question\""
        echo "Example: bash-ai-answer \"show me a python example of reading a csv\""
        echo ""
        echo "Searches the web (free) and answers with properly formatted code examples."
        echo "In the shell, press Ctrl-F on a typed question instead."
        echo ""
        echo "Follow-up questions keep the conversation; run bash-ai-reset to start fresh."
        return 1
    fi

    local query="$*"

    printf '\r⠋ Searching…'
    local answer
    answer="$(_bash_ai_query "$query" "answer" 2>/dev/null)"
    local exit_code=$?
    printf '\r\033[K'

    if (( exit_code == 0 )) && [[ -n "$answer" ]] && [[ "$answer" != "Error:"* ]] && [[ "$answer" != "API Error:"* ]]; then
        # Remember the turn so follow-up questions keep context
        _bash_ai_conv_append "$query" "$answer"

        # Render markdown through glow/mdcat/bat when available, else raw.
        # Separators frame the answer: query | answer | next prompt.
        printf '\n'
        _bash_ai_print_separator
        _bash_ai_render_markdown "$answer"
        printf '\n'
        _bash_ai_print_separator
        printf '\n'
    else
        printf '\033[31m❌ Failed to get an answer\033[0m\n'
        if [[ -n "$answer" ]]; then
            printf '\033[31m%s\033[0m\n' "$answer"
        fi
        echo ""
        return 1
    fi
}
