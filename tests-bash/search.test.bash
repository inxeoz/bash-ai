#!/usr/bin/env bash

# Tests for the web search module (answer mode)

# Load test helper
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

# Load required modules
source "$PLUGIN_DIR/lib-bash/config.bash"
source "$PLUGIN_DIR/lib-bash/context.bash"
source "$PLUGIN_DIR/lib-bash/utils.bash"
source "$PLUGIN_DIR/lib-bash/search.bash"

SAMPLE_DDG_HTML='<html><body><div class="result results_links results_links_deep web-result"><h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpage&amp;rut=abc">Example &amp; Title</a></h2><a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpage">This is a snippet about the example.</a></div><div class="result results_links results_links_deep web-result"><h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fsecond.example.com%2F&rut=def">Second Result</a></h2><a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fsecond.example.com%2F">Second snippet.</a></div></body></html>'

SAMPLE_DDG_CHALLENGE='<html><body><div class="anomaly-modal__title">Unfortunately, bots use DuckDuckGo too.</div><form id="challenge-form">Select all squares containing a duck</form></body></html>'

SAMPLE_BING_HTML='<ol id="b_results"><li class="b_algo"><h2><a target="_blank" href="https://www.bing.com/ck/a?!&amp;&amp;p=x&amp;u=a1aHR0cHM6Ly93d3cucHl0aG9uLm9yZy8&amp;ntb=1">Welcome to Python.org</a></h2><div class="b_caption"><p class="b_lineclamp2">The mission of the Python Software Foundation.</p></div></li><li class="b_algo"><h2><a target="_blank" href="https://www.bing.com/ck/a?!&amp;&amp;p=y&amp;u=aHR0cHM6Ly93d3cuZXhhbXBsZS5jb20v&amp;ntb=1">Example Site</a></h2><div class="b_caption"><p class="b_lineclamp2">Second snippet here.</p></div></li></ol>'

# Resolve backend tests
test_resolve_backend_auto_with_gemini() {
    export BASH_AI_PROVIDER="gemini"
    export GEMINI_API_KEY="test-key"
    unset BASH_AI_SEARCH_BACKEND

    assert_equals "$(_bash_ai_resolve_search_backend)" "gemini"

    unset GEMINI_API_KEY
}

test_resolve_backend_auto_with_other_providers() {
    export BASH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    unset BASH_AI_SEARCH_BACKEND

    assert_equals "$(_bash_ai_resolve_search_backend)" "ddg"
}

test_resolve_backend_explicit() {
    export BASH_AI_PROVIDER="anthropic"
    export BASH_AI_SEARCH_BACKEND="off"
    assert_equals "$(_bash_ai_resolve_search_backend)" "off"

    export BASH_AI_SEARCH_BACKEND="ddg"
    assert_equals "$(_bash_ai_resolve_search_backend)" "ddg"
}

# DuckDuckGo backend tests
test_ddg_parses_results() {
    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]]; then
            printf "%s" "$SAMPLE_DDG_HTML"
        fi
    }

    export BASH_AI_SEARCH_BACKEND="ddg"
    local output
    output=$(_bash_ai_web_search "python csv example")

    assert_contains "$output" "Web search results (DuckDuckGo)"
    assert_contains "$output" "Example & Title"
    assert_contains "$output" "https://example.com/page"
    assert_contains "$output" "This is a snippet about the example."
    assert_contains "$output" "Second Result"
}

test_ddg_respects_max_results() {
    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]]; then
            printf "%s" "$SAMPLE_DDG_HTML"
        fi
    }

    export BASH_AI_SEARCH_BACKEND="ddg"
    export BASH_AI_SEARCH_MAX_RESULTS="1"
    local output
    output=$(_bash_ai_web_search "python csv example")

    assert_contains "$output" "Example & Title"
    assert_not_contains "$output" "Second Result"
}

test_ddg_handles_empty_page() {
    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]]; then
            printf "%s" "<html><body>No results found</body></html>"
        fi
    }

    export BASH_AI_SEARCH_BACKEND="ddg"
    local output
    output=$(_bash_ai_web_search "nothing matches this")
    assert_equals "$output" ""
}

test_ddg_handles_curl_failure() {
    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]]; then
            return 1
        fi
    }

    export BASH_AI_SEARCH_BACKEND="ddg"
    local output
    output=$(_bash_ai_web_search "test")
    assert_equals "$output" ""
}

