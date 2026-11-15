#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/qs"
mkdir -p "$root"
cp -r "$here/../components" "$here/../services" "$here/../theme" "$root/"
cp "$here/smoke/airpods.qml" "$root/shell.qml"

mkdir -p "$tmp/state/librepods" "$tmp/bin"
cat > "$tmp/state/librepods/status.json" <<'JSON'
{"schema_version":1,"connected":true,"device_name":"Test AirPods","model_name":"AirPods 5","model_number":"A3439","is_pro_series":false,"is_headset":false,"supports_noise_off":true,"supports_noise_control":true,"supports_adaptive":true,"supports_conversational_awareness":true,"supports_one_bud_anc":true,"noise_mode":3,"adaptive_noise_level":60,"one_bud_anc_mode":true,"conversational_awareness":true,"ear_detection_behavior":0,"lid_state":0,"left":{"available":true,"charging":false,"in_ear":true,"level":93},"right":{"available":true,"charging":true,"in_ear":false,"level":97},"case":{"available":true,"charging":false,"level":82},"headset":{"available":false,"charging":false,"level":0}}
JSON
cat > "$tmp/bin/librepods-ctl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$AIRPODS_CTL_LOG"
case "$*" in
  ear:both|ear:off) echo "stub failure" >&2; exit 1 ;;
esac
exit 0
STUB
chmod +x "$tmp/bin/librepods-ctl"
: > "$tmp/ctl.log"

HOME="$tmp" XDG_STATE_HOME="$tmp/state" PATH="$tmp/bin:$PATH" \
  AIRPODS_STATE="$tmp/state/librepods/status.json" \
  AIRPODS_CTL="$tmp/bin/librepods-ctl" AIRPODS_CTL_LOG="$tmp/ctl.log" \
  AIRPODS_NO_LIFECYCLE=1 QT_QPA_PLATFORM=offscreen timeout 90 \
  quickshell -p "$root/shell.qml" > "$tmp/log" 2>&1

grep -oE 'SMOKE (OK|FAIL|DONE).*' "$tmp/log"
if ! grep -q 'SMOKE DONE failures=0' "$tmp/log"; then
  grep -iE 'error|warn|unavailable|cannot|failed' "$tmp/log" | head -20
  exit 1
fi
for verb in adaptive:65 ca:on onebud:on ear:both; do
  grep -qxF "$verb" "$tmp/ctl.log" || { echo "FAIL missing verb $verb"; exit 1; }
done
echo "OK (AirPods smoke tests)"
