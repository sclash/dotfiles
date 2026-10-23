

## Goal

Make the existing NixOS and WSL home-manager configuration work for any Linux
username and home directory. The repository stays at `~/dotfiles`; host-specific
hardware, hostname and architecture assumptions stay host-specific.

## Scope

In scope:

- any Linux username and home layout, including dotted usernames and homes that
  are not `/home/<user>`
- NixOS system configuration and the standalone WSL home-manager flake
- WSL application packages: Claude Code and opencode come from
  `nixpkgs-unstable`, replacing their native installers
- WSL instances whose OS user already exists and cannot be renamed: the WSL
  configuration inherits that account and never creates or modifies it
- per-machine sops age keys for both targets
- functional absolute paths in Nix modules, opencode config, static app configs
  and helper scripts
- tests and documentation for the dynamic behavior

Out of scope:

- macOS / nix-darwin
- non-Nix Linux distributions
- multi-host hardware, hostname or CPU-architecture abstraction
- desktop/server/WSL package profiles
- changing the `nixos/` + `wsl/` split into one root flake

## Decisions

- Identity comes from the environment, so switches use `--impure`.
  - Explicit `DOTFILES_USER` and `DOTFILES_HOME` overrides have the highest
    priority. They survive `sudo` (which sets `HOME=/root`) and let
    `nixos-install` target an account other than the live ISO user.
  - WSL: `USER` and `HOME` must describe the existing OS account and are used
    verbatim, whatever the username or home path. The WSL flake only deploys
    home-manager; it never creates, renames or alters a system user.
  - NixOS: `SUDO_USER` wins when set and not `root` (so `sudo nixos-rebuild`
    still sees the real user), otherwise `USER`. `HOME` is used unless it is
    `/root` or empty, in which case the home is `/home/<username>`. If the
    selected username is `root`, the home is `/root`.
- Pure evaluation (no environment, as in `nix flake check`) falls back to
  `asergi` / `/home/asergi` so checks remain deterministic. This fallback is for
  checks only; `wsl/bootstrap.sh` refuses to run as root and requires `USER` and
  `HOME` to be set before switching.
- The repository must be cloned at `~/dotfiles`.
- Every machine gets its own sops age key.
- One shared helper feeds the Nix modules. opencode's own config substitution is
  used for portability: `~`/`$HOME` expand in `{file:...}` and in
  `read`/`edit`/`external_directory` permission resources; `shell` resources do
  not expand, so they use `*` wildcards. No build-time renderer is needed.

## Identity plumbing

Add `lib/user.nix` returning:

```nix
{
  username;
  homeDirectory;
  dotfiles; # "${homeDirectory}/dotfiles"
}
```

Rules:

1. If `DOTFILES_USER`/`DOTFILES_HOME` are non-empty, use them as-is. These
   overrides beat everything else, including `sudo`.
2. `sudoUser = builtins.getEnv "SUDO_USER"`.
3. If `sudoUser` is non-empty and not `root`, use it; otherwise use
   `builtins.getEnv "USER"`.
4. If the result is empty, fall back to `asergi` (pure-eval fallback only).
5. If `username == "root"`, use `/root`.
6. Otherwise use `$HOME` unless it is `/root` or empty, in which case use
   `/home/<username>`.

Both flakes import this file once and pass the result through `specialArgs`.
`home.nix` receives it through its module arguments (`username`,
`homeDirectory`, `dotfiles`).

### WSL existing account

WSL runs standalone home-manager, so no `users.users` entry exists to change.
The handler must:

- run as the existing user (not via `sudo`), read `id -un`/`USER` and `HOME`,
  and home-manager targets exactly that account
- refuse to start when `EUID == 0`, when `USER` is empty, or when `HOME` is
  empty, with a message to re-run as the WSL user
- fail before switching if an impure evaluation of
  `homeConfigurations.default.config.home.username` / `homeDirectory` does not
  match the current `USER` / `HOME`, so a forgotten `--impure` cannot silently
  deploy to the fallback `/home/asergi` layout

Changes:

- `nixos/flake.nix`
  - replace the literal `username = "asergi"` values with the helper
  - `home-manager.users.${username} = ./home.nix`
  - standalone output renamed from `asergi@nixos-os` to `default`
- `nixos/configuration.nix`
  - `users.users.${username}`
  - greetd `user = username`
  - any other user literal
- `nixos/sops.nix`
  - `age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt"`
  - every `owner = username`
