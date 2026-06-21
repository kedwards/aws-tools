package cmd

import (
	"bytes"
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awssso "github.com/aws/aws-sdk-go-v2/service/sso"
	ssotypes "github.com/aws/aws-sdk-go-v2/service/sso/types"
	"github.com/spf13/cobra"
	"github.com/stretchr/testify/require"
	"gopkg.in/ini.v1"

	"github.com/kedwards/awst/v3/internal/sso"
)

type fakeSSOPortal struct{}

func (fakeSSOPortal) ListAccounts(_ context.Context, _ *awssso.ListAccountsInput, _ ...func(*awssso.Options)) (*awssso.ListAccountsOutput, error) {
	return &awssso.ListAccountsOutput{
		AccountList: []ssotypes.AccountInfo{{AccountId: aws.String("111122223333"), AccountName: aws.String("Acme Prod")}},
	}, nil
}

func (fakeSSOPortal) ListAccountRoles(_ context.Context, _ *awssso.ListAccountRolesInput, _ ...func(*awssso.Options)) (*awssso.ListAccountRolesOutput, error) {
	return &awssso.ListAccountRolesOutput{
		RoleList: []ssotypes.RoleInfo{{RoleName: aws.String("AdminAccess")}},
	}, nil
}

func runSSO(t *testing.T, d ssoDeps, args ...string) (stdout, stderr string, err error) {
	t.Helper()
	root := &cobra.Command{Use: "awst", SilenceUsage: true, SilenceErrors: true}
	root.AddCommand(newSSOCmd(d))
	var out, errBuf bytes.Buffer
	root.SetOut(&out)
	root.SetErr(&errBuf)
	root.SetArgs(args)
	err = root.Execute()
	return out.String(), errBuf.String(), err
}

func TestSSOConfigure_WritesProfiles(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config")
	cache := sso.NewCache(filepath.Join(t.TempDir(), "cache"))
	now := func() time.Time { return time.Date(2026, 6, 21, 12, 0, 0, 0, time.UTC) }

	// Pre-seed a valid token for the derived session "acme" so EnsureToken
	// short-circuits and no device flow / OIDC client is needed.
	require.NoError(t, cache.Save("acme", sso.Token{AccessToken: "atk", ExpiresAt: now().Add(time.Hour)}))

	d := ssoDeps{
		cache: cache,
		oidcFactory: func(context.Context, string) (sso.OIDCClient, error) {
			t.Fatal("oidcFactory must not be called when a valid token is cached")
			return nil, nil
		},
		portalFactory: func(context.Context, string) (sso.Portal, error) { return fakeSSOPortal{}, nil },
		openBrowser:   func(string) error { return nil },
		sleep:         func(time.Duration) {},
		now:           now,
		configPath:    func() string { return cfgPath },
	}

	_, stderr, err := runSSO(t, d, "sso", "configure",
		"--start-url", "https://acme.awsapps.com/start", "--sso-region", "us-east-1",
		"--naming", "accountid-role")
	require.NoError(t, err)
	require.Contains(t, stderr, "Wrote 1 profiles for 1 accounts")

	cfg, err := ini.Load(cfgPath)
	require.NoError(t, err)
	require.Equal(t, "https://acme.awsapps.com/start", cfg.Section("sso-session acme").Key("sso_start_url").String())
	sec := cfg.Section("profile 111122223333-adminaccess")
	require.Equal(t, "acme", sec.Key("sso_session").String())
	require.Equal(t, "111122223333", sec.Key("sso_account_id").String())
	require.Equal(t, "AdminAccess", sec.Key("sso_role_name").String())
	require.Equal(t, "us-east-1", sec.Key("region").String())
}

func TestSSOConfigure_RequiresFlags(t *testing.T) {
	d := defaultSSODeps()
	_, _, err := runSSO(t, d, "sso", "configure")
	require.Error(t, err)
	require.Contains(t, err.Error(), "required")
}

func TestSSOConfigure_RejectsBadNaming(t *testing.T) {
	d := defaultSSODeps()
	_, _, err := runSSO(t, d, "sso", "configure",
		"--start-url", "https://acme.awsapps.com/start", "--sso-region", "us-east-1", "--naming", "nope")
	require.Error(t, err)
	require.Contains(t, err.Error(), "invalid --naming")
}
