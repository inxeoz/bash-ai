#!/usr/bin/env bash

# Groq API provider for bash-ai (OpenAI-compatible)
# Uses GROQ_API_KEY

[[ -z "${_BASH_AI_PROVIDER_COMMON:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.bash"

# Function to call Groq API
_bash_ai_query_groq() {
    local query="$1"
    local mode="${2:-command}"
    local response

    _bash_ai_provider_init "$query" "$mode"
    local escaped_query="$_bash_ai_provider_escaped_query"
    local escaped_system_prompt="$_bash_ai_provider_escaped_system_prompt"
    local max_tokens="$_bash_ai_provider_max_tokens"


    # Determine token parameter based on model
    local token_param="max_completion_tokens"
    if [[ "$BASH_AI_GROQ_MODEL" == gpt-4* ]] || [[ "$BASH_AI_GROQ_MODEL" == gpt-3.5* ]] || [[ "$BASH_AI_GROQ_MODEL" == llama* ]] || [[ "$BASH_AI_GROQ_MODEL" == mixtral* ]]; then
        token_param="max_tokens"
    fi

    local temperature_param=""
    # Groq reasoning models (gpt-oss) may not support temperature
    if [[ "$BASH_AI_GROQ_MODEL" != gpt-5* && "$BASH_AI_GROQ_MODEL" != o1* && "$BASH_AI_GROQ_MODEL" != o3* && "$BASH_AI_GROQ_MODEL" != o4* ]]; then
        temperature_param=$',\n    "temperature": 0.3'
    fi

    local reasoning_effort_param=""
    if [[ -n "${BASH_AI_GROQ_REASONING_EFFORT:-}" ]]; then
        reasoning_effort_param=$',\n    "reasoning_effort": "'"${BASH_AI_GROQ_REASONING_EFFORT}"'"'
    fi

    local json_payload=$(cat <<EOF
{
    "model": "${BASH_AI_GROQ_MODEL}",
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
    "$token_param": $max_tokens${temperature_param}${reasoning_effort_param}
}
EOF
)

    # Call the API
    local api_key="${GROQ_API_KEY:-${BASH_AI_GROQ_API_KEY:-}}"
    local auth_args=()
    [[ -n "$api_key" ]] && auth_args=(--header "Authorization: Bearer $api_key")

    response=$(_bash_ai_curl "${BASH_AI_GROQ_URL}" \
        "${auth_args[@]}" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to Groq API"
        return 1
    fi

    _bash_ai_provider_extract_openai "$response" "$mode"
}
