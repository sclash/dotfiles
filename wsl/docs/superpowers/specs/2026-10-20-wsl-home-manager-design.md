# WSL home-manager flake: design

Date: 2026-10-20 · Status: approved design, awaiting spec review

## Goal
Port the user-level configuration in `~/dotfiles/nixos` (home-manager running inside NixOS) to a
**standalone home-manager flake** at `~/dotfiles/wsl/flake.nix`. A brand-new WSL (Ubuntu) instance
then gets the same CLI/TUI tools and their configs declaratively.

### Requirements (from the user)
- Port the CLI and TUI tools and their configurations. Leave out GUI applications (browsers etc.).
- opencode is **not** installed by home-manager. It keeps the native installer in `~/.opencode/bin`.
  home-manager links its configuration from `~/dotfiles/my-opencode/v2`.
- The entrypoint is a `flake.nix`.
- It must work on any fresh WSL instance, not only the current one.

### Decisions
| Topic | Decision |
|---|---|
| Claude Code | Keep the native, auto-updating binary in `~/.local/bin`. home-manager only links static config (4 skills). No package, `settings.json`, plugins or MCP through home-manager, so `/model`, `/plugin` and the herdr hook keep working. |
| Secrets | sops-nix **home-manager module**, with the same `nixos/secrets/secrets.yaml` and age key. Secrets appear at `~/.config/sops-nix/secrets/<name>` (backed by `/run/user/1000/secrets.d`). The v2 opencode config and the zsh exports move to these paths. |
| Layout | The WSL flake imports the portable modules from `../nixos/programs` unchanged. WSL-specific modules live in `wsl/modules/`. **No file under `nixos/` is modified.** |
| Pre-existing installs | Nix replaces rustup, nvm, the snaps (nvim, go, zig, node, pyright, ctags), `~/.local/bin/herdr`, oh-my-zsh and p10k. Starship replaces p10k. |
| Bootstrap | `wsl/bootstrap.sh` is idempotent. Removing old installs only happens with an opt-in `--cleanup` flag, which lists what it will delete and asks first. Plus `wsl/README.md`. |

### Out of scope
- GUI applications, and everything that is system-level on NixOS: boot, networking/VPN, display manager,
  compositor, audio, bluetooth, printing/scanning, fonts, openssh, firewall.
- A docker daemon. Docker Desktop's WSL integration provides the `docker` CLI.
- Declarative Claude Code plugins/MCP servers (they stay stateful and are managed by claude itself).
- Any change to the NixOS configuration.

## Environment baseline
Measured on the current instance:
- Ubuntu 22.04.5 (glibc 2.35), WSL2 kernel 6.18, `/etc/wsl.conf` has `systemd=true`, the user
  systemd session is running, and WSLg is available.
- Determinate Nix 3.23.3 (nix 2.35.3), daemon active, `nix-command flakes` enabled, empty user profile.
- `/etc/zsh/zshrc` sources `nix-daemon.sh`. zsh reads `~/.zshenv` (home-manager session vars) before
  `/etc/zsh/zshrc`, so `~/.nix-profile/bin` ends up ahead of `/usr/bin` in `PATH`.
- `my-opencode/v2` is **not tracked** in git (`?? my-opencode/v2/`).

## File layout
```
wsl/
  flake.nix            inputs + homeConfigurations."asergi"
  flake.lock           initial lock pinned to the revisions in nixos/flake.lock
  home.nix             entrypoint: imports, packages, links, session vars, git/man, genericLinux
  modules/
    zsh.nix            WSL zsh (adapted from nixos/programs/zsh.nix)
    herdr.nix          programs.herdr (pkgs-master) + config.toml link
    opencode.nix       out-of-store links into my-opencode/v2 (no package)
    claude-code.nix    4 skill links into my-opencode/v2/skills (no package, no settings)
    secrets.nix        sops-nix: age key + 4 secrets
  bootstrap.sh
  README.md
```

