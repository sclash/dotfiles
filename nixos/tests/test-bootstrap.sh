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
  mkdir -p "$H/dotfiles/nixos/secrets" "$T/bin" "$T/machine"
  cp "$SCRIPT" "$H/dotfiles/nixos/bootstrap.sh"
  printf 'creation_rules:\n  - path_regex: nixos/secrets/.*\n    age: age1existing\n' >"$H/dotfiles/.sops.yaml"
  echo 'x: ENC' >"$H/dotfiles/nixos/secrets/secrets.yaml"
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
  cat >"$T/bin/age-keygen" <<'S'
#!/usr/bin/env bash
echo "age-keygen $*" >>"$CALLS"
if [[ "$1" == -o ]]; then echo 'AGE-SECRET-KEY-NEW' >"$2"; exit 0; fi
if [[ "$1" == -y ]]; then
  grep -q 'AGE-SECRET-KEY' "$2" || exit 1
  echo age1thismachine
fi
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
check "generated key mode" "$(stat -c %a "$H/.config/sops/age/keys.txt")" 600
contains "tools from the flake lock" "$CALLS_TXT" "--inputs-from $H/dotfiles/nixos nixpkgs#age"

# A broken flake stops before anything is installed.
setup
REBUILD_EXIT=1 run_bootstrap
check "failed dry-build exit" "$RC" 1
contains "failed dry-build message" "$OUT" "nothing was changed"
lacks "failed dry-build installs nothing" "$(<"$LOG")" "sudo"

# Undecryptable secrets warn, print the fix, and still install.
setup
SOPS_EXIT=1 run_bootstrap
check "undecryptable secrets exit" "$RC" 0
contains "prints rekey command" "$OUT" "--add-recipient age1thismachine"
contains "still installs" "$(<"$LOG")" "nixos-rebuild boot"

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
check "dry-run creates no key" "$([[ -e "$H/.config/sops/age/keys.txt" ]] && echo yes || echo no)" no

# Imports a valid key, with the right mode.
setup
echo 'AGE-SECRET-KEY-IMPORTED' >"$T/existing.txt"
run_bootstrap --age-key "$T/existing.txt"
check "import exit" "$RC" 0
check "imported content" "$(<"$H/.config/sops/age/keys.txt")" "AGE-SECRET-KEY-IMPORTED"
check "imported mode" "$(stat -c %a "$H/.config/sops/age/keys.txt")" 600

# Rejects an invalid key without replacing the current one.
setup
mkdir -p "$H/.config/sops/age"
echo 'AGE-SECRET-KEY-CURRENT' >"$H/.config/sops/age/keys.txt"
echo 'not a key' >"$T/bad.txt"
run_bootstrap --age-key "$T/bad.txt"
check "bad key exit" "$RC" 1
check "bad key keeps current" "$(<"$H/.config/sops/age/keys.txt")" "AGE-SECRET-KEY-CURRENT"

# Adding a recipient appends once, re-encrypts, and never commits.
setup
run_bootstrap --add-recipient age1other
check "add-recipient exit" "$RC" 0
contains "appends recipient" "$(<"$H/dotfiles/.sops.yaml")" "age: age1existing,age1other"
contains "re-encrypts" "$(<"$LOG")" "updatekeys -y $H/dotfiles/nixos/secrets/secrets.yaml"
lacks "add-recipient never commits" "$(<"$LOG")" "commit"
run_bootstrap --add-recipient age1other
check "add-recipient once" "$(grep -c 'age1other' "$H/dotfiles/.sops.yaml")" 1
check "add-recipient not doubled" "$(grep -o 'age1other' "$H/dotfiles/.sops.yaml" | wc -l)" 1

# Rejects something that isn't a public key.
setup
run_bootstrap --add-recipient banana
check "bad recipient exit" "$RC" 1
contains "bad recipient unchanged" "$(<"$H/dotfiles/.sops.yaml")" "age: age1existing"

if ((FAIL)); then
  echo "FAILED: $FAIL failed, $PASS passed"
  exit 1
fi
echo "OK ($PASS bootstrap tests)"
