#!/usr/bin/env bash
# One-time: extract the Model S patch series from the currently-initialized
# panda and opendbc_repo submodules (which should be at xnor-tech's tips) into
# .modelS/panda-patches/ and .modelS/opendbc_repo-patches/.
#
# Run this from the openpilot repo root while on a branch that has panda/ and
# opendbc_repo/ pointed at xnor-tech (e.g. the current xnor-dev).
set -euo pipefail
ROOT="$(pwd)"

extract() {
  local sub="$1"
  local upstream_url="$2"
  local upstream_ref="${3:-master}"
  local out="${ROOT}/.modelS/${sub}-patches"

  echo "=== ${sub}"
  cd "${ROOT}/${sub}"

  git remote remove _modelS_upstream 2>/dev/null || true
  git remote add _modelS_upstream "${upstream_url}"
  git fetch _modelS_upstream "${upstream_ref}"

  local base tip n
  base=$(git merge-base HEAD _modelS_upstream/${upstream_ref})
  tip=$(git rev-parse HEAD)
  n=$(git rev-list --count "${base}..${tip}")

  echo "    base: ${base}  ($(git log -1 --format=%s ${base}))"
  echo "    tip:  ${tip}   ($(git log -1 --format=%s ${tip}))"
  echo "    patches: ${n}"

  git remote remove _modelS_upstream

  if [ "${n}" -eq 0 ]; then
    echo "    nothing to extract"
    cd "${ROOT}"
    return
  fi

  rm -rf "${out}"
  mkdir -p "${out}"
  git format-patch "${base}..${tip}" -o "${out}" > /dev/null
  echo "    wrote ${n} patches to .modelS/${sub}-patches/"
  cd "${ROOT}"
}

extract panda         https://github.com/commaai/panda   master
extract opendbc_repo  https://github.com/commaai/opendbc master

echo
echo "Done. Review the generated patches under .modelS/"
echo "Next: create the modelS-source branch and commit these patches + the .modelS/ scripts + workflow."
