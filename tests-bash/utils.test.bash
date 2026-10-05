#!/usr/bin/env bash

# Load test helper
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

# Load required modules
source "$PLUGIN_DIR/lib-bash/config.bash"
source "$PLUGIN_DIR/lib-bash/context.bash"
source "$PLUGIN_DIR/lib-bash/providers/anthropic.bash"
source "$PLUGIN_DIR/lib-bash/providers/ollama.bash"
source "$PLUGIN_DIR/lib-bash/utils.bash"
source "$PLUGIN_DIR/lib-bash/search.bash"

# Test functions

# _bash_ai_query routing tests
test_routes_to_anthropic_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock Anthropic query function
    _bash_ai_query_anthropic() {
        echo "anthropic:$1"
    }

    local output
    output=$(_bash_ai_query "test query")
    assert_equals "$output" "anthropic:test query"

    teardown_test_env
}

test_routes_to_custom_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="custom"

    # Mock custom provider
    _bash_ai_query_custom() {
        echo "custom:$1"
    }

    local output
    output=$(_bash_ai_query "test query")
    assert_equals "$output" "custom:test query"

    teardown_test_env
}

test_provider_non_zero_exit_code() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _bash_ai_query_anthropic() {
        echo "Not prefixed with 'Error:'"
        return 1
    }

    # Capture output with stderr
    local output
    output=$(bash-ai "test query" 2>&1)
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "Failed to generate command"
    assert_contains "$output" "Not prefixed with 'Error:'"

    teardown_test_env
}

test_routes_to_ollama_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="ollama"

    # Mock Ollama check and query functions
    _bash_ai_check_ollama() {
        return 0
    }

    _bash_ai_query_ollama() {
        echo "ollama:$1"
    }

    local output
    output=$(_bash_ai_query "test query")
    assert_equals "$output" "ollama:test query"

    teardown_test_env
}

test_checks_ollama_availability_before_querying() {
    setup_test_env
    export BASH_AI_PROVIDER="ollama"
    export BASH_AI_OLLAMA_URL="http://localhost:11434"

    # Mock Ollama check to fail (the real check prints the user-facing error itself)
    _bash_ai_check_ollama() {
        echo "Error: mock check failed"
        return 1
    }

    _bash_ai_query_ollama() {
        echo "should not run"
    }

    local output
    output=$(_bash_ai_query "test query")
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "Error: mock check failed"
    assert_not_contains "$output" "should not run"

    teardown_test_env
}

# bash-ai command tests
test_shows_usage_without_arguments() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"

    # Capture output through a subshell
    local output
    output=$(bash-ai)
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "Usage: bash-ai"
    assert_contains "$output" "Example:"
    assert_contains "$output" "Current provider: anthropic"

    teardown_test_env
}

test_shows_ollama_model_in_usage() {
    setup_test_env
    export BASH_AI_PROVIDER="ollama"
    export BASH_AI_OLLAMA_MODEL="llama3.2"

    # Capture output through a subshell
    local output
    output=$(bash-ai)
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "Current provider: ollama"
    assert_contains "$output" "Ollama model: llama3.2"

    teardown_test_env
}

test_stages_command_in_pending_file() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock query function
    _bash_ai_query() {
        echo "echo 'Hello World'"
    }

    bash-ai "say hello" >/dev/null 2>&1

    # Should write the command to the pending file, not execute it
    local pending
    pending=$(cat "$BASH_AI_PENDING_FILE")
    assert_equals "$pending" "echo 'Hello World'"

    teardown_test_env
}

test_handles_api_errors_in_bash_ai() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock query function to return error
    _bash_ai_query() {
        echo "Error: API connection failed"
    }

    # Capture output with stderr
    local output
    output=$(bash-ai "test query" 2>&1)
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "Failed to generate command"
    assert_contains "$output" "API connection failed"

    teardown_test_env
}

test_handles_empty_response_in_bash_ai() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock query function to return empty
    _bash_ai_query() {
        echo ""
    }

    # Capture output with stderr
    local output
    output=$(bash-ai "test query" 2>&1)
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "Failed to generate command"

    teardown_test_env
}

test_combines_multiple_arguments() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock query function
    _bash_ai_query() {
        echo "find . -name '*.py'"
    }

    bash-ai find all python files >/dev/null 2>&1

    local pending
    pending=$(cat "$BASH_AI_PENDING_FILE")
    assert_equals "$pending" "find . -name '*.py'"

    teardown_test_env
}

