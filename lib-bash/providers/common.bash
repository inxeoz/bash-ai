_BASH_AI_PROVIDER_COMMON=1
#!/usr/bin/env bash
# Provider deep module — shared helpers for all providers
# Interface: _bash_ai_provider_init(query, mode) sets globals for payload building
#            _bash_ai_provider_trim(result, mode) normalizes output per mode
# This concentrates context/prompt/max_tokens logic (was copied 8×).

_bash_ai_provider_init() {
    local query="$1" mode="${2:-command}"
    local context escaped_context system_prompt
    context=$(_bash_ai_build_context)
    escaped_context=$(_bash_ai_escape_json "$context")
    system_prompt=$(_bash_ai_get_system_prompt "$escaped_context" "$mode")
    _bash_ai_provider_escaped_system_prompt=$(_bash_ai_escape_json "$system_prompt")
    _bash_ai_provider_escaped_query=$(_bash_ai_escape_json "$query")
    local max=256
    [[ "$mode" == "answer" ]] && max="${BASH_AI_ANSWER_MAX_TOKENS:-4096}"
    _bash_ai_provider_max_tokens="$max"
}

_bash_ai_provider_trim() {
    local result="$1" mode="${2:-command}"
    if [[ "$mode" == "command" ]]; then
        printf '%s' "$result" | tr -d '\n' | sed 's/[[:space:]]*$//'
    else
        printf '%s' "$result" | sed 's/[[:space:]]*$//'
    fi
}

# Unified OpenAI-compatible response extraction (jq + fallback)
# Usage: _bash_ai_provider_extract_openai "$response" "$mode"
_bash_ai_provider_extract_openai() {
    local response="$1" mode="${2:-command}"
    local result error
    if command -v jq &>/dev/null; then
        result=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
        if [[ -z "$result" ]]; then
            error=$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null)
            if [[ -n "$error" ]]; then echo "API Error: $error"; else echo "Error: Unable to parse response"; fi
            return 1
        fi
    else
        result=$(printf '%s' "$response" | perl -0777 -ne 'print $1 if /"content"\s*:\s*"((?:[^"\\]|\\.)*)"/s' 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\r/\r/g; s/\\"/"/g; s/\\\\/\\/g')
        if [[ -z "$result" ]]; then
            error=$(printf '%s' "$response" | perl -0777 -ne 'print $1 if /"message"\s*:\s*"((?:[^"\\]|\\.)*)"/s' 2>/dev/null)
            if [[ -n "$error" ]]; then echo "API Error: $error"; else echo "Error: Unable to parse response (install jq for better reliability)"; fi
            return 1
        fi
    fi
    result=$(_bash_ai_provider_trim "$result" "$mode")
    printf '%s' "$result"
}
