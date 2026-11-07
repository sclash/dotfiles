#!/usr/bin/env bash
# Keeps this machine's secrets file in step with nixos/secrets/template.yaml.
# Runs before every `update`. It adds any new name as null and never changes a
# value already there. `update` carries on if this fails, because a name missing
# from the file just isn't installed yet.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO=$(dirname "$SCRIPT_DIR")
TEMPLATE="$SCRIPT_DIR/secrets/template.yaml"
SOPS_DIR="$HOME/.config/sops"
SECRETS="$SOPS_DIR/secrets.yaml"
KEY="$SOPS_DIR/age/keys.txt"
export SOPS_AGE_KEY_FILE="$KEY"

NAME_PATTERN='[A-Za-z0-9_.-]+'
TMP=""
trap '[[ -z "$TMP" ]] || rm -f "$TMP"' EXIT

fail() {
  echo "sync-secrets: $*" >&2
  exit 1
}

# Clones don't inherit git config, so each one has to turn on the hook that
# stops real values reaching the public template.
enable_hook() {
  git -C "$REPO" config --local --get core.hooksPath >/dev/null ||
    git -C "$REPO" config --local core.hooksPath .githooks
}

create_secrets() {
  local pubkey
  pubkey=$(sed -n 's/^# public key: //p' "$KEY")
  [[ -n "$pubkey" ]] || fail "no public key comment in $KEY"
  # sops looks for a .sops.yaml from the current directory, and creating a file
  # fails if it finds one with no matching rule, so create it from its own folder.
  (cd "$SOPS_DIR" && umask 077 && sops encrypt --age "$pubkey" --output "$SECRETS" "$TEMPLATE") ||
    fail "could not create $SECRETS"
  echo "Created $SECRETS"
}

# Works on a copy, which replaces the file only if it holds everything the file
# already did.
add_missing_names() {
  local -a missing=()
  local -A present=()
  local name
  while read -r name; do
    present[$name]=1
  done < <(sed -nE "s/^($NAME_PATTERN):.*/\\1/p" "$SECRETS")
  while read -r name; do
    [[ -n "${present[$name]:-}" ]] || missing+=("$name")
  done < <(sed -nE "s/^($NAME_PATTERN): null\$/\\1/p" "$TEMPLATE")
  ((${#missing[@]})) || return 0

  TMP=$(umask 077 && mktemp -p "$SOPS_DIR" --suffix=.yaml) || fail "could not create a temporary file"
  cp "$SECRETS" "$TMP" || fail "could not copy $SECRETS"
  for name in "${missing[@]}"; do
    sops set "$TMP" "[\"$name\"]" null || fail "could not add $name; $SECRETS is unchanged"
  done

  local before after
  before=$(sops -d "$SECRETS") || fail "could not read $SECRETS; it is unchanged"
  after=$(sops -d "$TMP" | grep -vxFf <(printf '%s: null\n' "${missing[@]}"))
  [[ "$before" == "$after" ]] || fail "adding names would change existing values; $SECRETS is unchanged"

  mv "$TMP" "$SECRETS" || fail "could not update $SECRETS"
  TMP=""
  echo "Added to $SECRETS: ${missing[*]}"
}

report_unset() {
  local -a unset_names
  mapfile -t unset_names < <(sed -nE "s/^($NAME_PATTERN): null\$/\\1/p" "$SECRETS")
  ((${#unset_names[@]})) || return 0
  echo "Secrets not set on this machine: ${unset_names[*]}"
  echo "To set them: sops edit ~/.config/sops/secrets.yaml, then update"
}

[[ -f "$TEMPLATE" ]] || fail "no template at $TEMPLATE"
[[ -f "$KEY" ]] || fail "no age key at $KEY. See SOPS-README.md"
command -v sops >/dev/null || fail "sops is not on PATH"

enable_hook
[[ -f "$SECRETS" ]] || create_secrets
add_missing_names
report_unset
