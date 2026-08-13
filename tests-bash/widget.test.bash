#!/usr/bin/env bash

# Load test helper
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

# Load required modules
source "$PLUGIN_DIR/lib-bash/config.bash"
source "$PLUGIN_DIR/lib-bash/context.bash"
source "$PLUGIN_DIR/lib-bash/utils.bash"
source "$PLUGIN_DIR/lib-bash/widget.bash"

# Test functions

# Calls the Ctrl-G hook directly (not in a subshell) so READLINE_LINE
# side effects are visible, capturing stdout to a file.
call_trigger() {
    local outfile="$1"
    shift
    READLINE_LINE="$1"
    _bash_ai_trigger > "$outfile" 2>&1
}

test_line_is_processed_as_query() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock the query function
    _bash_ai_query() {
        printf "ls -la"
    }

    local outfile
    outfile=$(mktemp)
    call_trigger "$outfile" "list all files"

    # Line should be replaced with the command, cursor at end
    assert_equals "$READLINE_LINE" "ls -la"
    assert_equals "$READLINE_POINT" "6"

    rm -f "$outfile"
    teardown_test_env
}

test_query_is_passed_untouched() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Capture the received query via a file (the mock runs in a subshell)
    local received_file
    received_file=$(mktemp)
    _bash_ai_query() {
        printf '%s' "$1" > "$received_file"
        printf "echo ok"
    }

    local outfile
    outfile=$(mktemp)
    call_trigger "$outfile" "# find large files"

    assert_equals "$(cat "$received_file")" "# find large files"

    rm -f "$outfile" "$received_file"
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
    call_trigger "$outfile" "list all files"

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "list all files"

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
    call_trigger "$outfile" "invalid query"

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
    call_trigger "$outfile" "empty response"

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "Failed to generate command"

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
    call_trigger "$outfile" "print greeting"

    assert_equals "$READLINE_LINE" "echo 'Hello, World!'"

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
    call_trigger "$outfile" ""

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

    local ai_called_file
    ai_called_file=$(mktemp)
    _bash_ai_query() {
        printf '1' > "$ai_called_file"
        printf "echo real"
    }

    local outfile
    outfile=$(mktemp)
    call_trigger "$outfile" "echo real"

    # Pending file untouched, the line was sent as the query instead
    assert_equals "$(cat "$ai_called_file")" "1"
    if [[ ! -s "$BASH_AI_PENDING_FILE" ]]; then
        echo "Expected pending file to be preserved when line is not empty"
        TEST_FAILED=1
    fi

    rm -f "$outfile" "$ai_called_file"
    teardown_test_env
}

test_empty_line_without_pending_shows_hint() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    local outfile
    outfile=$(mktemp)
    call_trigger "$outfile" ""

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "Ctrl-G"

    rm -f "$outfile"
    teardown_test_env
}

# Calls the Ctrl-F answer hook directly so READLINE_LINE state is visible
call_answer() {
    local outfile="$1"
    shift
    READLINE_LINE="$1"
    _bash_ai_answer > "$outfile" 2>&1
}

test_answer_prints_multiline_response() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Mock the query function to return a multi-line answer
    _bash_ai_query() {
        printf 'Here is an example:\n\n```python\nx = 1\nprint(x)\n```'
    }

    local outfile
    outfile=$(mktemp)
    call_answer "$outfile" "show me a python example"

    local output
    output=$(cat "$outfile")

    # The answer is printed in full with its formatting intact
    assert_contains "$output" "Here is an example:"
    assert_contains "$output" '```python'
    assert_contains "$output" "print(x)"
    assert_not_contains "$output" "Failed to get an answer"

    # The command line is untouched
    assert_equals "$READLINE_LINE" "show me a python example"

    rm -f "$outfile"
    teardown_test_env
}

test_answer_handles_api_errors() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _bash_ai_query() {
        printf "API Error: connection failed"
    }

    local outfile
    outfile=$(mktemp)
    call_answer "$outfile" "some question"

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "Failed to get an answer"
    assert_contains "$output" "API Error: connection failed"

    rm -f "$outfile"
    teardown_test_env
}

test_answer_empty_line_shows_hint() {
    setup_test_env
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    local outfile
    outfile=$(mktemp)
    call_answer "$outfile" ""

    local output
    output=$(cat "$outfile")
    assert_contains "$output" "Ctrl-F"

    rm -f "$outfile"
    teardown_test_env
}

# Run tests
echo "Running widget tests..."
run_test "Line is processed as query" test_line_is_processed_as_query
run_test "Query is passed untouched" test_query_is_passed_untouched
run_test "Query line is echoed to the terminal" test_query_line_is_echoed_to_terminal
run_test "Handles API errors gracefully" test_handles_api_errors_gracefully
run_test "Handles empty API response" test_handles_empty_api_response
run_test "Handles commands with special characters" test_handles_commands_with_special_characters
run_test "Inserts pending command on empty line" test_inserts_pending_command_on_empty_line
run_test "Ignores pending when line is not empty" test_ignores_pending_when_line_is_not_empty
run_test "Empty line without pending shows hint" test_empty_line_without_pending_shows_hint
run_test "Answer prints multiline response without touching the line" test_answer_prints_multiline_response
run_test "Answer handles API errors gracefully" test_answer_handles_api_errors
run_test "Answer empty line shows hint" test_answer_empty_line_shows_hint
finish_tests