# Bing fallback tests
test_bing_parses_results() {
    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]]; then
            return 1
        elif [[ "$*" == *"bing.com"* ]]; then
            printf "%s" "$SAMPLE_BING_HTML"
        fi
    }

    export BASH_AI_SEARCH_BACKEND="ddg"
    export BASH_AI_SEARCH_MAX_RESULTS="5"
    local output
    output=$(_bash_ai_web_search "python example")

    assert_contains "$output" "Web search results (Bing)"
    assert_contains "$output" "Welcome to Python.org"
    assert_contains "$output" "https://www.python.org/"
    assert_contains "$output" "The mission of the Python Software Foundation."
    # Both result styles: with and without the a1 marker prefix
    assert_contains "$output" "https://www.example.com/"
    assert_contains "$output" "Second snippet here."
}

test_ddg_challenge_falls_back_to_bing() {
    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]]; then
            printf "%s" "$SAMPLE_DDG_CHALLENGE"
        elif [[ "$*" == *"bing.com"* ]]; then
            printf "%s" "$SAMPLE_BING_HTML"
        fi
    }

    export BASH_AI_SEARCH_BACKEND="ddg"
    local output
    output=$(_bash_ai_web_search "python example")

    assert_contains "$output" "Web search results (Bing)"
    assert_contains "$output" "Welcome to Python.org"
    assert_not_contains "$output" "DuckDuckGo"
}

test_bing_handles_curl_failure() {
    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]] || [[ "$*" == *"bing.com"* ]]; then
            return 1
        fi
    }

    export BASH_AI_SEARCH_BACKEND="ddg"
    local output
    output=$(_bash_ai_web_search "test")
    assert_equals "$output" ""
}

test_bing_handles_empty_page() {
    curl() {
        if [[ "$*" == *"html.duckduckgo.com"* ]]; then
            return 1
        elif [[ "$*" == *"bing.com"* ]]; then
            printf "%s" "<html><body>No results</body></html>"
        fi
    }

    export BASH_AI_SEARCH_BACKEND="ddg"
    local output
    output=$(_bash_ai_web_search "test")
    assert_equals "$output" ""
}

# Off backend tests
test_off_backend_returns_nothing() {
    export BASH_AI_SEARCH_BACKEND="off"
    local output
    output=$(_bash_ai_web_search "any question")
    assert_equals "$output" ""
}

# Gemini backend tests
test_gemini_backend_extracts_grounded_answer() {
    curl() {
        if [[ "$*" == *"generateContent"* ]]; then
            printf '%s' '{"candidates":[{"content":{"parts":[{"text":"Grounded answer here"}]}}]}'
        fi
    }

    export BASH_AI_PROVIDER="anthropic"
    export BASH_AI_SEARCH_BACKEND="gemini"
    export GEMINI_API_KEY="test-key"

    local output
    output=$(_bash_ai_web_search "test question")

    assert_contains "$output" "Web search results (Google)"
    assert_contains "$output" "Grounded answer here"
}

test_gemini_backend_falls_back_to_ddg_on_failure() {
    curl() {
        if [[ "$*" == *"generateContent"* ]]; then
            printf '%s' '{"error":{"message":"googleSearch not supported"}}'
        elif [[ "$*" == *"html.duckduckgo.com"* ]]; then
            printf "%s" "$SAMPLE_DDG_HTML"
        fi
    }

    export BASH_AI_PROVIDER="anthropic"
    export BASH_AI_SEARCH_BACKEND="gemini"
    export GEMINI_API_KEY="test-key"

    local output
    output=$(_bash_ai_web_search "test question")

    assert_contains "$output" "Web search results (DuckDuckGo)"
    assert_contains "$output" "Example & Title"
}

# Run tests
echo "Running search tests..."
run_test "Auto backend resolves to gemini for gemini provider" test_resolve_backend_auto_with_gemini
run_test "Auto backend resolves to ddg for other providers" test_resolve_backend_auto_with_other_providers
run_test "Explicit backend setting is respected" test_resolve_backend_explicit
run_test "DuckDuckGo results are parsed" test_ddg_parses_results
run_test "DuckDuckGo respects max results" test_ddg_respects_max_results
run_test "DuckDuckGo handles empty pages" test_ddg_handles_empty_page
run_test "DuckDuckGo handles curl failure" test_ddg_handles_curl_failure
run_test "Bing parses results as fallback" test_bing_parses_results
run_test "DDG bot challenge falls back to Bing" test_ddg_challenge_falls_back_to_bing
run_test "Bing handles curl failure" test_bing_handles_curl_failure
run_test "Bing handles empty pages" test_bing_handles_empty_page
run_test "Off backend returns nothing" test_off_backend_returns_nothing
run_test "Gemini backend extracts grounded answer" test_gemini_backend_extracts_grounded_answer
run_test "Gemini backend falls back to ddg on failure" test_gemini_backend_falls_back_to_ddg_on_failure
finish_tests
