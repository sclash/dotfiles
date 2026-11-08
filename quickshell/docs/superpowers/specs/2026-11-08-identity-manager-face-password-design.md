# Identity Manager — Face and Password (addendum)

Extends `2026-11-08-identity-manager-design.md`, which listed Howdy as a non-goal. The current behaviour is in `specs/launchers/Identity-Manager.md`; this note records why it is built this way.

## Decisions

- **Three methods.** Password (always on, change only), face (IR camera), fingerprint (reader). Face and fingerprint default to enabled when their hardware is detected and show *Not available* otherwise.
- **Face is lock-screen only.** Howdy can be fooled by a good photo (its own docs say so), so it is never used for sudo, su, polkit, ssh or login. The `face.nix` assertion fails the build if any PAM service other than `hyprlock-face` enables it.
- **Switch without root.** hyprlock 0.9.5 has `auth:pam:module`. Two PAM services: `hyprlock` (password) and `hyprlock-face` (`pam_howdy` sufficient, then `pam_unix`). The per-user override picks one. Howdy failing, timing out or being skipped (no model, lid closed) falls through to the password.
- **Generated, not toggled, override.** `~/.local/state/hyprlock-auth.conf` is derived from the user's choices (`~/.local/state/identity/choices`) and the detected hardware on every refresh, so a reader or camera that appears later is picked up without stale state. It replaces `hyprlock-fingerprint.conf`, which is no longer read.
- **Camera detection.** A udev rule links the picture node of any camera named `*IR Camera*|*Infrared*` to `/dev/v4l/ir0`; Howdy's `device_path` defaults to it at a priority a plain `machine.nix` assignment overrides. No per-machine device path in the repo.
- **IR emitter.** `linux-enable-ir-emitter` is installed but its unit is skipped until `/dev/v4l/ir0` exists and `sudo linux-enable-ir-emitter configure` has stored a per-machine setting in `/var/lib/linux-enable-ir-emitter`. The launcher suggests that command when Howdy reports black frames.
- **Password form in the launcher.** `identity-passwd` drives `passwd` on a pty, as GNOME's `run-passwd` does: PAM's text conversation flushes typed-ahead input and reads a whole pipe buffer as one answer, so each answer is written only after its prompt. Passwords travel only on stdin. The form enforces non-empty fields and matching new passwords before anything is sent.

## Verified while designing (2026-11-08)

- HP EliteBook 845 G8 (4B7J7UC): no fingerprint part in HP's per-unit BOM, nothing on USB; IR camera `HP IR Camera` at USB interface 1.2 (`GREY` 640×360 @ 15 fps). Captured frames alternate lit/dark: the emitter strobes on its own, no `linux-enable-ir-emitter` needed on this machine.
- Howdy 3.0.0: `howdy -U <user> -y add <label>` takes the label from argv; models are JSON written by root with the default umask (world-readable); removing the last model deletes the file; `pam_howdy` returns `PAM_AUTHINFO_UNAVAIL` early without a model file. NixOS default `workaround = off`.
- hyprlock 0.9.5: the PAM thread waits for the first submitted input before `pam_authenticate`; `general:ignore_empty_input` defaults to 0, so an empty Enter starts the face check.

## Not verified

- The full lock-screen flow (Enter → face → unlock, and a password typed while Howdy is still looking) needs a rebuild on real hardware.
- The udev name match on IR cameras from other vendors.
- The fingerprint path on real hardware (no reader on the machine this was built on).
