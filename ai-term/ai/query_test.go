package ai

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// serve returns an httptest server whose handler validates the request
// (method, content type, auth header) and replies with body.
func serve(t *testing.T, wantAuth string, status int, body string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("method = %s, want POST", r.Method)
		}
		if ct := r.Header.Get("Content-Type"); ct != "application/json" {
			t.Errorf("content-type = %q, want application/json", ct)
		}
		if wantAuth != "" {
			got := r.Header.Get("Authorization")
			if got != "Bearer "+wantAuth {
				t.Errorf("authorization = %q, want Bearer %s", got, wantAuth)
			}
		}
		w.WriteHeader(status)
		w.Write([]byte(body))
	}))
}

func queryWithServer(t *testing.T, status int, body string, cfg Config) (string, error) {
	t.Helper()
	srv := serve(t, "", status, body)
	defer srv.Close()
	cfg.setURLs(srv.URL)
	return Query(context.Background(), cfg, srv.Client(), "list files")
}

func TestQueryAnthropic(t *testing.T) {
	t.Setenv("ANTHROPIC_API_KEY", "test-key")
	cfg := Config{Provider: "anthropic", AnthropicModel: "claude-haiku-4-5"}

	got, err := queryWithServer(t, http.StatusOK, `{"content":[{"type":"text","text":"ls -la"}]}`, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "ls -la" {
		t.Errorf("got %q, want %q", got, "ls -la")
	}
}

func TestQueryAnthropicEmptyContent(t *testing.T) {
	t.Setenv("ANTHROPIC_API_KEY", "test-key")
	cfg := Config{Provider: "anthropic", AnthropicModel: "m"}

	_, err := queryWithServer(t, http.StatusOK, `{"content":[]}`, cfg)
	if err == nil || !strings.Contains(err.Error(), "unable to parse") {
		t.Errorf("want parse error, got %v", err)
	}
}

func TestQueryAnthropicAPIError(t *testing.T) {
	t.Setenv("ANTHROPIC_API_KEY", "test-key")
	cfg := Config{Provider: "anthropic", AnthropicModel: "m"}

	_, err := queryWithServer(t, http.StatusBadRequest, `{"error":{"message":"bad key"}}`, cfg)
	if err == nil || !strings.Contains(err.Error(), "API Error: bad key") {
		t.Errorf("want API Error: bad key, got %v", err)
	}
}

func TestQueryOpenAI(t *testing.T) {
	t.Setenv("OPENAI_API_KEY", "test-key")
	cfg := Config{Provider: "openai", OpenAIModel: "gpt-5.4-mini"}

	got, err := queryWithServer(t, http.StatusOK, `{"choices":[{"message":{"content":"find . -name '*.go'"}}]}`, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "find . -name '*.go'" {
		t.Errorf("got %q", got)
	}
}

func TestQueryOpenAIMultilineCleanup(t *testing.T) {
	t.Setenv("OPENAI_API_KEY", "test-key")
	cfg := Config{Provider: "openai", OpenAIModel: "gpt-5.4-mini"}

	got, err := queryWithServer(t, http.StatusOK, `{"choices":[{"message":{"content":"ls -la\n\n  "}}]}`, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "ls -la" {
		t.Errorf("got %q, want %q", got, "ls -la")
	}
}

func TestQueryOpenAIError(t *testing.T) {
	t.Setenv("OPENAI_API_KEY", "test-key")
	cfg := Config{Provider: "openai", OpenAIModel: "m"}

	_, err := queryWithServer(t, http.StatusTooManyRequests, `{"error":{"message":"rate limited"}}`, cfg)
	if err == nil || !strings.Contains(err.Error(), "API Error: rate limited") {
		t.Errorf("want API Error: rate limited, got %v", err)
	}
}

func TestQueryGrok(t *testing.T) {
	t.Setenv("XAI_API_KEY", "test-key")
	cfg := Config{Provider: "grok", GrokModel: "grok-4.3"}

	got, err := queryWithServer(t, http.StatusOK, `{"choices":[{"message":{"content":"du -sh"}}]}`, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "du -sh" {
		t.Errorf("got %q", got)
	}
}

func TestQueryQwen(t *testing.T) {
	t.Setenv("QWEN_API_KEY", "test-key")
	cfg := Config{Provider: "qwen", QwenModel: "qwen-flash"}

	got, err := queryWithServer(t, http.StatusOK, `{"choices":[{"message":{"content":"ls"}}]}`, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "ls" {
		t.Errorf("got %q", got)
	}
}

func TestQueryMistral(t *testing.T) {
	t.Setenv("MISTRAL_API_KEY", "test-key")
	cfg := Config{Provider: "mistral", MistralModel: "mistral-small-latest"}

	got, err := queryWithServer(t, http.StatusOK, `{"choices":[{"message":{"content":"pwd"}}]}`, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "pwd" {
		t.Errorf("got %q", got)
	}
}

func TestQueryGemini(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "test-key")
	old := geminiBase
	geminiBase = "https://generativelanguage.googleapis.com"
	defer func() { geminiBase = old }()

	srv := serve(t, "", http.StatusOK, `{"candidates":[{"content":{"parts":[{"text":"whoami"}]}}]}`)
	defer srv.Close()
	geminiBase = srv.URL
	cfg := Config{Provider: "gemini", GeminiModel: "gemini-2.5-flash"}

	got, err := Query(context.Background(), cfg, srv.Client(), "list files")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "whoami" {
		t.Errorf("got %q", got)
	}
}

func TestQueryGeminiError(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "test-key")
	srv := serve(t, "", http.StatusBadRequest, `{"error":{"message":"quota exceeded"}}`)
	defer srv.Close()
	old := geminiBase
	geminiBase = srv.URL
	defer func() { geminiBase = old }()

	cfg := Config{Provider: "gemini", GeminiModel: "m"}
	_, err := Query(context.Background(), cfg, srv.Client(), "list files")
	if err == nil || !strings.Contains(err.Error(), "API Error: quota exceeded") {
		t.Errorf("want API Error: quota exceeded, got %v", err)
	}
}

func TestQueryOllama(t *testing.T) {
	t.Setenv("BASH_AI_OLLAMA_URL", "")
	cfg := Config{Provider: "ollama", OllamaModel: "llama3.2"}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodPost {
			t.Errorf("method = %s", r.Method)
		}
		switch r.URL.Path {
		case "/api/tags":
			w.Write([]byte(`{"models":[]}`))
		case "/api/generate":
			w.Write([]byte("{\"response\":\"```\\nls -la\\n```\"}"))
		default:
			t.Errorf("unexpected path %s", r.URL.Path)
		}
	}))
	defer srv.Close()
	cfg.OllamaURL = srv.URL

	got, err := Query(context.Background(), cfg, srv.Client(), "list files")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "ls -la" {
		t.Errorf("got %q, want %q (fences stripped)", got, "ls -la")
	}
}

func TestQueryOllamaUnreachable(t *testing.T) {
	t.Setenv("BASH_AI_OLLAMA_URL", "")
	cfg := Config{Provider: "ollama", OllamaModel: "m"}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()
	cfg.OllamaURL = srv.URL

	_, err := Query(context.Background(), cfg, srv.Client(), "list files")
	if err == nil || !strings.Contains(err.Error(), "Ollama is not reachable") {
		t.Errorf("want reachability error, got %v", err)
	}
}

func TestQueryCustomUnsupported(t *testing.T) {
	cfg := Config{Provider: "custom"}
	_, err := Query(context.Background(), cfg, nil, "hi")
	if err == nil || !strings.Contains(err.Error(), "custom") {
		t.Errorf("want custom provider error, got %v", err)
	}
}

func TestQueryDefaultsToAnthropic(t *testing.T) {
	t.Setenv("ANTHROPIC_API_KEY", "test-key")
	var cfg Config // zero value -> anthropic

	got, err := queryWithServer(t, http.StatusOK, `{"content":[{"type":"text","text":"echo hi"}]}`, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "echo hi" {
		t.Errorf("got %q", got)
	}
}

// setURLs points every config URL at the test server; only the provider
// under test actually receives requests.
func (c *Config) setURLs(base string) {
	c.AnthropicURL = base
	c.OpenAIURL = base
	c.QwenURL = base
	c.MistralURL = base
	c.GrokURL = base
	c.OllamaURL = base
}