## flake.nix
- Inputs (same channels as the NixOS flake):
  - `nixpkgs` = `nixpkgs/nixos-26.05`
  - `nixpkgs-unstable` = `nixpkgs/nixos-unstable`
  - `nixpkgs-master` = `github:nixos/nixpkgs`
  - `home-manager` = `github:nix-community/home-manager` (master), `inputs.nixpkgs.follows = "nixpkgs"`.
    Master is required for `programs.herdr`, `programs.uv.tool.*` and `programs.devenv`.
  - `sops-nix` = `github:Mic92/sops-nix`, `inputs.nixpkgs.follows = "nixpkgs"`
  - `ripwire-src` = `github:redhat-et/ripwire/v0.6.1`, `flake = false`
- Not carried over: flake-parts, nix-snapd, the nixd flake (use `pkgs.nixd`), walker/elephant, my-dotfiles,
  neovimrc, opencode-src.
- `pkgs`, `pkgs-unstable` and `pkgs-master` are each imported with `config.allowUnfree = true` for
  `x86_64-linux`. `pkgs-master` carries the ripwire overlay, copied verbatim from `nixos/flake.nix:104-127`.
  This duplication is accepted, so that `nixos/` stays untouched.
- Output:
  ```nix
  homeConfigurations."asergi" = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ ./home.nix sops-nix.homeManagerModules.sops ];
    extraSpecialArgs = { inherit pkgs-unstable pkgs-master; };
  };
  ```
- Lock: the initial `flake.lock` pins the same revisions as `nixos/flake.lock`, for parity with the laptop
  and binary-cache hits:
  - home-manager `92a0ed1b`
  - nixpkgs `b1b87598`
  - nixpkgs-unstable `7fd4004d`
  - nixpkgs-master `d47861e2`
  - sops-nix `ee48786c`
  - ripwire-src `30f14a27`
- Usage: `home-manager switch --flake ~/dotfiles/wsl#asergi`.

## home.nix
### Imports
- Unchanged from `../nixos/programs/`:
  - `tmux/tmux.nix`, `starship.nix`, `atuin.nix`, `uv/uv.nix`, `pandoc.nix`
  - `nushell.nix`, `devenv.nix`, `nvim-lsp.nix`, `ripwire.nix`
  - Their unused `unstable-pkgs` argument is never forced, so it needs no special arg.
- WSL modules: `modules/{zsh,herdr,opencode,claude-code,secrets}.nix`.
- Not imported:
  - `mcpservers.nix`: nothing consumes `~/.config/mcp/mcp.json`; on NixOS too, `enableMcpIntegration` is commented out.
  - `obs.nix`, `zathura.nix`, `quickshell.nix`, `swaync.nix`: GUI.
  - The NixOS `claude-code.nix`: it installs the package.
  - The NixOS `opencode/opencode.nix`: it installs the package and links v1.

### Settings
- `targets.genericLinux.enable = true` sets up XDG data dirs, locale archive and terminfo for Nix programs on Ubuntu.
- `targets.genericLinux.gpu.enable = false`. It defaults to true once genericLinux is enabled
  (`modules/targets/generic-linux/gpu/default.nix:21`), but nothing here is GUI.
- `programs.home-manager.enable = true`.
- `programs.git` and `programs.man` copied from `nixos/home.nix:135-148`.
- `home.language.base = "en_US.UTF-8"`.
- `home.sessionPath = [ "$HOME/.local/bin" "$HOME/.opencode/bin" ]`: native claude and native opencode.
- `home.sessionVariables`: `EDITOR`, `VISUAL` and `SUDO_EDITOR` = `nvim`.
- **No `LD_LIBRARY_PATH`.** The NixOS value (`nixos/home.nix:69-72`) would load Nix's libstdc++ into Ubuntu's
  own binaries (glibc 2.35) and break them. Nix binaries are RPATH'd, and PyPI wheels resolve against system libs.
- `home.stateVersion = "26.05"`.

### Links (all `config.lib.file.mkOutOfStoreSymlink`, so they stay pure-eval safe and live-editable)
| Target | Source |
|---|---|
| `~/.config/nvim` | `~/dotfiles/neovimrc` (git submodule) |
| `~/.config/starship` | `~/dotfiles/starship` |
| `~/.config/atuin` | `~/dotfiles/atuin` |

neovim is installed as a **package**, not `programs.neovim`. That way home-manager never generates an `init.lua`
inside the linked directory.

