package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// DefaultClient is a sane HTTP client for API calls.
var DefaultClient = &http.Client{Timeout: 120 * time.Second}

// geminiBase is the Gemini API base URL, overridable in tests.
var geminiBase = "https://generativelanguage.googleapis.com"

// ErrCustomUnsupported is returned for the "custom" provider, which has
// no Go equivalent (users define _bash_ai_query_custom in bash).
var ErrCustomUnsupported = fmt.Errorf("the 'custom' provider is not supported by ai-term; use the bash plugin instead")

// Query routes a natural-language query to the configured provider and
// returns the generated command. Mirrors _bash_ai_query.
func Query(ctx context.Context, cfg Config, client *http.Client, query string) (string, error) {
	if client == nil {
		client = DefaultClient
	}
	switch cfg.Provider {
	case "ollama":
		return queryOllama(ctx, cfg, client, query)
	case "gemini":
		return queryGemini(ctx, cfg, client, query)
	case "openai":
		return queryOpenAI(ctx, cfg, client, query)
	case "qwen":
		return queryQwen(ctx, cfg, client, query)
	case "grok":
		return queryGrok(ctx, cfg, client, query)
	case "mistral":
		return queryMistral(ctx, cfg, client, query)
	case "custom":
		return "", ErrCustomUnsupported
	default:
		return queryAnthropic(ctx, cfg, client, query)
	}
}

// requestPayload holds the system prompt and user query used by every
// provider.
type requestPayload struct {
	system string
	user   string
}

func buildPayload(query string) requestPayload {
	context := BuildContext()
	system := SystemPrompt(context)
	return requestPayload{system: system, user: query}
}

// ---- shared helpers ----

