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
unset DOTFILES_WSL_SECRETS
export LOCAL_SECRETS="$T/no-local.yaml"

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
printf 'github_pat:\nopenrouter:\nopencode:\ncheaper_inference:\n' > "$T/empty.yaml"
for f in full partial; do
  SOPS_AGE_KEY_FILE="$T/A.txt" sops --config "$T/.sops.yaml" -e -i "$T/$f.yaml"
done
SOPS_AGE_KEY_FILE="$T/A.txt" sops --config "$T/.sops.yaml" -e -i "$T/empty.yaml"

# --- static checks
expect "shellcheck clean" \
  nix run github:NixOS/nixpkgs/b1b875982b17dabde9b4a37f3e229e74913e6db3#shellcheck -- "$BOOT"
help=$(bash "$BOOT" --help 2>&1)
expect "--help exits 0" bash "$BOOT" --help
expect "--help mentions --cleanup" has "$help" --cleanup
expect "--help mentions --dry-run" has "$help" --dry-run
expect "--help mentions --new-secrets" has "$help" --new-secrets
expect "--help mentions --add-recipient" has "$help" --add-recipient
body=$(cat "$BOOT")
expect "not-root guard present" has "$body" "EUID == 0"
expect "identity guard present" has "$body" "homeConfigurations.default.config.home.username"
expect "identity guard present (home)" has "$body" "homeConfigurations.default.config.home.homeDirectory"

# --- identity guards (stub nix; the real one is not required)
mkdir -p "$T/bin"
cat > "$T/bin/nix" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG:-/dev/null}"
case "$*" in
  *homeConfigurations.default.config.home.username*) printf '%s\n' "${STUB_USER:?}" ;;
  *homeConfigurations.default.config.home.homeDirectory*) printf '%s\n' "${STUB_HOME:?}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/bin/nix"

rm -f "$T/nix.log"
out=$(PATH="$T/bin:$PATH" FLAKE=/fake HOME="$T/alice" STUB_LOG="$T/nix.log" STUB_USER="$(id -un)" STUB_HOME="$T/alice" \
  bash -c 'source "$1"; check_identity' _ "$BOOT" 2>&1)
rc=$?
expect "identity check passes for matching account" [ "$rc" -eq 0 ]
expect "identity check evaluates impurely" has "$(cat "$T/nix.log")" --impure

out=$(PATH="$T/bin:$PATH" FLAKE=/fake HOME="$T/alice" STUB_USER=someoneelse STUB_HOME="$T/alice" \
  bash -c 'source "$1"; check_identity' _ "$BOOT" 2>&1)
rc=$?
expect "identity mismatch exits 1" [ "$rc" -eq 1 ]
expect "identity mismatch message" has "$out" "but this account is"

out=$(PATH="$T/bin:$PATH" FLAKE=/fake HOME=/home/alice STUB_USER=asergi STUB_HOME=/home/asergi \
  bash -c 'source "$1"; check_identity' _ "$BOOT" 2>&1)
rc=$?
expect "pure-fallback identity mismatch exits 1" [ "$rc" -eq 1 ]
expect "pure-fallback mismatch message" has "$out" "but this account is"

out=$(env -u USER bash -c 'source "$1"; check_not_root' _ "$BOOT" 2>&1)
rc=$?
expect "missing USER refused" [ "$rc" -eq 1 ]
expect "missing USER message" has "$out" "USER and HOME must be set"

out=$(env -u HOME bash -c 'source "$1"; check_not_root' _ "$BOOT" 2>&1)
rc=$?
expect "missing HOME refused" [ "$rc" -eq 1 ]
expect "missing HOME message" has "$out" "USER and HOME must be set"

# --- sourced functions
# shellcheck source=../bootstrap.sh
source "$BOOT"
AGE_KEY_FILE="$T/A.txt"
expect "status ok" [ "$(secrets_status "$T/.sops.yaml" "$T/full.yaml")" = ok ]
expect "status missing-keys" \
  [ "$(secrets_status "$T/.sops.yaml" "$T/partial.yaml")" = missing-keys:cheaper_inference ]
expect "status missing" [ "$(secrets_status "$T/.sops.yaml" "$T/none.yaml")" = missing ]
expect "status empty values" [ "$(secrets_status "$T/.sops.yaml" "$T/empty.yaml")" = "empty-keys:github_pat,openrouter,opencode,cheaper_inference" ]
AGE_KEY_FILE="$T/B.txt"
expect "status undecryptable" [ "$(secrets_status "$T/.sops.yaml" "$T/full.yaml")" = undecryptable ]

