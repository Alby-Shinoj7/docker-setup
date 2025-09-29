#!/usr/bin/env sh
set -eu

dirname=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_root=$(cd "$dirname/.." && pwd)
script="$repo_root/install-docker.sh"

printf 'Running help check...\n'
if ! bash "$script" --help >/dev/null; then
  printf 'Help check failed\n' >&2
  exit 1
fi

printf 'Running dry-run smoke...\n'
if ! bash "$script" --dry-run -y --no-verify-run --skip-group-add >/dev/null; then
  printf 'Dry-run smoke failed\n' >&2
  exit 1
fi

printf 'Smoke tests passed.\n'
