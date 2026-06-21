package sso

import (
	"errors"
	"fmt"
	"os"
	"regexp"
	"strings"

	"gopkg.in/ini.v1"
)

// Naming schemes for generated profile names, selectable on the command line.
const (
	NameAccountRole   = "account-role"
	NameAccountIDRole = "accountid-role"
	NameAccount       = "account"
)

// NamingSchemes lists the accepted --naming values (for help text/validation).
var NamingSchemes = []string{NameAccountRole, NameAccountIDRole, NameAccount}

var unsafeChars = regexp.MustCompile(`[^a-z0-9-]+`)

// sanitize lowercases s and collapses any run of unsafe characters into a
// single dash, trimming leading/trailing dashes — yielding a clean profile
// name fragment.
func sanitize(s string) string {
	s = unsafeChars.ReplaceAllString(strings.ToLower(s), "-")
	return strings.Trim(s, "-")
}

// ProfileName builds the profile name for ar under the given scheme. multiRole
// indicates the account has more than one role, which the "account" scheme
// uses to decide whether to disambiguate with the role name.
func ProfileName(scheme string, ar AccountRole, multiRole bool) (string, error) {
	switch scheme {
	case NameAccountRole:
		return sanitize(ar.AccountName) + "-" + sanitize(ar.RoleName), nil
	case NameAccountIDRole:
		return ar.AccountID + "-" + sanitize(ar.RoleName), nil
	case NameAccount:
		if multiRole {
			return sanitize(ar.AccountName) + "-" + sanitize(ar.RoleName), nil
		}
		return sanitize(ar.AccountName), nil
	default:
		return "", fmt.Errorf("unknown naming scheme %q (want one of %s)", scheme, strings.Join(NamingSchemes, ", "))
	}
}

// NamedProfile is a profile to write: its config name plus the account/role it
// points at.
type NamedProfile struct {
	Name      string
	AccountID string
	RoleName  string
}

// WriteConfig merges an [sso-session] block and one [profile] block per entry
// into the AWS config file at path, preserving every other section. The
// existing file (if any) is backed up to path+".bak" first. Re-running with
// the same inputs is idempotent.
func WriteConfig(path string, sess SSOSession, defaultRegion string, profiles []NamedProfile) error {
	cfg, err := ini.Load(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("read %s: %w", path, err)
		}
		cfg = ini.Empty()
	} else if err := backup(path); err != nil {
		return err
	}

	s := cfg.Section("sso-session " + sess.Name)
	s.Key("sso_start_url").SetValue(sess.StartURL)
	s.Key("sso_region").SetValue(sess.Region)
	s.Key("sso_registration_scopes").SetValue("sso:account:access")

	for _, p := range profiles {
		sec := cfg.Section("profile " + p.Name)
		sec.Key("sso_session").SetValue(sess.Name)
		sec.Key("sso_account_id").SetValue(p.AccountID)
		sec.Key("sso_role_name").SetValue(p.RoleName)
		sec.Key("region").SetValue(defaultRegion)
	}

	if err := cfg.SaveTo(path); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

func backup(path string) error {
	body, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s for backup: %w", path, err)
	}
	if err := os.WriteFile(path+".bak", body, 0o600); err != nil {
		return fmt.Errorf("write backup %s.bak: %w", path, err)
	}
	return nil
}
