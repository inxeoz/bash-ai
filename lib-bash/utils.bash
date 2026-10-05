#!/usr/bin/env bash
# Orchestration module — deep module hiding search+conversation+provider ordering.
# Interface: _bash_ai_query(query, mode) → command string
#            bash-ai / bash-ai-answer / _bash_ai_version / _bash_ai_status

if ! declare -F _bash_ai_curl >/dev/null 2>&1; then
_bash_ai_curl() {
    curl -sN --connect-timeout 5 --max-time 60 --retry 2 --retry-delay 1 "$@"
}
fi

# Load deep modules when sourced standalone (tests do this). Plugin also sources them explicitly.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _f in prompt conversation markdown queue context search; do
    [[ -f "${_dir}/${_f}.bash" ]] && source "${_dir}/${_f}.bash"
done
[[ -f "${_dir}/providers/common.bash" ]] && source "${_dir}/providers/common.bash"
unset _dir _f

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
