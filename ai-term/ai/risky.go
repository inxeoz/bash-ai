package ai

import "strings"

// IsRisky reports whether a generated command matches patterns that
// deserve a second confirmation before it is handed to the shell:
// destructive operations, privilege escalation, force-pushes, and
// pipe-to-shell installers.
func IsRisky(cmd string) bool {
	for _, pat := range []string{
		"rm -rf",
		":(){",
		"sudo ",
		"git push -f",
		"git push --force",
		"dd if=",
		"| sh",
		"| bash",
		"> /dev/sda",
	} {
		if strings.Contains(cmd, pat) {
			return true
		}
	}
	return false
}