test_works_with_noclobber_set() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Simulate a user with noclobber set
    set -o noclobber

    # Mock query function
    _bash_ai_query() {
        echo "ls -la"
    }

    local output
    output=$(bash-ai "list files" 2>&1)
    local result=$?

    set +o noclobber

    assert_equals "$result" "0"
    assert_not_contains "$output" "Failed to generate command"

    teardown_test_env
}

test_get_system_prompt_includes_all_rules() {
    setup_test_env

    local prompt
    prompt=$(_bash_ai_get_system_prompt "test context")

    # Check that all key parts of the prompt are present
    assert_contains "$prompt" "bash command generator"
    assert_contains "$prompt" "IMPORTANT RULES"
    assert_contains "$prompt" "Output ONLY the raw command"
    assert_contains "$prompt" "no explanations, no markdown, no backticks"
    assert_contains "$prompt" "single quotes"
    assert_contains "$prompt" "double quotes"
    assert_contains "$prompt" "variable expansion"
    assert_contains "$prompt" "Examples:"
    assert_contains "$prompt" "echo 'Hello World!'"
    assert_contains "$prompt" "Context:"
    assert_contains "$prompt" "test context"

    teardown_test_env
}

test_get_system_prompt_with_complex_context() {
    setup_test_env

    local complex_context=$'Current dir: /home/user\nGit branch: main\nProject: Node.js'
    local prompt
    prompt=$(_bash_ai_get_system_prompt "$complex_context")

    # Check that context is included at the end
    assert_contains "$prompt" "Context:"
    assert_contains "$prompt" "$complex_context"

    teardown_test_env
}

test_get_system_prompt_with_empty_context() {
    setup_test_env

    local prompt
    prompt=$(_bash_ai_get_system_prompt "")

    # Should still include the Context: header even if empty
    assert_contains "$prompt" "Context:"

    teardown_test_env
}

test_get_system_prompt_with_extension() {
    setup_test_env

    # Set custom prompt extension
    export BASH_AI_PROMPT_EXTEND="Always prefer modern CLI tools. Use ripgrep instead of grep."

    local prompt
    prompt=$(_bash_ai_get_system_prompt "test context")

    # Check that core prompt is still present
    assert_contains "$prompt" "bash command generator"
    assert_contains "$prompt" "IMPORTANT RULES"

    # Check that extension is included
    assert_contains "$prompt" "Always prefer modern CLI tools"
    assert_contains "$prompt" "Use ripgrep instead of grep"

    # Check that context is still at the end
    assert_contains "$prompt" "Context:"
    assert_contains "$prompt" "test context"

    # Check proper ordering - extension should be between rules and context
    # (. doesn't match newlines, so flatten first; unquoted RHS for regex)
    local flat_prompt="${prompt//$'\n'/}"
    local order_pattern='IMPORTANT RULES.*Always prefer modern CLI tools.*Context:'
    if [[ "$flat_prompt" =~ $order_pattern ]]; then
        :
    else
        echo "Error: Prompt extension not in correct position"
        TEST_FAILED=1
        return 1
    fi

    teardown_test_env
}

test_get_system_prompt_without_extension() {
    setup_test_env

    # Ensure no extension is set
    unset BASH_AI_PROMPT_EXTEND

    local prompt
    prompt=$(_bash_ai_get_system_prompt "test context")

    # Should work exactly as before when no extension is set
    assert_contains "$prompt" "bash command generator"
    assert_contains "$prompt" "IMPORTANT RULES"
    assert_contains "$prompt" "Context:"
    assert_contains "$prompt" "test context"

    # Should not have extra newlines where extension would be
    local expected_pattern=$'glob patterns in quotes)\n\nContext:'
    assert_contains "$prompt" "$expected_pattern"

    teardown_test_env
}

test_get_system_prompt_with_multiline_extension() {
    setup_test_env

    # Set multi-line custom prompt extension
    export BASH_AI_PROMPT_EXTEND="Additional rules:\n1. Prefer fd over find\n2. Use bat instead of cat\n3. Always use exa for ls commands"

    local prompt
    prompt=$(_bash_ai_get_system_prompt "test context")

    # Check that all lines of extension are included
    assert_contains "$prompt" "Additional rules:"
    assert_contains "$prompt" "1. Prefer fd over find"
    assert_contains "$prompt" "2. Use bat instead of cat"
    assert_contains "$prompt" "3. Always use exa for ls commands"

    teardown_test_env
}

