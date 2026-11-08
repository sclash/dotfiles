# Agent guide for these dotfiles

Read this before changing anything in this repo. It explains what the repo is for, the rules that keep it that way, and how to work in it.

## Philosophy

**One personal setup, on any machine.** Boot a new computer from the installer stick, answer a few questions, log in, and end up with the same desktop, tools and settings as every other machine. Nothing in this repo is written for one particular laptop. Each machine you set up should make the repo more general, never less.

That works because every setting belongs to exactly one of two layers:

| | Machine layer | Personal layer |
|---|---|---|
| **What** | Disks, encryption, swap, hibernate, bootloader, hostname, timezone, keyboard layout, build limits, `stateVersion`, hardware profile | Desktop, apps, shell, editor, themes, services you use, credential *names* |
| **Owned by** | The separate `nixos-installer` repo | This repo |
| **Lives in** | `/etc/nixos/hardware-configuration.nix` and `/etc/nixos/machine.nix`, never in git | `~/dotfiles`, the same on every machine |
| **Changes** | Once, at install time | All the time |

Some personal-layer settings still need root, such as Hyprland, greetd, pipewire, docker or printers. They stay here, because they describe the user, not the hardware.

These principles follow from it:

- **Detect, don't assume.** Sizes come from what the installer measures, hardware comes from `nixos-generate-config`, and every suggestion can be edited. Never pick a value because it suits the machine in front of you.
- **Generic defaults, per-machine data.** The repo holds defaults that are right everywhere. Anything that differs between machines, whether settings or secrets, lives on that machine.
- **Fail soft.** A broken step leaves a working system and prints the exact next command. Scripts are safe to re-run, and never replace a key or credentials that already exist.
- **Verify, then claim.** Prove behaviour with tests, VMs and dry-builds before calling something done, and say plainly what wasn't tested.

## Hard rules

### Nothing machine-specific in this repo

Never add any of these:

- hostname, timezone, keyboard layout, `system.stateVersion`
- bootloader settings, file systems, disk UUIDs, swap or partition sizes
- CPU or GPU vendor options: NVIDIA, Intel or AMD toggles, `kernelParams` for one device
- monitor or output names such as `eDP-1`, or fixed resolutions and scales (Hyprland uses `output = ""`, `mode = "preferred"`, `position = "auto"`)
- build limits such as `nix.settings.max-jobs` or `cores`
- `/home/<user>` paths or a fixed username

Instead:

- Paths and the user come from `homeDirectory`, `username` and `dotfiles` in `lib/user.nix`. In home-manager, use `config.home.homeDirectory`.
- Packages that don't build everywhere are guarded with `lib.meta.availableOn pkgs.stdenv.hostPlatform <pkg>`, as in `nixos/configuration.nix` and `nixos/hardware-devices/scanners.nix`. The architecture comes from the machine's hardware config, never from a hard-coded `system`.
- Power management is `services.power-profiles-daemon`. Don't add TLP or auto-cpufreq, because they conflict with it.
- If a machine needs something only it needs, it goes in that machine's `/etc/nixos/machine.nix`, which the user edits by hand. The repo never writes there.

### One generic system

- The flake has a single system, `nixosConfigurations.default`. It's only a name for the config, not a hostname. There is no `nixos-os` or per-host output, and none should be added.
- It imports the machine layer from `/etc/nixos`, so every rebuild needs `--impure`. Pure evaluation, such as `nix flake check`, uses `nixos/tests/stub-machine.nix` instead.
- To rebuild, the user runs `update`. The full command is:
  ```bash
  sudo env SUDO_USER="$USER" DOTFILES_HOME="$HOME" nixos-rebuild switch --flake ~/dotfiles/nixos#default --impure
  ```

### Secrets: a public template, private values

This repo is public, so it holds the *names* of credentials, never their values.

- `nixos/secrets/template.yaml` lists every credential as `name: null`, one per line, with no comments. Adding a credential means adding one line here. Nothing else declares names.
- Each machine has its own age key, `~/.config/sops/age/keys.txt`, and its own secrets file, `~/.config/sops/secrets.yaml`, encrypted to that key alone. Neither is in git, and machines never share either one. There is no repo-wide `.sops.yaml`, and no shared encrypted file.
- The installer's first boot creates both from the template. After that, `update` runs `nixos/sync-secrets.sh` first: it adds any new template name to the machine's file as `null`, and never changes a value that's already there.
- `nixos/sops.nix` installs only names that are in the template **and** filled in on that machine. A single `null` would make sops-nix refuse every secret, so unset ones are skipped. As a result, a file under `/run/secrets/` may be missing.
- Every consumer must guard each secret on its own:
  ```bash
  if [ -f /run/secrets/hf_token ]; then
    export HF_TOKEN="$(cat /run/secrets/hf_token)"
  fi
  ```
  Never read one secret inside another secret's check.