### Packages
CLI subset of `nixos/home.nix` and of `environment.systemPackages` in `nixos/configuration.nix`.

`pkgs`:
- Editors and Nix tools: neovim, vim, tree-sitter, nixd, nix-prefetch-git, sops
- CLI utilities: tree, bat, eza, fd, jq, zoxide, zip, unzip, wget, wl-clipboard (WSLg clipboard), man-pages, man-pages-posix
- TUIs: gh, lazygit, lazydocker, lazysql, lazyssh, lazycli, btop, htop, ncdu, fastfetch, glow, hygg
- Media and profiling: ffmpeg, timg, chafa, flamegraph, hyperfine
- Build and debug: `lib.hiPrio gcc`, llvmPackages_latest.clang, llvmPackages_latest.lldb, gdb, valgrind, bear,
  gnumake, pkg-config. `hiPrio` resolves the `bin/cc` collision between the gcc and clang wrappers in the
  home-manager `buildEnv`.
- Runtimes and libs: lua, nodejs, typescript, icu, playwright
- `(import ../nixos/programs/open-research.nix { inherit pkgs; })` (`orx`)

`pkgs-unstable`, same channel as `configuration.nix:442-458` and `home.nix:131-132`: ripgrep, fzf,
universal-ctags, python3, bun, go, rustc, cargo, zig_0_17, agent-browser.

Dropped:
- GUI: firefox, chromium, google-chrome, chromedriver, tor-browser, vlc, mpv, flameshot, telegram-desktop,
  zennotes-desktop, ghostty, hypr*, walker/elephant, nautilus, evince, qt6.qtdeclarative
- Printing and scanning: cups, epsonscan2
- Docker: docker, docker-compose (Docker Desktop)
- Unsafe or meaningless in a user profile on Ubuntu: glibc, libgcc, glib, libllvm, libcxx, util-linux, dbus,
  lm_sensors, bluez, networkmanager
