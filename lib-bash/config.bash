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
    BASH_AI_MISTRAL_MODEL BASH_AI_MISTRAL_URL
    BASH_AI_PENDING_FILE
    BASH_AI_ANSWER_KEY BASH_AI_ANSWER_MAX_TOKENS
    BASH_AI_MARKDOWN_RENDERER BASH_AI_MARKDOWN_THEME
    BASH_AI_SEARCH_BACKEND BASH_AI_SEARCH_MAX_RESULTS
    BASH_AI_CONVERSATION_TURNS BASH_AI_CONVERSATION_FILE
    BASH_AI_PROMPT_EXTEND
    OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY QWEN_API_KEY XAI_API_KEY MISTRAL_API_KEY
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

# --- TOML config support (global + per-project, env wins) ---

# Try to set var to val, but respect env precedence (skip if env-set).
_bash_ai_toml_try_set() {
    local _var="$1" _val="$2"
    local _flag="_bash_ai_env_set_${_var}"
    if [[ -n "${!_flag:-}" ]]; then
        return 0
    fi
    printf -v "$_var" '%s' "$_val"
    export "$_var"
}

# Minimal TOML parser: handles key = "value" | 'value' | value,
# sections [general] [provider] [openai] [anthropic] [gemini] [ollama] [mistral] [grok] [qwen] [search] [answer],
# comments (#, ;) and quoted/unquoted values.
_bash_ai_load_toml_file() {
    local _file="$1"
    [[ -f "$_file" ]] || return 0
    local _section="" _line _key _val
    while IFS= read -r _line || [[ -n "$_line" ]]; do
        # Trim leading/trailing whitespace
        _line="$(printf '%s' "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$_line" || "$_line" == \#* || "$_line" == \;* ]] && continue
        # Section header [name]
        if [[ "$_line" =~ ^\[(.*)\]$ ]]; then
            _section="${BASH_REMATCH[1]}"
            _section="$(printf '%s' "$_section" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
            continue
        fi
        # key = value
        if [[ "$_line" =~ ^([^=]+)=[[:space:]]*(.*)$ ]]; then
            _key="${BASH_REMATCH[1]}"
            _val="${BASH_REMATCH[2]}"
            _key="$(printf '%s' "$_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
            _val="$(printf '%s' "$_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            # Extract value: quoted value keeps inside; unquoted strips trailing comment
            if [[ "$_val" == \"* ]]; then
                _val="$(printf '%s' "$_val" | sed -E 's/^"([^"]*)".*$/\1/')"
            elif [[ "$_val" == \'* ]]; then
                _val="$(printf '%s' "$_val" | sed -E "s/^'([^']*)'.*$/\1/")"
            else
                _val="$(printf '%s' "$_val" | sed -E 's/[[:space:]]*[#;].*$//')"
                _val="$(printf '%s' "$_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                # Strip surrounding quotes if still present (mixed)
                if [[ ${#_val} -ge 2 && "$_val" == \"*\" ]]; then
                    _val="${_val:1:-1}"
                elif [[ ${#_val} -ge 2 && "$_val" == \'*\' ]]; then
                    _val="${_val:1:-1}"
                fi
            fi

            # Map section+key to BASH_AI_* var
            case "$_section" in
                general|provider|"")
                    case "$_key" in
                        provider) _bash_ai_toml_try_set BASH_AI_PROVIDER "$_val" ;;
                        prompt_extend|prompt-extend) _bash_ai_toml_try_set BASH_AI_PROMPT_EXTEND "$_val" ;;
                        pending_file|pending-file) _bash_ai_toml_try_set BASH_AI_PENDING_FILE "$_val" ;;
                        conversation_turns|conversation-turns) _bash_ai_toml_try_set BASH_AI_CONVERSATION_TURNS "$_val" ;;
                        conversation_file|conversation-file) _bash_ai_toml_try_set BASH_AI_CONVERSATION_FILE "$_val" ;;
                        markdown_renderer|markdown-renderer) _bash_ai_toml_try_set BASH_AI_MARKDOWN_RENDERER "$_val" ;;
                        markdown_theme|markdown-theme) _bash_ai_toml_try_set BASH_AI_MARKDOWN_THEME "$_val" ;;
                        search_backend|search-backend) _bash_ai_toml_try_set BASH_AI_SEARCH_BACKEND "$_val" ;;
                        search_max_results|search-max-results) _bash_ai_toml_try_set BASH_AI_SEARCH_MAX_RESULTS "$_val" ;;
                        answer_max_tokens|answer-max-tokens) _bash_ai_toml_try_set BASH_AI_ANSWER_MAX_TOKENS "$_val" ;;
                        answer_key|answer-key) _bash_ai_toml_try_set BASH_AI_ANSWER_KEY "$_val" ;;
                    esac
                    ;;
            esac
            case "$_section" in
                openai)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_OPENAI_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_OPENAI_URL "$_val" ;;
                        thinking) _bash_ai_toml_try_set BASH_AI_OPENAI_THINKING "$_val" ;;
                        reasoning_effort|reasoning-effort) _bash_ai_toml_try_set BASH_AI_OPENAI_REASONING_EFFORT "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set BASH_AI_OPENAI_API_KEY "$_val"; _bash_ai_toml_try_set OPENAI_API_KEY "$_val" ;;
                    esac
                    ;;
                anthropic)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_ANTHROPIC_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_ANTHROPIC_URL "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set ANTHROPIC_API_KEY "$_val" ;;
                    esac
                    ;;
                gemini)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_GEMINI_MODEL "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set GEMINI_API_KEY "$_val" ;;
                    esac
                    ;;
                ollama)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_OLLAMA_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_OLLAMA_URL "$_val" ;;
                    esac
                    ;;
                qwen)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_QWEN_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_QWEN_URL "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set QWEN_API_KEY "$_val" ;;
                    esac
                    ;;
                grok)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_GROK_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_GROK_URL "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set XAI_API_KEY "$_val" ;;
                    esac
                    ;;
                mistral)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_MISTRAL_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_MISTRAL_URL "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set MISTRAL_API_KEY "$_val" ;;
                    esac
                    ;;
                search)
                    case "$_key" in
                        backend) _bash_ai_toml_try_set BASH_AI_SEARCH_BACKEND "$_val" ;;
                        max_results|max-results) _bash_ai_toml_try_set BASH_AI_SEARCH_MAX_RESULTS "$_val" ;;
                    esac
                    ;;
                answer)
                    case "$_key" in
                        max_tokens|max-tokens) _bash_ai_toml_try_set BASH_AI_ANSWER_MAX_TOKENS "$_val" ;;
                        key) _bash_ai_toml_try_set BASH_AI_ANSWER_KEY "$_val" ;;
                        markdown_renderer|markdown-renderer) _bash_ai_toml_try_set BASH_AI_MARKDOWN_RENDERER "$_val" ;;
                        markdown_theme|markdown-theme) _bash_ai_toml_try_set BASH_AI_MARKDOWN_THEME "$_val" ;;
                    esac
                    ;;
                conversation)
                    case "$_key" in
                        turns) _bash_ai_toml_try_set BASH_AI_CONVERSATION_TURNS "$_val" ;;
                        file) _bash_ai_toml_try_set BASH_AI_CONVERSATION_FILE "$_val" ;;
                    esac
                    ;;
            esac
        fi
    done < "$_file"
}

# Load TOML configs in precedence: defaults < global < project < env
# Global: $HOME/.config/bash-ai/config.toml and ${XDG_CONFIG_HOME:-$HOME/.config}/bash-ai/config.toml
# Project: ./.bash-ai.toml , ./bash-ai.toml , ./.bash-ai/config.toml
_bash_ai_load_toml() {
    local _f
    for _f in "$HOME/.config/bash-ai/config.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/bash-ai/config.toml" "./.bash-ai.toml" "./bash-ai.toml" "./.bash-ai/config.toml"; do
        _bash_ai_load_toml_file "$_f"
    done
}

# Hardened curl wrapper: timeout, retry, and no-buffer (streaming)
# Tests mock `curl` via function override, so this wrapper still routes
# through `curl` and remains mockable.
_bash_ai_curl() {
    curl -sN --connect-timeout 5 --max-time 60 --retry 2 --retry-delay 1 "$@"
}

# Load after defaults so TOML overrides defaults but never env (env flags above)
_bash_ai_load_toml
