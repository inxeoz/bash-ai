#!/usr/bin/env bash

# bash-ai - AI-powered command suggestions for bash
# Deep modules: Registry → Config → Prompt → Context → Conversation → Markdown → Queue/Risk/History → Search → Provider (common + adapters) → Orchestration → Widget

_BASH_AI_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${_BASH_AI_PLUGIN_DIR}/lib-bash/providers/registry.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/config.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/prompt.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/context.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/conversation.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/markdown.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/queue.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/risk.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/history.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/search.bash"
# Provider adapters plus shared helpers (registry is sourced above). The glob
# keeps the plugin decoupled from the provider list: a new adapter file is
# picked up automatically.
for _bash_ai_provider_file in "${_BASH_AI_PLUGIN_DIR}"/lib-bash/providers/*.bash; do
    source "$_bash_ai_provider_file"
done
unset _bash_ai_provider_file
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/utils.bash"
source "${_BASH_AI_PLUGIN_DIR}/lib-bash/widget.bash"

# Validate at startup but stay quiet: keep the result and report it only when
# bash-ai is used (see _bash_ai_query). The call itself is still required -
# it normalizes the openai-compatible alias that _bash_ai_query dispatches on.
_bash_ai_config_err="$(_bash_ai_validate_config 2>&1)"
_bash_ai_init_widget
