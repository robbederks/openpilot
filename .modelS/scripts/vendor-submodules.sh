#!/usr/bin/env bash
# Called from repo root after a rebase. For each vendored submodule:
#   1. init the submodule at the gitlink SHA (upstream SHA that upstream openpilot points to)
#   2. apply Model S patches from .modelS/<name>-patches/*.patch inside the submodule
#   3. strip the submodule's .git dir
#   4. remove the gitlink from the index and re-add as plain files
# Then remove the submodule's section from .gitmodules and commit.
set -euo pipefail

VENDORED=(panda opendbc_repo)
ROOT="$(pwd)"

if [ ! -f .gitmodules ]; then
  echo "No .gitmodules; nothing to vendor."
  exit 0
fi

git submodule update --init --no-recommend-shallow "${VENDORED[@]}"

for sub in "${VENDORED[@]}"; do
  if [ ! -d "${ROOT}/${sub}" ]; then
    echo "  skip ${sub} (not present)"
    continue
  fi
  patches_dir="${ROOT}/.modelS/${sub}-patches"

  if [ -d "${patches_dir}" ] && compgen -G "${patches_dir}/*.patch" > /dev/null; then
    echo "  applying $(ls "${patches_dir}"/*.patch | wc -l) patches to ${sub}"
    (cd "${ROOT}/${sub}" && git am --3way "${patches_dir}"/*.patch)
  else
    echo "  no patches for ${sub}"
  fi

  echo "  vendoring ${sub}"
  rm -rf "${ROOT}/${sub}/.git"
  git -C "${ROOT}" rm --cached "${sub}" > /dev/null
  # -f forces inclusion of files that match the submodule's own .gitignore
  # (e.g. panda's "obj/" pattern, which would otherwise silently drop tracked
  # files like panda/board/obj/.placeholder and panda/board/obj/*.bin.signed).
  git -C "${ROOT}" add -f "${sub}"
done

# Prune vendored entries from .gitmodules
python3 - "${VENDORED[@]}" <<'PY'
import sys, os, re
vendored = set(sys.argv[1:])
with open('.gitmodules') as f:
    text = f.read()
out = []
skip = False
for line in text.splitlines(keepends=True):
    m = re.match(r'\[submodule "([^"]+)"\]', line)
    if m:
        skip = False
        out.append(line)
        continue
    pm = re.match(r'\s*path\s*=\s*(\S+)', line)
    if pm and pm.group(1) in vendored:
        # drop preceding header + this block
        while out and not out[-1].lstrip().startswith('[submodule'):
            out.pop()
        if out and out[-1].lstrip().startswith('[submodule'):
            out.pop()
        skip = True
        continue
    if skip:
        if line.startswith('['):
            skip = False
            out.append(line)
        continue
    out.append(line)
new = ''.join(out).rstrip() + ('\n' if out else '')
if new.strip():
    with open('.gitmodules', 'w') as f:
        f.write(new)
else:
    os.remove('.gitmodules')
PY

if [ -f .gitmodules ]; then
  git add .gitmodules
else
  git rm .gitmodules 2>/dev/null || true
fi

if ! git diff --cached --quiet; then
  git commit -m "[CI] vendor submodules (${VENDORED[*]})"
fi
