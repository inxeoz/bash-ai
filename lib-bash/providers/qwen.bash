#!/usr/bin/env bash

# Qwen API provider for bash-ai

[[ -z "${_BASH_AI_PROVIDER_COMMON:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.bash"

# Function to call Qwen API
_bash_ai_query_qwen() {
    local query="$1"
    local mode="${2:-command}"
    local response
    
    _bash_ai_provider_init "$query" "$mode"
    local escaped_query="$_bash_ai_provider_escaped_query"
    local escaped_system_prompt="$_bash_ai_provider_escaped_system_prompt"
    local max_tokens="$_bash_ai_provider_max_tokens"

    local json_payload=$(cat <<EOF
{
    "model": "${BASH_AI_QWEN_MODEL}",
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
    response=$(_bash_ai_curl "${BASH_AI_QWEN_URL}" \
        --header "Authorization: Bearer $QWEN_API_KEY" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to QWEN API"
        return 1
    fi
    
    _bash_ai_provider_extract_openai "$response" "$mode"
}
