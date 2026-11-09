#!/usr/bin/env bash
# Runs the nm-vpn helper tests (tests/test_nm_vpn.py): pure logic, plus the
# CLI against a JSON-file backend and a fake nmcli. No NetworkManager is
# touched. Run from anywhere: bash quickshell/tests/test-nm-vpn.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if python3 -I "$here/test_nm_vpn.py" -v; then
  echo "OK (nm-vpn tests)"
else
  echo "nm-vpn tests failed"
  exit 1
fi
