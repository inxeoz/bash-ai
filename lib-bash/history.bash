#!/usr/bin/env bash
# History module — hides HISTIGNORE/HISTCONTROL bypass.
# Interface: _bash_ai_history_save(prompt)

_bash_ai_history_save() {
    local _line="$1"
    local _old_histignore="${HISTIGNORE-}" _old_histcontrol="${HISTCONTROL-}"
    HISTIGNORE=""; HISTCONTROL=""
    set -o history 2>/dev/null || true
    history -s "# $_line" 2>/dev/null || true
    history -a 2>/dev/null || true
    HISTIGNORE="$_old_histignore"
    HISTCONTROL="$_old_histcontrol"
}
