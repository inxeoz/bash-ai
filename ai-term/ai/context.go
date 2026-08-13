package ai

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// BuildContext gathers directory, project, git, and OS context for the
// prompt. Port of lib/context.zsh (_zsh_ai_build_context).
func BuildContext() string {
	var parts []string
	parts = append(parts, directoryContext())
	if pt := projectType(); pt != "unknown" {
		parts = append(parts, "Project type: "+pt)
	}
	if gc := gitContext(); gc != "" {
		parts = append(parts, gc)
	}
	parts = append(parts, "OS: "+runtimeOS())
	return strings.Join(parts, "\n")
}

func directoryContext() string {
	wd, err := os.Getwd()
	if err != nil {
		wd = "?"
	}
	ctx := "Current directory: " + wd

	entries, err := os.ReadDir(".")
	if err != nil {
		return ctx
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if len(names) <= 20 {
		if len(names) > 0 {
			list := names
			if len(list) > 10 {
				list = names[:10]
			}
			ctx += "\nFiles: " + strings.Join(list, ", ")
			if len(names) > 10 {
				ctx += fmt.Sprintf(" ... and %d more", len(names)-10)
			}
		}
	} else {
		ctx += fmt.Sprintf("\nFiles: %d files in directory", len(names))
	}
	return ctx
}

func projectType() string {
	for _, f := range []struct {
		marker string
		pt     string
	}{
		{"package.json", "node"},
		{"Cargo.toml", "rust"},
		{"requirements.txt", "python"},
		{"setup.py", "python"},
		{"pyproject.toml", "python"},
		{"Gemfile", "ruby"},
		{"go.mod", "go"},
		{"composer.json", "php"},
		{"pom.xml", "java"},
		{"build.gradle", "java"},
		{"docker-compose.yml", "docker"},
		{"Dockerfile", "docker"},
	} {
		if _, err := os.Stat(f.marker); err == nil {
			return f.pt
		}
	}
	return "unknown"
}

func gitContext() string {
	if _, err := exec.LookPath("git"); err != nil {
		return ""
	}
	cmd := exec.Command("git", "rev-parse", "--is-inside-work-tree")
	if err := cmd.Run(); err != nil {
		return ""
	}

	branch, _ := exec.Command("git", "branch", "--show-current").Output()
	status := "clean"
	if out, _ := exec.Command("git", "status", "--porcelain").Output(); len(out) > 0 {
		status = "dirty"
	}
	return fmt.Sprintf("Git: branch=%s, status=%s", strings.TrimSpace(string(branch)), status)
}

func runtimeOS() string {
	if v := os.Getenv("OSTYPE"); v != "" {
		return v
	}
	return runtime.GOOS
}
