#!/usr/bin/env bash
# Rebase modelS-source onto UPSTREAM_REPO#UPSTREAM_REF, vendor submodules, strip upstream CI,
# and force-push to refs/heads/modelS-$OUTPUT_SLUG. The upstream SHA the output was built
# from is encoded in the final commit's body (as "upstream-sha: <sha>") for cheap early-out
# on subsequent runs.
set -euo pipefail

: "${UPSTREAM_REPO:?}"
: "${UPSTREAM_REF:?}"
: "${OUTPUT_SLUG:?}"

OUTPUT_BRANCH="modelS-${OUTPUT_SLUG}"
ROOT="$(pwd)"

echo "=== Rebase Model S"
echo "    Upstream: ${UPSTREAM_REPO}#${UPSTREAM_REF}"
echo "    Output:   ${OUTPUT_BRANCH}"
echo

# Safety: never push to a remote that looks like an upstream (e.g. commaai/*).
ORIGIN_URL=$(git remote get-url origin)
echo "    Push target (origin): ${ORIGIN_URL}"
case "${ORIGIN_URL}" in
  *commaai/*|*xnor-tech/*)
    echo "REFUSING to run: origin points at ${ORIGIN_URL}, which looks like an upstream." >&2
    echo "This script only pushes to a personal fork. Aborting." >&2
    exit 2
    ;;
esac

# Fetch upstream
git remote remove upstream 2>/dev/null || true
git remote add upstream "${UPSTREAM_REPO}"
git fetch upstream "${UPSTREAM_REF}"
UPSTREAM_SHA=$(git rev-parse FETCH_HEAD)
echo "    Upstream SHA: ${UPSTREAM_SHA}"

# Early-out: if the tip of the existing modelS-<slug> was built from this
# same upstream SHA *and* the same modelS-source SHA (= rebase logic + patches),
# skip. Both SHAs are embedded in the tip commit body by the strip step below.
# Including modelS-source ensures the early-out invalidates whenever the rebase
# script, vendor script, or patch series changes.
git fetch origin modelS-source 2>/dev/null || true
SOURCE_SHA=$(git rev-parse origin/modelS-source)
if git fetch origin "refs/heads/${OUTPUT_BRANCH}:refs/remotes/origin/${OUTPUT_BRANCH}" 2>/dev/null; then
  MSG=$(git log -1 --format=%B "origin/${OUTPUT_BRANCH}")
  PREV_UPSTREAM_SHA=$(echo "${MSG}" | sed -n 's/^upstream-sha: //p' | head -1)
  PREV_SOURCE_SHA=$(echo "${MSG}" | sed -n 's/^modelS-source-sha: //p' | head -1)
  if [ -n "${PREV_UPSTREAM_SHA}" ] \
     && [ "${PREV_UPSTREAM_SHA}" = "${UPSTREAM_SHA}" ] \
     && [ "${PREV_SOURCE_SHA}" = "${SOURCE_SHA}" ]; then
    echo "    ${OUTPUT_BRANCH} already built from upstream ${UPSTREAM_SHA} and modelS-source ${SOURCE_SHA}; nothing to do."
    exit 0
  fi
fi

# Rebase modelS-source onto upstream
echo
echo "=== Rebasing modelS-source onto ${UPSTREAM_SHA}"
git checkout -B "${OUTPUT_BRANCH}" origin/modelS-source
git rebase "${UPSTREAM_SHA}"

# Apply panda/opendbc patches inside submodules, then vendor them into the tree
echo
echo "=== Applying submodule patches and vendoring"
bash "${ROOT}/.modelS/scripts/vendor-submodules.sh"

# Strip all .github/workflows/*.yaml and *.yml — output branch runs no workflows on fork.
# The rebase workflow itself fires from modelS-source (default branch), not from output branches.
# Also embed the upstream SHA in this commit's body so the next run can early-out.
echo
echo "=== Stripping upstream CI workflows"
if [ -d .github/workflows ]; then
  rm -f .github/workflows/*.yaml .github/workflows/*.yml
  git add -A .github/workflows/
fi
# Always make a tip commit that carries the upstream-sha marker, even if workflows dir
# was absent / already empty, so the early-out can read it on the next run.
git commit --allow-empty -m "[CI] strip workflows for fork distribution

upstream-sha: ${UPSTREAM_SHA}
upstream-ref: ${UPSTREAM_REF}
modelS-source-sha: ${SOURCE_SHA}"

# Push output branch.
# --no-verify skips the LFS pre-push hook (which would try to push to
# ssh://git@gitlab.com/commaai/openpilot-lfs and fail without credentials).
# Safe because we never modify LFS-tracked files; all pointers are unchanged
# from upstream and blobs remain fetchable from the configured LFS server.
echo
echo "=== Pushing ${OUTPUT_BRANCH}"
git push --force-with-lease --no-verify origin "${OUTPUT_BRANCH}"

echo
echo "=== Done"
