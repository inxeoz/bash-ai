#!/usr/bin/env bash

# bash-ai - AI-powered command suggestions for bash
# Deep modules: Config (toml adapter) → Prompt → Context → Conversation → Markdown → Queue/Risk/History → Search → Provider (common + adapters) → Orchestration → Widget

_BASH_AI_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${_BASH_AI_PLUGIN_DIR}/lib-bash/toml.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/config.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/prompt.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/context.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/conversation.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/markdown.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/queue.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/risk.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/history.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/search.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/common.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/anthropic.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/ollama.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/gemini.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/openai.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/qwen.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/grok.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/groq.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/mistral.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/utils.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/widget.bash"

if _bash_ai_validate_config; then
    _bash_ai_init_widget
fi
