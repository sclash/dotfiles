#!/usr/bin/env bash
# Checks for the WSL overlay of my-opencode/v2 (wsl/opencode).
# Usage: check-overlay.sh V2_DIR OVERLAY_DIR TESTS_DIR
set -uo pipefail

usage="usage: check-overlay.sh V2_DIR OVERLAY_DIR TESTS_DIR"
# Absolute paths: the drift check runs from inside V2.
V2=$(cd "${1:?$usage}" && pwd) || exit 2
OVERLAY=$(cd "${2:?$usage}" && pwd) || exit 2
TESTS=$(cd "${3:?$usage}" && pwd) || exit 2
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

# Drift: each copy records the checksum of the v2 original it was derived from.
SUMS="$OVERLAY/BASE.sha256"
if [[ ! -f "$SUMS" ]]; then
  fail "missing $SUMS"
else
  # Anything but OK/FAILED (a missing original, an unreadable file) is an
  # error too: the check must never pass because sha256sum could not run.
  while IFS= read -r line; do
    case "$line" in
      *': OK') ;;
      'sha256sum: WARNING:'*) ;;
      *': FAILED')
        file=${line%: FAILED}
        echo "drift: $file changed in my-opencode/v2; re-derive wsl/opencode/$file and refresh BASE.sha256"
        failures=$((failures + 1))
        ;;
      *) fail "checksum error: $line" ;;
    esac
  done < <(cd "$V2" && sha256sum -c "$SUMS" 2>&1)
  # Every recorded original has its copy in the overlay.
  while read -r _ file; do
    [[ -f "$OVERLAY/$file" ]] || fail "no overlay copy for $file"
  done < "$SUMS"
fi

# Copies must not carry NixOS-only paths or wording (opencode.jsonc keeps the
# original /run/secrets rules on purpose; the tooling files are exempt).
hits=$(grep -rnE '/run/current-system|nix-ld|dotfiles/nixos|NixOS|NixOs' "$OVERLAY" \
  --exclude=opencode.jsonc --exclude=sync_opencode_jsonc.py --exclude=BASE.sha256)
[[ -z "$hits" ]] || fail "NixOS-specific lines in the overlay:
$hits"

if [[ $failures -gt 0 ]]; then
  echo "$failures overlay checks failed"
  exit 1
fi
echo "OK (overlay)"
