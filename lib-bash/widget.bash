#!/usr/bin/env bash

# Readline binding for bash-ai
#
# Enter is NOT intercepted: normal commands keep 100% native readline
# display (intercepting Enter desyncs readline's cursor tracking and
# eats prompt renders). Instead, Ctrl-G ("generate") turns the current
# line into a query: type a request, press Ctrl-G, and the generated
# command replaces the line, ready to edit or run.
#
# Ctrl-F ("find") turns the line into an answer query: the full multi-line
# answer (web search + formatted code examples) is printed to the terminal
# and the prompt redraws below it. The command line itself is untouched.
# Note: Ctrl-F is readline's forward-char by default - if you want that
# binding back, set BASH_AI_ANSWER_KEY to another key (e.g. "\C-t").
#
# `bash-ai "..."` stages its command in a pending file; pressing Ctrl-G
# on an empty line inserts it (bash has no print -z).

_bash_ai_is_risky() {
    local cmd="$1"
    # rm -rf / , /* , ~ , ~/*
    if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+[^;|&]*-.*r.*f[^;|&]*[[:space:]]+/(\*)?([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+[^;|&]*-.*r.*f[^;|&]*[[:space:]]+~([/][*]?)?([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'mkfs\.'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'dd[[:space:]].*of=/dev/(sda|nvme|mmc)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Fq ':(){:|:&};:'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])shutdown([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])reboot([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])halt([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])poweroff([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'init[[:space:]]+(0|6)([[:space:]]|;|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push.*--force'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+reset[[:space:]]+--hard'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'chmod[[:space:]]+.*-R.*777.*[[:space:]]+/[[:space:]]*$' || printf '%s' "$cmd" | grep -Eq 'chmod[[:space:]]+.*777.*[[:space:]]+/[[:space:]]*($|;)' ; then return 0; fi
    # also catch chmod -R 777 /
    if printf '%s' "$cmd" | grep -Eq 'chmod.*-R.*777'; then
        if printf '%s' "$cmd" | grep -Eq '[[:space:]]/[[:space:]]*($|;|\||&)' ; then return 0; fi
    fi
    if printf '%s' "$cmd" | grep -Eq 'chown[[:space:]]+.*-R'; then return 0; fi
    return 1
}

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
        printf '\033[33mType a question and press Ctrl-F to search the web\033[0m\n'
        return 0
    fi

    # Echo the query line, save prompt to history with # prefix (so accidental re-run is a comment),
    # then run the query synchronously
    printf '\n%s\n' "$line"
    # Save prompt as # comment - bypass HISTIGNORE="#*" and ensure history is on
    {
        local _bash_ai_old_histignore="${HISTIGNORE-}"
        local _bash_ai_old_histcontrol="${HISTCONTROL-}"
        HISTIGNORE=""
        HISTCONTROL=""
        set -o history 2>/dev/null || true
        history -s "# $line" 2>/dev/null || true
        history -a 2>/dev/null || true
        HISTIGNORE="$_bash_ai_old_histignore"
        HISTCONTROL="$_bash_ai_old_histcontrol"
    }
    printf '⠋ Querying…'
    local cmd
    cmd="$(_bash_ai_query "$line" 2>/dev/null)"
    local exit_code=$?
    printf '\r\033[K'

    if (( exit_code == 0 )) && [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
        if _bash_ai_is_risky "$cmd"; then
            printf '\n\033[31m⚠️  Risky command detected: %s\033[0m\n' "$cmd"
            local ans
            read -rp "Continue? [y/N] " ans || ans=""
            if [[ "$ans" != [yY]* ]]; then
                READLINE_LINE="$line"
                READLINE_POINT="${#line}"
                return 0
            fi
        fi
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

# Ctrl-F ("find"): answer mode with web search. The multi-line answer is
# printed to the terminal; READLINE_LINE stays untouched so readline
# redraws the prompt below the answer.
_bash_ai_answer() {
    local line="${READLINE_LINE:-}"

    if [[ -z "$line" ]]; then
        printf '\n\033[33mType a question and press Ctrl-F to search the web\033[0m\n'
        return 0
    fi

    # Echo the query line, save prompt to history with # prefix, then run the answer query
    printf '\n%s\n' "$line"
    {
        local _bash_ai_old_histignore="${HISTIGNORE-}"
        local _bash_ai_old_histcontrol="${HISTCONTROL-}"
        HISTIGNORE=""
        HISTCONTROL=""
        set -o history 2>/dev/null || true
        history -s "# $line" 2>/dev/null || true
        history -a 2>/dev/null || true
        HISTIGNORE="$_bash_ai_old_histignore"
        HISTCONTROL="$_bash_ai_old_histcontrol"
    }
    printf '⠋ Searching…'
    local answer
    answer="$(_bash_ai_query "$line" "answer" 2>/dev/null)"
    local exit_code=$?
    printf '\r\033[K'

    if (( exit_code == 0 )) && [[ -n "$answer" ]] && [[ "$answer" != "Error:"* ]] && [[ "$answer" != "API Error:"* ]]; then
        # Remember the turn so follow-up questions keep context
        _bash_ai_conv_append "$line" "$answer"

        # Render markdown through glow/mdcat/bat when available, else raw.
        # Separators frame the answer: query | answer | next prompt.
        printf '\n'
        _bash_ai_print_separator
        _bash_ai_render_markdown "$answer"
        printf '\n'
        _bash_ai_print_separator
        printf '\n'

        # The question was answered on screen; don't leave it in the prompt
        READLINE_LINE=""
        READLINE_POINT=0
    else
        # Show error - keep it visible
        printf '\n\033[31m❌ Failed to get an answer\033[0m\n'
        if [[ -n "$answer" ]]; then
            printf '\033[31m%s\033[0m\n' "$answer"
        fi
        printf '\n'
    fi
    return 0
}

# Bind the trigger keys. Only meaningful in interactive shells with readline.
_bash_ai_init_widget() {
    if [[ $- != *i* ]]; then
        return 0
    fi

    bind -x '"\C-g": _bash_ai_trigger'
    bind -x "\"${BASH_AI_ANSWER_KEY:-\C-h}\": _bash_ai_answer"

    # Also bind the vi-mode insert keymap for users with `set -o vi`
    if set -o | grep -qE '^vi[[:space:]]+on'; then
        bind -m vi-insert -x '"\C-g": _bash_ai_trigger'
        bind -m vi-insert -x "\"${BASH_AI_ANSWER_KEY:-\C-h}\": _bash_ai_answer"
    fi

    # Conversation memory: after every command, clear the stored thread
    # unless the command was another search. Appended (never clobbering
    # the user's own PROMPT_COMMAND) and guarded against double-sourcing.
    if [[ "$PROMPT_COMMAND" != *"_bash_ai_conv_keep_or_clear"* ]]; then
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_bash_ai_conv_keep_or_clear"
    fi
}
