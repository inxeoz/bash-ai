#!/usr/bin/env bash
# TOML module — file adapter for Config. Hides parsing.
# Interface: _bash_ai_toml_try_set(var, val)  # respects env precedence
#            _bash_ai_load_toml_file(file)
#            _bash_ai_load_toml()

_bash_ai_toml_try_set() {
    local _var="$1" _val="$2"
    local _flag="_bash_ai_env_set_${_var}"
    if [[ -n "${!_flag:-}" ]]; then return 0; fi
    printf -v "$_var" '%s' "$_val"
    export "$_var"
}

_bash_ai_load_toml_file() {
    local _file="$1"
    [[ -f "$_file" ]] || return 0
    local _section="" _line _key _val
    while IFS= read -r _line || [[ -n "$_line" ]]; do
        _line="$(printf '%s' "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$_line" || "$_line" == \#* || "$_line" == \;* ]] && continue
        if [[ "$_line" =~ ^\[(.*)\]$ ]]; then
            _section="${BASH_REMATCH[1]}"
            _section="$(printf '%s' "$_section" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
            continue
        fi
        if [[ "$_line" =~ ^([^=]+)=[[:space:]]*(.*)$ ]]; then
            _key="${BASH_REMATCH[1]}"
            _val="${BASH_REMATCH[2]}"
            _key="$(printf '%s' "$_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
            _val="$(printf '%s' "$_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            if [[ "$_val" == \"* ]]; then
                _val="$(printf '%s' "$_val" | sed -E 's/^"([^"]*)".*$/\1/')"
            elif [[ "$_val" == \'* ]]; then
                _val="$(printf '%s' "$_val" | sed -E "s/^'([^']*)'.*$/\1/")"
            else
                _val="$(printf '%s' "$_val" | sed -E 's/[[:space:]]*[#;].*$//')"
                _val="$(printf '%s' "$_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                if [[ ${#_val} -ge 2 && "$_val" == \"*\" ]]; then _val="${_val:1:-1}"
                elif [[ ${#_val} -ge 2 && "$_val" == \'*\' ]]; then _val="${_val:1:-1}"; fi
            fi
            case "$_section" in
                general|provider|"")
                    case "$_key" in
                        provider)
                            if [[ "$_val" == "openai-compatible" || "$_val" == "openai_compatible" || "$_val" == "compatible" ]]; then _val="openai"; fi
                            _bash_ai_toml_try_set BASH_AI_PROVIDER "$_val" ;;
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
                openai|openai-compatible|openai_compatible|compatible)
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
                grok)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_GROK_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_GROK_URL "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set XAI_API_KEY "$_val" ;;
                    esac
                    ;;
                groq)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_GROQ_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_GROQ_URL "$_val" ;;
                        reasoning_effort|reasoning-effort) _bash_ai_toml_try_set BASH_AI_GROQ_REASONING_EFFORT "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set BASH_AI_GROQ_API_KEY "$_val"; _bash_ai_toml_try_set GROQ_API_KEY "$_val" ;;
                    esac
                    ;;
                mistral)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_MISTRAL_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_MISTRAL_URL "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set MISTRAL_API_KEY "$_val" ;;
                    esac
                    ;;
                qwen)
                    case "$_key" in
                        model) _bash_ai_toml_try_set BASH_AI_QWEN_MODEL "$_val" ;;
                        url) _bash_ai_toml_try_set BASH_AI_QWEN_URL "$_val" ;;
                        api_key|api-key) _bash_ai_toml_try_set QWEN_API_KEY "$_val" ;;
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

_bash_ai_load_toml() {
    local global_toml="${XDG_CONFIG_HOME:-$HOME/.config}/bash-ai/config.toml"
    local proj1="./.bash-ai.toml" proj2="./bash-ai.toml" proj3="./.bash-ai/config.toml"
    _bash_ai_load_toml_file "$global_toml"
    for _f in "$proj1" "$proj2" "$proj3"; do _bash_ai_load_toml_file "$_f"; done
}
