#!/usr/bin/env bash
# Tests quickshell/scripts/share-picker.sh (the XDPH custom picker) against a
# fake fallback picker. Touches no real portal or runtime file.
# Run from anywhere: bash quickshell/tests/test-share-picker.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
picker="$here/../scripts/share-picker.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/fallback" <<'STUB'
#!/usr/bin/env bash
echo "FALLBACK $*"
STUB
chmod +x "$work/fallback"

export QS_CAST_SOURCE_FILE="$work/source"
export QS_SHARE_PICKER_FALLBACK="$work/fallback"
# 0x56ce7e76fc80 = 95444884978816, 0x56ce7dc8b390 = 95444873556880
export XDPH_WINDOW_SHARING_LIST="11[HC>]ghostty[HT>]term[HE>]95444884978816[HA>]22[HC>]google-chrome[HT>]Meet[HE>]95444873556880[HA>]"

fails=0
check() { # name expected actual
    if [[ "$2" == "$3" ]]; then echo "ok   $1"
    else echo "FAIL $1: expected [$2] got [$3]"; fails=$((fails + 1)); fi
}
run() { bash "$picker" "$@"; }
choose() { printf '%s\n' "$1" > "$QS_CAST_SOURCE_FILE"; }

check "no choice -> stock picker, args kept" "FALLBACK --allow-token" "$(run --allow-token)"

choose "screen:SCREENCAST"
check "screen choice" "[SELECTION]/screen:SCREENCAST" "$(run)"
check "screen output keeps the newline XDPH strips" "$(printf '[SELECTION]/screen:SCREENCAST\n' | od -c)" "$(choose screen:SCREENCAST; run | od -c)"

choose "screen:SCREENCAST"; run >/dev/null
check "choice is one-shot" "FALLBACK " "$(run)"

choose "window:0x56ce7dc8b390"
check "window with 0x -> toplevel handle" "[SELECTION]/window:22" "$(run)"
choose "window:56ce7e76fc80"
check "window without 0x -> toplevel handle" "[SELECTION]/window:11" "$(run)"
choose "window:0xdeadbeef"
check "closed window -> stock picker" "FALLBACK " "$(run)"
choose "window:0xnothex"
check "malformed address -> stock picker" "FALLBACK " "$(run)"
choose "bogus"
check "unknown choice -> stock picker" "FALLBACK " "$(run)"

choose "screen:SCREENCAST"; touch -d '-2 minutes' "$QS_CAST_SOURCE_FILE"
check "stale choice -> stock picker" "FALLBACK " "$(run)"
check "stale choice is removed" "absent" "$([[ -e $QS_CAST_SOURCE_FILE ]] && echo present || echo absent)"

XDPH_WINDOW_SHARING_LIST="" choose "window:0x56ce7dc8b390"
check "no window list -> stock picker" "FALLBACK " "$(XDPH_WINDOW_SHARING_LIST='' run)"

if (( fails )); then echo "$fails failure(s)"; exit 1; fi
echo "all share-picker tests passed"
