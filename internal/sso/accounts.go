package sso

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	awssso "github.com/aws/aws-sdk-go-v2/service/sso"
)

// Portal is the subset of the SSO portal API used to enumerate the accounts
// and roles an access token grants. Kept local so tests can stub it.
type Portal interface {
	ListAccounts(ctx context.Context, in *awssso.ListAccountsInput, optFns ...func(*awssso.Options)) (*awssso.ListAccountsOutput, error)
	ListAccountRoles(ctx context.Context, in *awssso.ListAccountRolesInput, optFns ...func(*awssso.Options)) (*awssso.ListAccountRolesOutput, error)
}

// AccountRole is one account/role pairing the user can assume.
type AccountRole struct {
	AccountID   string
	AccountName string
	RoleName    string
}

// ListAccountRoles enumerates every account (ListAccounts) and every role
// within each account (ListAccountRoles) reachable with accessToken, flattened
// and paginated.
func ListAccountRoles(ctx context.Context, p Portal, accessToken string) ([]AccountRole, error) {
	var out []AccountRole

	var acctTok *string
	for {
		accts, err := p.ListAccounts(ctx, &awssso.ListAccountsInput{
			AccessToken: aws.String(accessToken),
			NextToken:   acctTok,
		})
		if err != nil {
			return nil, fmt.Errorf("list accounts: %w", err)
		}
		for _, a := range accts.AccountList {
			id, name := aws.ToString(a.AccountId), aws.ToString(a.AccountName)

			var roleTok *string
			for {
				roles, err := p.ListAccountRoles(ctx, &awssso.ListAccountRolesInput{
					AccessToken: aws.String(accessToken),
					AccountId:   a.AccountId,
					NextToken:   roleTok,
				})
				if err != nil {
					return nil, fmt.Errorf("list roles for account %s: %w", id, err)
				}
				for _, r := range roles.RoleList {
					out = append(out, AccountRole{
						AccountID:   id,
						AccountName: name,
						RoleName:    aws.ToString(r.RoleName),
					})
				}
				if roles.NextToken == nil {
					break
				}
				roleTok = roles.NextToken
			}
		}
		if accts.NextToken == nil {
			break
		}
		acctTok = accts.NextToken
	}
	return out, nil
}