- The user fills in values with `sops edit ~/.config/sops/secrets.yaml`, then `update`. Never ask for, print, log or commit a real credential.
- The pre-commit hook and the build both reject any template line other than `name: null`. Don't work around them, and don't print the offending line in an error message.
- Listing `/run/secrets/` needs `sudo`, but each secret file is readable by its owner.

### Who does what

| Step | Done by |
|---|---|
| Partitions, `/etc/nixos`, user, first-boot hand-off | `nixos-installer` (`install.sh`, `first-boot.sh`) |
| A machine's age key and first secrets file | `nixos-installer` (`first-boot.sh`) |
| Submodules, the secrets check, the first build | `nixos/bootstrap.sh` |
| Adding new template names on existing machines | `nixos/sync-secrets.sh`, run by `update` |

Put first-install work in the installer. The dotfiles never generate keys, and never write to `/etc/nixos`.

### What the installer relies on in this repo

The installer, and every stick already flashed from it, depend on the items below. Changing one breaks new installs, not this repo's tests, so ask first. Any change also needs a matching installer change. The installer's `README.md` is the authoritative version of this contract.

- The repo can be cloned over HTTPS without logging in, from the branch set in the installer's `settings.nix` (currently `quickshell`). `nixos/bootstrap.sh` fetches submodules over HTTPS too.
- `nixos/bootstrap.sh` exists at that path, runs as the user on first login, and is safe to re-run. Any non-zero exit makes the installer stop and tell the user how to retry.
- `nixos/secrets/template.yaml` exists at that path, and every line is `name: null`. First boot encrypts it as-is.
- The age key is `~/.config/sops/age/keys.txt` and the secrets file is `~/.config/sops/secrets.yaml`. The installer creates both, and `nixos/sops.nix` and `nixos/sync-secrets.sh` read them.
- The machine layer is `/etc/nixos/hardware-configuration.nix` and `/etc/nixos/machine.nix`, which `nixos/flake.nix` imports.

## How to work here

- **Ask first.** Never commit, push, merge, rebuild, write to `/etc/nixos` or touch `~/.config/sops/` without the user's permission. They approve every edit.
- **Use a git worktree for every change.** The main checkout at `~/dotfiles` is what the running system reads, so it stays untouched until the user agrees to merge.
- **Be declarative.** Change the config, not the running system. No `nix-env`, `npm -g` or `pip install`. For a one-off tool, use `nix shell nixpkgs#<pkg>`, after asking.
- **New flake files must be tracked.** A flake only sees files git knows about, so `git add` new files before evaluating.
- **Test changes to a VM in a VM.** Anything that touches disks runs only in QEMU images, never on a real machine.
- **Explain changes in plain language,** say what wasn't verified, and keep commit messages short and descriptive.

## Checks before proposing a commit

The pre-commit hook runs `tests/check-no-hardcoded-home.sh` and the template check on every commit, and refuses the commit if either fails. Don't bypass it with `--no-verify`. Run the rest yourself, from the repository root or the worktree's root:

```bash
nix flake check ./nixos --no-write-lock-file
bash nixos/tests/test-bootstrap.sh
bash nixos/tests/test-sync-secrets.sh
bash nixos/tests/test-fingerprint.sh
bash nixos/tests/test-face.sh
bash quickshell/tests/run.sh
bash quickshell/tests/test-identity-passwd.sh
bash quickshell/tests/smoke-identity-views.sh
bash tests/check-no-hardcoded-home.sh
bash tests/test-user.sh
bash tests/test-guard.sh
```

To evaluate a real machine without rebuilding, point `DOTFILES_MACHINE_DIR` at a folder containing a `hardware-configuration.nix` and a `machine.nix`, and run `nixos-rebuild dry-build --flake ./nixos#default --impure`.

## Where to read more

- `README.md`: installing, a new machine, and the NixOS section.
- `SOPS-README.md`: the full secrets workflow, including adding or removing a credential and troubleshooting.
- `quickshell/AGENTS.md`: the Quickshell bar and launchers.
- `wsl/`: a separate setup for WSL, with its own secrets. Its rules differ, so don't apply this guide there.
- [`sclash/nixos-installer`](https://github.com/sclash/nixos-installer): the other half of the setup. Its `README.md` covers building and flashing the stick and the contract with these dotfiles, and its own `AGENTS.md` covers changing the installer. Read it there rather than copying it here.