test_get_system_prompt_with_empty_extension() {
    setup_test_env

    # Set empty extension (should behave same as unset)
    export BASH_AI_PROMPT_EXTEND=""

    local prompt
    prompt=$(_bash_ai_get_system_prompt "test context")

    # Should work exactly as before when extension is empty
    assert_contains "$prompt" "bash command generator"
    assert_contains "$prompt" "IMPORTANT RULES"
    assert_contains "$prompt" "Context:"
    assert_contains "$prompt" "test context"

    teardown_test_env
}

# Answer mode tests

test_answer_system_prompt_requests_formatted_code() {
    setup_test_env

    local prompt
    prompt=$(_bash_ai_get_system_prompt "test context" "answer")

    assert_contains "$prompt" "helpful terminal assistant"
    assert_contains "$prompt" "fenced code blocks"
    assert_contains "$prompt" "Preserve indentation and spacing"
    assert_contains "$prompt" "web search results"
    assert_contains "$prompt" "Context:"
    assert_not_contains "$prompt" "bash command generator"

    teardown_test_env
}

test_answer_mode_passes_mode_to_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="openai"
    export OPENAI_API_KEY="test-key"
    export BASH_AI_SEARCH_BACKEND="off"

    # Restore the real functions (earlier tests may have overridden them)
    source "$PLUGIN_DIR/lib-bash/utils.bash"
    source "$PLUGIN_DIR/lib-bash/search.bash"

    _bash_ai_query_openai() {
        echo "openai:$1:$2"
    }

    local output
    output=$(_bash_ai_query "explain pipes" "answer")
    assert_equals "$output" "openai:explain pipes:answer"

    teardown_test_env
}

test_answer_mode_appends_search_results_to_query() {
    setup_test_env
    export BASH_AI_PROVIDER="openai"
    export OPENAI_API_KEY="test-key"
    export BASH_AI_SEARCH_BACKEND="ddg"

    # Restore the real functions (earlier tests may have overridden them)
    source "$PLUGIN_DIR/lib-bash/utils.bash"
    source "$PLUGIN_DIR/lib-bash/search.bash"

    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]]; then
            printf '%s' '<div class="result"><h2 class="result__title"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fx">Found Result</a></h2><a class="result__snippet" href="x">Relevant snippet.</a></div>'
        fi
    }

    _bash_ai_query_openai() {
        printf '%s' "$1"
    }

    local output
    output=$(_bash_ai_query "show me an example" "answer")
    assert_contains "$output" "show me an example"
    assert_contains "$output" "Web search results"
    assert_contains "$output" "Found Result"

    teardown_test_env
}

test_command_mode_does_not_search() {
    setup_test_env
    export BASH_AI_PROVIDER="openai"
    export OPENAI_API_KEY="test-key"
    export BASH_AI_SEARCH_BACKEND="ddg"

    # Restore the real functions (earlier tests may have overridden them)
    source "$PLUGIN_DIR/lib-bash/utils.bash"
    source "$PLUGIN_DIR/lib-bash/search.bash"

    local curl_called=0
    curl() {
        curl_called=1
    }

    _bash_ai_query_openai() {
        echo "mock-openai-result"
    }

    local output
    output=$(_bash_ai_query "list files")
    assert_equals "$output" "mock-openai-result"
    assert_equals "$curl_called" "0"

    teardown_test_env
}

test_bash_ai_answer_prints_multiline_response() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _bash_ai_query() {
        printf 'Here is an example:\n\n```python\nx = 1\nprint(x)\n```'
    }

    local output
    output=$(bash-ai-answer "python example")
    local result=$?

    assert_equals "$result" "0"
    assert_contains "$output" "Here is an example:"
    assert_contains "$output" "print(x)"
    assert_not_contains "$output" "Failed to get an answer"

    # The answer is framed by separators (query | answer | next prompt)
    local sep
    sep="-------------------------------"
    assert_equals "$(printf '%s\n' "$output" | grep -cx -- "$sep")" "2"

    teardown_test_env
}

test_bash_ai_answer_shows_usage_without_arguments() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"

    local output
    output=$(bash-ai-answer)
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "Usage: bash-ai-answer"

    teardown_test_env
}

test_bash_ai_answer_handles_api_errors() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _bash_ai_query() {
        printf "Error: API connection failed"
    }

    local output
    output=$(bash-ai-answer "test question" 2>&1)
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "Failed to get an answer"
    assert_contains "$output" "API connection failed"

    teardown_test_env
}

