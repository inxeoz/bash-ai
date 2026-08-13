#!/usr/bin/env bash

# Utility functions for bash-ai

# Function to get the standardized system prompt for all providers
# mode: "command" (Ctrl-G, single-line commands) or "answer" (Ctrl-H,
# explanations + properly formatted multi-line code examples)
_bash_ai_get_system_prompt() {
    local context="$1"
    local mode="${2:-command}"
    local base_prompt=""

    if [[ "$mode" == "answer" ]]; then
        base_prompt="You are a helpful terminal assistant. Answer the user's question with a clear explanation and, when relevant, properly formatted code examples.\n\nIMPORTANT RULES:\n1. Use fenced code blocks (like \`\`\`python ... \`\`\`) for code examples\n2. Preserve indentation and spacing exactly - proper formatting matters more than brevity\n3. Prefer working, idiomatic examples the user can paste and run\n4. If web search results are included in the user's message, use them as the primary source and cite their URLs\n5. Answer in plain text outside code blocks"
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

# Main query function that routes to the appropriate provider
# mode: "command" (default) or "answer"
_bash_ai_query() {
    local query="$1"
    local mode="${2:-command}"
    local backend=""

    # Answer mode: prepend web search results to the query. Skipped when
    # the backend is "gemini" (the Gemini provider grounds inline) or "off".
    if [[ "$mode" == "answer" ]]; then
        backend="$(_bash_ai_resolve_search_backend)"
        if [[ "$backend" != "gemini" ]]; then
            local search_ctx
            search_ctx="$(_bash_ai_web_search "$query")"
            if [[ -n "$search_ctx" ]]; then
                query=$(printf '%s\n\n%s' "$query" "$search_ctx")
            fi
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
    elif [[ "$BASH_AI_PROVIDER" == "mistral" ]]; then
        _bash_ai_query_mistral "$query" "$mode"
    elif [[ "$BASH_AI_PROVIDER" == "custom" ]]; then
        _bash_ai_query_custom "$query" "$mode"
    else
        _bash_ai_query_anthropic "$query" "$mode"
    fi
}

# Direct command: bash-ai "find large files modified this week"
# Bash cannot push text into the prompt from a plain function, so the
# generated command is staged in a pending file; pressing Ctrl-G on an
# empty line inserts it (handled by the Ctrl-G hook in widget.bash).
bash-ai() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: bash-ai \"your natural language command\""
        echo "Example: bash-ai \"find all python files modified today\""
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
        elif [[ "$BASH_AI_PROVIDER" == "mistral" ]]; then
            echo "Mistral model: $BASH_AI_MISTRAL_MODEL"
        fi
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
        # Stage the command; the Ctrl-G hook inserts it on an empty line.
        # The status line is green; the model's command stays uncolored.
        printf '%s\n' "$cmd" > "$BASH_AI_PENDING_FILE"
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
        return 1
    fi

    local query="$*"

    printf '\r⠋ Searching…'
    local answer
    answer="$(_bash_ai_query "$query" "answer" 2>/dev/null)"
    local exit_code=$?
    printf '\r\033[K'

    if (( exit_code == 0 )) && [[ -n "$answer" ]] && [[ "$answer" != "Error:"* ]] && [[ "$answer" != "API Error:"* ]]; then
        printf '\n%s\n\n' "$answer"
    else
        printf '\033[31m❌ Failed to get an answer\033[0m\n'
        if [[ -n "$answer" ]]; then
            printf '\033[31m%s\033[0m\n' "$answer"
        fi
        echo ""
        return 1
    fi
}