cp "$T/.sops.yaml" "$T/reg.sops.yaml"
register_recipient "$PUB_B" "$T/reg.sops.yaml"
register_recipient "$PUB_B" "$T/reg.sops.yaml"
expect "register_recipient appends once" [ "$(grep -o "$PUB_B" "$T/reg.sops.yaml" | wc -l)" -eq 1 ]
expect "register_recipient keeps A" grep -q "age: $PUB_A,$PUB_B\$" "$T/reg.sops.yaml"

# --- --new-secrets (dry run)
rm -f "$T/local.yaml"
out=$(DRY_RUN=1 PUBKEY="$PUB_A" LOCAL_SECRETS="$T/local.yaml" bash -c 'source "$1"; new_secrets' _ "$BOOT" 2>&1)
rc=$?
expect "new-secrets dry run exits 0" [ "$rc" -eq 0 ]
expect "new-secrets encrypts with age" has "$out" "--encrypt --age $PUB_A"
expect "new-secrets targets local file" has "$out" "$T/local.yaml"

# --- --new-secrets (real temp files)
printf 'creation_rules:\n  - path_regex: secrets/secrets\\.yaml$\n    age: %s\n' "$PUB_A" > "$T/local.sops.yaml"
LOCAL_REAL="$T/localdir/secrets.yaml"
mkdir -p "$T/localdir"
set +e
out=$(AGE_KEY_FILE="$T/A.txt" SOPS_CONFIG="$T/local.sops.yaml" LOCAL_SECRETS="$LOCAL_REAL" PUBKEY="$PUB_A" bash -c 'source "$1"; new_secrets' _ "$BOOT" 2>&1)
rc=$?
set +e
expect "new-secrets real exits 0" [ "$rc" -eq 0 ]
expect "new-secrets creates file" [ -f "$LOCAL_REAL" ]
expect "new-secrets mode 600" [ "$(stat -c %a "$LOCAL_REAL")" = 600 ]
decrypted=$(SOPS_AGE_KEY_FILE="$T/A.txt" sops --config "$T/local.sops.yaml" --filename-override secrets/secrets.yaml -d "$LOCAL_REAL")
expect "new-secrets has keys" has "$decrypted" "github_pat:"
expect "new-secrets values empty" has "$decrypted" 'github_pat: ""'
out=$(AGE_KEY_FILE="$T/A.txt" SOPS_CONFIG="$T/local.sops.yaml" LOCAL_SECRETS="$LOCAL_REAL" PUBKEY="$PUB_A" bash -c 'source "$1"; new_secrets' _ "$BOOT" 2>&1)
rc=$?
expect "new-secrets uses existing" [ "$rc" -eq 0 ]
expect "new-secrets existing message" has "$out" "using existing local secrets"
out=$(AGE_KEY_FILE="$T/A.txt" SOPS_CONFIG="$T/local.sops.yaml" PUBKEY="$PUB_A" bash -c 'source "$1"; ACTIVE_SECRETS="$2"; check_secrets' _ "$BOOT" "$LOCAL_REAL" 2>&1)
rc=$?
expect "empty local secrets do not block" [ "$rc" -eq 0 ]
expect "empty local secrets warning" has "$out" "local secrets are empty"

rm -f "$LOCAL_REAL"
out=$(AGE_KEY_FILE="$T/A.txt" SOPS_CONFIG="$T/missing.sops.yaml" LOCAL_SECRETS="$LOCAL_REAL" PUBKEY="$PUB_A" bash -c 'source "$1"; new_secrets' _ "$BOOT" 2>&1)
rc=$?
expect "new-secrets missing config exits 2" [ "$rc" -eq 2 ]
expect "new-secrets leaves no file" [ ! -e "$LOCAL_REAL" ]

mkdir -p "$T/localdir" "$T/tmpdir"
LOCAL_FAIL="$T/localdir/secrets.yaml"
out=$(TMPDIR="$T/tmpdir" AGE_KEY_FILE="$T/B.txt" SOPS_CONFIG="$T/local.sops.yaml" LOCAL_SECRETS="$LOCAL_FAIL" PUBKEY="$PUB_A" bash -c 'source "$1"; new_secrets' _ "$BOOT" 2>&1)
rc=$?
expect "new-secrets decrypt failure exits 2" [ "$rc" -eq 2 ]
expect "new-secrets leaves no target on failure" [ ! -e "$LOCAL_FAIL" ]
expect "new-secrets leaves no partial in target dir" [ -z "$(find "$T/localdir" -name '.wsl-secrets.*' -print -quit)" ]
expect "new-secrets leaves no plaintext template" [ -z "$(find "$T/tmpdir" -name 'tmp.*' -print -quit)" ]

