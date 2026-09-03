#!/usr/bin/env bash
[[ -z "${_BASH_AI_PROVIDER_COMMON:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.bash"


# OpenAI API provider for bash-ai

_bash_ai_openai_supports_temperature() {
    local model="$1"

    # These OpenAI reasoning models reject non-default temperature values.
    [[ "$model" != gpt-5* && "$model" != o1* && "$model" != o3* && "$model" != o4* ]]
}


# Function to call OpenAI API
_bash_ai_query_openai() {
    local query="$1"
    local mode="${2:-command}"
    local response

    _bash_ai_provider_init "$query" "$mode"
    local escaped_query="$_bash_ai_provider_escaped_query"
    local escaped_system_prompt="$_bash_ai_provider_escaped_system_prompt"
    local max_tokens="$_bash_ai_provider_max_tokens"

    # Determine token parameter based on model (newer models use max_completion_tokens)
    local token_param="max_completion_tokens"
    if [[ "$BASH_AI_OPENAI_MODEL" == gpt-4* ]] || [[ "$BASH_AI_OPENAI_MODEL" == gpt-3.5* ]]; then
        token_param="max_tokens"
    fi

    local temperature_param=""
    if _bash_ai_openai_supports_temperature "$BASH_AI_OPENAI_MODEL"; then
        temperature_param=$',\n    "temperature": 0.3'
    fi

    local thinking_param=""
    case "$BASH_AI_OPENAI_THINKING" in
        "") ;; # Don't override upstream defaults when unset
        0) thinking_param=$',\n    "chat_template_kwargs": { "enable_thinking": false }' ;;
        1) thinking_param=$',\n    "chat_template_kwargs": { "enable_thinking": true }' ;;
    esac

    local reasoning_effort_param=""
    if [[ -n "$BASH_AI_OPENAI_REASONING_EFFORT" ]]; then
        reasoning_effort_param=$',\n    "reasoning_effort": "'"$(_bash_ai_escape_json "$BASH_AI_OPENAI_REASONING_EFFORT")"'"'
    fi

    local json_payload=$(cat <<EOF
{
    "model": "${BASH_AI_OPENAI_MODEL}",
    "messages": [
        {
            "role": "system",
            "content": "$escaped_system_prompt"
        },
        {
            "role": "user",
            "content": "$escaped_query"
        }
    ],
    "$token_param": $max_tokens${temperature_param}${thinking_param}${reasoning_effort_param}
}
EOF
)

    # Call the API - only add auth header if API key is set
    # BASH_AI_OPENAI_API_KEY takes precedence (useful for LiteLLM and other proxies)
    local auth_args=()
    local api_key="${BASH_AI_OPENAI_API_KEY:-$OPENAI_API_KEY}"
    [[ -n "$api_key" ]] && auth_args=(--header "Authorization: Bearer $api_key")

    response=$(_bash_ai_curl "${BASH_AI_OPENAI_URL}" \
        "${auth_args[@]}" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to OpenAI API"
        return 1
    fi

    # Debug: Uncomment to see raw response
    # echo "DEBUG: Raw response: $response" >&2

    # Extract the content from the response
    # Try using jq if available, otherwise fall back to sed/grep
    if command -v jq &> /dev/null; then
        local result=$(printf "%s" "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
        if [[ -z "$result" ]]; then
            # Check for error message
            local error=$(printf "%s" "$response" | jq -r '.error.message // empty' 2>/dev/null)
            if [[ -n "$error" ]]; then
                echo "API Error: $error"
            else
                echo "Error: Unable to parse response"
            fi
            return 1
        fi
        # Clean up the response - newlines are stripped only for single-line
        # commands; answer mode keeps them so code keeps its formatting
        if [[ "$mode" == "command" ]]; then
            result=$(printf "%s" "$result" | tr -d '\n' | sed 's/[[:space:]]*$//')
        else
            result=$(printf "%s" "$result" | sed 's/[[:space:]]*$//')
        fi
        printf "%s" "$result"
    else
        # Fallback parsing without jq - handle responses with newlines
        # Use sed to extract the content field, handling potential newlines
        local result=$(printf "%s" "$response" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | head -1)

        # If the simple extraction failed, try a more complex approach for multiline responses
        if [[ -z "$result" ]]; then
            # Extract content field even if it contains escaped newlines
            result=$(printf "%s" "$response" | perl -0777 -ne 'print $1 if /"content":"((?:[^"\\]|\\.)*)"/s' 2>/dev/null)
        fi

        if [[ -z "$result" ]]; then
            echo "Error: Unable to parse response (install jq for better reliability)"
            return 1
        fi

        # Unescape JSON string (handle \n, \t, etc.) and clean up
        result=$(printf "%s" "$result" | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\r/\r/g; s/\\"/"/g; s/\\\\/\\/g')
        # Remove trailing newlines and spaces
        result=$(printf "%s" "$result" | sed 's/[[:space:]]*$//')
        printf "%s" "$result"
    fi
}
