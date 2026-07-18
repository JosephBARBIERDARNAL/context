#!/bin/sh
set -eu

usage() {
    echo "usage: ./release.sh <version>" >&2
    echo "example: ./release.sh 0.2.2" >&2
    exit 1
}

[ "$#" -eq 1 ] || usage

VERSION=$1
if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$'; then
    echo "error: version must look like 0.2.2" >&2
    exit 1
fi

TAG="v$VERSION"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

if [ "$(git branch --show-current)" != "main" ]; then
    echo "error: releases must be created from the main branch" >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "error: commit or stash all changes before releasing" >&2
    exit 1
fi

git fetch --tags origin

if git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null; then
    echo "error: tag $TAG already exists" >&2
    exit 1
fi

git tag --annotate "$TAG" --message "Context $VERSION"
git push --atomic origin main "$TAG"

echo "Release $TAG pushed. GitHub Actions will publish it shortly."
