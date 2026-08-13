package ai

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func chdir(t *testing.T, dir string) {
	t.Helper()
	old, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chdir(old) })
}

func TestBuildContextIncludesDirectoryAndFiles(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(dir, "b.txt"), []byte("x"), 0o644)
	chdir(t, dir)

	ctx := BuildContext()
	if !strings.Contains(ctx, "Current directory: "+dir) {
		t.Errorf("missing directory context: %s", ctx)
	}
	if !strings.Contains(ctx, "Files: a.txt, b.txt") {
		t.Errorf("missing file listing: %s", ctx)
	}
	if !strings.Contains(ctx, "OS: ") {
		t.Errorf("missing OS context: %s", ctx)
	}
}

func TestBuildContextManyFiles(t *testing.T) {
	dir := t.TempDir()
	for i := 0; i < 25; i++ {
		os.WriteFile(filepath.Join(dir, "f"+string(rune('a'+i))+".txt"), []byte("x"), 0o644)
	}
	chdir(t, dir)

	ctx := BuildContext()
	if !strings.Contains(ctx, "25 files in directory") {
		t.Errorf("expected count message, got: %s", ctx)
	}
}

func TestBuildContextProjectType(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "package.json"), []byte("{}"), 0o644)
	chdir(t, dir)

	ctx := BuildContext()
	if !strings.Contains(ctx, "Project type: node") {
		t.Errorf("expected node project type, got: %s", ctx)
	}
}

func TestBuildContextGitRepo(t *testing.T) {
	if _, err := os.Stat("/usr/bin/git"); err != nil {
		t.Skip("git not available")
	}
	dir := t.TempDir()
	run := func(name string, args ...string) {
		t.Helper()
		cmd := exec.Command(name, args...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%s %v: %v (%s)", name, args, err, out)
		}
	}
	run("git", "init", "-q", "-b", "test-branch")
	run("git", "config", "user.email", "t@t")
	run("git", "config", "user.name", "t")
	os.WriteFile(filepath.Join(dir, "f.txt"), []byte("x"), 0o644)
	run("git", "add", "f.txt")
	chdir(t, dir)

	ctx := BuildContext()
	if !strings.Contains(ctx, "Git: branch=test-branch, status=dirty") {
		t.Errorf("expected dirty git context, got: %s", ctx)
	}

	run("git", "commit", "-q", "-m", "init")
	ctx = BuildContext()
	if !strings.Contains(ctx, "Git: branch=test-branch, status=clean") {
		t.Errorf("expected clean git context, got: %s", ctx)
	}
}

func TestSystemPrompt(t *testing.T) {
	ctx := BuildContext()
	p := SystemPrompt(ctx)
	for _, want := range []string{
		"bash command generator",
		"Output ONLY the raw command",
		"Context:",
	} {
		if !strings.Contains(p, want) {
			t.Errorf("prompt missing %q", want)
		}
	}
}

func TestSystemPromptExtend(t *testing.T) {
	t.Setenv("BASH_AI_PROMPT_EXTEND", "Prefer rg over grep.")
	p := SystemPrompt("ctx")
	if !strings.Contains(p, "Prefer rg over grep.") {
		t.Errorf("prompt extension missing: %s", p)
	}
}