before=$(sha256sum "$T/local.sops.yaml" | cut -d' ' -f1)
LOCAL_OTHER="$T/localdir/other-secrets.yaml"
out=$(AGE_KEY_FILE="$T/A.txt" SOPS_CONFIG="$T/local.sops.yaml" LOCAL_SECRETS="$LOCAL_OTHER" PUBKEY="$PUB_A" bash -c 'source "$1"; new_secrets' _ "$BOOT" 2>&1)
rc=$?
after=$(sha256sum "$T/local.sops.yaml" | cut -d' ' -f1)
expect "new-secrets successful run exits 0" [ "$rc" -eq 0 ]
expect "new-secrets does not edit sops config" [ "$before" = "$after" ]

# --- package manager command mapping
expect "apt install cmd" has "$(DRY_RUN=1 PKG_MANAGER=apt install_packages zsh 2>&1)" "sudo apt-get install -y zsh"
expect "pacman install cmd" has "$(DRY_RUN=1 PKG_MANAGER=pacman install_packages zsh 2>&1)" "sudo pacman -S --needed --noconfirm zsh"
expect "dnf install cmd" has "$(DRY_RUN=1 PKG_MANAGER=dnf install_packages zsh 2>&1)" "sudo dnf install -y zsh"
expect "zypper install cmd" has "$(DRY_RUN=1 PKG_MANAGER=zypper install_packages zsh 2>&1)" "sudo zypper --non-interactive install zsh"

# --- locale handling (fixture locale.gen, stubbed locale/locale-gen)
mkdir -p "$T/bin"
printf '#en_US.UTF-8 UTF-8\n' > "$T/locale.gen"
cat > "$T/bin/locale" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$T/bin/locale-gen" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$T/bin/locale" "$T/bin/locale-gen"
out=$(PATH="$T/bin:$PATH" PKG_MANAGER=arch LOCALE_GEN="$T/locale.gen" bash -c 'source "$1"; DRY_RUN=1; ensure_locale' _ "$BOOT" 2>&1)
expect "locale uncomments locale.gen" has "$out" "sed -i -E"
expect "locale runs locale-gen" has "$out" "locale-gen"

# --- refusals (Review Focus 3)
out=$(HOME=/tmp/elsewhere bash "$BOOT" --dry-run 2>&1)
rc=$?
expect "wrong HOME exits 1" [ "$rc" -eq 1 ]
expect "wrong HOME message" has "$out" "expects the repo at /tmp/elsewhere/dotfiles"

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

# --- this instance, dry run (temp key/secrets so the check is hermetic)
out=$(AGE_KEY_FILE="$T/A.txt" SOPS_CONFIG="$T/.sops.yaml" SECRETS_FILE="$T/full.yaml" \
  bash "$BOOT" --dry-run 2>&1)
rc=$?
expect "dry run exits 0" [ "$rc" -eq 0 ]
expect "dry run prints DRY-RUN" has "$out" "DRY-RUN:"
expect "dry run switches" has "$out" "switch --flake $WSL#default -b hm-backup --impure"
if locale -a 2>/dev/null | grep -qix 'en_US.utf8'; then
  expect "locale present: not regenerated" lacks "$out" "locale-gen"
else
  expect "dry run generates locale" has "$out" "locale-gen"
fi
expect "nix already installed" lacks "$out" "install.determinate.systems"
expect "systemd already enabled" lacks "$out" "wsl.conf"
expect "shell already zsh" lacks "$out" "chsh"
out2=$(AGE_KEY_FILE="$T/A.txt" SOPS_CONFIG="$T/.sops.yaml" SECRETS_FILE="$T/full.yaml" \
  bash "$BOOT" --dry-run 2>&1)
expect "dry run is idempotent" [ "$out" = "$out2" ]

if ! command -v apt-get >/dev/null 2>&1 && command -v pacman >/dev/null 2>&1; then
  expect "does not call apt on Arch" lacks "$out" "apt-get"
fi

