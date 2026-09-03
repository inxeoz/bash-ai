#!/usr/bin/env bash
[[ -z "${_BASH_AI_PROVIDER_COMMON:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.bash"


# Ollama API provider for bash-ai

# Function to check if Ollama is reachable, printing the user-facing error when it isn't
# -f makes HTTP errors fail the check, so a wrong URL (e.g. a /v1 suffix
# that 404s) is caught here instead of surfacing later as a parse error
_bash_ai_check_ollama() {
    if _bash_ai_curl -f "${BASH_AI_OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
        return 0
    fi
    echo "Error: Ollama is not reachable at $BASH_AI_OLLAMA_URL"
    echo "Start Ollama with: ollama serve"
    echo "If it's already running, BASH_AI_OLLAMA_URL must be the base URL (e.g. http://localhost:11434, no /v1)"
    return 1
}


# Function to call Ollama API
_bash_ai_query_ollama() {
    local query="$1"
    local mode="${2:-command}"
    local response
    
    _bash_ai_provider_init "$query" "$mode"
    local escaped_query="$_bash_ai_provider_escaped_query"
    local escaped_system_prompt="$_bash_ai_provider_escaped_system_prompt"
    local num_predict_param=""
    [[ "$mode" == "answer" ]] && num_predict_param=$',\n    "num_predict": '"$_bash_ai_provider_max_tokens"
    local json_payload=$(cat <<EOF
{
    "model": "$BASH_AI_OLLAMA_MODEL",
    "prompt": "$escaped_query",
    "system": "$escaped_system_prompt",
    "stream": false,
    "think": false,
    "options": {
        "temperature": 0.3
    }${num_predict_param}
}
EOF
)
    
    # Call the API
    response=$(_bash_ai_curl "${BASH_AI_OLLAMA_URL}/api/generate" \
        --header "content-type: application/json" \
        --data "$json_payload")
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to Ollama. Is it running?"
        return 1
    fi
    
    # Extract the response
    if command -v jq &> /dev/null; then
        local result=$(printf "%s" "$response" | jq -r '.response // empty' 2>/dev/null)
        if [[ -z "$result" ]]; then
            # Check for error message
            local error=$(printf "%s" "$response" | jq -r '.error // empty' 2>/dev/null)
            if [[ -n "$error" ]]; then
                echo "Ollama Error: $error"
            else
                echo "Error: Unable to parse Ollama response"
                [[ -n "$response" ]] && echo "Response: ${response:0:200}"
            fi
            return 1
        fi
        # Clean up the response - markdown fences and newlines are stripped
        # only for single-line commands; answer mode keeps them so code
        # keeps its formatting
        if [[ "$mode" == "command" ]]; then
            result=$(printf "%s" "$result" | sed 's/^```[a-z]*$//' | tr -d '\n' | sed 's/[[:space:]]*$//')
        else
            result=$(printf "%s" "$result" | sed 's/[[:space:]]*$//')
        fi
        printf "%s" "$result"
    else
        # Fallback parsing without jq - handle responses with newlines
        # Use sed to extract the response field, handling potential newlines
        local result=$(printf "%s" "$response" | sed -n 's/.*"response":"\([^"]*\)".*/\1/p' | head -1)

        # If the simple extraction failed, try a more complex approach for multiline responses
        if [[ -z "$result" ]]; then
            # Extract response field even if it contains escaped newlines
            result=$(printf "%s" "$response" | perl -0777 -ne 'print $1 if /"response":"((?:[^"\\]|\\.)*)"/s' 2>/dev/null)
        fi

        if [[ -z "$result" ]]; then
            echo "Error: Unable to parse response (install jq for better reliability)"
            [[ -n "$response" ]] && echo "Response: ${response:0:200}"
            return 1
        fi

        # Remove markdown code fences in command mode only
        if [[ "$mode" == "command" ]]; then
            result=$(printf "%s" "$result" | sed 's/^```[a-z]*$//')
        fi

        # Unescape JSON string (handle \n, \t, etc.) and clean up
        result=$(printf "%s" "$result" | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\r/\r/g; s/\\"/"/g; s/\\\\/\\/g')
        # Remove trailing newlines and spaces
        result=$(printf "%s" "$result" | sed 's/[[:space:]]*$//')
        printf "%s" "$result"
    fi
}