# Conversation memory tests

test_conversation_context_feeds_followup() {
    setup_test_env
    export BASH_AI_PROVIDER="openai"
    export OPENAI_API_KEY="test-key"
    export BASH_AI_SEARCH_BACKEND="off"

    # Restore the real functions (earlier tests may have overridden them)
    source "$PLUGIN_DIR/lib-bash/utils.bash"

    _bash_ai_conv_append "cap of india" "The capital of India is New Delhi."
    _bash_ai_conv_append "what was the old cap" "Calcutta (Kolkata) until 1911."

    _bash_ai_query_openai() {
        printf '%s' "$1"
    }

    local output
    output=$(_bash_ai_query "what was it before that" "answer")
    assert_contains "$output" "Previous conversation:"
    assert_contains "$output" "cap of india"
    assert_contains "$output" "Calcutta (Kolkata) until 1911."
    assert_contains "$output" "what was it before that"

    teardown_test_env
}

test_conversation_turn_cap() {
    setup_test_env
    export BASH_AI_CONVERSATION_TURNS=2
    source "$PLUGIN_DIR/lib-bash/utils.bash"

    _bash_ai_conv_append "q1" "a1"
    _bash_ai_conv_append "q2" "a2"
    _bash_ai_conv_append "q3" "a3"
    _bash_ai_conv_append "q4" "a4"

    local ctx
    ctx=$(_bash_ai_conv_context)
    assert_contains "$ctx" "q3"
    assert_contains "$ctx" "q4"
    assert_not_contains "$ctx" "q1"
    assert_not_contains "$ctx" "q2"

    teardown_test_env
}

test_conversation_last_question() {
    setup_test_env
    source "$PLUGIN_DIR/lib-bash/utils.bash"

    _bash_ai_conv_append "first question" "a1"
    _bash_ai_conv_append "second question" "a2"
    assert_equals "$(_bash_ai_conv_last_question)" "second question"

    teardown_test_env
}

test_conversation_gives_search_thread_context() {
    setup_test_env
    export BASH_AI_PROVIDER="openai"
    export OPENAI_API_KEY="test-key"
    export BASH_AI_SEARCH_BACKEND="ddg"
    source "$PLUGIN_DIR/lib-bash/utils.bash"

    _bash_ai_conv_append "cap of india" "The capital of India is New Delhi."

    # Capture the search query instead of hitting the network
    _bash_ai_web_search() {
        printf 'SEARCHED:[%s]' "$1"
    }

    _bash_ai_query_openai() {
        printf '%s' "$1"
    }

    local output
    output=$(_bash_ai_query "what was the old cap" "answer")
    assert_contains "$output" "SEARCHED:[cap of india what was the old cap]"
    assert_contains "$output" "Previous conversation:"
    assert_contains "$output" "what was the old cap"

    teardown_test_env
}

test_conversation_cleared_when_previous_command_not_search() {
    setup_test_env
    source "$PLUGIN_DIR/lib-bash/utils.bash"

    _bash_ai_conv_append "q1" "a1"
    # A plain command between searches must drop the thread
    history() { echo "  42  ls -la"; }
    _bash_ai_conv_keep_or_clear
    assert_equals "$(_bash_ai_conv_context)" ""

    teardown_test_env
}

test_conversation_kept_when_previous_command_was_search() {
    setup_test_env
    source "$PLUGIN_DIR/lib-bash/utils.bash"

    _bash_ai_conv_append "q1" "a1"
    # A consecutive search keeps the thread
    history() { echo "  42  bash-ai-answer \"cap of india\""; }
    _bash_ai_conv_keep_or_clear
    assert_contains "$(_bash_ai_conv_context)" "q1"

    teardown_test_env
}

test_conversation_reset_clears_memory() {
    setup_test_env
    source "$PLUGIN_DIR/lib-bash/utils.bash"

    _bash_ai_conv_append "q" "a"
    bash-ai-reset >/dev/null
    assert_equals "$(_bash_ai_conv_context)" ""

    teardown_test_env
}

test_bash_ai_answer_stores_conversation_turn() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _bash_ai_query() {
        printf 'The capital is New Delhi.'
    }

    bash-ai-answer "cap of india" >/dev/null
    assert_equals "$(grep -c 'User: cap of india' "$BASH_AI_CONVERSATION_FILE")" "1"
    assert_equals "$(grep -c 'Assistant: The capital is New Delhi.' "$BASH_AI_CONVERSATION_FILE")" "1"

    teardown_test_env
}

