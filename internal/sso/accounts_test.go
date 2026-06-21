package sso

import (
	"context"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	awssso "github.com/aws/aws-sdk-go-v2/service/sso"
	ssotypes "github.com/aws/aws-sdk-go-v2/service/sso/types"
	"github.com/stretchr/testify/require"
)

// fakePortal returns two accounts (paginated across two pages); account 111 has
// two roles (also paginated), account 222 has one.
type fakePortal struct{}

func (fakePortal) ListAccounts(_ context.Context, in *awssso.ListAccountsInput, _ ...func(*awssso.Options)) (*awssso.ListAccountsOutput, error) {
	if in.NextToken == nil {
		return &awssso.ListAccountsOutput{
			AccountList: []ssotypes.AccountInfo{{AccountId: aws.String("111"), AccountName: aws.String("Acme Prod")}},
			NextToken:   aws.String("page2"),
		}, nil
	}
	return &awssso.ListAccountsOutput{
		AccountList: []ssotypes.AccountInfo{{AccountId: aws.String("222"), AccountName: aws.String("Acme Dev")}},
	}, nil
}

func (fakePortal) ListAccountRoles(_ context.Context, in *awssso.ListAccountRolesInput, _ ...func(*awssso.Options)) (*awssso.ListAccountRolesOutput, error) {
	if aws.ToString(in.AccountId) == "111" {
		if in.NextToken == nil {
			return &awssso.ListAccountRolesOutput{
				RoleList:  []ssotypes.RoleInfo{{RoleName: aws.String("Admin")}},
				NextToken: aws.String("r2"),
			}, nil
		}
		return &awssso.ListAccountRolesOutput{
			RoleList: []ssotypes.RoleInfo{{RoleName: aws.String("ReadOnly")}},
		}, nil
	}
	return &awssso.ListAccountRolesOutput{
		RoleList: []ssotypes.RoleInfo{{RoleName: aws.String("Dev")}},
	}, nil
}

func TestListAccountRoles_FlattensAndPaginates(t *testing.T) {
	got, err := ListAccountRoles(context.Background(), fakePortal{}, "atk")
	require.NoError(t, err)
	require.Equal(t, []AccountRole{
		{AccountID: "111", AccountName: "Acme Prod", RoleName: "Admin"},
		{AccountID: "111", AccountName: "Acme Prod", RoleName: "ReadOnly"},
		{AccountID: "222", AccountName: "Acme Dev", RoleName: "Dev"},
	}, got)
}