- `nixos/home.nix`, `wsl/home.nix`, `wsl/modules/*`, `nixos/programs/*`
  - out-of-store links use `${config.home.homeDirectory}/dotfiles/...` or the
    passed `dotfiles` value
  - zsh `update` aliases use the dynamic repo path and keep `--impure`
- `wsl/flake.nix` / `wsl/home.nix`
  - use the shared helper instead of its local `getEnv` block
- `wsl/bootstrap.sh`
  - refuse to run as root and require `USER`/`HOME`
  - before switching, evaluate the flake impurely and abort unless the evaluated
    username/home match the existing account
  - never call `useradd`, `usermod` or otherwise touch the OS account

`home.username` and `home.homeDirectory` remain the source of truth inside
home-manager. NixOS sets them through the NixOS module; the standalone outputs
set them from the helper.

## Secrets

Per-machine keys replace one shared identity, with no new shared script.

- `nixos/sops.nix` uses the derived username and home directory.
- `wsl/bootstrap.sh --add-recipient` stays as the WSL key-registration path.
- Fallback when no instance can decrypt the shared file: `wsl/bootstrap.sh
  --new-secrets` creates `~/.config/sops-nix/wsl-secrets.yaml`, encrypted to
  this instance's age key with the four required keys and empty values, then
  stops so the user can fill it. The local file is selected automatically when
  it exists; `DOTFILES_WSL_SECRETS` can point at it explicitly. `wsl/modules/
  secrets.nix` uses that variable when set, otherwise the shared file;
  `wsl/update.sh` exports it when the local file exists.
- NixOS key registration is documented, not scripted:
  append the machine's public key to the single `age:` line in
  `.sops.yaml` at the repo root, then run from the repo root
  `sops --config .sops.yaml updatekeys -y nixos/secrets/secrets.yaml`
  with `SOPS_AGE_KEY_FILE` pointing at that machine's key.
- Both READMEs document: create a key per machine, register the public key for
  the target that machine uses, then let the normal switch deploy secrets.
- The two `.sops.yaml` files stay separate.

## Portable opencode config

Use opencode's native substitution; keep the checked-in configs static.

- `{file:~/.config/sops-nix/secrets/<name>}` works on WSL; `{file:/run/secrets/<name>}`
  stays on NixOS.
- WSL `wsl/opencode/sync_opencode_jsonc.py` remains a WSL-only maintainer tool
  (it never runs at build or activation). Update it to emit portable paths:
  - file refs: `~/.config/sops-nix/secrets`
  - `read`/`edit`/`external_directory` mirrors: `~/.config/sops-nix/secrets`
    and `/run/user/*/secrets.d` (wildcard uid)
  - `shell` mirrors: `*/.config/sops-nix/secrets` and
    `~/.config/sops-nix/secrets` (raw text, no expansion) and
    `/run/user/*/secrets.d`
- `my-opencode/v1/opencode.jsonc` and `my-opencode/v2/opencode.jsonc`
  - replace the disabled filesystem MCP arguments `/home/asergi/...` with
    `{env:HOME}/...`
- NixOS `nixos/programs/opencode/opencode.nix`
  - switch every `my-opencode/v1` link to `my-opencode/v2` and keep the dynamic
    home path
  - add the `RIPWIRE.md` link required by v2's `instructions` list
- WSL `wsl/modules/opencode.nix` and `wsl/lib/v2-overlay.nix`
  - keep linking the static `wsl/opencode/opencode.jsonc`; no generated file,
    no exclusion
- Regenerate `wsl/opencode/opencode.jsonc` with the updated sync script and
  refresh `wsl/opencode/BASE.sha256` for `my-opencode/v2/opencode.jsonc`.
- Do not add `scripts/render-opencode.py`.

## Claude Code and other Nix modules

- `nixos/programs/claude-code/claude-code.nix`
  - allowed paths use `${config.home.homeDirectory}/...`
  - skill symlinks use `${config.home.homeDirectory}/dotfiles/...`
- `nixos/programs/mcpservers.nix`
  - permission paths use `${config.home.homeDirectory}/...`
- `nixos/programs/opencode/opencode.nix`
  - every out-of-store link uses the dynamic home path
  - all links point at `my-opencode/v2`, including `RIPWIRE.md`
- `nixos/programs/quickshell.nix`, `herdr.nix`, `uv/uv.nix`,
  `zsh.nix` and any other module with `/home/asergi` use dynamic paths

## WSL application packages

- `wsl/packages.nix` installs `claude-code` and `opencode` from
  `pkgs-unstable`.
