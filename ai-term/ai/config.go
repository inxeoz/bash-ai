// Package ai implements the query pipeline for ai-term: context
// building, system prompt construction, and provider routing. It is a
// Go port of lib-bash/utils.bash + lib-bash/context.bash + the provider
// modules, using net/http and encoding/json (no jq needed).
package ai

import "os"

// Config mirrors the BASH_AI_* environment variables of the bash plugin.
type Config struct {
	Provider string

	AnthropicURL   string
	AnthropicModel string

	OllamaURL   string
	OllamaModel string

	GeminiModel string

	OpenAIModel           string
	OpenAIURL             string
	OpenAIThinking        string // "" | "0" | "1"
	OpenAIReasoningEffort string

	QwenModel string
	QwenURL   string

	GrokModel string
	GrokURL   string

	MistralModel string
	MistralURL   string

	PromptExtend string
}

// Load reads configuration from the environment. Defaults and variable
// names match lib-bash/config.bash exactly.
func Load() Config {
	return Config{
		Provider:              getenv("BASH_AI_PROVIDER", "anthropic"),
		AnthropicURL:          getenv("BASH_AI_ANTHROPIC_URL", "https://api.anthropic.com/v1/messages"),
		AnthropicModel:        getenv("BASH_AI_ANTHROPIC_MODEL", "claude-haiku-4-5"),
		OllamaURL:             getenv("BASH_AI_OLLAMA_URL", "http://localhost:11434"),
		OllamaModel:           getenv("BASH_AI_OLLAMA_MODEL", "llama3.2"),
		GeminiModel:           getenv("BASH_AI_GEMINI_MODEL", "gemini-2.5-flash"),
		OpenAIModel:           getenv("BASH_AI_OPENAI_MODEL", "gpt-5.4-mini"),
		OpenAIURL:             getenv("BASH_AI_OPENAI_URL", "https://api.openai.com/v1/chat/completions"),
		OpenAIThinking:        os.Getenv("BASH_AI_OPENAI_THINKING"),
		OpenAIReasoningEffort: os.Getenv("BASH_AI_OPENAI_REASONING_EFFORT"),
		QwenModel:             getenv("BASH_AI_QWEN_MODEL", "qwen-flash"),
		QwenURL:               getenv("BASH_AI_QWEN_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"),
		GrokModel:             getenv("BASH_AI_GROK_MODEL", "grok-4.3"),
		GrokURL:               getenv("BASH_AI_GROK_URL", "https://api.x.ai/v1/chat/completions"),
		MistralModel:          getenv("BASH_AI_MISTRAL_MODEL", "mistral-small-latest"),
		MistralURL:            getenv("BASH_AI_MISTRAL_URL", "https://api.mistral.ai/v1/chat/completions"),
		PromptExtend:          os.Getenv("BASH_AI_PROMPT_EXTEND"),
	}
}

// Model returns the active model name for display in the status bar.
func (c Config) Model() string {
	switch c.Provider {
	case "ollama":
		return c.OllamaModel
	case "gemini":
		return c.GeminiModel
	case "openai":
		return c.OpenAIModel
	case "qwen":
		return c.QwenModel
	case "grok":
		return c.GrokModel
	case "mistral":
		return c.MistralModel
	default:
		return c.AnthropicModel
	}
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
