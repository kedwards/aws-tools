package cmd

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/spf13/cobra"
)

// version is overridden at build time via
// -ldflags "-X github.com/kedwards/awst/v3/cmd.version=<v>".
// When that is not set (plain `go build` / `go install ...@vX`), fall back to
// the module version recorded in the binary's build info so installed builds
// still report the right version instead of "dev".
var version = "dev"

func init() {
	if version != "dev" {
		return
	}
	if info, ok := debug.ReadBuildInfo(); ok {
		if v := info.Main.Version; v != "" && v != "(devel)" {
			version = v
		}
	}
}

func NewRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:           "awst",
		Short:         "AWS toolkit (Go port)",
		SilenceUsage:  true,
		SilenceErrors: true,
		Version:       version,
	}
	root.AddCommand(newCredsCmd(defaultDeps()))
	root.AddCommand(newLoginCmd(defaultLoginDeps()))
	root.AddCommand(newSSOCmd(defaultSSODeps()))
	root.AddCommand(newConnectCmd(defaultConnectDeps()))
	root.AddCommand(newExecCmd(defaultExecDeps()))
	root.AddCommand(newRunCmd(defaultRunDeps()))
	sd := defaultSessionsDeps()
	root.AddCommand(newListCmd(sd))
	root.AddCommand(newKillCmd(sd))
	root.AddCommand(newConfigCmd())
	root.AddCommand(newShellCmd())
	root.AddCommand(newConsoleCmd(defaultConsoleDeps()))
	root.AddCommand(newLogoutCmd(defaultLogoutDeps()))
	return root
}

func Execute() {
	if err := NewRootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
