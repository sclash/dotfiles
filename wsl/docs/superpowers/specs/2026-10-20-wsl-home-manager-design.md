# WSL home-manager flake: design

Date: 2026-10-20 · Status: approved; amended 2026-10-20 (wsl-only changes, overlay, managed Python, chromium, per-instance age keys)

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
- **Nothing outside `wsl/` is modified.** That covers `nixos/`, `my-opencode/` and every other directory in
  `~/dotfiles`. When a shared file conflicts with WSL, a corrected copy lives in `wsl/`, and home-manager
  links the copy instead of the original (amendment 2026-10-20).

### Decisions
| Topic | Decision |
|---|---|
| Claude Code | Keep the native, auto-updating binary in `~/.local/bin`. home-manager only links static config (4 skills). No package, `settings.json`, plugins or MCP through home-manager, so `/model`, `/plugin` and the herdr hook keep working. |
| Secrets | sops-nix **home-manager module** with WSL's own committed file, `wsl/secrets/secrets.yaml`. Every instance **generates** its own age key; nothing is copied. Each instance's public key is listed in `wsl/.sops.yaml`. You fill in the values with `sops edit`. Secrets appear at `~/.config/sops-nix/secrets/<name>` (backed by `/run/user/1000/secrets.d`). The zsh exports and the **WSL copy** of the opencode config use these paths. (amendment 2026-10-20) |
| v2 conflicts | An overlay at `wsl/opencode/` mirrors v2's layout but holds only the files that conflict with WSL. Everything else is linked live from v2. A checksum manifest flags drift when a v2 original changes. |
| Python wheels | A WSL copy of `uv.toml` sets `python-preference = "managed"`. uv's standalone Pythons use Ubuntu's normal loader, so wheels find `libstdc++` without any `LD_LIBRARY_PATH`. The WSL skill copies drop the nix-ld prefix, and `nix-ld-env.js` is not linked. |
| Browser | nixpkgs `chromium`, used headless by agent-browser and Playwright, plus `fonts.fontconfig` with noto-fonts and noto-fonts-color-emoji so pages render text. |
| Layout | The WSL flake imports the portable modules from `../nixos/programs` unchanged. WSL-specific modules live in `wsl/modules/`. **No file under `nixos/` is modified.** |
| Pre-existing installs | Nix replaces rustup, nvm, the snaps (nvim, go, zig, node, pyright, ctags), `~/.local/bin/herdr`, oh-my-zsh and p10k. Starship replaces p10k. |
| Bootstrap | `wsl/bootstrap.sh` is idempotent. Removing old installs only happens with an opt-in `--cleanup` flag, which lists what it will delete and asks first. Plus `wsl/README.md`. |

### Out of scope
- GUI applications, and everything that is system-level on NixOS: boot, networking/VPN, display manager,
  compositor, audio, bluetooth, printing/scanning, openssh, firewall. Terminal fonts belong on the Windows side;
  Linux-side fonts are installed only so headless chromium can render text.
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
- `my-opencode/v2` is committed (`4fceb51`), so the flake can read it at eval time.

