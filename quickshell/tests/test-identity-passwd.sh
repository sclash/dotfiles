#!/usr/bin/env bash
# Tests quickshell/scripts/identity-passwd.py against a fake passwd that
# prompts like shadow's passwd + pam_unix (LC_ALL=C). No real password is
# touched. Run from anywhere: bash quickshell/tests/test-identity-passwd.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
helper="$here/../scripts/identity-passwd.py"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/passwd" <<'STUB'
#!/usr/bin/env bash
# FAKE_MODE: ok | short | flush. FAKE_CURRENT: the accepted current password.
mode=${FAKE_MODE:-ok}
flush() { [[ $mode == flush ]] && { sleep 0.2; python3 -c 'import termios; termios.tcflush(0, termios.TCIFLUSH)'; }; }
echo "Changing password for tester."
flush; read -rsp "Current password: " cur; echo
if [[ $cur != "$FAKE_CURRENT" ]]; then
  echo "passwd: Authentication token manipulation error"
  echo "passwd: password unchanged"
  exit 10
fi
for _ in 1 2 3; do
  flush; read -rsp "New password: " n1; echo
  if [[ $mode == short && ${#n1} -lt 8 ]]; then
    echo "BAD PASSWORD: The password is shorter than 8 characters"; continue
  fi
  if [[ $n1 == "$cur" ]]; then echo "Password unchanged"; continue; fi
  flush; read -rsp "Retype new password: " n2; echo
  if [[ $n1 != "$n2" ]]; then echo "Sorry, passwords do not match."; continue; fi
  printf '%s' "$n1" > "$FAKE_RECORD"
  echo "passwd: password updated successfully"
  exit 0
done
echo "passwd: Have exhausted maximum number of retries for service"
echo "passwd: password unchanged"
exit 10
STUB
chmod +x "$work/passwd"

failures=0
# run <mode> <current-typed> <new> -> stdout of the helper
run() {
  rm -f "$work/record"
  printf '%s\n%s\n' "$2" "$3" | \
    FAKE_MODE="$1" FAKE_CURRENT="old-secret" FAKE_RECORD="$work/record" \
    IDENTITY_PASSWD_BIN="$work/passwd" timeout 40 python3 "$helper"
}
expect() { # actual expected description
  if [[ "$1" == "$2" ]]; then echo "OK   $3"; else echo "FAIL $3 (got: $1, want: $2)"; failures=$((failures + 1)); fi
}

out=$(run ok old-secret new-secret-123)
expect "$out" "OK" "valid change reports OK"
expect "$(cat "$work/record" 2>/dev/null)" "new-secret-123" "passwd received the new password"

out=$(run flush old-secret new-secret-123)
expect "$out" "OK" "answers only after each prompt (survives input flush)"

out=$(run ok wrong-secret new-secret-123)
expect "$out" "BAD_CURRENT" "wrong current password reports BAD_CURRENT"
[[ ! -e "$work/record" ]]; expect "$?" "0" "nothing changed on a wrong current password"

out=$(run short old-secret abc)
expect "$out" "REJECTED BAD PASSWORD: The password is shorter than 8 characters" "weak password is REJECTED with PAM's reason"

out=$(run ok old-secret old-secret)
expect "$out" "REJECTED Password unchanged" "same password is REJECTED"

out=$(printf 'only-one-line' | IDENTITY_PASSWD_BIN="$work/passwd" python3 "$helper")
expect "${out%% *}" "ERROR" "missing input is an ERROR"

out=$(printf 'a\nb\n' | IDENTITY_PASSWD_BIN="$work/does-not-exist" python3 "$helper")
expect "$out" "ERROR passwd not found" "missing passwd binary is an ERROR"

all=$(run short old-secret abc; run ok wrong-secret new-secret-123)
if [[ $all == *old-secret* || $all == *new-secret* || $all == *abc* ]]; then
  echo "FAIL output leaks a password"; failures=$((failures + 1))
else
  echo "OK   output never contains a password"
fi

if ((failures)); then echo "$failures identity-passwd tests failed"; exit 1; fi
echo "OK (identity-passwd tests)"