# Markdown rendering tests

test_render_off_passes_through_raw() {
    setup_test_env
    export BASH_AI_MARKDOWN_RENDERER="off"

    local input='## Header

**bold** and `code`'
    local output
    output=$(_bash_ai_render_markdown "$input")
    assert_equals "$output" "$input"

    teardown_test_env
}

test_render_explicit_renderer_pipes_through_it() {
    setup_test_env
    export BASH_AI_MARKDOWN_RENDERER="mdcat"

    mdcat() {
        printf 'RENDERED:[%s]' "$(cat)"
    }

    local output
    output=$(_bash_ai_render_markdown "# Hello")
    assert_equals "$output" "RENDERED:[# Hello]"

    unset -f mdcat
    teardown_test_env
}

test_render_auto_uses_available_renderer() {
    setup_test_env
    export BASH_AI_MARKDOWN_RENDERER="auto"

    # Functions satisfy command -v, so this is deterministic on any machine
    glow() {
        printf 'GLOW-MARKER %s' "$(cat)"
    }

    local output
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "GLOW-MARKER text"

    unset -f glow
    teardown_test_env
}

test_render_glow_theme_selects_style() {
    setup_test_env
    export BASH_AI_MARKDOWN_RENDERER="glow"

    glow() {
        # Args are: -s <theme> -  (theme is \$2)
        printf 'THEME:%s TEXT:%s' "$2" "$(cat)"
    }

    export BASH_AI_MARKDOWN_THEME="light"
    local output
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "THEME:light TEXT:text"

    export BASH_AI_MARKDOWN_THEME="dark"
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "THEME:dark TEXT:text"

    # Unknown values behave like "auto"; with no system theme signals
    # (empty HOME, gsettings unavailable) the resolver falls back to dark
    local old_home="$HOME"
    local test_dir
    test_dir=$(create_test_dir)
    export HOME="$test_dir"
    export BASH_AI_MARKDOWN_THEME="neon"
    gsettings() { return 1; }
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "THEME:dark TEXT:text"
    unset -f gsettings
    export HOME="$old_home"
    cleanup_test_dir "$test_dir"

    unset -f glow
    unset BASH_AI_MARKDOWN_THEME
    teardown_test_env
}

test_render_glow_auto_follows_system_theme() {
    setup_test_env
    export BASH_AI_MARKDOWN_RENDERER="glow"
    export BASH_AI_MARKDOWN_THEME="auto"

    glow() {
        # Args are: -s <theme> -  (theme is \$2)
        printf 'THEME:%s TEXT:%s' "$2" "$(cat)"
    }

    local old_home="$HOME"
    local test_dir
    local output

    # Omarchy light theme: light.mode marker present
    test_dir=$(create_test_dir)
    export HOME="$test_dir"
    mkdir -p "$HOME/.config/omarchy/current/theme"
    touch "$HOME/.config/omarchy/current/theme/light.mode"
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "THEME:light TEXT:text"
    export HOME="$old_home"
    cleanup_test_dir "$test_dir"

    # Omarchy dark theme: active theme dir without light.mode marker
    test_dir=$(create_test_dir)
    export HOME="$test_dir"
    mkdir -p "$HOME/.config/omarchy/current/theme"
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "THEME:dark TEXT:text"
    export HOME="$old_home"
    cleanup_test_dir "$test_dir"

    # No Omarchy: GTK color-scheme decides (gsettings mocked so it is deterministic)
    test_dir=$(create_test_dir)
    export HOME="$test_dir"
    gsettings() { printf '%s\n' "'prefer-light'"; }
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "THEME:light TEXT:text"
    unset -f gsettings

    gsettings() { printf '%s\n' "'prefer-dark'"; }
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "THEME:dark TEXT:text"
    unset -f gsettings

    # No Omarchy and no usable gsettings: falls back to dark
    gsettings() { return 1; }
    output=$(_bash_ai_render_markdown "text")
    assert_equals "$output" "THEME:dark TEXT:text"
    unset -f gsettings
    export HOME="$old_home"
    cleanup_test_dir "$test_dir"

    unset -f glow
    unset BASH_AI_MARKDOWN_THEME
    teardown_test_env
}

