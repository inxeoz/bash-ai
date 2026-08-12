#!/usr/bin/env bash

# Configuration and validation for bash-ai

# Set default values for configuration
: ${BASH_AI_PROVIDER:="anthropic"}  # Default to anthropic for backwards compatibility
: ${BASH_AI_OLLAMA_MODEL:="llama3.2"}  # Popular fast model
: ${BASH_AI_OLLAMA_URL:="http://localhost:11434"}  # Default Ollama URL
: ${BASH_AI_GEMINI_MODEL:="gemini-2.5-flash"}  # Fast Gemini 2.5 model
: ${BASH_AI_OPENAI_MODEL:="gpt-5.4-mini"}  # Default to GPT-5.4 mini (gpt-5-mini is deprecated)
: ${BASH_AI_OPENAI_URL:="https://api.openai.com/v1/chat/completions"}  # Default to OpenAI
: ${BASH_AI_OPENAI_THINKING:=""}  # Configure thinking for supported models: 0 or 1, default unset/empty
: ${BASH_AI_OPENAI_REASONING_EFFORT:=""}  # Configure reasoning effort for supported OpenAI-compatible models
: ${BASH_AI_QWEN_MODEL:="qwen-flash"}  # Default to qwen-flash (fast, low-cost Qwen3 tier)
: ${BASH_AI_QWEN_URL:="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"}  # Default to Qwen API
: ${BASH_AI_ANTHROPIC_MODEL:="claude-haiku-4-5"}  # Default Anthropic model
: ${BASH_AI_ANTHROPIC_URL:="https://api.anthropic.com/v1/messages"}  # Default Anthropic URL
: ${BASH_AI_GROK_MODEL:="grok-4.3"}  # Default Grok model (provider sends reasoning_effort=none for speed)
: ${BASH_AI_GROK_URL:="https://api.x.ai/v1/chat/completions"}  # Default Grok URL
: ${BASH_AI_MISTRAL_MODEL:="mistral-small-latest"}  # Default Mistral model
: ${BASH_AI_MISTRAL_URL:="https://api.mistral.ai/v1/chat/completions"}  # Default Mistral URL

# Inline trigger configuration
: ${BASH_AI_COMMENT_HOOK:="true"}  # Set to false/off/no/0 to disable the inline trigger widget entirely
: ${BASH_AI_TRIGGER:="# "}  # Prompt prefix that triggers AI (e.g. ",," instead of "# ")
: ${BASH_AI_PENDING_FILE:="/tmp/bash-ai-pending"}  # Scratch file used by `bash-ai "..."` to hand the command to the Enter hook

# Return 0 if the inline trigger widget should be enabled, 1 otherwise
_bash_ai_comment_hook_enabled() {
    case "${BASH_AI_COMMENT_HOOK,,}" in
        false|off|no|0|disabled) return 1 ;;
        *) return 0 ;;
    esac
}

# Optional: Extend the system prompt with custom instructions
# BASH_AI_PROMPT_EXTEND - Add custom instructions to the AI prompt without replacing the core prompt
# Example: export BASH_AI_PROMPT_EXTEND="Always prefer ripgrep (rg) over grep. Use modern CLI tools when available."

# Provider validation
_bash_ai_validate_config() {
    if [[ "$BASH_AI_PROVIDER" != "anthropic" ]] && [[ "$BASH_AI_PROVIDER" != "ollama" ]] && [[ "$BASH_AI_PROVIDER" != "gemini" ]] && [[ "$BASH_AI_PROVIDER" != "qwen" ]] && [[ "$BASH_AI_PROVIDER" != "openai" ]] && [[ "$BASH_AI_PROVIDER" != "grok" ]] && [[ "$BASH_AI_PROVIDER" != "mistral" ]] && [[ "$BASH_AI_PROVIDER" != "custom" ]]; then
        echo "bash-ai: Error: Invalid provider '$BASH_AI_PROVIDER'. Use 'anthropic', 'ollama', 'gemini', 'openai', 'qwen', 'grok', 'mistral', or 'custom'."
        return 1
    fi

    # Check requirements based on provider
    if [[ "$BASH_AI_PROVIDER" == "anthropic" ]]; then
        if [[ -z "$ANTHROPIC_API_KEY" ]]; then
            echo "bash-ai: Warning: ANTHROPIC_API_KEY not set. Plugin will not function."
            echo "bash-ai: Set ANTHROPIC_API_KEY or use BASH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$BASH_AI_PROVIDER" == "gemini" ]]; then
        if [[ -z "$GEMINI_API_KEY" ]]; then
            echo "bash-ai: Warning: GEMINI_API_KEY not set. Plugin will not function."
            echo "bash-ai: Set GEMINI_API_KEY or use BASH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$BASH_AI_PROVIDER" == "openai" ]]; then
        # Only require API key when using the default OpenAI URL
        # Custom URLs (local servers, proxies) may not need authentication
        if [[ -z "$OPENAI_API_KEY" && -z "$BASH_AI_OPENAI_API_KEY" && "$BASH_AI_OPENAI_URL" == "https://api.openai.com/v1/chat/completions" ]]; then
            echo "bash-ai: Warning: OPENAI_API_KEY not set. Plugin will not function."
            echo "bash-ai: Set OPENAI_API_KEY or use BASH_AI_PROVIDER=ollama for local models."
            return 1
        fi

        if [[ -n "$BASH_AI_OPENAI_THINKING" && "$BASH_AI_OPENAI_THINKING" != "0" && "$BASH_AI_OPENAI_THINKING" != "1" ]]; then
            echo "bash-ai: Error: BASH_AI_OPENAI_THINKING must be 0, 1, or unset."
            return 1
        fi

    elif [[ "$BASH_AI_PROVIDER" == "qwen" ]]; then
        if [[ -z "$QWEN_API_KEY" ]]; then
            echo "bash-ai: Warning: QWEN_API_KEY not set. Plugin will not function."
            echo "bash-ai: Set QWEN_API_KEY or use BASH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$BASH_AI_PROVIDER" == "grok" ]]; then
        if [[ -z "$XAI_API_KEY" ]]; then
            echo "bash-ai: Warning: XAI_API_KEY not set. Plugin will not function."
            echo "bash-ai: Set XAI_API_KEY or use BASH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$BASH_AI_PROVIDER" == "mistral" ]]; then
        if [[ -z "$MISTRAL_API_KEY" ]]; then
            echo "bash-ai: Warning: MISTRAL_API_KEY not set. Plugin will not function."
            echo "bash-ai: Set MISTRAL_API_KEY or use BASH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$BASH_AI_PROVIDER" == "custom" ]]; then
        if ! declare -F _bash_ai_query_custom >/dev/null 2>&1; then
            echo "bash-ai: Warning: _bash_ai_query_custom is not defined. Plugin will not function."
            echo "bash-ai: Define _bash_ai_query_custom to use a custom provider."
            return 1
        fi
    fi

    return 0
}
