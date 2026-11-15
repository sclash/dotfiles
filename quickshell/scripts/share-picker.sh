#!/usr/bin/env bash
# xdg-desktop-portal-hyprland share picker (screencopy:custom_picker_binary in
# hypr/xdph.conf). The Screen Cast launcher writes the source it wants to a
# one-shot file just before StartStream; when that file is fresh, answer the
# portal with it and show no dialog. Every other screen share (browser, OBS)
# finds no file and gets the stock hyprland-share-picker.
#
# File: $XDG_RUNTIME_DIR/quickshell-cast-source, one line:
#   screen:<output>       e.g. screen:SCREENCAST
#   window:<address>      Hyprland window address, with or without 0x
# Reply to XDPH on stdout: [SELECTION]/screen:<output> or
# [SELECTION]/window:<toplevel handle>. Tested by
# quickshell/tests/test-share-picker.sh.
set -u

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
source_file="${QS_CAST_SOURCE_FILE:-$runtime_dir/quickshell-cast-source}"
# A choice older than this belongs to a connect that never reached the
# portal; it must not silently answer a later, unrelated share.
max_age="${QS_CAST_SOURCE_MAX_AGE:-30}"
fallback="${QS_SHARE_PICKER_FALLBACK:-hyprland-share-picker}"

fallback_picker() { exec "$fallback" "$@"; }

# XDPH_WINDOW_SHARING_LIST is
#   <handle>[HC>]<class>[HT>]<title>[HE>]<window address, decimal>[HA>]...
# Print the handle whose Hyprland window address matches $1 (decimal).
handle_for_address() {
    local want="$1" list="${XDPH_WINDOW_SHARING_LIST:-}" entry
    while [[ "$list" == *"[HA>]"* ]]; do
        entry="${list%%"[HA>]"*}"
        list="${list#*"[HA>]"}"
        if [[ "${entry##*"[HE>]"}" == "$want" ]]; then
            printf '%s\n' "${entry%%"[HC>]"*}"
            return 0
        fi
    done
    return 1
}

[[ -f "$source_file" ]] || fallback_picker "$@"

age=$(( $(date +%s) - $(stat -c %Y "$source_file" 2>/dev/null || echo 0) ))
choice="$(head -n 1 "$source_file" 2>/dev/null || true)"
rm -f "$source_file"
(( age >= 0 && age <= max_age )) || fallback_picker "$@"

case "$choice" in
    screen:?*)
        # XDPH drops the last character of the output name (it expects the
        # newline), so the newline is required.
        printf '[SELECTION]/%s\n' "$choice"
        exit 0
        ;;
    window:?*)
        hex="${choice#window:}"
        hex="${hex#0x}"
        [[ "$hex" =~ ^[0-9a-fA-F]+$ ]] || fallback_picker "$@"
        if handle="$(handle_for_address "$((16#$hex))")"; then
            printf '[SELECTION]/window:%s\n' "$handle"
            exit 0
        fi
        ;;
esac

# Unknown choice or a window that no longer exists: let the user pick.
fallback_picker "$@"
