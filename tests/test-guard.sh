#!/usr/bin/env bash
# Self-test for check-no-hardcoded-home.sh in a throwaway git repo.
set -uo pipefail

T=$(mktemp -d)
N=$(mktemp -d)
trap 'rm -rf "$T" "$N"' EXIT
failures=0

pass() { echo "OK   $*"; }
fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

ASERGI_HOME=$(printf '/home/%s' asergi)
ALICE_HOME=$(printf '/home/%s/dotfiles' alice)

mkdir -p "$T/tests" "$T/lib"
cp "$(cd "$(dirname "$0")" && pwd)/check-no-hardcoded-home.sh" "$T/tests/check-no-hardcoded-home.sh"
printf 'home = "%s"\n' "$ASERGI_HOME" > "$T/lib/user.nix"
printf 'home = "%s"\n' "$ALICE_HOME" > "$T/functional.nix"

git -C "$T" init -q
git -C "$T" add .

out=$(bash "$T/tests/check-no-hardcoded-home.sh" 2>&1)
rc=$?
if [[ $rc -eq 1 ]] && [[ "$out" == *functional.nix* ]]; then
  pass "hardcoded functional file is rejected"
else
  fail "hardcoded functional file: rc=$rc out=$out"
fi

rm -f "$T/functional.nix"
git -C "$T" add -A
out=$(bash "$T/tests/check-no-hardcoded-home.sh" 2>&1)
rc=$?
if [[ $rc -eq 0 ]] && [[ "$out" == "OK (no hardcoded home)" ]]; then
  pass "allowed fallback passes"
else
  fail "allowed fallback: rc=$rc out=$out"
fi

mkdir -p "$N/tests"
cp "$(cd "$(dirname "$0")" && pwd)/check-no-hardcoded-home.sh" "$N/tests/check-no-hardcoded-home.sh"
out=$(bash "$N/tests/check-no-hardcoded-home.sh" 2>&1)
rc=$?
if [[ $rc -eq 2 ]] && [[ "$out" == *"git grep failed"* ]]; then
  pass "not a git repo is rejected"
else
  fail "not a git repo: rc=$rc out=$out"
fi

if ((failures)); then
  echo "$failures guard tests failed"
  exit 1
fi
echo "OK (guard tests)"
