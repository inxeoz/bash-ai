#!/usr/bin/env bash

# Readline binding for bash-ai
#
# Enter is NOT intercepted: normal commands keep 100% native readline
# display (intercepting Enter desyncs readline's cursor tracking and
# eats prompt renders). Instead, Ctrl-G ("generate") turns the current
# line into a query: type a request, press Ctrl-G, and the generated
# command replaces the line, ready to edit or run.
#
# `bash-ai "..."` stages its command in a pending file; pressing Ctrl-G
# on an empty line inserts it (bash has no print -z).

_bash_ai_trigger() {
    local line="${READLINE_LINE:-}"

    # A command staged by `bash-ai "..."`: insert it on an empty line
    if [[ -z "$line" ]] && [[ -s "$BASH_AI_PENDING_FILE" ]]; then
        READLINE_LINE="$(cat "$BASH_AI_PENDING_FILE")"
        READLINE_POINT="${#READLINE_LINE}"
        rm -f "$BASH_AI_PENDING_FILE"
        return 0
    fi

    if [[ -z "$line" ]]; then
        printf '\n\033[33mType a request and press Ctrl-G, or use: ,, query\033[0m\n'
        return 0
    fi

    # Echo the query line, then run the query synchronously (backgrounding
    # from an interactive bash prints a job spec: [1] pid), then replace
    # the line with the generated command
    printf '\n%s\n' "$line"
    printf '⠋ Querying…'
    local cmd
    cmd="$(_bash_ai_query "$line" 2>/dev/null)"
    local exit_code=$?
    printf '\r\033[K'

    if (( exit_code == 0 )) && [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
        READLINE_LINE="$cmd"
        READLINE_POINT="${#cmd}"
    else
        # Show error - keep it visible
        printf '\n\033[31m❌ Failed to generate command\033[0m\n'
        if [[ -n "$cmd" ]]; then
            printf '\033[31m%s\033[0m\n' "$cmd"
        fi
        printf '\n'
    fi
    return 0
}

# Bind the trigger key. Only meaningful in interactive shells with readline.
_bash_ai_init_widget() {
    if [[ $- != *i* ]]; then
        return 0
    fi

    bind -x '"\C-g": _bash_ai_trigger'

    # Also bind the vi-mode insert keymap for users with `set -o vi`
    if set -o | grep -qE '^vi[[:space:]]+on'; then
        bind -m vi-insert -x '"\C-g": _bash_ai_trigger'
    fi
}
