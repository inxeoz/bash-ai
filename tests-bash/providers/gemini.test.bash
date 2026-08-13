#!/usr/bin/env bash

# Load test helper
source "$(dirname "${BASH_SOURCE[0]}")/../test_helper.bash"

# Load the context and gemini provider modules
source "$PLUGIN_DIR/lib-bash/utils.bash"
source "$PLUGIN_DIR/lib-bash/context.bash"
source "$PLUGIN_DIR/lib-bash/config.bash"
source "$PLUGIN_DIR/lib-bash/providers/gemini.bash"

# Test functions

test_default_model_configuration() {
    setup_test_env
    
    # Source config to get default values
    source "$PLUGIN_DIR/lib-bash/config.bash"
    
    assert_equals "$BASH_AI_GEMINI_MODEL" "gemini-2.5-flash"
    
    teardown_test_env
}

test_validation_fails_without_api_key() {
    setup_test_env
    unset GEMINI_API_KEY
    export BASH_AI_PROVIDER="gemini"
    
    _bash_ai_validate_config >/dev/null 2>&1
    local result=$?
    
    assert_equals "$result" "1"
    
    teardown_test_env
}

test_validation_succeeds_with_api_key() {
    setup_test_env
    export GEMINI_API_KEY="test-key"
    export BASH_AI_PROVIDER="gemini"
    
    _bash_ai_validate_config >/dev/null 2>&1
    local result=$?
    
    assert_equals "$result" "0"
    
    teardown_test_env
}

test_routes_queries_to_gemini_provider() {
    setup_test_env
    export GEMINI_API_KEY="test-key"
    export BASH_AI_PROVIDER="gemini"
    
    # Mock the gemini query function
    _bash_ai_query_gemini() {
        echo "gemini-response"
    }
    
    local output=$(_bash_ai_query "test query")
    assert_equals "$output" "gemini-response"
    
    teardown_test_env
}

test_gemini_query_function_exists() {
    setup_test_env
    export GEMINI_API_KEY="test-key"
    export BASH_AI_PROVIDER="gemini"
    
    # Load the provider
    source "$PLUGIN_DIR/lib-bash/providers/gemini.bash"
    
    # Check if function exists
    if type _bash_ai_query_gemini >/dev/null 2>&1; then
        local result=0
    else
        local result=1
    fi
    
    assert_equals "$result" "0"
    
    teardown_test_env
}

test_successful_api_call_with_jq() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    
    # Mock jq as available
    mock_jq "true"
    
    # Mock successful curl response
    local mock_response='{"candidates":[{"content":{"parts":[{"text":"git status"}]}}]}'
    mock_curl_response "$mock_response" 0
    
    local output
    output=$(_bash_ai_query_gemini "show git status")
    local result=$?
    
    assert_equals "$result" "0"
    assert_equals "$output" "git status"
    
    teardown_test_env
}

test_successful_api_call_without_jq() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    
    # Mock jq as unavailable
    mock_jq "false"
    
    # Mock successful curl response
    local mock_response='{"candidates":[{"content":{"parts":[{"text":"ls -la"}]}}]}'
    mock_curl_response "$mock_response" 0
    
    local output
    output=$(_bash_ai_query_gemini "list files")
    local result=$?
    
    assert_equals "$result" "0"
    assert_equals "$output" "ls -la"
    
    teardown_test_env
}

test_handles_api_error_response() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    
    # Mock jq as available
    mock_jq "true"
    
    # Mock error response
    local mock_response='{"error":{"message":"Invalid API key"}}'
    mock_curl_response "$mock_response" 0
    
    local output
    output=$(_bash_ai_query_gemini "test query")
    local result=$?
    
    assert_equals "$result" "1"
    assert_contains "$output" "API Error: Invalid API key"
    
    teardown_test_env
}

test_handles_curl_connection_failure() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    
    # Mock curl failure
    mock_command "curl" "" 1
    
    local output
    output=$(_bash_ai_query_gemini "test query")
    local result=$?
    
    assert_equals "$result" "1"
    assert_contains "$output" "Failed to connect to Gemini API"
    
    teardown_test_env
}

test_handles_empty_response() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    
    # Mock jq as available
    mock_jq "true"
    
    # Mock empty response
    local mock_response='{}'
    mock_curl_response "$mock_response" 0
    
    local output
    output=$(_bash_ai_query_gemini "test query")
    local result=$?
    
    assert_equals "$result" "1"
    assert_contains "$output" "Unable to parse response"
    
    teardown_test_env
}

test_handles_response_with_escaped_newline_with_jq() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    
    # Mock jq as available
    mock_jq "true"
    
    # Mock response with escaped newline
    local mock_response='{"candidates":[{"content":{"parts":[{"text":"git status\n"}]}}]}'
    mock_curl_response "$mock_response" 0
    
    local output
    output=$(_bash_ai_query_gemini "check git status")
    local result=$?
    
    assert_equals "$result" "0"
    assert_equals "$output" "git status"
    
    teardown_test_env
}

