package connect

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/codebuild"
	cbtypes "github.com/aws/aws-sdk-go-v2/service/codebuild/types"
)

// CodeBuildClient is the slice of *codebuild.Client used to find builds with a
// debug session running.
type CodeBuildClient interface {
	ListBuildsForProject(ctx context.Context, in *codebuild.ListBuildsForProjectInput, optFns ...func(*codebuild.Options)) (*codebuild.ListBuildsForProjectOutput, error)
	BatchGetBuilds(ctx context.Context, in *codebuild.BatchGetBuildsInput, optFns ...func(*codebuild.Options)) (*codebuild.BatchGetBuildsOutput, error)
}

// DebugBuild is a CodeBuild build with an active SSM debug session. Target is
// the build's debugSession.sessionTarget — an SSM StartSession target you can
// open a shell against, exactly like an instance id.
type DebugBuild struct {
	ID     string
	Status string
	Phase  string
	Target string
}

// maxDebugBuilds caps how many recent builds we inspect for a debug session.
// ponytail: first 10 like the bash tool; widen if projects routinely debug more.
const maxDebugBuilds = 10

// ListDebugBuilds returns the builds for project that have a debug session
// enabled. With explicitID set it inspects only that build and skips listing.
func ListDebugBuilds(ctx context.Context, c CodeBuildClient, project, explicitID string) ([]DebugBuild, error) {
	var ids []string
	if explicitID != "" {
		ids = []string{explicitID}
	} else {
		out, err := c.ListBuildsForProject(ctx, &codebuild.ListBuildsForProjectInput{
			ProjectName: aws.String(project),
			SortOrder:   cbtypes.SortOrderTypeDescending,
		})
		if err != nil {
			return nil, fmt.Errorf("list builds for project %q: %w", project, err)
		}
		ids = out.Ids
		if len(ids) > maxDebugBuilds {
			ids = ids[:maxDebugBuilds]
		}
	}
	if len(ids) == 0 {
		return nil, nil
	}

	out, err := c.BatchGetBuilds(ctx, &codebuild.BatchGetBuildsInput{Ids: ids})
	if err != nil {
		return nil, fmt.Errorf("get build details: %w", err)
	}

	var builds []DebugBuild
	for _, b := range out.Builds {
		if b.DebugSession == nil || aws.ToString(b.DebugSession.SessionTarget) == "" {
			continue
		}
		builds = append(builds, DebugBuild{
			ID:     aws.ToString(b.Id),
			Status: string(b.BuildStatus),
			Phase:  aws.ToString(b.CurrentPhase),
			Target: aws.ToString(b.DebugSession.SessionTarget),
		})
	}
	return builds, nil
}
