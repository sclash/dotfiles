#!/usr/bin/env bash
# Tests nixos/sync-secrets.sh with real sops, age and git, in a throwaway HOME
# with throwaway keys. Nothing here touches this machine's secrets.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
if ! command -v sops >/dev/null || ! command -v age-keygen >/dev/null; then
  exec nix shell --inputs-from "$HERE/.." nixpkgs#age nixpkgs#sops -c bash "$0" "$@"
fi

SCRIPT="$HERE/../sync-secrets.sh"
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

# A fresh HOME with the repo at ~/dotfiles and the given names in the template.
setup() {
  T=$(mktemp -d -p "$ROOT")
  H="$T/home"
  mkdir -p "$H/dotfiles/nixos/secrets" "$T/elsewhere"
  cp "$SCRIPT" "$H/dotfiles/nixos/sync-secrets.sh"
  git -C "$H/dotfiles" init -q
  # An unrelated sops config in the working directory must not get in the way.
  printf 'creation_rules:\n  - path_regex: nothing-matches$\n    age: age1x\n' >"$T/elsewhere/.sops.yaml"
  KEY="$H/.config/sops/age/keys.txt"
  SECRETS="$H/.config/sops/secrets.yaml"
  template "$@"
}

template() {
  printf '%s: null\n' "$@" >"$H/dotfiles/nixos/secrets/template.yaml"
}

new_key() {
  mkdir -p "$(dirname "$KEY")"
  age-keygen -o "$KEY" 2>/dev/null
}

sync_secrets() {
  OUT=$(cd "$T/elsewhere" && env -u SOPS_AGE_KEY_FILE HOME="$H" bash "$H/dotfiles/nixos/sync-secrets.sh" 2>&1)
  RC=$?
}

decrypted() {
  SOPS_AGE_KEY_FILE="$KEY" sops -d "$SECRETS" 2>&1
}

# Sets one value the way you would, through sops edit.
fill() {
  (cd "$T/elsewhere" && SOPS_AGE_KEY_FILE="$KEY" NAME="$1" VALUE="$2" EDITOR="$T/set-value" sops edit "$SECRETS")
}

set_value_editor() {
  cat >"$T/set-value" <<'S'
#!/usr/bin/env bash
sed -i "s|^$NAME: .*|$NAME: $VALUE|" "$1"
S
  chmod +x "$T/set-value"
}

leftovers() {
  find "$H/.config/sops" -maxdepth 1 -name 'tmp.*' | wc -l
}

# No age key: stops, and creates nothing.
setup alpha
sync_secrets
check "no key exit" "$RC" 1
contains "no key message" "$OUT" "no age key"
check "no key creates no file" "$([[ -e "$SECRETS" ]] && echo yes || echo no)" no

# A key and no file: creates it from the template, with every name null.
setup alpha beta
new_key
sync_secrets
check "create exit" "$RC" 0
contains "create says so" "$OUT" "Created $SECRETS"
check "created mode" "$(stat -c %a "$SECRETS")" 600
check "created names are null" "$(decrypted)" $'alpha: null\nbeta: null'
contains "lists unset names" "$OUT" "not set on this machine: alpha beta"
check "turns on the hook" "$(git -C "$H/dotfiles" config --local --get core.hooksPath)" .githooks
check "create leaves no temp file" "$(leftovers)" 0

# Another machine's key can't open it.
cp "$KEY" "$T/this-machine"
age-keygen -o "$T/other" 2>/dev/null
SOPS_AGE_KEY_FILE="$T/other" sops -d "$SECRETS" >/dev/null 2>&1
check "other key is refused" "$?" 128

# A new name is added as null, and filled-in values are kept exactly.
setup alpha beta
set_value_editor
new_key
sync_secrets
fill alpha real-alpha-value
fill beta real-beta-value
ALPHA_LINE=$(grep '^alpha:' "$SECRETS")
template alpha beta gamma
sync_secrets
check "add exit" "$RC" 0
contains "add says so" "$OUT" "Added to $SECRETS: gamma"
check "keeps values and adds null" "$(decrypted)" $'alpha: real-alpha-value\nbeta: real-beta-value\ngamma: null'
check "doesn't touch existing ciphertext" "$(grep '^alpha:' "$SECRETS")" "$ALPHA_LINE"
check "add keeps mode" "$(stat -c %a "$SECRETS")" 600
check "add leaves no temp file" "$(leftovers)" 0
contains "lists only the unset name" "$OUT" "not set on this machine: gamma"

# Nothing to do: the file isn't rewritten.
BEFORE=$(sha256sum "$SECRETS")
sync_secrets
check "no-op exit" "$RC" 0
check "no-op leaves file identical" "$(sha256sum "$SECRETS")" "$BEFORE"
lacks "no-op adds nothing" "$OUT" "Added"

# Everything filled in: nothing to report.
fill gamma real-gamma-value
sync_secrets
check "all filled exit" "$RC" 0
check "all filled says nothing" "$OUT" ""

# A name removed from the template keeps its value in the file.
template alpha gamma
sync_secrets
check "removed name exit" "$RC" 0
contains "removed name's value stays" "$(decrypted)" "beta: real-beta-value"

# Several new names at once.
template alpha gamma delta epsilon
sync_secrets
contains "adds several" "$OUT" "Added to $SECRETS: delta epsilon"
contains "keeps value alongside several" "$(decrypted)" "gamma: real-gamma-value"

# A key that can't open the file: leaves it alone and says why.
setup alpha
new_key
sync_secrets
age-keygen -o "$KEY.new" 2>/dev/null
mv "$KEY.new" "$KEY"
template alpha beta
BEFORE=$(sha256sum "$SECRETS")
sync_secrets
check "wrong key exit" "$RC" 1
contains "wrong key names the file" "$OUT" "$SECRETS is unchanged"
check "wrong key leaves file identical" "$(sha256sum "$SECRETS")" "$BEFORE"
check "wrong key leaves no temp file" "$(leftovers)" 0

# An existing hook setting is kept.
setup alpha
new_key
git -C "$H/dotfiles" config --local core.hooksPath custom-hooks
sync_secrets
check "keeps existing hook setting" "$(git -C "$H/dotfiles" config --local --get core.hooksPath)" custom-hooks

if ((FAIL)); then
  echo "FAILED: $FAIL failed, $PASS passed"
  exit 1
fi
echo "OK ($PASS sync-secrets tests)"
