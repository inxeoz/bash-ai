#!/usr/bin/env bash

# Load test helper
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

# Load required modules
source "$PLUGIN_DIR/lib-bash/config.bash"
source "$PLUGIN_DIR/lib-bash/context.bash"
source "$PLUGIN_DIR/lib-bash/utils.bash"
source "$PLUGIN_DIR/lib-bash/widget.bash"

# Test functions

# Calls the Enter hook directly (not in a subshell) so READLINE_LINE
# side effects are visible, capturing stdout to a file.
call_accept_line() {
    local outfile="$1"
    shift
    READLINE_LINE="$1"
    _bash_ai_accept_line > "$outfile" 2>&1
}

test_ai_commands_starting_with_hash_are_processed() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock the query function
    _bash_ai_query() {
        printf "ls -la"
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "# list all files"

    # Buffer should be replaced with command, cursor at end
    assert_equals "$READLINE_LINE" "ls -la"
    assert_equals "$READLINE_POINT" "6"

    rm -f "$outfile"
    teardown_test_env
}

test_query_line_is_echoed_to_terminal() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _bash_ai_query() {
        printf "ls -la"
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "# list all files"

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "# list all files"

    rm -f "$outfile"
    teardown_test_env
}

test_handles_api_errors_gracefully() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock the query function to return error
    _bash_ai_query() {
        printf "Error: API connection failed"
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "# invalid query"

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "Failed to generate command"
    assert_contains "$output" "API connection failed"

    rm -f "$outfile"
    teardown_test_env
}

test_handles_empty_api_response() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock the query function to return empty
    _bash_ai_query() {
        printf ""
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "# empty response"

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "Failed to generate command"

    rm -f "$outfile"
    teardown_test_env
}

test_custom_trigger_is_processed() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    export BASH_AI_TRIGGER=",,"

    # Echo back the query so we can verify the trigger prefix was stripped
    _bash_ai_query() {
        printf "query:%s" "$1"
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" ",,list all files"

    assert_equals "$READLINE_LINE" "query:list all files"

    rm -f "$outfile"
    teardown_test_env
}

test_default_hash_ignored_when_trigger_changed() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    export BASH_AI_TRIGGER=",,"

    local executed=0
    some_normal_command() {
        executed=1
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "# list files"

    # With a custom trigger, a leading "# " is a normal comment line,
    # which evals to nothing - nothing to assert about execution, but the
    # AI path must NOT have run and the query must not have been sent
    assert_not_contains "$(cat "$outfile")" "Querying"

    rm -f "$outfile"
    teardown_test_env
}

test_multiline_buffers_execute_without_ai_processing() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    local ai_called=0
    _bash_ai_query() {
        ai_called=1
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" $'# list files\nand show details'

    assert_equals "$ai_called" "0"
    assert_equals "$READLINE_LINE" ""

    rm -f "$outfile"
    teardown_test_env
}

test_normal_commands_execute_without_ai_processing() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    local ai_called=0
    _bash_ai_query() {
        ai_called=1
    }

    local executed=0
    normal_test_cmd() {
        executed=1
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "normal_test_cmd"

    assert_equals "$ai_called" "0"
    assert_equals "$executed" "1"
    assert_equals "$READLINE_LINE" ""

    rm -f "$outfile"
    teardown_test_env
}

test_normal_command_is_echoed() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "echo hello"

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "echo hello"
    assert_contains "$output" "hello"

    rm -f "$outfile"
    teardown_test_env
}

test_inserts_pending_command_on_empty_line() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    printf '%s\n' "du -sh * | sort -hr | head -n1" > "$BASH_AI_PENDING_FILE"

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" ""

    assert_equals "$READLINE_LINE" "du -sh * | sort -hr | head -n1"
    assert_equals "$READLINE_POINT" "30"

    # Pending file consumed
    if [[ -s "$BASH_AI_PENDING_FILE" ]]; then
        echo "Expected pending file to be removed after insertion"
        TEST_FAILED=1
    fi

    rm -f "$outfile"
    teardown_test_env
}

test_ignores_pending_when_line_is_not_empty() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    printf '%s\n' "du -sh *" > "$BASH_AI_PENDING_FILE"

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "echo real"

    # Pending file untouched, normal command executed
    assert_contains "$(cat "$outfile")" "echo real"
    if [[ ! -s "$BASH_AI_PENDING_FILE" ]]; then
        echo "Expected pending file to be preserved when line is not empty"
        TEST_FAILED=1
    fi

    rm -f "$outfile"
    teardown_test_env
}

test_handles_commands_with_special_characters() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _bash_ai_query() {
        printf "echo 'Hello, World!'"
    }

    local outfile
    outfile=$(mktemp)
    call_accept_line "$outfile" "# print greeting"

    assert_equals "$READLINE_LINE" "echo 'Hello, World!'"

    rm -f "$outfile"
    teardown_test_env
}

test_init_widget_skips_binding_when_disabled() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    export BASH_AI_COMMENT_HOOK="false"

    local bind_called=0
    bind() {
        bind_called=1
    }

    _bash_ai_init_widget

    assert_equals "$bind_called" "0"

    teardown_test_env
}

# Run tests
echo "Running widget tests..."
run_test "AI commands starting with # are processed" test_ai_commands_starting_with_hash_are_processed
run_test "Query line is echoed to the terminal" test_query_line_is_echoed_to_terminal
run_test "Handles API errors gracefully" test_handles_api_errors_gracefully
run_test "Handles empty API response" test_handles_empty_api_response
run_test "Custom trigger is processed" test_custom_trigger_is_processed
run_test "Default '# ' ignored when trigger changed" test_default_hash_ignored_when_trigger_changed
run_test "Multiline buffers execute without AI processing" test_multiline_buffers_execute_without_ai_processing
run_test "Normal commands execute without AI processing" test_normal_commands_execute_without_ai_processing
run_test "Normal command is echoed" test_normal_command_is_echoed
run_test "Inserts pending command on empty line" test_inserts_pending_command_on_empty_line
run_test "Ignores pending when line is not empty" test_ignores_pending_when_line_is_not_empty
run_test "Handles commands with special characters" test_handles_commands_with_special_characters
run_test "Init widget skips binding when disabled" test_init_widget_skips_binding_when_disabled
finish_tests
