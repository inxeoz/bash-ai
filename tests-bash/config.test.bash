#!/usr/bin/env bash

# Load test helper
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

# Load the config module
source "$PLUGIN_DIR/lib-bash/config.bash"

# Test functions
test_default_provider() {
    setup_test_env
    unset BASH_AI_PROVIDER
    source "$PLUGIN_DIR/lib-bash/config.bash"
    assert_equals "$BASH_AI_PROVIDER" "anthropic"
    teardown_test_env
}

test_default_ollama_model() {
    setup_test_env
    unset BASH_AI_OLLAMA_MODEL
    source "$PLUGIN_DIR/lib-bash/config.bash"
    assert_equals "$BASH_AI_OLLAMA_MODEL" "llama3.2"
    teardown_test_env
}

test_default_ollama_url() {
    setup_test_env
    unset BASH_AI_OLLAMA_URL
    source "$PLUGIN_DIR/lib-bash/config.bash"
    assert_equals "$BASH_AI_OLLAMA_URL" "http://localhost:11434"
    teardown_test_env
}

test_validates_anthropic_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    _bash_ai_validate_config >/dev/null 2>&1
    local result=$?
    assert_equals "$result" "0"
    teardown_test_env
}

test_validates_ollama_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="ollama"
    _bash_ai_validate_config >/dev/null 2>&1
    local result=$?
    assert_equals "$result" "0"
    teardown_test_env
}

test_rejects_invalid_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="invalid"
    _bash_ai_validate_config >/dev/null 2>&1
    local result=$?
    assert_equals "$result" "1"
    teardown_test_env
}

test_validates_gemini_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="gemini"
    export GEMINI_API_KEY="test-key"
    _bash_ai_validate_config >/dev/null 2>&1
    local result=$?
    assert_equals "$result" "0"
    teardown_test_env
}

test_validates_openai_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="openai"
    export OPENAI_API_KEY="test-key"
    _bash_ai_validate_config >/dev/null 2>&1
    local result=$?
    assert_equals "$result" "0"
    teardown_test_env
}

test_validates_custom_provider() {
    setup_test_env
    export BASH_AI_PROVIDER="custom"

    _bash_ai_query_custom() {
        return 0
    }

    _bash_ai_validate_config >/dev/null 2>&1
    assert_equals "$?" "0"

    unset -f _bash_ai_query_custom
    teardown_test_env
}

test_rejects_missing_custom_provider_function() {
    setup_test_env
    export BASH_AI_PROVIDER="custom"
    unset -f _bash_ai_query_custom 2>/dev/null

    _bash_ai_validate_config >/dev/null 2>&1
    assert_equals "$?" "1"

    teardown_test_env
}

test_comment_hook_enabled_by_default() {
    setup_test_env
    unset BASH_AI_COMMENT_HOOK
    source "$PLUGIN_DIR/lib-bash/config.bash"
    _bash_ai_comment_hook_enabled
    local result=$?
    assert_equals "$result" "0"
    teardown_test_env
}

test_comment_hook_can_be_disabled() {
    setup_test_env
    local value
    for value in false off no 0 disabled FALSE Off; do
        export BASH_AI_COMMENT_HOOK="$value"
        _bash_ai_comment_hook_enabled
        assert_equals "$?" "1"
    done
    unset BASH_AI_COMMENT_HOOK
    teardown_test_env
}

test_default_trigger_is_hash() {
    setup_test_env
    unset BASH_AI_TRIGGER
    source "$PLUGIN_DIR/lib-bash/config.bash"
    assert_equals "$BASH_AI_TRIGGER" "# "
    teardown_test_env
}

# Run tests
echo "Running config tests..."
run_test "Default provider is anthropic" test_default_provider
run_test "Default Ollama model is llama3.2" test_default_ollama_model
run_test "Default Ollama URL is localhost:11434" test_default_ollama_url
run_test "Validates anthropic provider" test_validates_anthropic_provider
run_test "Validates ollama provider" test_validates_ollama_provider
run_test "Rejects invalid provider" test_rejects_invalid_provider
run_test "Validates gemini provider" test_validates_gemini_provider
run_test "Validates openai provider" test_validates_openai_provider
run_test "Validates custom provider" test_validates_custom_provider
run_test "Rejects missing custom provider function" test_rejects_missing_custom_provider_function
run_test "Comment hook enabled by default" test_comment_hook_enabled_by_default
run_test "Comment hook can be disabled" test_comment_hook_can_be_disabled
run_test "Default trigger is '# '" test_default_trigger_is_hash
finish_tests
