#!/usr/bin/env bash

# Grok (X.AI) API provider for bash-ai

[[ -z "${_BASH_AI_PROVIDER_COMMON:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.bash"

# Function to call Grok API
_bash_ai_query_grok() {
    local query="$1"
    local mode="${2:-command}"
    local response

    _bash_ai_provider_init "$query" "$mode"
    local escaped_query="$_bash_ai_provider_escaped_query"
    local escaped_system_prompt="$_bash_ai_provider_escaped_system_prompt"
    local max_tokens="$_bash_ai_provider_max_tokens"


    local json_payload=$(cat <<EOF
{
    "model": "${BASH_AI_GROK_MODEL}",
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
    "max_completion_tokens": $max_tokens,
    "temperature": 0.3,
    "reasoning_effort": "none"
}
EOF
)

    # Call the API
    response=$(_bash_ai_curl "${BASH_AI_GROK_URL}" \
        --header "Authorization: Bearer $XAI_API_KEY" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to Grok API"
        return 1
    fi

    _bash_ai_provider_extract_openai "$response" "$mode"
}
