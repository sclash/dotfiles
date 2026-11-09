#!/usr/bin/env bash
# Every vpn.data / vpn.secrets key in services/vpnSchema.js must appear as a
# string in its NetworkManager plugin's binaries. Builds (usually fetches)
# the plugins from the flake's pinned nixpkgs. Native (WireGuard) and common
# fields are NetworkManager settings, not plugin keys, and are skipped.
# The sstp plugin is flagged insecure in nixpkgs; it is only built to read its
# strings (NIXPKGS_ALLOW_INSECURE, --impure), never installed by this test.
# Run: bash quickshell/tests/test-vpn-schema-keys.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
schema="$here/../services/vpnSchema.js"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

declare -A pkg=(
  [l2tp]=networkmanager-l2tp
  [openvpn]=networkmanager-openvpn
  [strongswan]=networkmanager-strongswan
  [sstp]=networkmanager-sstp
)

# "<type> <key>" for each plugin field, read from the one-line-per-field layout.
python3 - "$schema" > "$tmp/keys" <<'PY'
import re, sys
cur, native = None, False
for line in open(sys.argv[1]):
    m = re.match(r"^    ([a-z0-9]+): \{", line)
    if m:
        cur, native = m.group(1), "native: true" in line
        continue
    k = re.search(r'\{ key: "([^"]+)"', line)
    if cur and k and not native:
        print(cur, k.group(1))
PY

failures=0
for type in $(cut -d' ' -f1 "$tmp/keys" | sort -u); do
  attr=${pkg[$type]:-}
  if [[ -z $attr ]]; then echo "FAIL no plugin package known for schema type $type"; failures=$((failures + 1)); continue; fi
  out=$(NIXPKGS_ALLOW_INSECURE=1 nix build --impure --no-link --print-out-paths --inputs-from "$root/nixos" "nixpkgs#$attr" 2>/dev/null | head -n 1)
  if [[ -z $out ]]; then echo "FAIL could not build $attr"; failures=$((failures + 1)); continue; fi
  find "$out" -type f \( -name '*.so*' -o -perm -u+x \) -exec strings {} + 2>/dev/null | sort -u > "$tmp/strings-$type"
  while read -r t key; do
    [[ $t == "$type" ]] || continue
    if grep -Fxq -- "$key" "$tmp/strings-$type"; then
      echo "OK   $type: $key"
    elif grep -Eq -- "-$(printf '%s' "$key" | sed 's/[][\\.*^$+?(){}|]/\\&/g')\$" "$tmp/strings-$type"; then
      # The linker merges a short string into the tail of a longer one
      # ("password" inside "http-proxy-password"), so it has no line of its own.
      echo "OK   $type: $key (tail of a longer plugin key)"
    else
      echo "FAIL $type: \"$key\" is not a key of $attr"
      failures=$((failures + 1))
    fi
  done < "$tmp/keys"
done

if ((failures)); then echo "$failures schema key checks failed"; exit 1; fi
echo "OK (VPN schema keys match the plugins)"