test_handles_response_with_escaped_newline_without_jq() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    
    # Mock jq as unavailable
    mock_jq "false"
    
    # Mock response with escaped newline
    local mock_response='{"candidates":[{"content":{"parts":[{"text":"ls -la\n"}]}}]}'
    mock_curl_response "$mock_response" 0
    
    local output
    output=$(_bash_ai_query_gemini "list files")
    local result=$?
    
    assert_equals "$result" "0"
    assert_equals "$output" "ls -la"
    
    teardown_test_env
}

# Answer mode tests

# Captures the JSON payload sent to the Gemini API
capture_gemini_payload() {
    local mode="$1"
    local search_backend="${2:-gemini}"
    export GEMINI_API_KEY="test-api-key"
    export BASH_AI_SEARCH_BACKEND="$search_backend"
    local payload_file=$(mktemp)

    curl() {
        local prev_arg=""
        for arg in "$@"; do
            if [[ "$prev_arg" == "--data" ]]; then
                echo "$arg" > "$payload_file"
                break
            fi
            prev_arg="$arg"
        done
        printf '%s' '{"candidates":[{"content":{"parts":[{"text":"answer text"}]}}]}'
        return 0
    }

    mock_jq "true"
    _bash_ai_query_gemini "test question" "$mode" "$search_backend" >/dev/null
    local captured_payload=$(cat "$payload_file")
    rm -f "$payload_file"
    unset BASH_AI_SEARCH_BACKEND
    printf "%s" "$captured_payload"
}

test_answer_mode_uses_large_token_budget() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    local captured_payload=$(capture_gemini_payload "answer")
    assert_contains "$captured_payload" '"maxOutputTokens": 4096'
    teardown_test_env
}

test_command_mode_uses_small_token_budget() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    local captured_payload=$(capture_gemini_payload "command")
    assert_contains "$captured_payload" '"maxOutputTokens": 256'
    teardown_test_env
}

test_answer_mode_includes_google_search_grounding() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    local captured_payload=$(capture_gemini_payload "answer" "gemini")
    assert_contains "$captured_payload" '"googleSearch": {}'
    teardown_test_env
}

test_answer_mode_omits_grounding_when_backend_is_off() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    local captured_payload=$(capture_gemini_payload "answer" "off")
    assert_not_contains "$captured_payload" "googleSearch"
    teardown_test_env
}

test_answer_mode_appends_sources() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    mock_jq "true"

    local mock_response='{"candidates":[{"content":{"parts":[{"text":"Grounded answer\n\n```python\nprint(1)\n```"}]},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com/a"}},{"web":{"uri":"https://example.com/b"}}]}}]}'
    mock_curl_response "$mock_response" 0

    local output
    output=$(_bash_ai_query_gemini "test question" "answer" "gemini")
    local result=$?

    assert_equals "$result" "0"
    assert_contains "$output" "Grounded answer"
    assert_contains "$output" "print(1)"
    assert_contains "$output" "Sources:"
    assert_contains "$output" " - https://example.com/a"
    assert_contains "$output" " - https://example.com/b"

    teardown_test_env
}

test_answer_mode_without_grounding_has_no_sources() {
    setup_test_env
    export GEMINI_API_KEY="test-api-key"
    mock_jq "true"

    local mock_response='{"candidates":[{"content":{"parts":[{"text":"plain answer"}]}}]}'
    mock_curl_response "$mock_response" 0

    local output
    output=$(_bash_ai_query_gemini "test question" "answer" "off")

    assert_contains "$output" "plain answer"
    assert_not_contains "$output" "Sources:"

    teardown_test_env
}

# Run tests
echo "Running gemini provider tests..."
run_test "Default model configuration" test_default_model_configuration
run_test "Validation fails without API key" test_validation_fails_without_api_key
run_test "Validation succeeds with API key" test_validation_succeeds_with_api_key
run_test "Routes queries to gemini provider" test_routes_queries_to_gemini_provider
run_test "Gemini query function exists" test_gemini_query_function_exists
run_test "Successful API call with jq available" test_successful_api_call_with_jq
run_test "Successful API call without jq" test_successful_api_call_without_jq
run_test "Handles API error response" test_handles_api_error_response
run_test "Handles curl connection failure" test_handles_curl_connection_failure
run_test "Handles empty response" test_handles_empty_response
run_test "Handles response with escaped newline (with jq)" test_handles_response_with_escaped_newline_with_jq
run_test "Handles response with escaped newline (without jq)" test_handles_response_with_escaped_newline_without_jq
run_test "Answer mode uses large token budget" test_answer_mode_uses_large_token_budget
run_test "Command mode uses small token budget" test_command_mode_uses_small_token_budget
run_test "Answer mode includes Google Search grounding" test_answer_mode_includes_google_search_grounding
run_test "Answer mode omits grounding when backend is off" test_answer_mode_omits_grounding_when_backend_is_off
run_test "Answer mode appends grounding sources" test_answer_mode_appends_sources
run_test "Answer mode without grounding has no sources" test_answer_mode_without_grounding_has_no_sources
finish_tests
