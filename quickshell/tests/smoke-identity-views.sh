#!/usr/bin/env bash
# Loads every Identity Manager view inside Quickshell (offscreen, no
# compositor needed) and runs the checks in smoke/identity-views.qml.
# HOME is a temporary directory so IdentityService never touches real state.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Quickshell only loads files under its config root, so build one with the
# smoke shell at the top and copies of what the views import.
root="$tmp/qs"
mkdir -p "$root"
cp -r "$here/../components" "$here/../services" "$here/../theme" "$root/"
cp "$here/smoke/identity-views.qml" "$root/shell.qml"

# A stand-in identity-passwd: makes the password form live, and records any
# call, because a mismatched form must never reach it.
mkdir -p "$tmp/bin"
printf '#!/bin/sh\ntouch "%s/passwd-called"\necho "ERROR stub"\n' "$tmp" > "$tmp/bin/identity-passwd"
chmod +x "$tmp/bin/identity-passwd"

# QS_NO_POLKIT_AGENT: never register a second polkit agent in the live session.
HOME="$tmp" PATH="$tmp/bin:$PATH" QS_NO_POLKIT_AGENT=1 QT_QPA_PLATFORM=offscreen timeout 60 \
  quickshell -p "$root/shell.qml" > "$tmp/log" 2>&1

grep -oE 'SMOKE (OK|FAIL|DONE).*' "$tmp/log"
fail=0
if [[ -e "$tmp/passwd-called" ]]; then
  echo "FAIL identity-passwd was called for a form that should have been refused"
  fail=1
fi
state="$tmp/.local/state"
if [[ "$(cat "$state/identity/choices" 2>/dev/null)" == "face=off" ]]; then
  echo "OK   setChoice wrote ~/.local/state/identity/choices"
else
  echo "FAIL choices file: $(cat "$state/identity/choices" 2>&1)"; fail=1
fi
if grep -q 'module = hyprlock$' "$state/hyprlock-auth.conf" 2>/dev/null \
   && ! grep -q 'label {' "$state/hyprlock-auth.conf"; then
  echo "OK   face off -> hyprlock-auth.conf selects the password-only PAM service"
else
  echo "FAIL hyprlock-auth.conf: $(cat "$state/hyprlock-auth.conf" 2>&1)"; fail=1
fi
if ((fail)) || ! grep -q 'SMOKE DONE failures=0' "$tmp/log"; then
  echo "--- quickshell log (errors) ---"
  grep -iE 'error|warn|unavailable|cannot|failed' "$tmp/log" | head -20
  exit 1
fi
echo "OK (identity view smoke tests)"
