#!/usr/bin/env bash
# Fail if a tracked functional file still hardcodes a home directory.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
cd "$ROOT" || exit 1

# Allowed: the pure-eval fallback, tests that assert it, the fallback note,
# and historical design/plan documents.
hits=$(git grep -n -E '/home/[A-Za-z0-9._-]+' -- . \
  ':!lib/user.nix' \
  ':!tests/test-user.sh' \
  ':!wsl/tests/test-bootstrap.sh' \
  ':!nixos/tests/check-generation.sh' \
  ':!wsl/README.md' \
  ':!docs/' \
  ':!wsl/docs/')
status=$?
if ((status > 1)); then
  echo "check-no-hardcoded-home: git grep failed (exit $status)" >&2
  exit 2
fi
if [[ -n "$hits" ]]; then
  echo "$hits"
  echo "hardcoded home found; use lib/user.nix or a portable path"
  exit 1
fi
echo "OK (no hardcoded home)"
