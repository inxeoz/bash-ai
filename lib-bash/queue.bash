#!/usr/bin/env bash
# Queue module — pending-file adapter. Hides atomic mktemp→mv handshake.
# Interface: _bash_ai_queue_push(cmd) — stage command
#            _bash_ai_queue_pop() → prints and clears, or empty
#            _bash_ai_queue_has() → 0 if pending exists

_bash_ai_queue_push() {
    local cmd="$1" tmp
    tmp=$(mktemp "${BASH_AI_PENDING_FILE}.tmp.XXXXXX")
    printf '%s\n' "$cmd" > "$tmp" && mv -f "$tmp" "$BASH_AI_PENDING_FILE"
}

_bash_ai_queue_pop() {
    [[ -s "$BASH_AI_PENDING_FILE" ]] || return 1
    cat "$BASH_AI_PENDING_FILE"
    rm -f "$BASH_AI_PENDING_FILE"
}

_bash_ai_queue_has() {
    [[ -s "${BASH_AI_PENDING_FILE:-/tmp/bash-ai-pending}" ]]
}
