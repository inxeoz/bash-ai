#!/usr/bin/env bash
# Markdown module — hides renderer selection + theme detection.
# Interface: _bash_ai_resolve_markdown_theme() → light|dark
#            _bash_ai_render_markdown(text)

_bash_ai_resolve_markdown_theme() {
    local theme="${BASH_AI_MARKDOWN_THEME:-auto}"
    if [[ "$theme" == "light" || "$theme" == "dark" ]]; then printf '%s' "$theme"; return 0; fi
    if [[ -f "$HOME/.config/omarchy/current/theme/light.mode" ]]; then printf 'light'; return 0; fi
    if [[ -d "$HOME/.config/omarchy/current/theme" ]]; then printf 'dark'; return 0; fi
    if command -v gsettings &>/dev/null; then
        local scheme; scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
        if [[ "$scheme" == *"prefer-light"* ]]; then printf 'light'; return 0; fi
    fi
    printf 'dark'
}

_bash_ai_render_markdown() {
    local text="$1" renderer="${BASH_AI_MARKDOWN_RENDERER:-auto}" cmd=""
    if [[ "$renderer" == "auto" ]]; then
        local candidate
        for candidate in glow mdcat bat; do command -v "$candidate" &>/dev/null && { cmd="$candidate"; break; }; done
    elif [[ "$renderer" != "off" ]] && [[ -n "$renderer" ]]; then
        command -v "$renderer" &>/dev/null && cmd="$renderer"
    fi
    if [[ -z "$cmd" ]]; then printf '%s' "$text"; return 0; fi
    case "$cmd" in
        glow) local theme; theme="$(_bash_ai_resolve_markdown_theme)"; printf '%s\n' "$text" | glow -s "$theme" - ;;
        mdcat) printf '%s\n' "$text" | mdcat ;;
        bat) printf '%s\n' "$text" | bat --language=markdown --style=plain ;;
        *) printf '%s\n' "$text" | "$cmd" ;;
    esac
}
