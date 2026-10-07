#!/usr/bin/env bash

# Mistral AI API provider for bash-ai

[[ -z "${_BASH_AI_PROVIDER_COMMON:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.bash"

# Function to call Mistral API
_bash_ai_query_mistral() {
    local query="$1"
    local mode="${2:-command}"
    local response
    
    _bash_ai_provider_init "$query" "$mode"
    local escaped_query="$_bash_ai_provider_escaped_query"
    local escaped_system_prompt="$_bash_ai_provider_escaped_system_prompt"
    local max_tokens="$_bash_ai_provider_max_tokens"

    local json_payload=$(cat <<EOF
{
    "model": "${BASH_AI_MISTRAL_MODEL}",
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
    "max_tokens": $max_tokens,
    "temperature": 0.3
}
EOF
)
    
    # Call the API
    response=$(_bash_ai_curl "${BASH_AI_MISTRAL_URL}" \
        --header "Authorization: Bearer $MISTRAL_API_KEY" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        printf "%s" "Error: Failed to connect to Mistral API"
        return 1
    fi
    
    # Debug: Uncomment to see raw response
    # printf "%s" "DEBUG: Raw response: $response" >&2
    
    _bash_ai_provider_extract_openai "$response" "$mode"
}