func postJSON(ctx context.Context, client *http.Client, url string, headers map[string]string, payload any) ([]byte, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("Error: failed to build request: %v", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("Error: failed to build request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := client.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("Error: failed to connect to API: %v", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("Error: failed to read response: %v", err)
	}
	if resp.StatusCode >= 400 {
		if msg := errorMessage(data); msg != "" {
			return nil, fmt.Errorf("API Error: %s", msg)
		}
		return nil, fmt.Errorf("API Error: HTTP %d", resp.StatusCode)
	}
	return data, nil
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type openAIResponse struct {
	Choices []struct {
		Message chatMessage `json:"message"`
	} `json:"choices"`
}

// ---- anthropic ----

type anthropicPayload struct {
	Model     string        `json:"model"`
	MaxTokens int           `json:"max_tokens"`
	System    string        `json:"system"`
	Messages  []chatMessage `json:"messages"`
}

type anthropicResponse struct {
	Content []struct {
		Text string `json:"text"`
	} `json:"content"`
}

func queryAnthropic(ctx context.Context, cfg Config, client *http.Client, query string) (string, error) {
	p := buildPayload(query)
	data, err := postJSON(ctx, client, cfg.AnthropicURL, map[string]string{
		"x-api-key":         os.Getenv("ANTHROPIC_API_KEY"),
		"anthropic-version": "2023-06-01",
	}, anthropicPayload{
		Model:     cfg.AnthropicModel,
		MaxTokens: 256,
		System:    p.system,
		Messages:  []chatMessage{{Role: "user", Content: p.user}},
	})
	if err != nil {
		return "", err
	}
	var resp anthropicResponse
	if err := json.Unmarshal(data, &resp); err != nil || len(resp.Content) == 0 || resp.Content[0].Text == "" {
		return "", fmt.Errorf("Error: unable to parse response")
	}
	return cleanResult(resp.Content[0].Text, false), nil
}

// ---- openai-compatible (openai, qwen, mistral, grok) ----

type openAIPayload struct {
	Model               string        `json:"model"`
	Messages            []chatMessage `json:"messages"`
	MaxCompletionTokens int           `json:"max_completion_tokens,omitempty"`
	MaxTokens           int           `json:"max_tokens,omitempty"`
	Temperature         *float64      `json:"temperature,omitempty"`
	ReasoningEffort     string        `json:"reasoning_effort,omitempty"`
	ChatTemplateKwargs  *chatTemplate `json:"chat_template_kwargs,omitempty"`
}

type chatTemplate struct {
	EnableThinking bool `json:"enable_thinking"`
}

func queryOpenAI(ctx context.Context, cfg Config, client *http.Client, query string) (string, error) {
	p := buildPayload(query)

	payload := openAIPayload{
		Model:    cfg.OpenAIModel,
		Messages: []chatMessage{{Role: "system", Content: p.system}, {Role: "user", Content: p.user}},
	}
	// Older models use max_tokens; newer ones reject it in favor of
	// max_completion_tokens.
	if strings.HasPrefix(cfg.OpenAIModel, "gpt-4") || strings.HasPrefix(cfg.OpenAIModel, "gpt-3.5") {
		payload.MaxTokens = 256
	} else {
		payload.MaxCompletionTokens = 256
	}
	// Reasoning models reject non-default temperature.
	if supportsTemperature(cfg.OpenAIModel) {
		t := 0.3
		payload.Temperature = &t
	}
	switch cfg.OpenAIThinking {
	case "0":
		payload.ChatTemplateKwargs = &chatTemplate{EnableThinking: false}
	case "1":
		payload.ChatTemplateKwargs = &chatTemplate{EnableThinking: true}
	}
	payload.ReasoningEffort = cfg.OpenAIReasoningEffort

	headers := map[string]string{}
	if key := openAIKey(); key != "" {
		headers["Authorization"] = "Bearer " + key
	}

	data, err := postJSON(ctx, client, cfg.OpenAIURL, headers, payload)
	if err != nil {
		return "", err
	}
	return parseOpenAIResponse(data)
}

func queryQwen(ctx context.Context, cfg Config, client *http.Client, query string) (string, error) {
	p := buildPayload(query)
	t := 0.3
	data, err := postJSON(ctx, client, cfg.QwenURL, map[string]string{
		"Authorization": "Bearer " + os.Getenv("QWEN_API_KEY"),
	}, openAIPayload{
		Model:       cfg.QwenModel,
		Messages:    []chatMessage{{Role: "system", Content: p.system}, {Role: "user", Content: p.user}},
		MaxTokens:   256,
		Temperature: &t,
	})
	if err != nil {
		return "", err
	}
	return parseOpenAIResponse(data)
}

func queryMistral(ctx context.Context, cfg Config, client *http.Client, query string) (string, error) {
	p := buildPayload(query)
	t := 0.3
	data, err := postJSON(ctx, client, cfg.MistralURL, map[string]string{
		"Authorization": "Bearer " + os.Getenv("MISTRAL_API_KEY"),
	}, openAIPayload{
		Model:       cfg.MistralModel,
		Messages:    []chatMessage{{Role: "system", Content: p.system}, {Role: "user", Content: p.user}},
		MaxTokens:   256,
		Temperature: &t,
	})
	if err != nil {
		return "", err
	}
	return parseOpenAIResponse(data)
}

func queryGrok(ctx context.Context, cfg Config, client *http.Client, query string) (string, error) {
	p := buildPayload(query)
	t := 0.3
	data, err := postJSON(ctx, client, cfg.GrokURL, map[string]string{
		"Authorization": "Bearer " + os.Getenv("XAI_API_KEY"),
	}, openAIPayload{
		Model:               cfg.GrokModel,
		Messages:            []chatMessage{{Role: "system", Content: p.system}, {Role: "user", Content: p.user}},
		MaxCompletionTokens: 256,
		Temperature:         &t,
		ReasoningEffort:     "none",
	})
	if err != nil {
		return "", err
	}
	return parseOpenAIResponse(data)
}

func parseOpenAIResponse(data []byte) (string, error) {
	var resp openAIResponse
	if err := json.Unmarshal(data, &resp); err != nil || len(resp.Choices) == 0 || resp.Choices[0].Message.Content == "" {
		return "", fmt.Errorf("Error: unable to parse response")
	}
	return cleanResult(resp.Choices[0].Message.Content, false), nil
}

// supportsTemperature mirrors _bash_ai_openai_supports_temperature:
// gpt-5*/o1*/o3*/o4* reasoning models reject non-default temperatures.
func supportsTemperature(model string) bool {
	for _, prefix := range []string{"gpt-5", "o1", "o3", "o4"} {
		if strings.HasPrefix(model, prefix) {
			return false
		}
	}
	return true
}

func openAIKey() string {
	if k := os.Getenv("BASH_AI_OPENAI_API_KEY"); k != "" {
		return k
	}
	return os.Getenv("OPENAI_API_KEY")
}

// ---- gemini ----

type geminiPayload struct {
	Contents []struct {
		Role  string `json:"role"`
		Parts []struct {
			Text string `json:"text"`
		} `json:"parts"`
	} `json:"contents"`
	SystemInstruction struct {
		Parts []struct {
			Text string `json:"text"`
		} `json:"parts"`
	} `json:"systemInstruction"`
	GenerationConfig struct {
		Temperature     float64 `json:"temperature"`
		MaxOutputTokens int     `json:"maxOutputTokens"`
		ThinkingConfig  struct {
			ThinkingBudget int `json:"thinkingBudget"`
		} `json:"thinkingConfig"`
	} `json:"generationConfig"`
}

type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
}

func queryGemini(ctx context.Context, cfg Config, client *http.Client, query string) (string, error) {
	p := buildPayload(query)
	var payload geminiPayload
	payload.Contents = append(payload.Contents, struct {
		Role  string `json:"role"`
		Parts []struct {
			Text string `json:"text"`
		} `json:"parts"`
	}{Role: "user", Parts: []struct {
		Text string `json:"text"`
	}{{Text: p.user}}})
	payload.SystemInstruction.Parts = append(payload.SystemInstruction.Parts, struct {
		Text string `json:"text"`
	}{Text: p.system})
	payload.GenerationConfig.Temperature = 0.3
	payload.GenerationConfig.MaxOutputTokens = 256
	payload.GenerationConfig.ThinkingConfig.ThinkingBudget = 0

	url := fmt.Sprintf("%s/v1beta/models/%s:generateContent?key=%s",
		geminiBase, cfg.GeminiModel, os.Getenv("GEMINI_API_KEY"))

	data, err := postJSON(ctx, client, url, nil, payload)
	if err != nil {
		return "", err
	}
	var resp geminiResponse
	if err := json.Unmarshal(data, &resp); err != nil || len(resp.Candidates) == 0 ||
		len(resp.Candidates[0].Content.Parts) == 0 || resp.Candidates[0].Content.Parts[0].Text == "" {
		return "", fmt.Errorf("Error: unable to parse response")
	}
	return cleanResult(resp.Candidates[0].Content.Parts[0].Text, false), nil
}

// ---- ollama ----

type ollamaGeneratePayload struct {
	Model   string  `json:"model"`
	Prompt  string  `json:"prompt"`
	System  string  `json:"system"`
	Stream  bool    `json:"stream"`
	Think   bool    `json:"think"`
	Options options `json:"options"`
}

type options struct {
	Temperature float64 `json:"temperature"`
}

type ollamaResponse struct {
	Response string `json:"response"`
}

// CheckOllama verifies the Ollama server is reachable, mirroring
// _bash_ai_check_ollama.
func CheckOllama(ctx context.Context, client *http.Client, cfg Config) error {
	if client == nil {
		client = DefaultClient
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, cfg.OllamaURL+"/api/tags", nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("Error: Ollama is not reachable at %s\nStart Ollama with: ollama serve\nIf it's already running, BASH_AI_OLLAMA_URL must be the base URL (e.g. http://localhost:11434, no /v1)", cfg.OllamaURL)
	}
	resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("Error: Ollama is not reachable at %s", cfg.OllamaURL)
	}
	return nil
}

func queryOllama(ctx context.Context, cfg Config, client *http.Client, query string) (string, error) {
	if err := CheckOllama(ctx, client, cfg); err != nil {
		return "", err
	}
	p := buildPayload(query)
	data, err := postJSON(ctx, client, cfg.OllamaURL+"/api/generate", nil, ollamaGeneratePayload{
		Model:   cfg.OllamaModel,
		Prompt:  p.user,
		System:  p.system,
		Stream:  false,
		Think:   false,
		Options: options{Temperature: 0.3},
	})
	if err != nil {
		return "", err
	}
	var resp ollamaResponse
	if err := json.Unmarshal(data, &resp); err != nil || resp.Response == "" {
		var m struct {
			Error string `json:"error"`
		}
		json.Unmarshal(data, &m)
		if m.Error != "" {
			return "", fmt.Errorf("Ollama Error: %s", m.Error)
		}
		return "", fmt.Errorf("Error: unable to parse Ollama response")
	}
	return cleanResult(resp.Response, true), nil
}
