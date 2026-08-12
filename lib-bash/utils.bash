#!/usr/bin/env bash

# Utility functions for bash-ai

# Function to get the standardized system prompt for all providers
_bash_ai_get_system_prompt() {
    local context="$1"
    local base_prompt="You are a bash command generator. Generate syntactically correct bash commands based on the user's natural language request.\n\nIMPORTANT RULES:\n1. Output ONLY the raw command - no explanations, no markdown, no backticks\n2. For arguments containing spaces or special characters, use single quotes\n3. Use double quotes only when variable expansion is needed\n4. Properly escape special characters within quotes\n\nExamples:\n- echo 'Hello World!' (spaces require quotes)\n- echo \"Current user: \$USER\" (variable expansion needs double quotes)\n- grep 'pattern with spaces' file.txt\n- find . -name '*.txt' (glob patterns in quotes)"

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
_bash_ai_query() {
    local query="$1"

    if [[ "$BASH_AI_PROVIDER" == "ollama" ]]; then
        # The check prints its own user-facing error when Ollama is unreachable
        _bash_ai_check_ollama || return 1
        _bash_ai_query_ollama "$query"
    elif [[ "$BASH_AI_PROVIDER" == "gemini" ]]; then
        _bash_ai_query_gemini "$query"
    elif [[ "$BASH_AI_PROVIDER" == "openai" ]]; then
        _bash_ai_query_openai "$query"
    elif [[ "$BASH_AI_PROVIDER" == "qwen" ]]; then
        _bash_ai_query_qwen "$query"
    elif [[ "$BASH_AI_PROVIDER" == "grok" ]]; then
        _bash_ai_query_grok "$query"
    elif [[ "$BASH_AI_PROVIDER" == "mistral" ]]; then
        _bash_ai_query_mistral "$query"
    elif [[ "$BASH_AI_PROVIDER" == "custom" ]]; then
        _bash_ai_query_custom "$query"
    else
        _bash_ai_query_anthropic "$query"
    fi
}

# Direct command: bash-ai "find large files modified this week"
# Bash cannot push text into the prompt from a plain function, so the
# generated command is staged in a pending file; pressing Enter on an
# empty line inserts it (handled by the Enter hook in widget.bash).
bash-ai() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: bash-ai \"your natural language command\""
        echo "Example: bash-ai \"find all python files modified today\""
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
        # Stage the command; the Enter hook inserts it on an empty line
        printf '%s\n' "$cmd" > "$BASH_AI_PENDING_FILE"
        echo "Command ready. Press Enter to insert:"
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
