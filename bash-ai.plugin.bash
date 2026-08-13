#!/usr/bin/env bash

# bash-ai - AI-powered command suggestions for bash (port of zsh-ai)
# Supports Anthropic Claude, Google Gemini, OpenAI, Mistral AI, Groq,
# Qwen, and local Ollama models

# Get the directory where this plugin is installed
_BASH_AI_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all the module files
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/config.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/context.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/anthropic.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/ollama.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/gemini.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/openai.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/qwen.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/grok.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/mistral.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/utils.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/search.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/widget.bash"

# Initialize the plugin
if _bash_ai_validate_config; then
    _bash_ai_init_widget
fi