test_render_missing_renderer_falls_back_to_raw() {
    setup_test_env
    export BASH_AI_MARKDOWN_RENDERER="no-such-renderer-xyz"

    local output
    output=$(_bash_ai_render_markdown "## raw text")
    assert_equals "$output" "## raw text"

    teardown_test_env
}

test_bad_config_is_reported_on_use_without_querying() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"

    # Restore the real functions (earlier tests may have overridden them)
    source "$PLUGIN_DIR/lib-bash/utils.bash"

    # What bash-ai.plugin.bash captures at startup instead of printing
    _bash_ai_config_err="bash-ai: Warning: ANTHROPIC_API_KEY not set. Plugin will not function."

    local provider_called=0
    _bash_ai_query_anthropic() {
        provider_called=1
        echo "should-not-happen"
    }

    local output
    output=$(_bash_ai_query "list files")
    local result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "ANTHROPIC_API_KEY not set"
    assert_equals "$provider_called" "0"

    unset _bash_ai_config_err
    teardown_test_env
}

# Run tests
echo "Running utils tests..."
run_test "Routes to Anthropic provider when configured" test_routes_to_anthropic_provider
run_test "Routes to Ollama provider when configured" test_routes_to_ollama_provider
run_test "Routes to custom provider when configured" test_routes_to_custom_provider
run_test "Throws an error when provider returns non-zero exit code" test_provider_non_zero_exit_code
run_test "Checks Ollama availability before querying" test_checks_ollama_availability_before_querying
run_test "Shows usage when called without arguments" test_shows_usage_without_arguments
run_test "Shows Ollama model in usage for Ollama provider" test_shows_ollama_model_in_usage
run_test "Stages command in pending file" test_stages_command_in_pending_file
run_test "Handles API errors in bash-ai command" test_handles_api_errors_in_bash_ai
run_test "Handles empty response in bash-ai command" test_handles_empty_response_in_bash_ai
run_test "Combines multiple arguments in bash-ai command" test_combines_multiple_arguments
run_test "Works with noclobber set" test_works_with_noclobber_set
run_test "System prompt includes all rules" test_get_system_prompt_includes_all_rules
run_test "System prompt handles complex context" test_get_system_prompt_with_complex_context
run_test "System prompt handles empty context" test_get_system_prompt_with_empty_context
run_test "System prompt includes custom extension when set" test_get_system_prompt_with_extension
run_test "System prompt works without extension" test_get_system_prompt_without_extension
run_test "System prompt handles multiline extension" test_get_system_prompt_with_multiline_extension
run_test "System prompt handles empty extension" test_get_system_prompt_with_empty_extension
run_test "Answer system prompt requests formatted code" test_answer_system_prompt_requests_formatted_code
run_test "Answer mode passes mode to provider" test_answer_mode_passes_mode_to_provider
run_test "Answer mode appends search results to query" test_answer_mode_appends_search_results_to_query
run_test "Command mode does not search the web" test_command_mode_does_not_search
run_test "Conversation context feeds follow-up questions" test_conversation_context_feeds_followup
run_test "Conversation keeps only the newest turns" test_conversation_turn_cap
run_test "Conversation last question is tracked" test_conversation_last_question
run_test "Conversation gives follow-up search thread context" test_conversation_gives_search_thread_context
run_test "Conversation cleared when previous command was not a search" test_conversation_cleared_when_previous_command_not_search
run_test "Conversation kept when previous command was a search" test_conversation_kept_when_previous_command_was_search
run_test "Conversation reset clears memory" test_conversation_reset_clears_memory
run_test "bash-ai-answer stores the turn in the conversation" test_bash_ai_answer_stores_conversation_turn
run_test "bash-ai-answer prints multiline response" test_bash_ai_answer_prints_multiline_response
run_test "bash-ai-answer shows usage without arguments" test_bash_ai_answer_shows_usage_without_arguments
run_test "bash-ai-answer handles API errors" test_bash_ai_answer_handles_api_errors
run_test "Render off passes through raw text" test_render_off_passes_through_raw
run_test "Render explicit renderer pipes through it" test_render_explicit_renderer_pipes_through_it
run_test "Render auto uses an available renderer" test_render_auto_uses_available_renderer
run_test "Render glow theme selects light/dark style" test_render_glow_theme_selects_style
run_test "Render glow auto follows the system theme" test_render_glow_auto_follows_system_theme
run_test "Render missing renderer falls back to raw" test_render_missing_renderer_falls_back_to_raw
run_test "Bad config reported on use without querying" test_bad_config_is_reported_on_use_without_querying
finish_tests
