#!/usr/bin/env bash

# Web search for bash-ai answer mode (Ctrl-H)
#
# Two free backends:
# - gemini: Google Search grounding via the Gemini API (needs GEMINI_API_KEY,
#   free tier). Used automatically when BASH_AI_PROVIDER=gemini.
# - ddg: DuckDuckGo HTML endpoint, no API key, works with every provider.
#
# Search is best-effort: failures return empty output and the model answers
# from its own knowledge instead.

# Resolve the effective search backend from BASH_AI_SEARCH_BACKEND
# (auto|gemini|ddg|off). "auto" picks Gemini grounding for the Gemini
# provider and DuckDuckGo for everything else.
_bash_ai_resolve_search_backend() {
    local backend="${BASH_AI_SEARCH_BACKEND:-auto}"
    if [[ "$backend" == "auto" ]]; then
        if [[ "$BASH_AI_PROVIDER" == "gemini" ]] && [[ -n "${GEMINI_API_KEY:-}" ]]; then
            backend="gemini"
        else
            backend="ddg"
        fi
    fi
    printf '%s' "$backend"
}

# DuckDuckGo HTML backend: scrape the top results and print them as a
# numbered, header-prefixed block for the model. Prints nothing on failure.
_bash_ai_search_ddg() {
    local query="$1"
    local html

    html=$(curl -sG --max-time 20 \
        -A "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0" \
        "https://html.duckduckgo.com/html/" \
        --data-urlencode "q=$query" \
        --data-urlencode "kl=us-en" 2>/dev/null)
    [[ -n "$html" ]] || return 1

    local parsed
    parsed=$(printf '%s' "$html" | perl -0777 -e '
use strict;
use warnings;
my $max = ($ARGV[0] // 5) + 0;
$max = 5 if $max < 1;
my $html = <STDIN>;
my @out;
my $re = qr{<div[^>]*class="[^"]*result[^"]*"[^>]*>(.*?)(?=<div[^>]*class="[^"]*result|\z)}s;
while ($html =~ /$re/g) {
    my $block = $1;
    next unless $block =~ /class="result__a"/;
    my ($title) = $block =~ m{<a[^>]*class="result__a"[^>]*>(.*?)</a>}s;
    my ($href)  = $block =~ m{<a[^>]*class="result__a"[^>]*href="([^"]*)"}s;
    my ($snip)  = $block =~ m{<a[^>]*class="result__snippet"[^>]*>(.*?)</a>}s;
    next unless defined $title;
    for my $s ($title, $snip) {
        next unless defined $s;
        $s =~ s/<[^>]+>//g;
        $s =~ s/&amp;/&/g; $s =~ s/&lt;/</g; $s =~ s/&gt;/>/g;
        $s =~ s/&quot;/"/g; $s =~ s/&#0*39;/'"'"'/g; $s =~ s/&#x27;/'"'"'/g;
        $s =~ s/&#x2F;/\//g;
        $s =~ s/\s+/ /g;
        $s =~ s/^\s+|\s+$//g;
    }
    my $url = "";
    if (defined $href && $href =~ /uddg=([^&]+)/) {
        my $u = $1;
        $u =~ s/\+/ /g;
        $u =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        $url = $u;
    } elsif (defined $href) {
        $url = $href;
    }
    push @out, "$title\t$url\t$snip";
    last if @out >= $max;
}
if (@out) {
    print "Web search results (DuckDuckGo):\n\n";
    for my $i (0 .. $#out) {
        my ($t, $u, $s) = split /\t/, $out[$i], 3;
        print "$i. $t\n   $u\n   $s\n" if defined $t;
    }
}
' "$BASH_AI_SEARCH_MAX_RESULTS")
    [[ -n "$parsed" ]] || return 1
    printf '%s' "$parsed"
}

# Gemini backend: ask the model with Google Search grounding enabled and
# print the grounded answer. Prints nothing on failure (caller falls back).
_bash_ai_search_gemini() {
    local query="$1"
    local escaped_query
    escaped_query=$(_bash_ai_escape_json "$query")

    local json_payload=$(cat <<EOF
{
    "contents": [
        {
            "role": "user",
            "parts": [
                {
                    "text": "$escaped_query"
                }
            ]
        }
    ],
    "tools": [
        {
            "googleSearch": {}
        }
    ],
    "generationConfig": {
        "maxOutputTokens": ${BASH_AI_ANSWER_MAX_TOKENS:-4096}
    }
}
EOF
)

    local response
    response=$(curl -s --max-time 30 \
        "https://generativelanguage.googleapis.com/v1beta/models/${BASH_AI_GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}" \
        --header "content-type: application/json" \
        --data "$json_payload" 2>&1)
    [[ -n "$response" ]] || return 1

    local answer=""
    if command -v jq &> /dev/null; then
        answer=$(printf "%s" "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    else
        answer=$(printf "%s" "$response" | perl -0777 -ne 'print $1 if /"text":"((?:[^"\\]|\\.)*)"/s' 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\r/\r/g; s/\\"/"/g; s/\\\\/\\/g')
    fi
    [[ -n "$answer" ]] || return 1

    printf 'Web search results (Google):\n\n%s' "$answer"
}

# Public search entry point: prints a formatted web-results block for the
# query, or nothing when search is off/failed. "gemini" results are only
# used as a fallback here - the Gemini provider handles grounding inline.
_bash_ai_web_search() {
    local query="$1"
    local backend
    backend="$(_bash_ai_resolve_search_backend)"

    case "$backend" in
        off|"")
            return 0
            ;;
        gemini)
            local grounded
            grounded="$(_bash_ai_search_gemini "$query")"
            if [[ -n "$grounded" ]]; then
                printf '%s' "$grounded"
            else
                _bash_ai_search_ddg "$query"
            fi
            ;;
        ddg)
            _bash_ai_search_ddg "$query"
            ;;
        *)
            printf 'bash-ai: Warning: Unknown BASH_AI_SEARCH_BACKEND '\''%s'\'' (use auto, gemini, ddg, or off)\n' "$backend" >&2
            _bash_ai_search_ddg "$query"
            ;;
    esac
}
