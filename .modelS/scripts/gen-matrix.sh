#!/usr/bin/env bash
# Emit a GH Actions matrix JSON to $GITHUB_OUTPUT.
# If DISPATCH_REF is set (from workflow_dispatch), use a single-entry matrix.
# Otherwise, read .modelS/branches.yml and emit one entry per tracked branch.
set -euo pipefail

if [ -n "${DISPATCH_REF:-}" ]; then
  slug="${DISPATCH_SLUG:-}"
  if [ -z "$slug" ]; then
    # derive a slug from the ref: pull/1234/head -> pr-1234, refs/heads/foo -> foo
    case "$DISPATCH_REF" in
      pull/*/head) slug="pr-$(echo "$DISPATCH_REF" | cut -d/ -f2)" ;;
      refs/heads/*) slug="${DISPATCH_REF#refs/heads/}" ;;
      *) slug=$(echo "$DISPATCH_REF" | tr '/' '-') ;;
    esac
  fi
  matrix=$(jq -cn --arg ref "$DISPATCH_REF" --arg slug "$slug" '{include:[{upstream:$ref, slug:$slug}]}')
else
  matrix=$(python3 -c "
import yaml, json, sys
with open('.modelS/branches.yml') as f:
    cfg = yaml.safe_load(f)
include = []
for b in cfg.get('tracked', []):
    ref = b['upstream']
    slug = b.get('slug') or ref.replace('/', '-')
    include.append({'upstream': ref, 'slug': slug})
print(json.dumps({'include': include}))
")
fi

echo "matrix=$matrix" >> "$GITHUB_OUTPUT"
echo "$matrix" | jq .