## File layout
```
wsl/
  flake.nix            inputs, homeConfigurations."asergi", checks
  flake.lock           initial lock pinned to the revisions in nixos/flake.lock
  home.nix             entrypoint: imports, links, session vars, git/man, genericLinux
  packages.nix         home.packages + fonts
  lib/overlay-links.nix  base+overlay → home.file entries (shared by opencode and claude-code)
  modules/
    zsh.nix            WSL zsh (adapted from nixos/programs/zsh.nix)
    herdr.nix          programs.herdr (pkgs-master) + config.toml link
    opencode.nix       ~/.config/opencode from v2 + overlay (no package)
    claude-code.nix    4 skills from v2 + overlay (no package, no settings)
    secrets.nix        sops-nix: age key + 4 secrets
  .sops.yaml           creation rule for secrets/secrets.yaml; one age recipient per instance
  secrets/secrets.yaml sops-encrypted: github_pat, openrouter, opencode, cheaper_inference
  opencode/            overlay: WSL copies of conflicting v2 files only
    BASE.sha256        checksums of the v2 originals each copy derives from
    sync_opencode_jsonc.py  regenerates opencode/opencode.jsonc from v2
  uv/uv.toml           WSL copy of nixos/programs/uv/uv.toml
  tests/               generation, overlay and sync tests
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
| `~/.config/uv/uv.toml` | `~/dotfiles/wsl/uv/uv.toml`. This overrides the imported `uv.nix` entry with `lib.mkForce`. The copy differs from the nixos one only in `python-preference = "managed"`. |

neovim is installed as a **package**, not `programs.neovim`. That way home-manager never generates an `init.lua`
inside the linked directory.

### Packages
CLI subset of `nixos/home.nix` and of `environment.systemPackages` in `nixos/configuration.nix`.

`pkgs`:
- Editors and Nix tools: neovim, vim, tree-sitter, nixd, nix-prefetch-git, sops, age
- CLI utilities: tree, bat, eza, fd, jq, zoxide, zip, unzip, wget, wl-clipboard (WSLg clipboard), man-pages, man-pages-posix
- TUIs: gh, lazygit, lazydocker, lazysql, lazyssh, lazycli, btop, htop, ncdu, fastfetch, glow, hygg
- Media and profiling: ffmpeg, timg, chafa, flamegraph, hyperfine
- Build and debug: `lib.hiPrio gcc`, llvmPackages_latest.clang, llvmPackages_latest.lldb, gdb, valgrind, bear,
  gnumake, pkg-config. `hiPrio` resolves the `bin/cc` collision between the gcc and clang wrappers in the
  home-manager `buildEnv`.
- Runtimes and libs: lua, nodejs, typescript, icu, playwright
- Browser and fonts: chromium (headless, for agent-browser and Playwright), noto-fonts, noto-fonts-color-emoji;
  `fonts.fontconfig.enable = true`
- `(import ../nixos/programs/open-research.nix { inherit pkgs; })` (`orx`)

`pkgs-unstable`, same channel as `configuration.nix:442-458` and `home.nix:131-132`: ripgrep, fzf,
universal-ctags, python3, bun, go, rustc, cargo, zig_0_17, agent-browser.

Dropped:
- GUI: firefox, google-chrome, chromedriver, tor-browser, vlc, mpv, flameshot, telegram-desktop,
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

### lib/overlay-links.nix
A pure function that turns a base tree (v2) plus an overlay tree (`wsl/opencode`) into `home.file` entries.
All links are out-of-store, so edits to either tree take effect without a rebuild.
- For each path, from the top-level item downwards:
  - **Excluded** path → no entry.
  - Missing from both base and overlay → no entry.
  - No overlay entry, and no exclude below it → **one link to the base path**. A whole directory becomes one link.
  - Overlay entry is a file → link to the overlay file.
  - Overlay entry is a directory, or an exclude lies below the path → expand it. Children are the union of the base and
    overlay listings, and each child is handled by the same rules.
- Directory listings use `builtins.readDir` on the flake source (`../my-opencode/v2`, `./opencode`), so the
  layout is fixed at eval time. A new file inside an expanded directory needs `update`; untouched subtrees stay live.

### modules/opencode.nix
- `~/.config/opencode/<item>` = overlay-links over base `~/dotfiles/my-opencode/v2` and overlay
  `~/dotfiles/wsl/opencode`. The items are: `opencode.jsonc`, `AGENTS.md`, `CLAUDE.md`, `RIPWIRE.md`, `agents`,
  `commands`, `instructions`, `plugins`, `prompts`, `scripts`, `skills`, `tools`. `RIPWIRE.md` is new compared to v1;
  v2's `instructions` lists it. `plugins/nix-ld-env.js` is excluded.
- `~/.agents` → `~/dotfiles/.agents`.
- `home.sessionVariables.OPENCODE_DISABLE_CLAUDE_CODE_SKILLS = "true"`.
- Not touched:
  - herdr-managed `tui.jsonc`, `herdr-tui-session.js` and `herdr-opencode/`
  - runtime `cli.json` and `service.json`
  - v2's `evals/`, `package-lock.json` and `vastai`
- No package. The binary stays at `~/.opencode/bin/opencode`, on `PATH` via `home.sessionPath`.

### modules/claude-code.nix
- `~/.claude/skills/{explore-codebase,high-perf-systems,download-video,transcribe-media}` = overlay-links for
  `skills/<name>`, with the same base and overlay as opencode. `transcribe-media` therefore picks up its WSL copy.
  On NixOS these point at the removed `my-opencode/skills/*`.
- Nothing else under `~/.claude` is managed.

### modules/secrets.nix
- `sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt"`.
- `sops.defaultSopsFile = ../secrets/secrets.yaml` (the path is relative to `wsl/modules/`).
- `sops.secrets = { github_pat = {}; openrouter = {}; opencode = {}; cheaper_inference = {}; }`. All four keys must
  be present in the file: sops-nix fails the whole service if a declared secret is missing.
- `wsl/.sops.yaml` holds a single creation rule. Its `age:` value is **one line** of comma-separated recipients,
  so bootstrap can append a recipient safely:
  ```yaml
  creation_rules:
    - path_regex: secrets/secrets\.yaml$
      age: age1…,age1…
  ```
  sops looks for its config starting in the current directory, and the repo-root `.sops.yaml` (NixOS rules)
  would shadow this one. So every documented sops command passes `--config ~/dotfiles/wsl/.sops.yaml`.
- First instance: during implementation, the age key is generated here, the file is created with
  `CHANGEME` values, and you then `sops edit` it to put in the real API keys.
- The `sops-nix` systemd user service decrypts into `/run/user/1000/secrets.d/` and links each secret at
  `~/.config/sops-nix/secrets/<name>` (sops-nix `defaultSymlinkPath`).

## WSL overlay (wsl/opencode/)
Copies of the v2 files that conflict with WSL. `my-opencode/` itself is never edited.

### opencode.jsonc (generated)
`wsl/opencode/sync_opencode_jsonc.py BASE OUT` regenerates it from v2; `--check` fails if OUT is stale. The
transform touches only the text it must, so comments and formatting are preserved:
- `{file:/run/secrets/<name>}` → `{file:/home/asergi/.config/sops-nix/secrets/<name>}` (4 provider `apiKey`s).
- Each `permissions` rule whose `resource` contains `/run/secrets` or `/run/secrets.d` is kept, and is
  **immediately followed** by mirrors that have the same `action` and `effect`. In each mirror, that token
  is replaced by:
  - `/run/user/1000/secrets.d`
  - `/home/asergi/.config/sops-nix/secrets`
  - `~/.config/sops-nix/secrets`, for `shell` rules only

  A mirror identical to a rule already in the list is skipped. Source today: 29 rules.

### Prose copies (hand-edited)
Files: `CLAUDE.md`; `skills/agent-browser/SKILL.md`; `skills/webapp-testing/SKILL.md` and
`skills/webapp-testing/examples/{console_logging,element_discovery,static_html_automation}.py`;
`skills/web-artifacts-builder/SKILL.md`; `skills/pptx/SKILL.md` and `skills/pptx/editing.md`;
`skills/transcribe-media/SKILL.md`; `skills/strategic-compact/SKILL.md`.

Each copy starts from the v2 original and changes only what is wrong on WSL:
- Remove the `LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib` prefix, including the `env …` and
  line-continuation forms. Remove prose saying the prefix is required. The replacement fact, where the text
  explains why: uv uses uv-managed Python on this host, so wheels load Ubuntu's `libstdc++` directly.
- Replace `/run/current-system/sw/bin/chromium` and `/run/current-system/sw/bin/google-chrome` with
  `/home/asergi/.nix-profile/bin/chromium`. Where the text explains why: Playwright's downloaded Chromium
  needs apt system libraries that this host doesn't have.
- "NixOS" host wording becomes "Ubuntu on WSL with a declarative Nix home-manager setup", and the config
  location becomes `/home/asergi/dotfiles/wsl` (packages in `packages.nix`). The "declarative, never
  imperative" rules stay.
- `strategic-compact`: drop the `nix-ld-env.js` bullet, because that plugin is not linked on WSL.

### Drift detection
`wsl/opencode/BASE.sha256` holds the `sha256sum` lines (relative to v2) of the original behind every copied
file. A flake check fails when a v2 original changes, or when `opencode.jsonc` is stale. Then the copy is
re-derived and the checksum refreshed.

### Constraints checked on the overlay
- No overlay file other than `opencode.jsonc` contains `/run/current-system`, `nix-ld`, `dotfiles/nixos`, `NixOS` or `NixOs`.
- `opencode.jsonc` keeps the disabled `nixos` MCP entry. `nix run github:utensils/mcp-nixos` works on any host.

## Collision handling
The first switch runs with `-b hm-backup`. For any target that exists and is not a home-manager link, the pinned
home-manager **moves** the file or directory to `<target>.hm-backup` and then links (`modules/files.nix:357-373`).
That covers directories too, so no custom activation step is needed. Expected on the current instance:
- `~/.zshrc`, `~/.zshenv`
- `~/.config/tmux/tmux.conf`
- `~/.config/nvim` (a real copy of neovimrc)
- `~/.config/herdr/config.toml`
- `~/.config/opencode/plugins/herdr-agent-state.js`. `plugins/` becomes a real directory of per-file links,
  because `nix-ld-env.js` is excluded, so the existing directory is kept.

Known behaviour: herdr's integration installer rewrites `plugins/herdr-agent-state.js`. If it writes through
the link, the change lands in `my-opencode/v2`, the same as on NixOS today.

## bootstrap.sh
Bash, `set -euo pipefail`. Every step checks before acting, so re-running it is safe.
Exit codes: 0 = done; 1 = precondition failed (wrong `$HOME` or repo location); 2 = action needed from the user
(restart WSL, or fix secrets access), with the exact next command printed.
1. **systemd:** if `/etc/wsl.conf` lacks `systemd=true`, write `[boot]\nsystemd=true` with sudo. Then tell the
   user to run `wsl.exe --shutdown` and re-run, and exit 2.
2. **Shell and locale:** `sudo apt-get install -y zsh git curl` if any is missing. Run `chsh -s /usr/bin/zsh`
   if the login shell differs. Run `sudo locale-gen en_US.UTF-8` if `locale -a` lacks it.
3. **Nix:** if `nix` is missing, install Determinate Nix
   (`curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm`) and source
   `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
4. **Submodules:** `git -C ~/dotfiles submodule update --init neovimrc`.
5. **Age key:** if `~/.config/sops/age/keys.txt` is missing, **generate** it with `age-keygen` from the flake's
   pinned `age` package (mode 600). Then register its public key in `wsl/.sops.yaml` (appended to the `age:` line,
   only if it isn't there yet), and print the public key.
6. **Secrets access:** a read-only check with the pinned `sops`. It covers whether `wsl/secrets/secrets.yaml` exists,
   whether this key decrypts it, and whether all four keys are present. On a problem, exit 2 with instructions:
   - file missing → create it with `sops --config … wsl/secrets/secrets.yaml` (template with the 4 keys).
   - can't decrypt (a new instance) → on an instance that can decrypt, run `bootstrap.sh --add-recipient <pubkey>`
     (it appends the key and runs `sops updatekeys`), commit, pull here, re-run. Alternatively, re-create the
     file, which drops the other instances' access.
   - keys missing → `sops edit` and add them.
7. **Switch:** if `home-manager` is on `PATH`, use it; otherwise use `nix run ~/dotfiles/wsl#home-manager --` (the
   locked revision). Either way, run `switch --flake ~/dotfiles/wsl#asergi -b hm-backup`.
8. **`--add-recipient AGE_PUBKEY`** (separate mode, run on an instance that can decrypt): register the key, run
   `sops --config wsl/.sops.yaml updatekeys -y wsl/secrets/secrets.yaml`, and remind the user to commit.
9. **`--cleanup`** (only with the flag): print what is present among the items below, ask `[y/N]`, then remove them:
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
- fresh-instance steps: clone with `--recurse-submodules`, then `./bootstrap.sh` (it generates the age key). Then
  `--add-recipient` on an existing instance, or create the secrets file. Re-run `./bootstrap.sh`, then
  `./bootstrap.sh --cleanup`.
- daily use: `update`
- adding packages
- editing secrets: `sops --config ~/dotfiles/wsl/.sops.yaml ~/dotfiles/wsl/secrets/secrets.yaml`; the 4 required keys
- the `max-jobs` note
- troubleshooting: backups named `*.hm-backup`, and `systemctl --user status sops-nix`

## Prerequisites (repo state)
- `my-opencode/v2` is committed (done, `4fceb51`).
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
   - `uvx --from markitdown markitdown --help` runs (numpy loads) with no `LD_LIBRARY_PATH`.
   - `agent-browser doctor` resolves the Nix chromium and passes its live launch test.
   - A headless chromium screenshot of a page shows rendered text.
5. Fresh-instance acceptance test, together with the user:
   - `wsl.exe --install Ubuntu-24.04 --name hm-test`
   - clone dotfiles and run `bootstrap.sh`. It generates a key and stops with exit 2.
   - run `--add-recipient` on this instance (on a throwaway branch), bring that change over, and re-run.
   - repeat steps 3-4, then `wsl.exe --unregister hm-test`. Delete the throwaway branch so the test key never
     reaches the real branch.
