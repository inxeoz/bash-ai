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
[[ -f "${_dir}/providers/registry.bash" ]] && source "${_dir}/providers/registry.bash"
[[ -f "${_dir}/providers/common.bash" ]] && source "${_dir}/providers/common.bash"
unset _dir _f

# Main query function that routes to the appropriate provider
# mode: "command" (default) or "answer"
_bash_ai_query() {
    local query="$1"
    local mode="${2:-command}"
    local backend=""

    # Bad config is reported here, not at every shell startup
    if [[ -n "${_bash_ai_config_err:-}" ]]; then
        printf '%s\n' "$_bash_ai_config_err"
        return 1
    fi

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

    # Dispatch by naming convention: _bash_ai_query_<provider>. Providers
    # are self-contained; an optional _bash_ai_provider_<name>_precheck
    # hook (e.g. Ollama reachability) runs before the query.
    local provider="$BASH_AI_PROVIDER"
    local fn="_bash_ai_query_${provider}"
    if ! declare -F "$fn" >/dev/null 2>&1; then
        echo "bash-ai: Error: Provider '$provider' has no query implementation." >&2
        return 1
    fi
    local precheck="_bash_ai_provider_${provider}_precheck"
    if declare -F "$precheck" >/dev/null 2>&1; then
        "$precheck" || return 1
    fi
    "$fn" "$query" "$mode" "$backend"
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
    local label model
    label="$(_bash_ai_provider_field "$BASH_AI_PROVIDER" label 2>/dev/null)"
    model="$(_bash_ai_provider_field "$BASH_AI_PROVIDER" model 2>/dev/null)"
    if [[ -n "$model" && "$model" != "-" ]]; then
        echo "$label model: $model"
    fi
}

_bash_ai_status() {
    echo "bash-ai status"
    echo "  provider: $BASH_AI_PROVIDER"
    local model url key_envs key_mode
    model="$(_bash_ai_provider_field "$BASH_AI_PROVIDER" model 2>/dev/null)"
    url="$(_bash_ai_provider_field "$BASH_AI_PROVIDER" url 2>/dev/null)"
    key_envs="$(_bash_ai_provider_field "$BASH_AI_PROVIDER" key_envs 2>/dev/null)"
    key_mode="$(_bash_ai_provider_field "$BASH_AI_PROVIDER" key_mode 2>/dev/null)"
    [[ -n "$model" && "$model" != "-" ]] && echo "  model: $model"
    [[ -n "$url" && "$url" != "-" ]] && echo "  url: $url"
    local key_status="missing"
    if [[ "$key_mode" == "none" ]]; then
        if [[ "$BASH_AI_PROVIDER" == "ollama" ]]; then
            key_status="n/a (local)"
        else
            key_status="n/a (custom)"
        fi
    elif _bash_ai_provider_key_value "$key_envs" >/dev/null 2>&1; then
        key_status="***set"
    fi
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
