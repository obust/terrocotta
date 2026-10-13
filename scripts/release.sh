#!/usr/bin/env bash

# Publish a Terrocotta package bundle as a GitHub release.
#
# Usage: scripts/release.sh <tag>
#
# The script:
#   1. Validates the semantic-version tag and required tools.
#   2. Verifies GitHub authentication and a clean working tree.
#   3. Requires committed release notes at docs/release/<tag>.md.
#   4. Rejects an existing local tag or GitHub release.
#   5. Runs the package test suite.
#   6. Runs `roc check` on every runnable example.
#   7. Creates one content-addressed .tar.zst bundle under dist/<tag>/.
#   8. Shows the repository, commit, tag, bundle, and notes for confirmation.
#   9. Creates the GitHub release and tag using the committed release notes.

set -euo pipefail

# Parse and validate the release tag.
usage() {
	echo "Usage: $0 <tag>" >&2
	exit 2
}

if [[ $# -ne 1 ]]; then
	usage
fi

release_tag=$1
root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ! $release_tag =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
	echo "Error: tag must be a semantic version such as 0.1.0 or 0.2.0-rc.1." >&2
	exit 2
fi

# Check local tooling and GitHub authentication.
for command_name in git gh roc; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Error: required command not found: $command_name" >&2
		exit 1
	fi
done

expected_roc_version=$(tr -d '\r\n' < "$root_dir/.roc-version")
package_roc_version=$(sed -nE 's/^[[:space:]]*roc: "([^"]+)",?$/\1/p' "$root_dir/package/main.roc")
if [[ $package_roc_version != "$expected_roc_version" ]]; then
	echo "Error: package/main.roc pins '$package_roc_version'; expected '$expected_roc_version' from .roc-version." >&2
	exit 1
fi

installed_roc_version=$(roc version | awk '{print $NF}')
if [[ $installed_roc_version != "$expected_roc_version" ]]; then
	echo "Error: expected Roc $expected_roc_version, found $installed_roc_version." >&2
	exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
	echo "Error: GitHub CLI is not authenticated. Run: gh auth login" >&2
	exit 1
fi

# Resolve the repository and require a clean, unpublished commit.
cd "$root_dir"
release_notes_path="$root_dir/docs/release/$release_tag.md"

if [[ -n $(git status --porcelain) ]]; then
	echo "Error: the working tree must be clean before publishing a release." >&2
	exit 1
fi

if [[ ! -s $release_notes_path ]]; then
	echo "Error: release notes not found or empty: docs/release/$release_tag.md" >&2
	exit 1
fi

if git rev-parse --verify --quiet "refs/tags/$release_tag" >/dev/null; then
	echo "Error: local tag already exists: $release_tag" >&2
	exit 1
fi

if gh release view "$release_tag" >/dev/null 2>&1; then
	echo "Error: GitHub release already exists: $release_tag" >&2
	exit 1
fi

release_repository=$(git remote get-url origin)
release_commit=$(git rev-parse HEAD)
release_dist_dir="$root_dir/dist/$release_tag"
mkdir -p "$release_dist_dir"

# Validate the package and every declared example entrypoint.
echo "Running checks..."
scripts/check.sh

echo "Running tests..."
scripts/test.sh

# Build and locate the content-addressed release bundle.
echo "Creating package bundle..."
scripts/bundle.sh --output-dir "$release_dist_dir"

shopt -s nullglob
bundle_files=("$release_dist_dir"/*.tar.zst)
shopt -u nullglob

if [[ ${#bundle_files[@]} -ne 1 ]]; then
	echo "Error: expected one .tar.zst bundle, found ${#bundle_files[@]}." >&2
	exit 1
fi

# Show the resolved release inputs and require explicit confirmation.
bundle_path=${bundle_files[0]}

echo
echo "Repository: $release_repository"
echo "Tag:        $release_tag"
echo "Commit:     $release_commit"
echo "Bundle:     $(basename "$bundle_path")"
echo "Notes:      docs/release/$release_tag.md"
echo

read -r -p "Publish this GitHub release? [y/N] " confirmation
if [[ $confirmation != "y" && $confirmation != "Y" ]]; then
	echo "Release cancelled."
	exit 0
fi

# Create the GitHub tag and release with the committed notes, then upload the bundle.
gh release create "$release_tag" "$bundle_path" \
	--target "$release_commit" \
	--title "$release_tag" \
	--notes-file "$release_notes_path"

echo "Published release $release_tag."
