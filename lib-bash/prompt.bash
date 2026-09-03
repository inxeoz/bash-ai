#!/usr/bin/env bash
# Prompt module — deep interface hides escaping + system prompt building.
# Interface: _bash_ai_escape_json(str) → escaped
#            _bash_ai_get_system_prompt(context, mode) → prompt
#            _bash_ai_print_separator()

_bash_ai_escape_json() {
    printf '%s' "$1" | perl -0777 -pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g; s/\f/\\f/g; s/\x08/\\b/g; s/[\x00-\x07\x0B\x0E-\x1F]//g'
}

_bash_ai_get_system_prompt() {
    local context="$1" mode="${2:-command}" base_prompt=""
    if [[ "$mode" == "answer" ]]; then
        base_prompt='You are a helpful terminal assistant. Answer the user'"'"'s question with a clear explanation and, when relevant, properly formatted code examples.

IMPORTANT RULES:
1. Use fenced code blocks (like ```python ... ```) for code examples
2. Preserve indentation and spacing exactly - proper formatting matters more than brevity
3. Prefer working, idiomatic examples the user can paste and run
4. If web search results are included in the user'"'"'s message, use them as the primary source and cite their URLs
5. If a previous conversation is included in the user'"'"'s message, it is context: interpret the current question as a follow-up to it
6. Answer in plain text outside code blocks'
    else
        base_prompt='You are a bash command generator. Generate syntactically correct bash commands based on the user'"'"'s natural language request.

IMPORTANT RULES:
1. Output ONLY the raw command - no explanations, no markdown, no backticks
2. For arguments containing spaces or special characters, use single quotes
3. Use double quotes only when variable expansion is needed
4. Properly escape special characters within quotes

Examples:
- echo '"'"'Hello World!'"'"' (spaces require quotes)
- echo "Current user: $USER" (variable expansion needs double quotes)
- grep '"'"'pattern with spaces'"'"' file.txt
- find . -name '"'"'*.txt'"'"' (glob patterns in quotes)'
    fi
    printf '%b' "$base_prompt"
    if [[ -n "$BASH_AI_PROMPT_EXTEND" ]]; then
        printf '\n\n%b' "$BASH_AI_PROMPT_EXTEND"
    fi
    printf '\n\nContext:\n%s' "$context"
}

_bash_ai_print_separator() {
    printf -- '-------------------------------\n'
}
