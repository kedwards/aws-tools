package connect

import (
	"context"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/codebuild"
	cbtypes "github.com/aws/aws-sdk-go-v2/service/codebuild/types"
	"github.com/stretchr/testify/require"
)

type stubCodeBuild struct {
	ids        []string // ids ListBuildsForProject returns
	builds     []cbtypes.Build
	listInput  *codebuild.ListBuildsForProjectInput
	batchInput *codebuild.BatchGetBuildsInput
}

func (s *stubCodeBuild) ListBuildsForProject(_ context.Context, in *codebuild.ListBuildsForProjectInput, _ ...func(*codebuild.Options)) (*codebuild.ListBuildsForProjectOutput, error) {
	s.listInput = in
	return &codebuild.ListBuildsForProjectOutput{Ids: s.ids}, nil
}

func (s *stubCodeBuild) BatchGetBuilds(_ context.Context, in *codebuild.BatchGetBuildsInput, _ ...func(*codebuild.Options)) (*codebuild.BatchGetBuildsOutput, error) {
	s.batchInput = in
	return &codebuild.BatchGetBuildsOutput{Builds: s.builds}, nil
}

func debugBuild(id, target string) cbtypes.Build {
	return cbtypes.Build{
		Id:           aws.String(id),
		BuildStatus:  cbtypes.StatusTypeInProgress,
		CurrentPhase: aws.String("BUILD"),
		DebugSession: &cbtypes.DebugSession{SessionEnabled: aws.Bool(true), SessionTarget: aws.String(target)},
	}
}

func TestListDebugBuilds_FiltersNonDebug(t *testing.T) {
	c := &stubCodeBuild{
		ids: []string{"p:1", "p:2"},
		builds: []cbtypes.Build{
			debugBuild("p:1", "sandbox-abc"),
			{Id: aws.String("p:2"), BuildStatus: cbtypes.StatusTypeSucceeded}, // no debug session
		},
	}
	got, err := ListDebugBuilds(context.Background(), c, "p", "")
	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, DebugBuild{ID: "p:1", Status: "IN_PROGRESS", Phase: "BUILD", Target: "sandbox-abc"}, got[0])
}

func TestListDebugBuilds_CapsAtTen(t *testing.T) {
	ids := make([]string, 15)
	for i := range ids {
		ids[i] = "p:" + string(rune('a'+i))
	}
	c := &stubCodeBuild{ids: ids}
	_, err := ListDebugBuilds(context.Background(), c, "p", "")
	require.NoError(t, err)
	require.Len(t, c.batchInput.Ids, maxDebugBuilds, "only the first 10 ids are inspected")
}

func TestListDebugBuilds_ExplicitIDSkipsListing(t *testing.T) {
	c := &stubCodeBuild{builds: []cbtypes.Build{debugBuild("p:7", "sandbox-7")}}
	got, err := ListDebugBuilds(context.Background(), c, "p", "p:7")
	require.NoError(t, err)
	require.Nil(t, c.listInput, "explicit build id must skip ListBuildsForProject")
	require.Equal(t, []string{"p:7"}, c.batchInput.Ids)
	require.Len(t, got, 1)
	require.Equal(t, "sandbox-7", got[0].Target)
}

func TestListDebugBuilds_DescendingSort(t *testing.T) {
	c := &stubCodeBuild{ids: []string{"p:1"}, builds: []cbtypes.Build{debugBuild("p:1", "s")}}
	_, err := ListDebugBuilds(context.Background(), c, "p", "")
	require.NoError(t, err)
	require.Equal(t, cbtypes.SortOrderTypeDescending, c.listInput.SortOrder)
}
