#!/usr/bin/env bash

# Qwen API provider for bash-ai

# Function to call Qwen API
_bash_ai_query_qwen() {
    local query="$1"
    local mode="${2:-command}"
    local response
    
    # Build context
    local context=$(_bash_ai_build_context)
    local escaped_context=$(_bash_ai_escape_json "$context")
    local system_prompt=$(_bash_ai_get_system_prompt "$escaped_context" "$mode")
    local escaped_system_prompt=$(_bash_ai_escape_json "$system_prompt")

    # Answer mode gets a bigger token budget for code examples
    local max_tokens=256
    [[ "$mode" == "answer" ]] && max_tokens="${BASH_AI_ANSWER_MAX_TOKENS:-4096}"
    
    # Prepare the JSON payload - escape quotes in the query
    local escaped_query=$(_bash_ai_escape_json "$query")

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
    response=$(curl -s "${BASH_AI_QWEN_URL}" \
        --header "Authorization: Bearer $QWEN_API_KEY" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to QWEN API"
        return 1
    fi
    
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
