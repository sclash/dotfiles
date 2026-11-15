#!/usr/bin/env bash
# Offscreen lifecycle smoke for AirPodsService: runs the checks in
# smoke/airpods-lifecycle.qml against a stub systemctl and a stub bluetoothctl.
# No real service, no real systemctl and no real AirPods are touched.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/qs"
mkdir -p "$root"
cp -r "$here/../services" "$here/../theme" "$root/"
cp "$here/smoke/airpods-lifecycle.qml" "$root/shell.qml"

mkdir -p "$tmp/bin" "$tmp/state"
cat > "$tmp/bin/systemctl" <<'STUB'
#!/bin/sh
# Stand-in systemctl: logs the verb, writes a status file on the first start,
# fails the second start and starts silently on the third (the timeout case).
verb="$2"
printf '%s\n' "$verb" >> "$AIRPODS_SYSTEMCTL_LOG"
case "$verb" in
  start)
    n=$(cat "$AIRPODS_SYSTEMCTL_COUNT" 2>/dev/null || echo 0)
    n=$((n + 1))
    printf '%s\n' "$n" > "$AIRPODS_SYSTEMCTL_COUNT"
    if [ "$n" -eq 1 ]; then
      printf '%s\n' '{"schema_version":1,"connected":false}' > "$AIRPODS_STATE"
    elif [ "$n" -eq 2 ]; then
      echo "stub: unit failed to start" >&2
      exit 1
    fi
    ;;
  stop)
    rm -f "$AIRPODS_STATE"
    ;;
esac
exit 0
STUB
chmod +x "$tmp/bin/systemctl"

cat > "$tmp/bin/bluetoothctl" <<'STUB'
#!/bin/sh
# Stand-in bluetoothctl: a controller and no connected devices, so the real
# AirPods can never keep wantDaemon true.
case "$1" in
  show) printf 'Controller 00:00:00:00:00:00 stub\nPowered: yes\n' ;;
esac
exit 0
STUB
chmod +x "$tmp/bin/bluetoothctl"

: > "$tmp/systemctl.log"
printf '0\n' > "$tmp/systemctl.count"

HOME="$tmp" XDG_STATE_HOME="$tmp/state" PATH="$tmp/bin:$PATH" \
  AIRPODS_STATE="$tmp/status.json" \
  AIRPODS_START_TIMEOUT_MS=500 \
  AIRPODS_SYSTEMCTL_LOG="$tmp/systemctl.log" \
  AIRPODS_SYSTEMCTL_COUNT="$tmp/systemctl.count" \
  QT_QPA_PLATFORM=offscreen timeout 90 \
  quickshell -p "$root/shell.qml" > "$tmp/log" 2>&1

grep -oE 'SMOKE (OK|FAIL|DONE).*' "$tmp/log"
fail=0
if grep -q 'SMOKE DONE failures=0' "$tmp/log"; then
  mapfile -t calls < "$tmp/systemctl.log"
  starts=$(grep -c '^start$' "$tmp/systemctl.log" || true)
  stops=$(grep -c '^stop$' "$tmp/systemctl.log" || true)
  if [[ ${#calls[@]} -lt 5 || ${calls[0]} != start || ${calls[1]} != stop ]]; then
    echo "FAIL the first open did not start once and the close did not stop: ${calls[*]}"
    fail=1
  fi
  if [[ "$starts" -ne 3 ]]; then
    echo "FAIL expected 3 starts (open, failed start, panel retry), got $starts: ${calls[*]}"
    fail=1
  fi
  if [[ "$stops" -lt 3 ]]; then
    echo "FAIL expected 3 stops (close, timeout, final close), got $stops: ${calls[*]}"
    fail=1
  fi
  if [[ ${calls[-1]} != stop ]]; then
    echo "FAIL the final close did not stop the unit: ${calls[*]}"
    fail=1
  fi
  last_start=-1
  for i in "${!calls[@]}"; do
    [[ ${calls[$i]} == start ]] && last_start=$i
  done
  stop_after=0
  for ((i = last_start + 1; i < ${#calls[@]}; i++)); do
    [[ ${calls[$i]} == stop ]] && stop_after=1
  done
  if ((!stop_after)); then
    echo "FAIL no stop after the timed-out start: ${calls[*]}"
    fail=1
  fi
  ((fail)) || echo "OK   systemctl calls: ${calls[*]}"
else
  fail=1
fi
if ((fail)); then
  echo "--- quickshell log (errors) ---"
  grep -iE 'error|warn|unavailable|cannot|failed' "$tmp/log" | head -20
  exit 1
fi
echo "OK (AirPods lifecycle smoke tests)"
