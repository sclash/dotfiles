#!/usr/bin/env bash
# Tests for wsl/bootstrap.sh. Mutating behaviour is exercised only on temp
# files (throwaway age keys, sops files); runs against this instance use
# --dry-run.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WSL=$(dirname "$HERE")
BOOT="$WSL/bootstrap.sh"
failures=0
count=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

expect() {
  local desc=$1
  shift
  count=$((count + 1))
  "$@" || fail "$desc"
}

has() { grep -qF -- "$2" <<<"$1"; }
lacks() { ! grep -qF -- "$2" <<<"$1"; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

age() { nix shell "$WSL#age" -c "$@" 2>/dev/null; }
sops() { nix run "$WSL#sops" -- "$@" 2>/dev/null; }

age age-keygen -o "$T/A.txt"
age age-keygen -o "$T/B.txt"
PUB_A=$(age age-keygen -y "$T/A.txt")
PUB_B=$(age age-keygen -y "$T/B.txt")

write_config() {
  printf 'creation_rules:\n  - path_regex: .*\\.yaml$\n    age: %s\n' "$1" > "$2"
}
write_config "$PUB_A" "$T/.sops.yaml"
printf 'github_pat: x\nopenrouter: x\nopencode: x\ncheaper_inference: x\n' > "$T/full.yaml"
printf 'github_pat: x\nopenrouter: x\nopencode: x\n' > "$T/partial.yaml"
for f in full partial; do
  SOPS_AGE_KEY_FILE="$T/A.txt" sops --config "$T/.sops.yaml" -e -i "$T/$f.yaml"
done

# --- static checks
expect "shellcheck clean" \
  nix run github:NixOS/nixpkgs/b1b875982b17dabde9b4a37f3e229e74913e6db3#shellcheck -- "$BOOT"
help=$(bash "$BOOT" --help 2>&1)
expect "--help exits 0" bash "$BOOT" --help
expect "--help mentions --cleanup" has "$help" --cleanup
expect "--help mentions --dry-run" has "$help" --dry-run
expect "--help mentions --add-recipient" has "$help" --add-recipient

# --- sourced functions
# shellcheck source=../bootstrap.sh
source "$BOOT"
AGE_KEY_FILE="$T/A.txt"
expect "status ok" [ "$(secrets_status "$T/.sops.yaml" "$T/full.yaml")" = ok ]
expect "status missing-keys" \
  [ "$(secrets_status "$T/.sops.yaml" "$T/partial.yaml")" = missing-keys:cheaper_inference ]
expect "status missing" [ "$(secrets_status "$T/.sops.yaml" "$T/none.yaml")" = missing ]
AGE_KEY_FILE="$T/B.txt"
expect "status undecryptable" [ "$(secrets_status "$T/.sops.yaml" "$T/full.yaml")" = undecryptable ]

cp "$T/.sops.yaml" "$T/reg.sops.yaml"
register_recipient "$PUB_B" "$T/reg.sops.yaml"
register_recipient "$PUB_B" "$T/reg.sops.yaml"
expect "register_recipient appends once" [ "$(grep -o "$PUB_B" "$T/reg.sops.yaml" | wc -l)" -eq 1 ]
expect "register_recipient keeps A" grep -q "age: $PUB_A,$PUB_B\$" "$T/reg.sops.yaml"

# --- refusals (Review Focus 3)
out=$(HOME=/tmp/elsewhere bash "$BOOT" --dry-run 2>&1)
rc=$?
expect "wrong HOME exits 1" [ "$rc" -eq 1 ]
expect "wrong HOME message" has "$out" "expects the repo at /home/asergi/dotfiles"

out=$(AGE_KEY_FILE="$T/B.txt" SOPS_CONFIG="$T/.sops.yaml" SECRETS_FILE="$T/full.yaml" \
  bash "$BOOT" --dry-run 2>&1)
rc=$?
expect "undecryptable exits 2" [ "$rc" -eq 2 ]
expect "undecryptable prints add-recipient" has "$out" "--add-recipient $PUB_B"
expect "undecryptable stops before switch" lacks "$out" "switch --flake"

out=$(AGE_KEY_FILE="$T/new.txt" SOPS_CONFIG="$T/.sops.yaml" SECRETS_FILE="$T/full.yaml" \
  bash "$BOOT" --dry-run 2>&1)
expect "missing key is generated" has "$out" "DRY-RUN: nix shell $WSL#age -c age-keygen -o $T/new.txt"

# --- --add-recipient (on temp files, key A can decrypt)
out=$(AGE_KEY_FILE="$T/A.txt" SOPS_CONFIG="$T/.sops.yaml" SECRETS_FILE="$T/full.yaml" \
  bash "$BOOT" --add-recipient "$PUB_B" 2>&1)
rc=$?
expect "--add-recipient exits 0" [ "$rc" -eq 0 ]
AGE_KEY_FILE="$T/B.txt"
expect "added recipient can decrypt" [ "$(secrets_status "$T/.sops.yaml" "$T/full.yaml")" = ok ]

# --- this instance, dry run
out=$(bash "$BOOT" --dry-run 2>&1)
rc=$?
expect "dry run exits 0" [ "$rc" -eq 0 ]
expect "dry run prints DRY-RUN" has "$out" "DRY-RUN:"
expect "dry run switches" has "$out" "switch --flake /home/asergi/dotfiles/wsl#asergi -b hm-backup"
if locale -a 2>/dev/null | grep -qix 'en_US.utf8'; then
  expect "locale present: not regenerated" lacks "$out" "locale-gen"
else
  expect "dry run generates locale" has "$out" "locale-gen en_US.UTF-8"
fi
expect "nix already installed" lacks "$out" "install.determinate.systems"
expect "systemd already enabled" lacks "$out" "wsl.conf"
expect "shell already zsh" lacks "$out" "chsh"
out2=$(bash "$BOOT" --dry-run 2>&1)
expect "dry run is idempotent" [ "$out" = "$out2" ]

# Cleanup against a fake legacy $HOME (stub snap on PATH), never the real one.
H="$T/home"; mkdir -p "$H/.oh-my-zsh" "$H/.nvm" "$T/bin"
printf '#!/bin/sh\n[ "$1" = list ] && [ "$2" = nvim ]\n' > "$T/bin/snap"; chmod +x "$T/bin/snap"
cleanup_out=$(HOME="$H" PATH="$T/bin:$PATH" bash -c 'source "$1"; DRY_RUN=1; cleanup' _ "$BOOT" 2>&1)
expect "cleanup lists oh-my-zsh" has "$cleanup_out" "~/.oh-my-zsh"
expect "cleanup lists snap nvim" has "$cleanup_out" "snap nvim"
expect "cleanup prints removals" has "$cleanup_out" "DRY-RUN: rm -rf $H/.oh-my-zsh"
expect "cleanup dry run removes nothing" [ -d "$H/.oh-my-zsh" ]
# The .sops.yaml registered locally must not block pulling the re-encrypted secrets.
out=$(AGE_KEY_FILE="$T/B.txt" SOPS_CONFIG="$T/.sops.yaml" SECRETS_FILE="$T/partial.yaml" bash "$BOOT" --dry-run 2>&1)
expect "undecryptable says to discard local .sops.yaml" has "$out" "git checkout -- wsl/.sops.yaml"

if [[ $failures -gt 0 ]]; then
  echo "$failures of $count bootstrap tests failed"
  exit 1
fi
echo "OK ($count bootstrap tests)"
