#!/usr/bin/env bash

# Tests for Groq provider

# Source test helper and the files we're testing
source "$(dirname "${BASH_SOURCE[0]}")/../test_helper.bash"
source "${PLUGIN_DIR}/lib-bash/config.bash"
source "${PLUGIN_DIR}/lib-bash/context.bash"
source "${PLUGIN_DIR}/lib-bash/providers/groq.bash"
source "${PLUGIN_DIR}/lib-bash/utils.bash"

# Mock curl to test API interactions
curl() {
    if [[ "$*" == *"${BASH_AI_GROQ_URL}"* ]]; then
        # Simulate successful response
        cat <<EOF
{
    "choices": [
        {
            "message": {
                "content": "ls -la"
            }
        }
    ]
}
EOF
        return 0
    fi
    # Call real curl for other requests
    command curl "$@"
}

test_groq_query_success() {
    export GROQ_API_KEY="test-key"
    export BASH_AI_GROQ_MODEL="openai/gpt-oss-20b"

    local result=$(_bash_ai_query_groq "list files")
    assert_equals "$result" "ls -la"
}

test_groq_query_error_response() {
    export GROQ_API_KEY="test-key"
    export BASH_AI_GROQ_MODEL="openai/gpt-oss-20b"

    # Override curl to return an error
    curl() {
        if [[ "$*" == *"${BASH_AI_GROQ_URL}"* ]]; then
            cat <<EOF
{
    "error": {
        "message": "Invalid API key"
    }
}
EOF
            return 0
        fi
        command curl "$@"
    }

    local result=$(_bash_ai_query_groq "list files")
    assert_contains "$result" "API Error:"
}

test_groq_json_escaping() {
    export GROQ_API_KEY="test-key"
    export BASH_AI_GROQ_MODEL="openai/gpt-oss-20b"

    # Test with special characters
    local result=$(_bash_ai_query_groq "test \"quotes\" and \$variables")
    # Should not fail due to JSON escaping issues
    assert_not_empty "$result"
}

test_handles_response_with_newline() {
    export GROQ_API_KEY="test-key"
    export BASH_AI_GROQ_MODEL="openai/gpt-oss-20b"

    # Override curl to return response with newline
    curl() {
        if [[ "$*" == *"${BASH_AI_GROQ_URL}"* ]]; then
            cat <<EOF
{
    "choices": [
        {
            "message": {
                "content": "cd /home"
            }
        }
    ]
}
EOF
            return 0
        fi
        return 1
    }

    local result=$(_bash_ai_query_groq "go home")
    assert_equals "$result" "cd /home"
}

test_handles_response_without_jq() {
    export GROQ_API_KEY="test-key"
    export BASH_AI_GROQ_MODEL="openai/gpt-oss-20b"

    # Mock jq as unavailable
    command() {
        if [[ "$1" == "-v" && "$2" == "jq" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    # Override curl for consistent response
    curl() {
        if [[ "$*" == *"${BASH_AI_GROQ_URL}"* ]]; then
            echo '{"choices":[{"message":{"content":"echo test"}}]}'
            return 0
        fi
        builtin command curl "$@"
    }

    local result=$(_bash_ai_query_groq "echo test")
    assert_equals "$result" "echo test"
}

test_uses_configurable_api_url() {
    export GROQ_API_KEY="test-key"
    export BASH_AI_GROQ_MODEL="openai/gpt-oss-20b"
    export BASH_AI_GROQ_URL="https://custom.groq.api/v1/chat/completions"

    # Override curl to check the custom URL is used
    curl() {
        if [[ "$*" == *"https://custom.groq.api/v1/chat/completions"* ]]; then
            echo '{"choices":[{"message":{"content":"custom url works"}}]}'
            return 0
        fi
        return 1
    }

    local result=$(_bash_ai_query_groq "test")
    assert_equals "$result" "custom url works"

    # Reset to default
    export BASH_AI_GROQ_URL="https://api.groq.com/openai/v1/chat/completions"
}

# Capture the JSON --data payload sent to the Groq API
capture_groq_payload() {
    export GROQ_API_KEY="test-key"
    export BASH_AI_GROQ_MODEL="openai/gpt-oss-20b"
    local payload_file=$(mktemp)

    curl() {
        if [[ "$*" == *"${BASH_AI_GROQ_URL}"* ]]; then
            local prev_arg=""
            for arg in "$@"; do
                if [[ "$prev_arg" == "--data" ]]; then
                    echo "$arg" > "$payload_file"
                    break
                fi
                prev_arg="$arg"
            done
            echo '{"choices":[{"message":{"content":"test"}}]}'
            return 0
        fi
        command curl "$@"
    }

    _bash_ai_query_groq "test" >/dev/null
    local captured_payload=$(cat "$payload_file")
    rm -f "$payload_file"
    printf "%s" "$captured_payload"
}

test_uses_max_completion_tokens() {
    assert_contains "$(capture_groq_payload)" '"max_completion_tokens"'
}

test_uses_groq_api_key() {
    export GROQ_API_KEY="test-secret-key"
    export BASH_AI_GROQ_MODEL="openai/gpt-oss-20b"

    # Test that the function uses GROQ_API_KEY (not OPENAI_API_KEY)
    # If GROQ_API_KEY is set, the query should succeed
    local result=$(_bash_ai_query_groq "test")
    assert_not_empty "$result"
}

test_uses_reasoning_effort_none() {
    # By default groq should not send reasoning_effort (let server default), only when BASH_AI_GROQ_REASONING_EFFORT is set
    local payload
    payload="$(capture_groq_payload)"
    # Should NOT contain reasoning_effort by default
    if echo "$payload" | grep -q "reasoning_effort"; then
        echo "Expected no reasoning_effort by default, got: $payload" >&2
        return 1
    fi
    # When set, it should appear
    export BASH_AI_GROQ_REASONING_EFFORT="low"
    payload="$(capture_groq_payload)"
    assert_contains "$payload" '"reasoning_effort": "low"'
    unset BASH_AI_GROQ_REASONING_EFFORT
}

# Run tests
echo "Running Groq provider tests..."
run_test "Groq query success" test_groq_query_success
run_test "Groq error response handling" test_groq_query_error_response
run_test "Groq JSON escaping" test_groq_json_escaping
run_test "Handles response with trailing newline" test_handles_response_with_newline
run_test "Handles response without jq and with newline" test_handles_response_without_jq
run_test "Uses configurable API URL (BASH_AI_GROQ_URL)" test_uses_configurable_api_url
run_test "Uses max_completion_tokens parameter" test_uses_max_completion_tokens
run_test "Uses reasoning_effort parameter when set" test_uses_reasoning_effort_none
run_test "Uses GROQ_API_KEY environment variable" test_uses_groq_api_key
finish_tests
