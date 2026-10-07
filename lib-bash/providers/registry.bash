#!/usr/bin/env bash
# Provider registry — the single source of truth for provider metadata.
#
# To add a provider:
#   1. add its name to _BASH_AI_PROVIDERS below
#   2. add a line to _bash_ai_provider_spec()
#   3. create lib-bash/providers/<name>.bash defining _bash_ai_query_<name>()
#   4. add its BASH_AI_<NAME>_* defaults to lib-bash/config.bash
#
# A provider file may also define these optional hooks:
#   _bash_ai_provider_<name>_precheck   run before the query; nonzero aborts
#   _bash_ai_provider_<name>_validate   extra config validation
#
# spec fields (pipe separated):
#   label | model | url | key_envs (space separated) | key_mode
# key_mode: required | optional | none

[[ -n "${_BASH_AI_REGISTRY_LOADED:-}" ]] && return 0
_BASH_AI_REGISTRY_LOADED=1

_BASH_AI_PROVIDERS="anthropic ollama gemini openai qwen grok groq mistral custom"
_BASH_AI_OPENAI_DEFAULT_URL="https://api.openai.com/v1/chat/completions"

_bash_ai_provider_known() {
    [[ " ${_BASH_AI_PROVIDERS} " == *" $1 "* ]]
}

_bash_ai_provider_spec() {
    case "$1" in
        anthropic)
            printf 'Anthropic|%s|%s|ANTHROPIC_API_KEY|required' \
                "$BASH_AI_ANTHROPIC_MODEL" "$BASH_AI_ANTHROPIC_URL" ;;
        ollama)
            printf 'Ollama|%s|%s||none' \
                "$BASH_AI_OLLAMA_MODEL" "$BASH_AI_OLLAMA_URL" ;;
        gemini)
            printf 'Gemini|%s|%s|GEMINI_API_KEY|required' \
                "$BASH_AI_GEMINI_MODEL" "https://generativelanguage.googleapis.com" ;;
        openai)
            # A key is only required for the real OpenAI endpoint; local
            # servers and proxies on a custom URL may be keyless.
            local mode="required"
            [[ "$BASH_AI_OPENAI_URL" != "$_BASH_AI_OPENAI_DEFAULT_URL" ]] && mode="optional"
            printf 'OpenAI|%s|%s|OPENAI_API_KEY BASH_AI_OPENAI_API_KEY|%s' \
                "$BASH_AI_OPENAI_MODEL" "$BASH_AI_OPENAI_URL" "$mode" ;;
        qwen)
            printf 'Qwen|%s|%s|QWEN_API_KEY|required' \
                "$BASH_AI_QWEN_MODEL" "$BASH_AI_QWEN_URL" ;;
        grok)
            printf 'Grok|%s|%s|XAI_API_KEY|required' \
                "$BASH_AI_GROK_MODEL" "$BASH_AI_GROK_URL" ;;
        groq)
            printf 'Groq|%s|%s|GROQ_API_KEY BASH_AI_GROQ_API_KEY|required' \
                "$BASH_AI_GROQ_MODEL" "$BASH_AI_GROQ_URL" ;;
        mistral)
            printf 'Mistral|%s|%s|MISTRAL_API_KEY|required' \
                "$BASH_AI_MISTRAL_MODEL" "$BASH_AI_MISTRAL_URL" ;;
        custom)
            printf 'Custom|-|-|-|none' ;;
        *)
            return 1 ;;
    esac
}

# _bash_ai_provider_field <provider> <label|model|url|key_envs|key_mode>
_bash_ai_provider_field() {
    local spec label model url key_envs key_mode
    spec="$(_bash_ai_provider_spec "$1")" || return 1
    IFS='|' read -r label model url key_envs key_mode <<< "$spec"
    case "$2" in
        label) printf '%s' "$label" ;;
        model) printf '%s' "$model" ;;
        url) printf '%s' "$url" ;;
        key_envs) printf '%s' "$key_envs" ;;
        key_mode) printf '%s' "$key_mode" ;;
        *) return 1 ;;
    esac
}

# Value of the first set env var in a space-separated list; nonzero if none.
_bash_ai_provider_key_value() {
    local env envs
    read -ra envs <<< "$1"
    for env in "${envs[@]}"; do
        if [[ -n "${!env:-}" ]]; then
            printf '%s' "${!env}"
            return 0
        fi
    done
    return 1
}
