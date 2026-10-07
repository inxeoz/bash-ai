#!/usr/bin/env bash

# Configuration and validation for bash-ai
#
# Config lives in your shell: set BASH_AI_* (and provider key) env vars in
# ~/.bashrc before sourcing the plugin. `: ${VAR:=default}` below means env
# wins, defaults fill the gaps.

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
: ${BASH_AI_GROQ_MODEL:="openai/gpt-oss-20b"}  # Default Groq model (Groq-hosted, fast reasoning with low effort)
: ${BASH_AI_GROQ_URL:="https://api.groq.com/openai/v1/chat/completions"}  # Default Groq URL
: ${BASH_AI_GROQ_REASONING_EFFORT:=""}  # Groq reasoning effort: low | medium | high for gpt-oss models
: ${BASH_AI_GROQ_API_KEY:=""}  # Optional alt to GROQ_API_KEY
: ${BASH_AI_MISTRAL_MODEL:="mistral-small-latest"}  # Default Mistral model
: ${BASH_AI_MISTRAL_URL:="https://api.mistral.ai/v1/chat/completions"}  # Default Mistral URL

# Inline trigger configuration
# (The Enter hook was dropped in the bash port: intercepting Enter
# desyncs readline's display. Use Ctrl-G or the ,, alias instead.)
: ${BASH_AI_PENDING_FILE:="/tmp/bash-ai-pending"}  # Scratch file used by `bash-ai "..."` to hand the command to the Ctrl-G hook

# Answer mode configuration (Ctrl-F)
# Ctrl-G generates a single-line command; Ctrl-F answers questions with
# multi-line, properly formatted code examples, optionally backed by web search.
# Note: Ctrl-F is readline's forward-char by default - set BASH_AI_ANSWER_KEY
# to another key (e.g. "\C-t") if you want to keep it.
: ${BASH_AI_ANSWER_KEY:="\C-f"}  # Readline binding for the answer widget
: ${BASH_AI_ANSWER_MAX_TOKENS:=4096}  # Token budget for answer-mode responses (command mode stays at 256)

# Markdown rendering for answer mode (Ctrl-F)
# "auto" renders through the first of glow/mdcat/bat found in PATH and
# prints raw text when none is installed; "off" always prints raw.
: ${BASH_AI_MARKDOWN_RENDERER:="auto"}
# Color scheme used when the renderer is glow: "light" renders with
# `glow -s light`, "dark" with `glow -s dark`, "auto" (default) follows
# the system theme (Omarchy light.mode marker, then GTK color-scheme).
: ${BASH_AI_MARKDOWN_THEME:="auto"}

# Web search configuration (answer mode only)
# Backend: "auto" = Gemini grounding when BASH_AI_PROVIDER=gemini, else DuckDuckGo;
# "gemini" = Google Search grounding (Gemini provider only);
# "ddg" = DuckDuckGo HTML endpoint (any provider, no API key);
# "off" = no live search, answer from model knowledge only.
: ${BASH_AI_SEARCH_BACKEND:="auto"}
: ${BASH_AI_SEARCH_MAX_RESULTS:=5}  # Max web results fed to the model (DuckDuckGo backend)

# Answer-mode conversation memory: previous Q/A turns are fed back to the
# model so follow-up questions ("what about X?") keep context. 0 disables.
: ${BASH_AI_CONVERSATION_TURNS:=6}
: ${BASH_AI_CONVERSATION_FILE:="${XDG_CONFIG_HOME:-$HOME/.config}/bash-ai/conversation.log"}

# Provider metadata (labels, key rules, defaults) shared by validation, status and dispatch
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers/registry.bash"

# The custom provider has no provider file: its only contract is a
# user-defined _bash_ai_query_custom function.
_bash_ai_provider_custom_validate() {
    if ! declare -F _bash_ai_query_custom >/dev/null 2>&1; then
        echo "bash-ai: Warning: _bash_ai_query_custom is not defined. Plugin will not function."
        echo "bash-ai: Define _bash_ai_query_custom to use a custom provider."
        return 1
    fi
}

# Provider validation
# Generic key check driven by the registry, plus an optional per-provider
# _bash_ai_provider_<name>_validate hook for provider-specific rules.
_bash_ai_validate_config() {
    # Normalize openai-compatible alias to openai
    case "$BASH_AI_PROVIDER" in
        openai-compatible|openai_compatible|compatible) BASH_AI_PROVIDER="openai" ;;
    esac

    local provider="$BASH_AI_PROVIDER"
    if ! _bash_ai_provider_known "$provider"; then
        echo "bash-ai: Error: Invalid provider '$provider'. Use one of: ${_BASH_AI_PROVIDERS// /, }."
        return 1
    fi

    local key_envs key_mode key_env
    key_envs="$(_bash_ai_provider_field "$provider" key_envs)"
    key_mode="$(_bash_ai_provider_field "$provider" key_mode)"
    if [[ "$key_mode" == "required" ]]; then
        key_env="${key_envs%% *}"
        if ! _bash_ai_provider_key_value "$key_envs" >/dev/null; then
            echo "bash-ai: Warning: $key_env not set. Plugin will not function."
            echo "bash-ai: Set $key_env or use BASH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    fi

    local hook="_bash_ai_provider_${provider}_validate"
    if declare -F "$hook" >/dev/null 2>&1; then
        "$hook" || return 1
    fi

    return 0
}

# Hardened curl wrapper: timeout, retry, and no-buffer (streaming)
# Tests mock `curl` via function override, so this wrapper still routes
# through `curl` and remains mockable.
_bash_ai_curl() {
    curl -sN --connect-timeout 5 --max-time 60 --retry 2 --retry-delay 1 "$@"
}
