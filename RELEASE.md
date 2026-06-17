# Release Management

This document describes the release process for `aws-tools`.

## Version Management

We follow [Semantic Versioning](https://semver.org/) (SemVer):

- **MAJOR** version (X.0.0): Incompatible API changes or breaking changes
- **MINOR** version (0.X.0): New features, backwards compatible
- **PATCH** version (0.0.X): Bug fixes, backwards compatible

Current version is tracked in the `VERSION` file at the repository root.

## Prerequisites

Before creating a release, ensure you have:

1. **GitHub CLI (`gh`)** installed and authenticated
   ```bash
   # Install gh (if not already installed)
   # macOS: brew install gh
   # Linux: see https://cli.github.com/
   
   # Authenticate
   gh auth login
   ```

2. **Task** (go-task) installed for running release commands
   ```bash
   # macOS: brew install go-task
   # Linux: see https://taskfile.dev/installation/
   ```

3. **All changes committed** to the repository
   - No uncommitted changes
   - All tests passing (`task ci`)
   - On the `main` branch (or ready to merge)

## Creating a Release

### Option 1: Interactive Release (Recommended)

Run the release script interactively:

```bash
task release
```

This will:
1. Show the current version
2. Ask you to select the bump type (patch/minor/major)
3. Show what the new version will be
4. Ask for confirmation
5. Run tests (`task ci`)
6. Update the VERSION file
7. Commit the version bump
8. Create and push a git tag
9. Create a GitHub release with auto-generated release notes

### Option 2: Direct Release Commands

Create a specific type of release directly:

```bash
# Interactive release (recommended for first time)
task release

# Patch release (bug fixes: 0.1.0 -> 0.1.1)
task release:patch

# Minor release (new features: 0.1.0 -> 0.2.0)
task release:minor

# Major release (breaking changes: 0.1.0 -> 1.0.0)
task release:major
```

### Option 3: Manual Script

You can also call the release script directly:

```bash
./scripts/release.sh patch
./scripts/release.sh minor
./scripts/release.sh major
```

## Release Process Details

When you create a release, the following happens automatically:

1. **Validation**
   - Checks for uncommitted changes
   - Warns if not on `main` branch
   - Validates VERSION file format

2. **Version Bump**
   - Reads current version from VERSION file
   - Calculates new version based on bump type
   - Updates VERSION file

3. **Testing**
   - Runs `task ci` (linting + unit tests)
   - Fails the release if tests don't pass

4. **Git Operations**
   - Commits VERSION file with message: `chore: bump version to X.Y.Z`
   - Creates an annotated git tag: `vX.Y.Z`
   - Pushes commit and tag to GitHub

5. **GitHub Release**
   - Creates a GitHub release using `gh` CLI
   - Auto-generates release notes from commits since last tag
   - Includes installation instructions in the release

6. **Image Publishing** (automatic via CI)
   - The release workflow (`.github/workflows/release.yml`) builds and pushes the runtime image to GHCR
   - Tags: `vX.Y.Z`, `vX.Y`, `vX`, `latest`
   - Multi-arch: `linux/amd64` and `linux/arm64`
   - Verify: `docker pull ghcr.io/kedwards/aws-tools:vX.Y.Z`

## Installing Specific Versions

### For End Users

Users can install a specific version using the installer:

```bash
# Install latest release (default)
curl -sSL https://raw.githubusercontent.com/kedwards/aws-tools/main/install.sh | bash

# Install specific version
curl -sSL https://raw.githubusercontent.com/kedwards/aws-tools/main/install.sh | bash -s v0.1.0

# Install from main branch (development version)
curl -sSL https://raw.githubusercontent.com/kedwards/aws-tools/main/install.sh | bash -s main
```

### For Existing Installations

Users can update to a specific version:

```bash
# Update to latest release
awst update

# Update to specific version
awst update v1.3.1

# Update to main branch
awst update main
```

### Checking Installed Version

```bash
awst --version
```

## Release Checklist

Before creating a release, ensure:

- [ ] All planned features/fixes are merged to `main`
- [ ] Tests are passing (`task ci`)
- [ ] Documentation is up to date (README.md, WARP.md, etc.)
- [ ] CHANGELOG or commit messages clearly describe changes
- [ ] No uncommitted changes in working directory
- [ ] You're on the `main` branch
- [ ] You have GitHub CLI authenticated (`gh auth status`)
- [ ] Image is available on GHCR after the release workflow completes (`docker pull ghcr.io/kedwards/aws-tools:vX.Y.Z`)

## Hotfix Releases

For urgent bug fixes:

1. Create a hotfix branch from the latest release tag:
   ```bash
   git checkout -b hotfix/critical-fix v0.1.0
   ```

2. Make the fix and commit it

3. Run the release script (will create v0.1.1):
   ```bash
   ./scripts/release.sh patch
   ```

4. Merge the hotfix branch back to main:
   ```bash
   git checkout main
   git merge hotfix/critical-fix
   git push origin main
   ```

## Troubleshooting

### Release script fails during git push

If the script fails while pushing:

```bash
# Push manually
git push origin main
git push origin vX.Y.Z

# Then create the GitHub release manually
gh release create vX.Y.Z --title "Release vX.Y.Z" --generate-notes
```

### Tests fail during release

The release will be aborted. Fix the tests and try again:

```bash
# Fix the issues
task ci

# Try release again
task release
```

### Need to delete a release

```bash
# Delete GitHub release
gh release delete vX.Y.Z

# Delete local tag
git tag -d vX.Y.Z

# Delete remote tag
git push origin :refs/tags/vX.Y.Z

# Revert VERSION file commit
git reset --hard HEAD^
git push origin main --force
```

## Team Workflow

### For Maintainers

1. Review and merge PRs to `main`
2. When ready to release, run `task release`
3. Follow the interactive prompts
4. Announce the release to the team

### For Contributors

1. Work on feature branches
2. Submit PRs to `main`
3. Maintainers will handle releases
4. Update to the latest version: `awst update`

## Version History

View all releases:
```bash
gh release list
```

View specific release:
```bash
gh release view v0.1.0
```

See all tags:
```bash
git tag -l
```
