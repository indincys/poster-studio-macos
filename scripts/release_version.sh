#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 0.1.3" >&2
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"

if [[ ! "${VERSION}" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
  echo "Version must use x.y.z format" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

BRANCH="$(git branch --show-current)"
if [[ -z "${BRANCH}" ]]; then
  echo "Detached HEAD is not supported for release." >&2
  exit 1
fi

if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists locally." >&2
  exit 1
fi

if git rev-parse --verify "@{upstream}" >/dev/null 2>&1; then
  read -r AHEAD BEHIND <<<"$(git rev-list --left-right --count HEAD...@{upstream} | awk '{print $1" "$2}')"
  if [[ "${BEHIND}" != "0" ]]; then
    echo "Current branch is behind upstream. Pull/rebase first." >&2
    exit 1
  fi
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

./scripts/package_app.sh "${VERSION}"

git tag "${TAG}"
git push origin "${BRANCH}"
git push origin "${TAG}"

echo "Pushed ${BRANCH} and ${TAG}."
echo "GitHub Actions will build the release and upload dist/PosterStudio-arm64-${VERSION}.zip to Releases."