# Cleanup against a fake legacy $HOME (stub snap on PATH), never the real one.
H="$T/home"; mkdir -p "$H/.oh-my-zsh" "$H/.nvm" "$T/bin"
mkdir -p "$H/.local/bin" "$H/.local/share/claude/versions" "$H/.opencode/bin"
: > "$H/.local/bin/claude"
: > "$H/.local/share/claude/versions/1"
: > "$H/.opencode/bin/opencode"
printf '#!/bin/sh\n[ "$1" = list ] && [ "$2" = nvim ]\n' > "$T/bin/snap"; chmod +x "$T/bin/snap"
cleanup_out=$(HOME="$H" PATH="$T/bin:$PATH" bash -c 'source "$1"; DRY_RUN=1; cleanup' _ "$BOOT" 2>&1)
expect "cleanup lists oh-my-zsh" has "$cleanup_out" "~/.oh-my-zsh"
expect "cleanup lists snap nvim" has "$cleanup_out" "snap nvim"
expect "cleanup lists native claude" has "$cleanup_out" "native claude"
expect "cleanup lists native opencode" has "$cleanup_out" "native opencode"
expect "cleanup prints removals" has "$cleanup_out" "DRY-RUN: rm -rf $H/.oh-my-zsh"
expect "cleanup dry run removes nothing" [ -d "$H/.oh-my-zsh" ]
expect "cleanup dry run keeps claude payload" [ -e "$H/.local/share/claude/versions/1" ]
expect "cleanup dry run keeps opencode install" [ -e "$H/.opencode/bin/opencode" ]
expect "cleanup does not list claude data" lacks "$cleanup_out" ".claude"
expect "cleanup does not list opencode data" lacks "$cleanup_out" "local/share/opencode"
# The .sops.yaml registered locally must not block pulling the re-encrypted secrets.
out=$(AGE_KEY_FILE="$T/B.txt" SOPS_CONFIG="$T/.sops.yaml" SECRETS_FILE="$T/partial.yaml" bash "$BOOT" --dry-run 2>&1)
expect "undecryptable says to discard local .sops.yaml" has "$out" "git checkout -- wsl/.sops.yaml"

# --- update.sh secrets precedence and identity guard
mkdir -p "$T/updatebin" "$T/updatehome/dotfiles" "$T/updatehome/.config/sops-nix"
: > "$T/updatehome/.config/sops-nix/wsl-secrets.yaml"
: > "$T/custom.yaml"
cat > "$T/updatebin/nix" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *homeConfigurations.default.config.home.username*) printf '%s' "${STUB_USER:?}" ;;
  *homeConfigurations.default.config.home.homeDirectory*) printf '%s' "${STUB_HOME:?}" ;;
  *"#sops"*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat > "$T/updatebin/home-manager" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${DOTFILES_WSL_SECRETS:-}" > "${STUB_OUT:?}"
EOF
chmod +x "$T/updatebin/nix" "$T/updatebin/home-manager"
STUB_USER=$(id -un)
STUB_HOME=$T/updatehome
export STUB_USER STUB_HOME
out=$(HOME="$STUB_HOME" STUB_OUT="$T/update.out" DOTFILES_WSL_SECRETS="$T/custom.yaml" PATH="$T/updatebin:$PATH" bash "$WSL/update.sh" 2>&1)
rc=$?
expect "update.sh explicit override exits 0" [ "$rc" -eq 0 ]
expect "update.sh keeps explicit override" has "$(cat "$T/update.out")" "$T/custom.yaml"
expect "update.sh does not use local default" lacks "$(cat "$T/update.out")" "$STUB_HOME/.config/sops-nix/wsl-secrets.yaml"
out=$(env -u DOTFILES_WSL_SECRETS HOME="$STUB_HOME" STUB_OUT="$T/update.out" PATH="$T/updatebin:$PATH" bash "$WSL/update.sh" 2>&1)
rc=$?
expect "update.sh default exits 0" [ "$rc" -eq 0 ]
expect "update.sh falls back to local file" [ "$(cat "$T/update.out")" = "$STUB_HOME/.config/sops-nix/wsl-secrets.yaml" ]
out=$(HOME="$STUB_HOME" STUB_OUT="$T/update.out" DOTFILES_WSL_SECRETS="$T/custom.yaml" STUB_USER=someoneelse PATH="$T/updatebin:$PATH" bash "$WSL/update.sh" 2>&1)
rc=$?
expect "update.sh identity mismatch exits 1" [ "$rc" -eq 1 ]
expect "update.sh identity mismatch message" has "$out" "but this account is"

if [[ $failures -gt 0 ]]; then
  echo "$failures of $count bootstrap tests failed"
  exit 1
fi
echo "OK ($count bootstrap tests)"
