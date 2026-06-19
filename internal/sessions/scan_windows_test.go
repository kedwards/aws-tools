//go:build windows

package sessions

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// These exercise the real shell32 CommandLineToArgvW syscall — runs only on
// the windows CI runner, where it actually matters.

func TestCommandLineToArgv_PluginShape(t *testing.T) {
	// The plugin's argv as awst/the AWS CLI pass it: space-free JSON blobs.
	got := commandLineToArgv(`C:\bin\session-manager-plugin.exe {"SessionId":"s"} us-east-1 StartSession dev {"Target":"i-1"} https://ep`)
	require.Equal(t, []string{
		`C:\bin\session-manager-plugin.exe`,
		`{"SessionId":"s"}`,
		"us-east-1",
		"StartSession",
		"dev",
		`{"Target":"i-1"}`,
		"https://ep",
	}, got)
}

func TestCommandLineToArgv_Quoting(t *testing.T) {
	require.Equal(t, []string{"prog.exe", "a b", "c"}, commandLineToArgv(`prog.exe "a b" c`))
}

func TestCommandLineToArgv_Empty(t *testing.T) {
	require.Nil(t, commandLineToArgv(""))
}
