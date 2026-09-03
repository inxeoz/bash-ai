#!/usr/bin/env bash

# Configuration and validation for bash-ai

# --- Env precedence tracking (env > toml > defaults) ---
# Record which BASH_AI_* vars were explicitly set in env before defaults,
# so TOML only overrides defaults, never env.
_bash_ai_toml_vars=(
    BASH_AI_PROVIDER
    BASH_AI_OLLAMA_MODEL BASH_AI_OLLAMA_URL
    BASH_AI_GEMINI_MODEL
    BASH_AI_OPENAI_MODEL BASH_AI_OPENAI_URL BASH_AI_OPENAI_THINKING BASH_AI_OPENAI_REASONING_EFFORT BASH_AI_OPENAI_API_KEY
    BASH_AI_QWEN_MODEL BASH_AI_QWEN_URL
    BASH_AI_ANTHROPIC_MODEL BASH_AI_ANTHROPIC_URL
    BASH_AI_GROK_MODEL BASH_AI_GROK_URL
    BASH_AI_GROQ_MODEL BASH_AI_GROQ_URL BASH_AI_GROQ_REASONING_EFFORT BASH_AI_GROQ_API_KEY
    BASH_AI_MISTRAL_MODEL BASH_AI_MISTRAL_URL
    BASH_AI_PENDING_FILE
    BASH_AI_ANSWER_KEY BASH_AI_ANSWER_MAX_TOKENS
    BASH_AI_MARKDOWN_RENDERER BASH_AI_MARKDOWN_THEME
    BASH_AI_SEARCH_BACKEND BASH_AI_SEARCH_MAX_RESULTS
    BASH_AI_CONVERSATION_TURNS BASH_AI_CONVERSATION_FILE
    BASH_AI_PROMPT_EXTEND
    OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY QWEN_API_KEY XAI_API_KEY MISTRAL_API_KEY GROQ_API_KEY BASH_AI_GROQ_API_KEY
)
for _bash_ai_v in "${_bash_ai_toml_vars[@]}"; do
    unset "_bash_ai_env_set_${_bash_ai_v}" 2>/dev/null
done
for _bash_ai_v in "${_bash_ai_toml_vars[@]}"; do
    # Only treat non-empty value as env-set (empty string allows default/toml to fill)
    eval "[[ -n \"\${${_bash_ai_v}:-}\" ]]" && printf -v "_bash_ai_env_set_${_bash_ai_v}" '%s' '1'
done
unset _bash_ai_v

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

# Provider validation
_bash_ai_validate_config() {
    # Normalize openai-compatible alias to openai
    if [[ "$BASH_AI_PROVIDER" == "openai-compatible" || "$BASH_AI_PROVIDER" == "openai_compatible" || "$BASH_AI_PROVIDER" == "compatible" ]]; then
        BASH_AI_PROVIDER="openai"
    fi
    if [[ "$BASH_AI_PROVIDER" != "anthropic" ]] && [[ "$BASH_AI_PROVIDER" != "ollama" ]] && [[ "$BASH_AI_PROVIDER" != "gemini" ]] && [[ "$BASH_AI_PROVIDER" != "qwen" ]] && [[ "$BASH_AI_PROVIDER" != "openai" ]] && [[ "$BASH_AI_PROVIDER" != "grok" ]] && [[ "$BASH_AI_PROVIDER" != "groq" ]] && [[ "$BASH_AI_PROVIDER" != "mistral" ]] && [[ "$BASH_AI_PROVIDER" != "custom" ]]; then
        echo "bash-ai: Error: Invalid provider '$BASH_AI_PROVIDER'. Use 'anthropic', 'ollama', 'gemini', 'openai' (or 'openai-compatible'), 'grok', 'groq', 'mistral', or 'custom'."
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
    elif [[ "$BASH_AI_PROVIDER" == "groq" ]]; then
        if [[ -z "$GROQ_API_KEY" && -z "$BASH_AI_GROQ_API_KEY" ]]; then
            echo "bash-ai: Warning: GROQ_API_KEY not set. Plugin will not function."
            echo "bash-ai: Set GROQ_API_KEY or use BASH_AI_PROVIDER=ollama for local models."
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

# --- TOML config support (global + per-project, env wins) ---

# Try to set var to val, but respect env precedence (skip if env-set).
# TOML adapter — deep module hides parsing (see lib-bash/toml.bash)
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${_dir}/toml.bash" ]] && source "${_dir}/toml.bash"
unset _dir

# Hardened curl wrapper: timeout, retry, and no-buffer (streaming)
# Tests mock `curl` via function override, so this wrapper still routes
# through `curl` and remains mockable.
_bash_ai_curl() {
    curl -sN --connect-timeout 5 --max-time 60 --retry 2 --retry-delay 1 "$@"
}

# Load after defaults so TOML overrides defaults but never env (env flags above)
_bash_ai_load_toml
