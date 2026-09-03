#!/usr/bin/env bash
# Widget — thin adapter for readline. Delegates to deep modules:
#   Risk (is_risky), History (save), Queue (pending), Orchestration (query)

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _f in risk history queue prompt conversation; do
    [[ -f "${_dir}/${_f}.bash" ]] && source "${_dir}/${_f}.bash"
done
[[ -f "${_dir}/context.bash" ]] && source "${_dir}/context.bash" 2>/dev/null || true
[[ -f "${_dir}/search.bash" ]] && source "${_dir}/search.bash" 2>/dev/null || true
[[ -f "${_dir}/utils.bash" ]] && source "${_dir}/utils.bash" 2>/dev/null || true
unset _dir _f

# Fallback if risk/history not loaded (standalone sourcing)
if ! declare -F _bash_ai_is_risky >/dev/null 2>&1; then
    _bash_ai_is_risky() { return 1; }
fi
if ! declare -F _bash_ai_history_save >/dev/null 2>&1; then
    _bash_ai_history_save() {
        local _line="$1"; local _old_histignore="${HISTIGNORE-}" _old_histcontrol="${HISTCONTROL-}"
        HISTIGNORE=""; HISTCONTROL=""; set -o history 2>/dev/null || true
        history -s "# $_line" 2>/dev/null || true; history -a 2>/dev/null || true
        HISTIGNORE="$_old_histignore"; HISTCONTROL="$_old_histcontrol"
    }
fi

_bash_ai_trigger() {
    local line="${READLINE_LINE:-}"
    if [[ -z "$line" ]] && _bash_ai_queue_has 2>/dev/null; then
        READLINE_LINE="$(_bash_ai_queue_pop 2>/dev/null)"
        READLINE_POINT="${#READLINE_LINE}"
        return 0
    fi
    if [[ -z "$line" ]]; then
        printf '\n\033[33mType a request and press Ctrl-G, or use: ,, query\033[0m\n'
        printf '\033[33mType a question and press Ctrl-F to search the web\033[0m\n'
        return 0
    fi
    printf '\n%s\n' "$line"
    _bash_ai_history_save "$line"
    printf '⠋ Querying…'
    local cmd; cmd="$(_bash_ai_query "$line" 2>/dev/null)"
    local exit_code=$?
    printf '\r\033[K'
    if (( exit_code == 0 )) && [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
        if _bash_ai_is_risky "$cmd"; then
            printf '\n\033[31m⚠️  Risky command detected: %s\033[0m\n' "$cmd"
            local ans; read -rp "Continue? [y/N] " ans || ans=""
            if [[ "$ans" != [yY]* ]]; then READLINE_LINE="$line"; READLINE_POINT="${#line}"; return 0; fi
        fi
        READLINE_LINE="$cmd"; READLINE_POINT="${#cmd}"
    else
        printf '\n\033[31m❌ Failed to generate command\033[0m\n'
        [[ -n "$cmd" ]] && printf '\033[31m%s\033[0m\n' "$cmd"
        printf '\n'
    fi
}

_bash_ai_answer() {
    local line="${READLINE_LINE:-}"
    if [[ -z "$line" ]]; then
        printf '\n\033[33mType a question and press Ctrl-F to search the web\033[0m\n'
        return 0
    fi
    printf '\n%s\n' "$line"
    _bash_ai_history_save "$line"
    printf '⠋ Searching…'
    local answer; answer="$(_bash_ai_query "$line" "answer" 2>/dev/null)"
    local exit_code=$?
    printf '\r\033[K'
    if (( exit_code == 0 )) && [[ -n "$answer" ]] && [[ "$answer" != "Error:"* ]] && [[ "$answer" != "API Error:"* ]]; then
        _bash_ai_conv_append "$line" "$answer"
        printf '\n'; _bash_ai_print_separator; _bash_ai_render_markdown "$answer"; printf '\n'; _bash_ai_print_separator; printf '\n'
        READLINE_LINE=""; READLINE_POINT=0
    else
        printf '\n\033[31m❌ Failed to get an answer\033[0m\n'
        [[ -n "$answer" ]] && printf '\033[31m%s\033[0m\n' "$answer"
        printf '\n'
    fi
}

_bash_ai_init_widget() {
    if [[ $- != *i* ]]; then return 0; fi
    bind -x '"\C-g": _bash_ai_trigger'
    bind -x "\"${BASH_AI_ANSWER_KEY:-\C-f}\": _bash_ai_answer"
    if set -o | grep -qE '^vi[[:space:]]+on'; then
        bind -m vi-insert -x '"\C-g": _bash_ai_trigger'
        bind -m vi-insert -x "\"${BASH_AI_ANSWER_KEY:-\C-f}\": _bash_ai_answer"
    fi
    if [[ "$PROMPT_COMMAND" != *"_bash_ai_conv_keep_or_clear"* ]]; then
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_bash_ai_conv_keep_or_clear"
    fi
}
