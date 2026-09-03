#!/usr/bin/env bash

# Google Gemini API provider for bash-ai

[[ -z "${_BASH_AI_PROVIDER_COMMON:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.bash"

# Function to call Gemini API
# mode: "command" (default) or "answer". In answer mode with the gemini
# search backend, Google Search grounding is enabled inline so the model
# answers from live web results.
_bash_ai_query_gemini() {
    local query="$1"
    local mode="${2:-command}"
    local search_backend="${3:-auto}"
    local response
    
    _bash_ai_provider_init "$query" "$mode"
    local max_output_tokens="$_bash_ai_provider_max_tokens"
    local escaped_query="$_bash_ai_provider_escaped_query"
    local escaped_system_prompt="$_bash_ai_provider_escaped_system_prompt"

    # Google Search grounding for answer mode (gemini backend)
    local grounding_tool=""
    if [[ "$mode" == "answer" ]] && [[ "$search_backend" == "gemini" ]]; then
        grounding_tool=$',\n    "tools": [\n        {\n            "googleSearch": {}\n        }\n    ]'
    fi
    
    # Prepare the JSON payload
    local json_payload=$(cat <<EOF
{
    "contents": [
        {
            "role": "user",
            "parts": [
                {
                    "text": "$escaped_query"
                }
            ]
        }
    ],
    "systemInstruction": {
        "parts": [
            {
                "text": "$escaped_system_prompt"
            }
        ]
    },
    "generationConfig": {
        "temperature": 0.3,
        "maxOutputTokens": $max_output_tokens,
        "thinkingConfig": {
            "thinkingBudget": 0
        }
    }${grounding_tool}
}
EOF
)
    
    # Call the API
    response=$(_bash_ai_curl "https://generativelanguage.googleapis.com/v1beta/models/${BASH_AI_GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to Gemini API"
        return 1
    fi
    
    # Debug: Uncomment to see raw response
    # echo "DEBUG: Raw response: $response" >&2
    
    # Extract the content from the response
    # Try using jq if available, otherwise fall back to sed/grep
    if command -v jq &> /dev/null; then
        local result=$(printf "%s" "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
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

        # Answer mode: append grounding sources when Google Search was used
        if [[ "$mode" == "answer" ]] && [[ "$search_backend" == "gemini" ]]; then
            local sources
            sources=$(printf "%s" "$response" | jq -r '.candidates[0].groundingMetadata.groundingChunks[]?.web.uri // empty' 2>/dev/null)
            if [[ -n "$sources" ]]; then
                sources=$(printf '%s' "$sources" | sed 's/^/ - /')
                result=$(printf '%s\n\nSources:\n%s' "$result" "$sources")
            fi
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