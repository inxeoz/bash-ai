#!/usr/bin/env bash
# Conversation module — deep module hiding file I/O + trimming.
# Interface: _bash_ai_conv_file() → path
#            _bash_ai_conv_append(q, a)
#            _bash_ai_conv_context() → block
#            _bash_ai_conv_keep_or_clear()
#            _bash_ai_conv_last_question() → str
#            bash-ai-reset

_bash_ai_conv_file() {
    printf '%s' "${BASH_AI_CONVERSATION_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/bash-ai/conversation.log}"
}

_bash_ai_conv_append() {
    local q="$1" a="$2"
    local n="${BASH_AI_CONVERSATION_TURNS:-6}"
    [[ "$n" == "0" ]] && return 0
    local file; file="$(_bash_ai_conv_file)"
    mkdir -p "$(dirname "$file")" 2>/dev/null
    printf 'User: %s\nAssistant: %s\n\n==== bash-ai turn ====\n' "$q" "$a" >> "$file"
    N="$n" perl -0777 -i -e '
        my $n = $ENV{N};
        my $s = <>;
        my @t = split /\n==== bash-ai turn ====\n/, $s;
        pop @t if @t && $t[-1] eq "";
        @t = @t[-$n..-1] if @t > $n;
        print join("\n==== bash-ai turn ====\n", @t), "\n==== bash-ai turn ====\n" if @t;
    ' "$file"
}

_bash_ai_conv_context() {
    local n="${BASH_AI_CONVERSATION_TURNS:-6}"
    [[ "$n" == "0" ]] && return 0
    local file; file="$(_bash_ai_conv_file)"
    [[ -s "$file" ]] || return 0
    N="$n" perl -0777 -e '
        my $n = $ENV{N};
        my $s = <STDIN>;
        my @t = split /\n==== bash-ai turn ====\n/, $s;
        pop @t if @t && $t[-1] eq "";
        @t = @t[-$n..-1] if @t > $n;
        print "Previous conversation:\n\n" if @t;
        for my $t (@t) { print "$t\n" }
    ' < "$file"
}

_bash_ai_conv_keep_or_clear() {
    [[ "${BASH_AI_CONVERSATION_TURNS:-6}" != "0" ]] || return 0
    case "$(history 1 2>/dev/null)" in
        *bash-ai-answer*) return 0 ;;
    esac
    rm -f "$(_bash_ai_conv_file)"
}

_bash_ai_conv_last_question() {
    local file; file="$(_bash_ai_conv_file)"
    [[ -s "$file" ]] || return 0
    tail -n 100 "$file" | grep '^User: ' | tail -1 | sed 's/^User: //'
}

bash-ai-reset() {
    rm -f "$(_bash_ai_conv_file)"
    echo "bash-ai: conversation cleared"
}