- perf (Ubuntu's linux-tools matches the WSL kernel); rr (WSL2 exposes no PMU)

## configuration.nix coverage
| Item | On WSL |
|---|---|
| `programs.neovim` + `EDITOR`/`VISUAL`/`SUDO_EDITOR` (41-47) | neovim package + `home.sessionVariables` |
| `documentation.dev.enable` (41) | man-pages, man-pages-posix, `programs.man` |
| `programs.zsh.promptInit` with starship/atuin init (236-242) | home-manager starship/atuin zsh integration |
| `users.defaultUserShell = zsh` (297) | `bootstrap.sh`: `chsh -s /usr/bin/zsh` |
| `i18n.defaultLocale` (115) | `home.language.base`; `bootstrap.sh` runs `locale-gen en_US.UTF-8` |
| `nix.settings.max-jobs = 2; cores = 4` (89-90) | Not ported (laptop OOM cap; WSL RAM is set by `.wslconfig`). README explains how to add it back. |
| `nix.settings.experimental-features` (83) | Already enabled by Determinate Nix |
| `nixpkgs.config.allowUnfree` (52) | `allowUnfree` on all three package sets |
| `programs.nix-ld` (306-314) | Not needed: Ubuntu runs foreign binaries natively |
| `virtualisation.docker` (234) | Docker Desktop WSL integration |
| `programs.wireshark` (243-248) | Dropped (capture needs system capabilities); `wireshark-cli` can be added later |
| `sops.nix` | `modules/secrets.nix` |
| `time.timeZone` (82) | WSL inherits it from Windows |
| Boot, networking, VPN, greetd, hyprland/hyprlock, portals, GTK env, nvidia, pipewire, bluetooth, upower, udisks2, fonts, wshowkeys, walker, openssh, firewall, printers, scanners | System-level or GUI: out of scope |

## WSL modules
### modules/zsh.nix
Adapted copy of `nixos/programs/zsh.nix`:
- Same options: completion, autosuggestion, autocd, syntax highlighting, history settings.
- Aliases:
  - `ll` and `edit` as before.
  - `update = "home-manager switch --flake ~/dotfiles/wsl#asergi -b hm-backup"`.
  - `ftm = "${config.home.homeDirectory}/dotfiles/scripts/tmux-sessionizer.sh"`.
- `initContent` keeps the `show_eza_tree` function and the `lz` alias. Its secret exports read
  `${config.sops.secrets.github_pat.path}` and `${config.sops.secrets.openrouter.path}` instead of `/run/secrets/*`,
  and keep the `[ -f … ]` guard.

### modules/herdr.nix
- `programs.herdr = { enable = true; package = pkgs-master.herdr; };` with no `settings`. The home-manager module
  leaves `config.toml` unmanaged when settings are empty (`modules/programs/herdr.nix`, option description).
- `xdg.configFile."herdr/config.toml"` → out-of-store link to `~/dotfiles/herdr/config.toml`. Only the file is
  linked, because herdr keeps sockets, logs and `session.json` in `~/.config/herdr`. Linking the whole
  directory would put them in the repo.

### modules/opencode.nix
- Out-of-store links from `~/dotfiles/my-opencode/v2/` to `~/.config/opencode/<item>`. The items are:
  `opencode.jsonc`, `AGENTS.md`, `CLAUDE.md`, `RIPWIRE.md`, `agents`, `commands`, `instructions`, `plugins`,
  `prompts`, `scripts`, `skills`, `tools`. `RIPWIRE.md` is new compared to v1; v2's `instructions` lists it.
- `~/.agents` → `~/dotfiles/.agents`.
- `home.sessionVariables.OPENCODE_DISABLE_CLAUDE_CODE_SKILLS = "true"`.
- Not touched:
  - herdr-managed `tui.jsonc`, `herdr-tui-session.js` and `herdr-opencode/`
  - runtime `cli.json` and `service.json`
  - v2's `evals/`, `package-lock.json` and `vastai`
- No package. The binary stays at `~/.opencode/bin/opencode`, on `PATH` via `home.sessionPath`.

### modules/claude-code.nix
- `~/.claude/skills/{explore-codebase,high-perf-systems,download-video,transcribe-media}` → out-of-store links to
  `~/dotfiles/my-opencode/v2/skills/<name>`. On NixOS these point at the removed `my-opencode/skills/*`.
- Nothing else under `~/.claude` is managed.

### modules/secrets.nix
- `sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt"`.
- `sops.defaultSopsFile = ../../nixos/secrets/secrets.yaml` (the path is relative to `wsl/modules/`).
- `sops.secrets = { github_pat = {}; openrouter = {}; opencode = {}; cheaper_inference = {}; }`.
- The `sops-nix` systemd user service decrypts into `/run/user/1000/secrets.d/` and links each secret at
  `~/.config/sops-nix/secrets/<name>` (sops-nix `defaultSymlinkPath`).

## Edits in my-opencode/v2
v2 is only used by WSL today; NixOS uses v1.
- `opencode.jsonc` lines 19, 123, 128 and 136: change `{file:/run/secrets/<name>}` to
  `{file:/home/asergi/.config/sops-nix/secrets/<name>}`.
- `opencode.jsonc` permission rules: every rule denying `/run/secrets` and `/run/secrets.d` gets equivalents
  for `/home/asergi/.config/sops-nix/secrets` and `/run/user/1000/secrets.d`. The existing rules stay, so agents
  still cannot read the keys. Affected: the path rules around lines 652-667, 747-762, 842-857, 937-952 and
  1222-1237, and the bash-pattern rules at lines 962-1002.
- `CLAUDE.md:14` and `skills/agent-browser/SKILL.md:16-19`: point to `~/dotfiles/wsl` (`home.nix`) instead of
  `~/dotfiles/nixos`.

## Collision handling
The first switch runs with `-b hm-backup`. For any target that exists and is not a home-manager link, the pinned
home-manager **moves** the file or directory to `<target>.hm-backup` and then links (`modules/files.nix:357-373`).
That covers directories too, so no custom activation step is needed. Expected on the current instance:
- `~/.zshrc`, `~/.zshenv`
- `~/.config/tmux/tmux.conf`
- `~/.config/nvim` (a real copy of neovimrc)
- `~/.config/herdr/config.toml`
- `~/.config/opencode/plugins`

Known behaviour, the same as on NixOS today: herdr's integration installer writes its opencode plugin through the
`plugins` link into the repo.

## bootstrap.sh
Bash, `set -euo pipefail`. Every step checks before acting, so re-running it is safe.
1. **systemd:** if `/etc/wsl.conf` lacks `systemd=true`, write `[boot]\nsystemd=true` with sudo. Then tell the
   user to run `wsl.exe --shutdown` and re-run, and exit 0.
2. **Shell and locale:** `sudo apt-get install -y zsh git curl` if any is missing. Run `chsh -s /usr/bin/zsh`
   if the login shell differs. Run `sudo locale-gen en_US.UTF-8` if `locale -a` lacks it.
3. **Nix:** if `nix` is missing, install Determinate Nix
   (`curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm`) and source
   `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
4. **Submodules:** `git -C ~/dotfiles submodule update --init neovimrc`.
5. **Age key:** if `~/.config/sops/age/keys.txt` is missing, print how to copy it (e.g. `cp /mnt/c/... ~/.config/sops/age/keys.txt; chmod 600 …`) and exit 1.
6. **Switch:** if `home-manager` is on `PATH`, use it; otherwise use `nix run home-manager/master --`. Either way,
   run `switch --flake ~/dotfiles/wsl#asergi -b hm-backup`.
7. **`--cleanup`** (only with the flag): print what is present among the items below, ask `[y/N]`, then remove them:
   - snaps nvim, go, zig, node, pyright, universal-ctags
   - `rustup self uninstall -y`, plus the `. "$HOME/.cargo/env"` lines in `~/.profile` and `~/.bashrc`
   - `~/.nvm`, `~/.oh-my-zsh`, `~/.p10k.zsh`
   - `~/.local/bin/herdr`
   - `sudo rm /usr/local/bin/pyright` plus `/usr/local/lib/node_modules/pyright`
   - `~/.tmux/plugins` and `~/.config/tmux/plugins` (old TPM)
   - apt packages are left alone, because the Nix profile comes first in `PATH`.

## README.md
Covers:
- prerequisites (Windows: WSL, Docker Desktop integration, Nerd Font in the terminal)
- fresh-instance steps: clone with `--recurse-submodules`, copy the age key, `./bootstrap.sh`, then `./bootstrap.sh --cleanup`
- daily use: `update`
- adding packages
- editing secrets: `sops ~/dotfiles/nixos/secrets/secrets.yaml`
- the `max-jobs` note
- troubleshooting: backups named `*.hm-backup`, and `systemctl --user status sops-nix`

## Prerequisites (repo state)
- `my-opencode/v2` must be committed, otherwise a fresh clone has no opencode config. Review `v2/vastai`
  (144 bytes) for credentials before committing.
- The new `wsl/` files must be `git add`ed before `nix` can evaluate the flake.

## Verification
1. `nix flake check ~/dotfiles/wsl`, then `home-manager build --flake ~/dotfiles/wsl#asergi`. Inspect the
   `result/home-files` links.
2. `home-manager switch --flake ~/dotfiles/wsl#asergi -b hm-backup -n` (dry run): review the collision list.
3. Real switch. Then, in a new login shell:
   - `which -a nvim tmux herdr rg go zig node cargo uv starship atuin`: the Nix profile wins.
   - `ls -l ~/.config/{nvim,starship,atuin,uv/uv.toml,herdr/config.toml} ~/.config/opencode/`: every link
     resolves into `~/dotfiles`.
   - `systemctl --user status sops-nix` is active/exited OK, `~/.config/sops-nix/secrets/` holds 4 entries, and
     `$GITHUB_PERSONAL_ACCESS_TOKEN` is non-empty.
4. Apps:
   - opencode starts with the v2 config, and a provider authenticated via `{file:}` responds.
   - `claude` is still the native binary, and a `/model` change persists.
   - `nvim`: `:checkhealth vim.lsp` passes, and servers resolve from `PATH`.
   - tmux plugins load.
   - `uv tool list` shows graphifyy; `ripwire --version` and `orx --help` run.
5. Fresh-instance acceptance test, together with the user:
   - `wsl.exe --install Ubuntu-24.04 --name hm-test`
   - clone dotfiles, copy the age key, run `bootstrap.sh`
   - repeat steps 3-4, then `wsl.exe --unregister hm-test`
