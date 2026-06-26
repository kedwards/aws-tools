package console

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/kedwards/awst/v3/internal/paths"
)

// GrantedContainerInstalled reports whether the Granted Containers Firefox
// extension is installed in any local Firefox profile. Detection is best-effort
// (a missing/unreadable profile just means "not found") and is used to decide
// whether `awst console` opens a container tab by default.
func GrantedContainerInstalled() bool {
	for _, g := range firefoxExtensionGlobs() {
		matches, err := filepath.Glob(g)
		if err != nil {
			continue
		}
		for _, m := range matches {
			if grantedInExtensionsFile(m) {
				return true
			}
		}
	}
	return false
}

// firefoxExtensionGlobs returns the per-OS globs that match every Firefox
// profile's extensions.json.
func firefoxExtensionGlobs() []string {
	switch runtime.GOOS {
	case "darwin":
		return []string{filepath.Join(paths.HomeDir(), "Library", "Application Support", "Firefox", "Profiles", "*", "extensions.json")}
	case "windows":
		base := os.Getenv("APPDATA")
		if base == "" {
			return nil
		}
		return []string{filepath.Join(base, "Mozilla", "Firefox", "Profiles", "*", "extensions.json")}
	default:
		return []string{filepath.Join(paths.HomeDir(), ".mozilla", "firefox", "*", "extensions.json")}
	}
}

// grantedInExtensionsFile reports whether the Firefox extensions.json at path
// lists an active add-on whose name contains "granted" (case-insensitive) —
// i.e. the Granted Containers extension. Matching on "granted" tolerates name
// variants while excluding the unrelated "AWS SSO Containers" extension.
func grantedInExtensionsFile(path string) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	var f struct {
		Addons []struct {
			Active        bool `json:"active"`
			DefaultLocale struct {
				Name string `json:"name"`
			} `json:"defaultLocale"`
		} `json:"addons"`
	}
	if err := json.Unmarshal(b, &f); err != nil {
		return false
	}
	for _, a := range f.Addons {
		if a.Active && strings.Contains(strings.ToLower(a.DefaultLocale.Name), "granted") {
			return true
		}
	}
	return false
}
