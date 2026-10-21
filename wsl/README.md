# WSL home-manager

A standalone [home-manager](https://github.com/nix-community/home-manager) flake that sets up the same CLI/TUI
environment as `../nixos` on any Ubuntu WSL instance. GUI apps and NixOS system services are left out.

- `flake.nix`: inputs (pinned to the same revisions as `nixos/flake.lock`) and `homeConfigurations.asergi`
- `home.nix`: imports, links, session variables, build limits
- `packages.nix`: the package set
- `modules/`: WSL-specific modules (zsh, herdr, secrets, opencode, claude-code)
- `opencode/`: WSL copies of the `my-opencode/v2` files that don't fit this host (see below)
- `bootstrap.sh`: brings a fresh instance up to this flake
- Shared modules come unchanged from `../nixos/programs`. Nothing outside `wsl/` is edited for WSL.

## Prerequisites (Windows side)

- WSL 2 with an Ubuntu distro, and a user named `asergi`. The repo must be cloned at `/home/asergi/dotfiles`.
- Docker Desktop with WSL integration enabled for this distro, if you want `docker` and `lazydocker`.
- A Nerd Font (e.g. JetBrainsMono Nerd Font) set in Windows Terminal. Terminal fonts are a Windows concern.
- opencode and Claude Code are installed with their native installers. Neither is managed by this flake.

## Fresh instance

```bash
git clone --recurse-submodules https://github.com/sclash/dotfiles ~/dotfiles
cd ~/dotfiles && git switch wsl-home-manager   # until merged
bash ~/dotfiles/wsl/bootstrap.sh
```

`bootstrap.sh` is idempotent: re-run it after each "ACTION NEEDED" message. In order, it:

1. enables systemd in `/etc/wsl.conf` (then asks you to run `wsl.exe --shutdown` from Windows)
2. installs zsh, git and curl from apt, makes zsh the login shell, and generates `en_US.UTF-8`
3. installs Determinate Nix if it's missing
4. initialises the `neovimrc` submodule
5. **generates this instance's age key** at `~/.config/sops/age/keys.txt` and adds its public key to `wsl/.sops.yaml`
6. checks that this key can decrypt `wsl/secrets/secrets.yaml` (see Secrets)
7. runs `home-manager switch -b hm-backup`. Existing files in the way are moved to `<file>.hm-backup`.

Then remove the pre-Nix installs, so nothing shadows the Nix versions. It lists what it found and asks before removing:

```bash
bash ~/dotfiles/wsl/bootstrap.sh --cleanup
```

`--dry-run` prints every mutating command instead of running it.

## Daily use

```bash
update          # alias: home-manager switch --flake ~/dotfiles/wsl#asergi -b hm-backup
```

To add a package, edit `packages.nix`, `git add`, then `update`. Flakes only see files in the git index, so stage new
files before `nix` commands.

## Secrets

Secrets live in `wsl/secrets/secrets.yaml`, encrypted with sops. Each instance has **its own generated age key**,
which is never copied. Every instance's public key is listed on the single `age:` line of `wsl/.sops.yaml`. The
sops-nix user service decrypts the secrets to `~/.config/sops-nix/secrets/<name>`.

The file must contain all four keys: `github_pat`, `openrouter`, `opencode`, `cheaper_inference`. sops-nix fails the
whole service if one is missing. Edit them with:

```bash
cd ~/dotfiles/wsl && nix run .#sops -- --config .sops.yaml secrets/secrets.yaml
```

Always pass `--config` (or run from `wsl/`): the repo-root `.sops.yaml` holds the NixOS rules.

On a **new instance**, bootstrap stops at step 6 and prints its public key. Grant it access from an instance that can
already decrypt the file, then commit and bring the change over:

```bash
bash ~/dotfiles/wsl/bootstrap.sh --add-recipient age1...   # adds the key, runs sops updatekeys
git add wsl/.sops.yaml wsl/secrets/secrets.yaml && git commit -m "wsl: add recipient"
```

If no instance can decrypt any more, delete `secrets/secrets.yaml`, re-run bootstrap and create the file again.

## opencode and Claude Code config

`~/.config/opencode` is linked from `../my-opencode/v2`. Where a v2 file is wrong for this host, `wsl/opencode/` holds
a copy at the same relative path, and that copy is linked instead. Today that means:

- `opencode.jsonc`: secrets read from the sops-nix paths. It's generated with
  `python3 wsl/opencode/sync_opencode_jsonc.py my-opencode/v2/opencode.jsonc wsl/opencode/opencode.jsonc`.
- `CLAUDE.md` and a few skills: no NixOS paths or nix-ld prefixes.

The `nix-ld-env.js` plugin is not linked. `wsl/opencode/BASE.sha256` records the v2 originals. When one changes,
`nix flake check` fails with `drift: <file>`. Re-derive the copy, then refresh the checksum:

```bash
cd ~/dotfiles/my-opencode/v2 && sha256sum $(awk '{print $2}' ../../wsl/opencode/BASE.sha256) > ../../wsl/opencode/BASE.sha256
```

Claude Code only gets four skills linked into `~/.claude/skills`. Its settings stay its own.

## Python

`uv` uses its own managed Pythons (`wsl/uv/uv.toml`: `python-preference = "managed"`). PyPI wheels then load Ubuntu's
`libstdc++` directly. Don't set `LD_LIBRARY_PATH`: it would break Ubuntu's own programs.

## Build limits

The VM has about 3.6 GiB of RAM, so `~/.config/nix/nix.conf` sets `max-jobs = 1` and `cores = 2`. The first switch
passes the same values as flags. On a VM with more memory (Windows `%UserProfile%\.wslconfig`: `[wsl2]` and
`memory=8GB`), raise them in `home.nix`.

Packages are picked so that nothing heavy compiles locally. ripwire is the cached nixpkgs-master build (0.6.5),
not NixOS's v0.6.1 source pin, and lldb comes from nixos-unstable.

## Tests

```bash
nix flake check ~/dotfiles/wsl            # generation assertions, overlay, overlay-links
bash ~/dotfiles/wsl/tests/test-bootstrap.sh
bash ~/dotfiles/wsl/tests/check-live.sh   # after a switch: PATH, links, secrets, apps
```

## Troubleshooting

- `Existing file '…' would be clobbered`: a `*.hm-backup` from an earlier switch is in the way. Inspect it, delete it, and re-run.
- Secrets missing: run `systemctl --user status sops-nix`, and `ls ~/.config/sops-nix/secrets`.
- Out of memory during a build: check `nix build … --dry-run` for derivations that would compile locally, and prefer
  a cached variant.
