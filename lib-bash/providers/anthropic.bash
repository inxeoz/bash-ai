#!/usr/bin/env bash

# Anthropic Claude API provider for bash-ai

[[ -z "${_BASH_AI_PROVIDER_COMMON:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.bash"

# Function to call Anthropic API
_bash_ai_query_anthropic() {
    local query="$1"
    local mode="${2:-command}"
    local response
    
    _bash_ai_provider_init "$query" "$mode"
    local escaped_query="$_bash_ai_provider_escaped_query"
    local escaped_system_prompt="$_bash_ai_provider_escaped_system_prompt"
    local max_tokens="$_bash_ai_provider_max_tokens"
    local json_payload=$(cat <<EOF
{
    "model": "$BASH_AI_ANTHROPIC_MODEL",
    "max_tokens": $max_tokens,
    "system": "$escaped_system_prompt",
    "messages": [
        {
            "role": "user",
            "content": "$escaped_query"
        }
    ]
}
EOF
)
    
    # Call the API
    response=$(_bash_ai_curl "${BASH_AI_ANTHROPIC_URL}" \
        --header "x-api-key: $ANTHROPIC_API_KEY" \
        --header "anthropic-version: 2023-06-01" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to Anthropic API"
        return 1
    fi
    
    # Debug: Uncomment to see raw response
    # echo "DEBUG: Raw response: $response" >&2
    
    # Extract the content from the response
    # Try using jq if available, otherwise fall back to sed/grep
    if command -v jq &> /dev/null; then
        local result=$(printf "%s" "$response" | jq -r '.content[0].text // empty' 2>/dev/null)
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
        # Use sed to extract the text field, handling potential newlines
        local result=$(printf "%s" "$response" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | head -1)

        # If the simple extraction failed, try a more complex approach for multiline responses
        if [[ -z "$result" ]]; then
            # Extract text field even if it contains escaped newlines
            result=$(printf "%s" "$response" | perl -0777 -ne 'print $1 if /"text":"((?:[^"\\]|\\.)*)"/s' 2>/dev/null)
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