#!/usr/bin/env bash

# Readline widget and key binding for bash-ai
#
# bash has no zle, so Enter is intercepted with `bind -x` and the prompt
# line is read/replaced through READLINE_LINE / READLINE_POINT.
#
# IMPORTANT: both \C-j (line feed) and \C-m (carriage return) must be
# bound. Terminals and PTYs convert the Enter key's \r to \n before
# readline sees it (ICRNL), and which one arrives varies by setup.

# Execute a line like accept-line would. bash has no `.accept-line`
# delegate, so the line is stored in history and run through eval.
# The line is echoed first: readline erases lines consumed by a
# bind -x callback during the prompt redraw.
_bash_ai_execute_line() {
    local line="$1"
    if [[ -n "$line" ]]; then
        # Drop to a fresh line first and echo there. Writing the echo at
        # column 0 of the input line would overwrite the prompt glyphs.
        printf '\n%s\n' "$line"
        builtin history -s -- "$line"
        READLINE_LINE=""
        eval -- "$line"
    else
        READLINE_LINE=""
        return 0
    fi
}

# Custom binding to intercept Enter key
_bash_ai_accept_line() {
    local trigger="${BASH_AI_TRIGGER:-# }"
    local line="${READLINE_LINE:-}"

    # A command staged by `bash-ai "..."`: insert it on an empty Enter
    if [[ -z "$line" ]] && [[ -s "$BASH_AI_PENDING_FILE" ]]; then
        READLINE_LINE="$(cat "$BASH_AI_PENDING_FILE")"
        READLINE_POINT="${#READLINE_LINE}"
        rm -f "$BASH_AI_PENDING_FILE"
        return 0
    fi

    # Check if the line starts with the configured trigger
    if [[ "$line" == "$trigger"* ]]; then
        # Multiline buffers come from pasted blocks; treat them as normal
        # shell input so `# comment` lines inside the paste stay comments
        if [[ "$line" == *$'\n'* ]] || [[ "$line" == *$'\x1b'* ]]; then
            _bash_ai_execute_line "$line"
            return $?
        fi

        # Extract the query (remove the trigger prefix)
        local query="${line#"$trigger"}"

        # Echo the query line on a fresh line before touching the buffer.
        # readline does not echo lines consumed by a bind -x callback, and
        # writing at column 0 of the input line would overwrite the prompt.
        printf '\n%s\n' "$line"

        # Run the query synchronously. A background job from an interactive
        # bash prints a job spec ([1] pid) even with job control off, so the
        # progress indicator is static rather than animated.
        printf '⠋ Querying…'
        local cmd
        cmd="$(_bash_ai_query "$query" 2>/dev/null)"
        local exit_code=$?
        printf '\r\033[K'

        if (( exit_code == 0 )) && [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
            # Replace the line with the generated command; the next prompt
            # redraws with it, ready to edit or run
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
    fi

    # Normal command - execute as usual
    _bash_ai_execute_line "$line"
    return $?
}

# Bind the Enter key. Only meaningful in interactive shells with readline.
_bash_ai_init_widget() {
    # Respect the toggle: when disabled, never intercept accept-line so the
    # inline trigger (default "# ") behaves like a normal shell comment.
    _bash_ai_comment_hook_enabled || return

    if [[ $- != *i* ]]; then
        return 0
    fi

    bind -x '"\C-j": _bash_ai_accept_line'
    bind -x '"\C-m": _bash_ai_accept_line'

    # Also bind the vi-mode keymaps for users with `set -o vi`
    if set -o | grep -qE '^vi[[:space:]]+on'; then
        bind -m vi-insert -x '"\C-j": _bash_ai_accept_line'
        bind -m vi-insert -x '"\C-m": _bash_ai_accept_line'
        bind -m vi-command -x '"\C-j": _bash_ai_accept_line'
        bind -m vi-command -x '"\C-m": _bash_ai_accept_line'
    fi
}
