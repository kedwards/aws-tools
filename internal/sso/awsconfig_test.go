package sso

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"gopkg.in/ini.v1"
)

func TestProfileName(t *testing.T) {
	ar := AccountRole{AccountID: "111122223333", AccountName: "Acme Prod", RoleName: "AdminAccess"}
	cases := []struct {
		scheme    string
		multiRole bool
		want      string
	}{
		{NameAccountRole, false, "acme-prod-adminaccess"},
		{NameAccountIDRole, false, "111122223333-adminaccess"},
		{NameAccount, false, "acme-prod"},
		{NameAccount, true, "acme-prod-adminaccess"}, // disambiguate when multiple roles
	}
	for _, tc := range cases {
		got, err := ProfileName(tc.scheme, ar, tc.multiRole)
		require.NoError(t, err)
		require.Equal(t, tc.want, got)
	}

	_, err := ProfileName("bogus", ar, false)
	require.Error(t, err)
}

func TestWriteConfig_PreservesExistingAndIsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config")
	require.NoError(t, os.WriteFile(path, []byte("[profile keep]\nregion = eu-west-1\n"), 0o600))

	sess := SSOSession{Name: "acme", Region: "us-east-1", StartURL: "https://acme.awsapps.com/start"}
	profiles := []NamedProfile{
		{Name: "acme-prod-admin", AccountID: "111", RoleName: "Admin"},
		{Name: "acme-dev-ro", AccountID: "222", RoleName: "ReadOnly"},
	}

	require.NoError(t, WriteConfig(path, sess, "us-east-1", profiles))

	// Backup of the original content exists.
	bak, err := os.ReadFile(path + ".bak")
	require.NoError(t, err)
	require.Contains(t, string(bak), "[profile keep]")

	cfg, err := ini.Load(path)
	require.NoError(t, err)
	require.Equal(t, "eu-west-1", cfg.Section("profile keep").Key("region").String(), "unrelated profile preserved")
	require.Equal(t, "https://acme.awsapps.com/start", cfg.Section("sso-session acme").Key("sso_start_url").String())
	require.Equal(t, "111", cfg.Section("profile acme-prod-admin").Key("sso_account_id").String())
	require.Equal(t, "acme", cfg.Section("profile acme-dev-ro").Key("sso_session").String())

	// Re-running with the same inputs produces an identical file.
	first, err := os.ReadFile(path)
	require.NoError(t, err)
	require.NoError(t, WriteConfig(path, sess, "us-east-1", profiles))
	second, err := os.ReadFile(path)
	require.NoError(t, err)
	require.Equal(t, string(first), string(second), "WriteConfig should be idempotent")
}
