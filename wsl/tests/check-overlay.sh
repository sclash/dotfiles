#!/usr/bin/env bash
# Checks for the WSL overlay of my-opencode/v2 (wsl/opencode).
# Usage: check-overlay.sh V2_DIR OVERLAY_DIR TESTS_DIR
set -uo pipefail

V2=${1:?usage: check-overlay.sh V2_DIR OVERLAY_DIR TESTS_DIR}
OVERLAY=${2:?}
TESTS=${3:?}
failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

export PYTHONDONTWRITEBYTECODE=1
export SYNC_OPENCODE_DIR="$OVERLAY"

# Unit tests of the opencode.jsonc transform.
python3 -m unittest discover -s "$TESTS" -p 'test_*.py' 2>&1 | tee /dev/stderr | tail -3 \
  | grep -q '^OK' || fail "sync_opencode_jsonc unit tests"

# The committed copy is exactly the transform of v2's file.
python3 "$OVERLAY/sync_opencode_jsonc.py" --check "$V2/opencode.jsonc" "$OVERLAY/opencode.jsonc" \
  || fail "opencode.jsonc is stale: run wsl/opencode/sync_opencode_jsonc.py my-opencode/v2/opencode.jsonc wsl/opencode/opencode.jsonc"

if [[ $failures -gt 0 ]]; then
  echo "$failures overlay checks failed"
  exit 1
fi
echo "OK (overlay)"
