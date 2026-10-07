#!/usr/bin/env bash

# Tests for the provider registry and generic dispatch.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

source "$PLUGIN_DIR/lib-bash/providers/registry.bash"
source "$PLUGIN_DIR/lib-bash/config.bash"
source "$PLUGIN_DIR/lib-bash/context.bash"
source "$PLUGIN_DIR/lib-bash/utils.bash"

# Load every provider adapter, as the plugin does at startup
for _provider_file in "$PLUGIN_DIR"/lib-bash/providers/*.bash; do
    source "$_provider_file"
done
unset _provider_file

test_registry_lists_known_providers() {
    assert_equals "$(_bash_ai_provider_known anthropic && echo yes)" "yes"
    assert_equals "$(_bash_ai_provider_known custom && echo yes)" "yes"
    _bash_ai_provider_known bogus && { echo "bogus should not be known"; TEST_FAILED=1; return 1; }
    return 0
}

test_every_registered_provider_has_a_spec() {
    local p spec fields
    for p in $_BASH_AI_PROVIDERS; do
        spec="$(_bash_ai_provider_spec "$p")" || { echo "$p has no spec"; TEST_FAILED=1; return 1; }
        fields=$(printf '%s' "$spec" | awk -F'|' '{print NF}')
        if [[ "$fields" != "5" ]]; then
            echo "$p spec has $fields fields, expected 5"
            TEST_FAILED=1
            return 1
        fi
    done
    return 0
}

test_every_query_provider_has_an_implementation() {
    local p
    for p in $_BASH_AI_PROVIDERS; do
        [[ "$p" == "custom" ]] && continue
        if ! declare -F "_bash_ai_query_${p}" >/dev/null 2>&1; then
            echo "missing _bash_ai_query_${p}"
            TEST_FAILED=1
            return 1
        fi
    done
    return 0
}

test_openai_key_mode_follows_url() {
    export BASH_AI_OPENAI_URL="https://api.openai.com/v1/chat/completions"
    assert_equals "$(_bash_ai_provider_field openai key_mode)" "required"
    export BASH_AI_OPENAI_URL="http://localhost:8080/v1/chat/completions"
    assert_equals "$(_bash_ai_provider_field openai key_mode)" "optional"
    return 0
}

test_unknown_provider_is_rejected_by_dispatch() {
    setup_test_env
    unset _bash_ai_config_err
    export BASH_AI_PROVIDER="bogus"

    local output result
    output=$(_bash_ai_query "list files" 2>&1)
    result=$?

    assert_equals "$result" "1"
    assert_contains "$output" "no query implementation"
    teardown_test_env
}

test_convention_added_provider_is_dispatched() {
    setup_test_env
    unset _bash_ai_config_err
    export BASH_AI_PROVIDER="demo"

    _BASH_AI_PROVIDERS="$_BASH_AI_PROVIDERS demo"
    _bash_ai_query_demo() { echo "demo:$1"; }

    local output
    output=$(_bash_ai_query "list files")
    assert_equals "$output" "demo:list files"

    unset -f _bash_ai_query_demo
    _BASH_AI_PROVIDERS="${_BASH_AI_PROVIDERS% demo}"
    teardown_test_env
}

test_status_is_registry_driven() {
    setup_test_env
    export BASH_AI_PROVIDER="qwen"
    export BASH_AI_QWEN_MODEL="qwen-flash"

    local output
    output=$(_bash_ai_status)
    assert_contains "$output" "provider: qwen"
    assert_contains "$output" "model: qwen-flash"
    teardown_test_env
}

test_usage_is_registry_driven() {
    setup_test_env
    export BASH_AI_PROVIDER="grok"
    export BASH_AI_GROK_MODEL="grok-4.3"

    local output
    output=$(_bash_ai_usage)
    assert_contains "$output" "Current provider: grok"
    assert_contains "$output" "Grok model: grok-4.3"
    teardown_test_env
}

echo "Running provider registry tests..."
run_test "Known providers are listed" test_registry_lists_known_providers
run_test "Every provider has a 5-field spec" test_every_registered_provider_has_a_spec
run_test "Every query provider has an implementation" test_every_query_provider_has_an_implementation
run_test "OpenAI key mode follows the URL" test_openai_key_mode_follows_url
run_test "Unknown provider is rejected by dispatch" test_unknown_provider_is_rejected_by_dispatch
run_test "Convention-added provider is dispatched" test_convention_added_provider_is_dispatched
run_test "Status is registry-driven" test_status_is_registry_driven
run_test "Usage is registry-driven" test_usage_is_registry_driven
finish_tests
