#!/usr/bin/env bash
# Tests nixos/bootstrap.sh in a throwaway HOME with stubbed commands. Nothing
# real is rebuilt, and sudo, nix and nixos-rebuild never run.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../bootstrap.sh"
PASS=0
FAIL=0

check() {
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (expected '$3', got '$2')"
  fi
}

contains() {
  if grep -qF -- "$3" <<<"$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (missing '$3')"
    printf '%s\n' "$2" | sed 's/^/    /'
  fi
}

lacks() {
  if grep -qF -- "$3" <<<"$2"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (unexpected '$3')"
  else
    PASS=$((PASS + 1))
  fi
}

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# Each test gets a fresh HOME with the repo at ~/dotfiles and stubbed tools.
setup() {
  T=$(mktemp -d -p "$ROOT")
  H="$T/home"
  mkdir -p "$H/dotfiles/nixos" "$H/.config/sops/age" "$T/bin" "$T/machine"
  cp "$SCRIPT" "$H/dotfiles/nixos/bootstrap.sh"
  # What the installer leaves behind.
  KEY="$H/.config/sops/age/keys.txt"
  SECRETS="$H/.config/sops/secrets.yaml"
  echo 'AGE-SECRET-KEY-CURRENT' >"$KEY"
  echo 'github_pat: null' >"$SECRETS"
  touch "$T/machine/hardware-configuration.nix" "$T/machine/machine.nix"
  LOG="$T/calls.log"
  touch "$LOG"

  # nix shell ... -c CMD runs CMD, which is itself stubbed below.
  cat >"$T/bin/nix" <<'S'
#!/usr/bin/env bash
echo "nix $*" >>"$CALLS"
while (($#)) && [[ "$1" != -c ]]; do shift; done
shift
exec "$@"
S
  cat >"$T/bin/sops" <<'S'
#!/usr/bin/env bash
echo "sops $*" >>"$CALLS"
exit "${SOPS_EXIT:-0}"
S
  cat >"$T/bin/nixos-rebuild" <<'S'
#!/usr/bin/env bash
echo "nixos-rebuild $*" >>"$CALLS"
exit "${REBUILD_EXIT:-0}"
S
  cat >"$T/bin/sudo" <<'S'
#!/usr/bin/env bash
echo "sudo $*" >>"$CALLS"
S
  cat >"$T/bin/git" <<'S'
#!/usr/bin/env bash
echo "git $*" >>"$CALLS"
if [[ "$*" == *"submodule status"* ]]; then echo "-abc neovimrc"; fi
S
  chmod +x "$T"/bin/*
}

run_bootstrap() {
  OUT=$(env HOME="$H" USER=tester PATH="$T/bin:$PATH" CALLS="$LOG" \
    DOTFILES_MACHINE_DIR="$T/machine" SOPS_EXIT="${SOPS_EXIT:-0}" \
    REBUILD_EXIT="${REBUILD_EXIT:-0}" AGE_KEY_FILE="$H/.config/sops/age/keys.txt" \
    bash "$H/dotfiles/nixos/bootstrap.sh" "$@" </dev/null 2>&1)
  RC=$?
}

# Installs for next boot, and dry-builds first.
setup
run_bootstrap
check "full run exit" "$RC" 0
CALLS_TXT=$(<"$LOG")
contains "dry-build first" "$(grep nixos-rebuild "$LOG" | head -1)" "nixos-rebuild dry-build --flake $H/dotfiles/nixos#default --impure"
contains "installs with boot" "$CALLS_TXT" "sudo env SUDO_USER=tester DOTFILES_HOME=$H nixos-rebuild boot --flake $H/dotfiles/nixos#default --impure"
lacks "never switches a running session" "$CALLS_TXT" "nixos-rebuild switch"
contains "submodule over https" "$CALLS_TXT" "url.https://github.com/.insteadOf=git@github.com: submodule update --init neovimrc"
lacks "never a recursive submodule init" "$CALLS_TXT" "--recursive"
contains "tools from the flake lock" "$CALLS_TXT" "--inputs-from $H/dotfiles/nixos nixpkgs#sops"
contains "checks the machine's own secrets" "$CALLS_TXT" "sops -d $SECRETS"
contains "says how to enter credentials" "$OUT" "sops edit ~/.config/sops/secrets.yaml"
check "keeps the key" "$(<"$KEY")" "AGE-SECRET-KEY-CURRENT"
check "keeps the secrets" "$(<"$SECRETS")" "github_pat: null"

# A broken flake stops before anything is installed.
setup
REBUILD_EXIT=1 run_bootstrap
check "failed dry-build exit" "$RC" 1
contains "failed dry-build message" "$OUT" "nothing was changed"
lacks "failed dry-build installs nothing" "$(<"$LOG")" "sudo"

# Undecryptable secrets warn, and still install.
setup
SOPS_EXIT=1 run_bootstrap
check "undecryptable secrets exit" "$RC" 0
contains "warns about the file" "$OUT" "can't read $SECRETS"
contains "still installs" "$(<"$LOG")" "nixos-rebuild boot"
check "undecryptable file kept" "$(<"$SECRETS")" "github_pat: null"

# Missing secrets warn too, and bootstrap doesn't create them: the installer does.
setup
rm "$SECRETS"
run_bootstrap
check "missing secrets exit" "$RC" 0
contains "warns about the missing file" "$OUT" "can't read $SECRETS"
contains "missing secrets still installs" "$(<"$LOG")" "nixos-rebuild boot"
check "creates no secrets" "$([[ -e "$SECRETS" ]] && echo yes || echo no)" no

# Missing machine layer: action needed, nothing done.
setup
rm "$T/machine/machine.nix"
run_bootstrap
check "missing machine.nix exit" "$RC" 2
contains "names the missing file" "$OUT" "machine.nix is missing"
lacks "missing machine.nix installs nothing" "$(<"$LOG")" "nixos-rebuild"

# Must live at ~/dotfiles.
setup
mkdir -p "$H/elsewhere/nixos"
mv "$H/dotfiles/nixos/bootstrap.sh" "$H/elsewhere/nixos/"
OUT=$(env HOME="$H" USER=tester PATH="$T/bin:$PATH" CALLS="$LOG" DOTFILES_MACHINE_DIR="$T/machine" \
  bash "$H/elsewhere/nixos/bootstrap.sh" </dev/null 2>&1)
check "wrong location exit" "$?" 1
contains "wrong location message" "$OUT" "must be at ~/dotfiles"

# Dry run changes nothing.
setup
run_bootstrap --dry-run
check "dry-run exit" "$RC" 0
contains "dry-run prints install" "$OUT" "DRY-RUN: sudo env SUDO_USER=tester"
lacks "dry-run runs no sudo" "$(<"$LOG")" "sudo"

# The old shared-secrets flags are gone.
setup
run_bootstrap --add-recipient age1other
check "add-recipient rejected" "$RC" 1
run_bootstrap --age-key "$KEY"
check "age-key rejected" "$RC" 1

if ((FAIL)); then
  echo "FAILED: $FAIL failed, $PASS passed"
  exit 1
fi
echo "OK ($PASS bootstrap tests)"