- `wsl/home.nix` drops `$HOME/.opencode/bin` from `home.sessionPath`, so the Nix
  profile is the only source.
- `wsl/bootstrap.sh --cleanup` offers to remove the native binaries and install
  payloads (`~/.local/bin/claude`, `~/.local/share/claude`, `~/.opencode`);
  auth/settings/sessions under `~/.claude` and `~/.local/share/opencode` stay.
- `wsl/tests/check-generation.sh` asserts the generation has `claude` and
  `opencode` in `home-path/bin`.
- `wsl/tests/check-live.sh` expects both from `~/.nix-profile/bin`, not from the
  native install locations.
- `wsl/modules/{opencode,claude-code}.nix` keep their config-only roles and
  update their comments; the packages are not enabled through the NixOS program
  modules.
- NixOS `programs.opencode.package` uses `pkgs-unstable.opencode` because the
  `pkgs-master` source build fails `installShellCompletion` (the rebuilt package
  ships no bash completion file). This is a build fix, not a WSL-only feature.

## Static configuration files

- `i3/config`
  - wallpaper and `i3status` config use `$HOME/...` (`i3` runs these through a
    shell)
- `hypr/*`
  - remove or neutralize commented `/home/asergi` paths; the active wallpaper
    paths already use `~/dotfiles`
- `ghostty/config`
  - remove stale absolute home paths from comments
- Markdown guidance in `my-opencode/*`, `wsl/opencode/*` and skill files
  - use `~/dotfiles` or `~/.nix-profile/...` instead of `/home/asergi/...`

## Tests and guards

- WSL generation checks assert the static opencode JSON contains no
  `/home/asergi` and uses `~`/wildcard paths.
- Update `wsl/tests/test_sync_opencode_jsonc.py` for the portable output
  (`~/.config/sops-nix/secrets`, `/run/user/*/secrets.d`, shell globs).
- Add a repository check that functional files (Nix, shell, Python, app configs)
  contain no `/home/asergi`; the only allowed occurrence is the pure-evaluation
  fallback in `lib/user.nix`.
- Add a NixOS flake check that evaluates `nixosConfigurations.nixos-os` with a
  non-`asergi` `USER`/`HOME` (impure) and verifies:
  - the single user name and home directory
  - sops owner and key path
  - the zsh alias and generated links
- Add WSL tests that:
  - run with a temporary existing username/home (including a dotted name and a
    home outside `/home`) and assert the generated config uses them verbatim
  - assert the bootstrap refuses `EUID 0` and empty `USER`/`HOME`
  - assert a missing `--impure` identity mismatch is rejected before switching
  - assert the generation contains `claude` and `opencode` from
    `pkgs-unstable`
- Keep the existing WSL bootstrap and live checks passing, updating fixed
  `asergi` expectations to the derived home and both apps to the Nix profile.

## Documentation

- Update the root README, `wsl/README.md`, `wsl/wsl-setup-from-scratch.md` and
  `wsl/opencode/CLAUDE.md`:
  - any username, repo at `~/dotfiles`
  - `--impure` is required for all switches
  - per-machine age key creation and registration
  - opencode config is static and portable (`~`/wildcards); the WSL sync script
    is a maintainer tool, not part of activation
  - WSL installs Claude Code and opencode from `nixpkgs-unstable`; native
    installs are removed with `bootstrap.sh --cleanup`
- Update `wsl/docs/superpowers/plans/2026-10-20-wsl-home-manager.md` only where it
  states hard requirements that changed (`asergi`, `#asergi`, `/home/asergi`).

## Rollout

1. Land the helper and Nix module changes.
2. Update the static opencode configs and regenerate the WSL copy.
3. Run `nix flake check` for both flakes in pure and impure mode.
4. Run the WSL bootstrap tests and live checks.
5. On each machine: generate its age key, register the public key for the target,
   then run the normal switch with `--impure`.
6. Existing machines keep their current key by registering it; no secret
   re-encryption is needed for a machine that can already decrypt.

## Error handling

- Missing keys: `wsl/bootstrap.sh` prints the `age-keygen` command; the NixOS
  README gives the same command.
- Undecryptable secrets: existing bootstrap message remains.
- WSL running as root, or with an empty `USER`/`HOME`: abort before evaluating,
  with the command to re-run as the existing WSL user.
- WSL identity mismatch (forgotten `--impure`): abort before switching, naming
  both the evaluated and the actual account; never silently deploy to
  `/home/asergi`.
