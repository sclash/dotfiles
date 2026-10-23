# WSL home-manager flake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A standalone home-manager flake in `~/dotfiles/wsl` that gives any fresh Ubuntu WSL instance the NixOS
user environment's CLI/TUI tools and configs. It links opencode/Claude config from `my-opencode/v2`, with
WSL-corrected copies kept in `wsl/opencode/`.

**Architecture:** `flake.nix` builds `homeConfigurations.default` from `home.nix`. Identity (username, home directory,
dotfiles path) comes from `lib/user.nix`, which reads `$USER`/`$HOME` and falls back to the historical layout in pure
evaluation. `home.nix` imports portable modules
unchanged from `../nixos/programs`, plus WSL modules in `wsl/modules`. A pure helper (`lib/overlay-links.nix`) maps
a base tree (v2) plus an overlay tree (`wsl/opencode`) to out-of-store `home.file` links. Correctness is checked
by flake `checks`: assertions on the built generation, overlay tests and the sync script's tests. A live check
script runs after the switch.

**Tech Stack:** Nix flakes (Determinate Nix 2.35), home-manager master, sops-nix, Bash, Python 3 (stdlib only),
`unittest`.

**Spec:** `wsl/docs/superpowers/specs/2026-10-20-wsl-home-manager-design.md` (read it alongside this plan).

## Global Constraints

- Create or modify files **only under `~/dotfiles/wsl/`**. Never edit `nixos/`, `my-opencode/` or any
  other directory in `~/dotfiles`.
- Work on branch `wsl-home-manager`, created from `quickshell` in the main checkout. Don't use a worktree: the
  out-of-store links target `$HOME/dotfiles`.
- System `x86_64-linux`; the username and home directory come from `$USER`/`$HOME` via `lib/user.nix`, with flake
  output `homeConfigurations.default`.
- Input locks equal the revisions in `nixos/flake.lock`:
  - nixpkgs `b1b875982b17dabde9b4a37f3e229e74913e6db3`
  - nixpkgs-unstable `7fd4004d0511991fff3a0524856a9be09e28c5f0`
  - nixpkgs-master `d47861e2b824b32538f87e93ce5fe44f1931533b`
  - home-manager `92a0ed1be12f1e20093faf8af63bae2c74ad521e`
  - sops-nix `ee48786c6f9160d2c1a084aac841f68195b8420c`
  - ripwire-src `30f14a274d24ce56a1984e04306b972e1a565d6f`. Dropped in Task 2 (amendment 2026-10-21): WSL uses the
    cached `pkgs-master.ripwire` 0.6.5, because compiling the v0.6.1 pin runs the 3.6 GiB VM out of memory.
- Build limits: `nix.settings = { max-jobs = 1; cores = 2; }` (Task 2). The first switch passes `--max-jobs 1 --cores 2`.
- `config.allowUnfree = true` on `pkgs`, `pkgs-unstable` and `pkgs-master`. `home.enableNixpkgsReleaseCheck = false`.
- No `LD_LIBRARY_PATH` anywhere in the generation.
- Every link to a dotfiles path is `config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/…"`.
- Flakes only see files in the git index, so `git add` new files before any `nix` command.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- All checks: `nix flake check ~/dotfiles/wsl -L`. One check:
  `nix build ~/dotfiles/wsl#checks.x86_64-linux.<name> -L --no-link`.

## Review Focus

1. **Secrets missing** (no age key yet, or before `sops-nix.service` has run): a new zsh must start without
   errors, and the token variables just stay unset. → Task 4 asserts the `[ -f … ]` guards.
2. **Second `update` after the first switch**: earlier `*.hm-backup` files must not make later switches fail.
   → Task 10 runs `update` twice.
3. **Bootstrap on a new or misconfigured instance.** These are tested in Task 9:
   - Repo not at `$HOME/dotfiles`, or missing `$USER`/`$HOME`: bootstrap must refuse with exit 1.
   - Secrets file missing, not decryptable by this instance's freshly generated key, or missing one of the 4 keys:
     bootstrap must stop **before** switching, with exit 2 and the exact next command. Otherwise sops-nix would
     fail at activation.
4. **A v2 original of a copied file changes**: the drift check must fail and name the file. → Task 7 negative test.
5. **An agent reaching secrets through `~/.config/sops-nix/secrets` or `/run/user/*/secrets.d`** instead of
   `/run/secrets`: deny rules must exist for both, and for the tilde form in shell rules. → Task 6 unit tests.

---

### Task 1: Flake skeleton, base home config, generation check

**Files:**
- Create: `wsl/flake.nix`, `wsl/home.nix`, `wsl/tests/check-generation.sh`, `wsl/flake.lock` (generated)

**Interfaces:**
- Produces:
  - Flake outputs `homeConfigurations.default` and `checks.x86_64-linux.generation`.
  - The `generation` check is `pkgs.runCommand "hm-generation-check" { nativeBuildInputs = [ pkgs.jq ]; }` and runs
    `bash ${./tests/check-generation.sh} ${self.homeConfigurations.default.activationPackage}`, then `touch $out`.
  - Module args `pkgs-unstable` and `pkgs-master` (via `extraSpecialArgs`).
  - `tests/check-generation.sh GEN` takes `GEN` = the activation package. It provides these helpers, which later tasks reuse:
    - `has_bin NAME…` / `lacks_bin NAME…` test `$GEN/home-path/bin/NAME`.
    - `has_path REL` / `lacks_path REL` test `$GEN/REL`.
    - `is_dir REL` passes when `$GEN/home-files/REL` is a real directory, not a symlink.
    - `links_to REL TARGET` follows the symlink chain of `$GEN/home-files/REL` until it leaves `/nix/store`, then compares that path with TARGET.
    - `contains FILE STR` / `lacks FILE STR` run `grep -F` on `$GEN/FILE`.
    - `run_contains STR BIN ARGS…` runs `$GEN/home-path/bin/BIN ARGS…` and greps the output.
    - `fail MSG` records a failure. Use it for one-off `[[ … ]] || fail "…"` assertions; `$GEN` is set for them.
  - Each failure prints `FAIL: <helper> <args>`. The script exits 1 if anything failed, and otherwise prints `OK (<n> assertions)`.
  - Assertions are grouped under `# --- Task N: …` headers.

- [ ] **Step 1: Create the branch.** Run `git -C ~/dotfiles switch -c wsl-home-manager`.
  Expected: `Switched to a new branch 'wsl-home-manager'`.

- [ ] **Step 2: Write `tests/check-generation.sh`** with the helpers above and the Task 1 assertions:
  ```bash
  # --- Task 1: base
  has_bin home-manager
  V=home-path/etc/profile.d/hm-session-vars.sh
  contains $V 'export EDITOR="nvim"'; contains $V 'export VISUAL="nvim"'; contains $V 'export SUDO_EDITOR="nvim"'
  contains $V '.opencode/bin'; contains $V '.local/bin'; contains $V 'LANG="en_US.UTF-8"'
  contains $V 'XDG_DATA_DIRS'          # targets.genericLinux
  lacks $V 'LD_LIBRARY_PATH'
  contains home-files/.config/git/config 'name = sclash'
  ```

- [ ] **Step 3: Write `flake.nix` and a minimal `home.nix`.**
  - Inputs (explicit URLs):
    - `nixpkgs` = `github:NixOS/nixpkgs/nixos-26.05`
    - `nixpkgs-unstable` = `github:NixOS/nixpkgs/nixos-unstable`
    - `nixpkgs-master` = `github:NixOS/nixpkgs`
    - `home-manager` = `github:nix-community/home-manager`, follows nixpkgs
    - `sops-nix` = `github:Mic92/sops-nix`, follows nixpkgs
    - `ripwire-src` = `github:redhat-et/ripwire/v0.6.1`, `flake = false`
  - `pkgs-master` overlay: copy only the `ripwire` override from `nixos/flake.nix:105-113`.
  - Modules: `[ ./home.nix sops-nix.homeManagerModules.sops ]`.
  - `home.nix` holds only `home.username = user.username`, `home.homeDirectory = user.homeDirectory` (where
    `user = import ../lib/user.nix`) and `home.stateVersion = "26.05"`.

- [ ] **Step 4: Stage the files and pin the lock.**
  ```bash
  cd ~/dotfiles && git add wsl/flake.nix wsl/home.nix wsl/tests/check-generation.sh
  nix flake lock ./wsl \
    --override-input nixpkgs github:NixOS/nixpkgs/b1b875982b17dabde9b4a37f3e229e74913e6db3 \
    --override-input nixpkgs-unstable github:NixOS/nixpkgs/7fd4004d0511991fff3a0524856a9be09e28c5f0 \
    --override-input nixpkgs-master github:NixOS/nixpkgs/d47861e2b824b32538f87e93ce5fe44f1931533b \
    --override-input home-manager github:nix-community/home-manager/92a0ed1be12f1e20093faf8af63bae2c74ad521e \
    --override-input sops-nix github:Mic92/sops-nix/ee48786c6f9160d2c1a084aac841f68195b8420c \
    --override-input ripwire-src github:redhat-et/ripwire/30f14a274d24ce56a1984e04306b972e1a565d6f
  git add wsl/flake.lock
  python3 -c "import json;a,b=(json.load(open(f))['nodes'] for f in ('nixos/flake.lock','wsl/flake.lock'));ks=['nixpkgs','nixpkgs-unstable','nixpkgs-master','home-manager','sops-nix','ripwire-src'];bad=[k for k in ks if a[k]['locked']['rev']!=b[k]['locked']['rev']];print('lock parity', 'OK' if not bad else bad)"
  ```
  Expected: `lock parity OK`.

- [ ] **Step 5: Run the check.** `nix build ./wsl#checks.x86_64-linux.generation -L --no-link`
  Expected: FAIL. The lines include `FAIL: contains … export EDITOR="nvim"`.

- [ ] **Step 6: Fill in `home.nix`** with the spec's "home.nix › Settings":
  - `targets.genericLinux.enable = true` and `targets.genericLinux.gpu.enable = false`
  - `home.enableNixpkgsReleaseCheck = false`, `programs.home-manager.enable = true`
  - `programs.git` and `programs.man` copied from `nixos/home.nix:135-148`
  - `home.language.base = "en_US.UTF-8"`
  - `home.sessionPath = [ "$HOME/.local/bin" "$HOME/.opencode/bin" ]`
  - `EDITOR`, `VISUAL` and `SUDO_EDITOR` = `"nvim"`

- [ ] **Step 7: Run the check again.** Same command. Expected: `OK (<n> assertions)` and no FAIL lines. Also run
  `nix eval ./wsl#homeConfigurations.default.config.targets.genericLinux.gpu.enable`. Expected: `false`.

- [ ] **Step 8: Commit.** `git add wsl && git commit -m "wsl: flake skeleton, base home config, generation check"`

### Task 2: Shared program modules, herdr, dotfile links, uv.toml copy

**Files:**
- Modify: `wsl/home.nix` (imports, `home.file`), `wsl/tests/check-generation.sh`
- Create: `wsl/modules/herdr.nix`, `wsl/uv/uv.toml`

**Interfaces:** Consumes `pkgs-master` (Task 1).

- [ ] **Step 1: Append the Task 2 assertions.**
  ```bash
  # --- Task 2: program modules + links
  has_bin tmux starship atuin nu uv devenv pandoc xelatex ripwire herdr \
          vtsls pyright clangd gopls zls lua-language-server texlab rust-analyzer \
          codelldb debugpy-adapter prettier black dlv
  run_contains 0.6.5 ripwire --version
  contains home-files/.config/nix/nix.conf 'max-jobs = 1'; contains home-files/.config/nix/nix.conf 'cores = 2'
  lacks_bin nix
  contains home-files/.config/tmux/tmux.conf sessionx
  contains home-files/.config/tmux/tmux.conf continuum-restore
  links_to .config/nvim      "$HOMEDIR/dotfiles/neovimrc"
  links_to .config/starship  "$HOMEDIR/dotfiles/starship"
  links_to .config/atuin     "$HOMEDIR/dotfiles/atuin"
  links_to .config/uv/uv.toml "$HOMEDIR/dotfiles/wsl/uv/uv.toml"
  is_dir   .config/herdr
  links_to .config/herdr/config.toml "$HOMEDIR/dotfiles/herdr/config.toml"
  ```

- [ ] **Step 2: Run the check.** Expected: FAIL (`has_bin tmux` …).

- [ ] **Step 3: Implement.**
  - `home.nix` imports `../nixos/programs/{tmux/tmux.nix,starship.nix,atuin.nix,uv/uv.nix,pandoc.nix,nushell.nix,devenv.nix,nvim-lsp.nix,ripwire.nix}` and `./modules/herdr.nix`.
  - It adds `home.file` links for `.config/nvim`, `.config/starship` and `.config/atuin` (spec "Links" table).
  - It overrides `home.file.".config/uv/uv.toml".source = lib.mkForce (…/dotfiles/wsl/uv/uv.toml)`.
  - `modules/herdr.nix`: `programs.herdr = { enable = true; package = pkgs-master.herdr; }`, plus
    `xdg.configFile."herdr/config.toml"` linked out-of-store to `~/dotfiles/herdr/config.toml`.
  - `wsl/uv/uv.toml` is a byte copy of `nixos/programs/uv/uv.toml`, except
    `python-preference = "managed"`.

- [ ] **Step 4: Verify.**
  - The check prints `OK`.
  - `sed 's/^python-preference = .*/python-preference = "managed"/' nixos/programs/uv/uv.toml | cmp - wsl/uv/uv.toml` exits 0.
  - `git status --short -- nixos my-opencode` is empty.

- [ ] **Step 5: Commit.** `git commit -m "wsl: shared program modules, herdr, dotfile links, managed-python uv.toml"`

### Task 3: Package set, chromium, fonts

**Files:**
- Create: `wsl/packages.nix`
- Modify: `wsl/home.nix` (import `./packages.nix`), `wsl/tests/check-generation.sh`

**Interfaces:** Consumes `pkgs-unstable` (Task 1).

- [ ] **Step 1: Append the Task 3 assertions.**
  ```bash
  # --- Task 3: packages
  has_bin nvim vim tree-sitter nixd nix-prefetch-git sops age age-keygen tree bat eza fd jq zoxide zip unzip wget wl-copy \
          gh lazygit lazydocker lazysql lazyssh lazycli btop htop ncdu fastfetch glow hygg \
          ffmpeg timg chafa flamegraph.pl hyperfine gcc clang lldb gdb valgrind bear make pkg-config lua \
          node npm tsc playwright chromium orx rg fzf ctags python3 bun go rustc cargo zig agent-browser
  [[ "$(readlink -f "$GEN/home-path/bin/cc")" == *gcc-wrapper* ]] || fail "cc resolves to gcc"
  lacks_bin firefox google-chrome ghostty docker perf rr ldd
  has_path home-files/.config/fontconfig/conf.d/10-hm-fonts.conf
  [[ -n "$(find -L "$GEN/home-path/share/fonts" -iname 'NotoSans-Regular*' -print -quit)" ]] || fail "noto sans"
  [[ -n "$(find -L "$GEN/home-path/share/fonts" -iname 'NotoColorEmoji*' -print -quit)" ]] || fail "noto emoji"
  ```
  If nixpkgs names a binary differently (e.g. `lazycli`, `hygg`), assert the package's real main binary and
  say so in the commit message.

- [ ] **Step 2: Run the check.** Expected: FAIL (`has_bin nvim` …).

- [ ] **Step 3: Implement `packages.nix`** with the spec's "Packages" list. Use `lib.hiPrio pkgs.gcc` and
  `(import ../nixos/programs/open-research.nix { inherit pkgs; })`. Add `fonts.fontconfig.enable = true`. If another
  `buildEnv` collision appears, prefer the `pkgs-unstable` side with `lib.hiPrio` and note it in the commit.

- [ ] **Step 4: Run the check.** Expected: `OK`.

- [ ] **Step 5: Commit.** `git commit -m "wsl: package set, headless chromium, noto fonts"`

### Task 4: Secrets and zsh

**Files:**
- Create: `wsl/modules/secrets.nix`, `wsl/modules/zsh.nix`, `wsl/.sops.yaml`, `wsl/secrets/secrets.yaml`
- Modify: `wsl/home.nix` (imports), `wsl/flake.nix` (`packages`), `wsl/tests/check-generation.sh`

**Interfaces:**
- Produces:
  - `config.sops.secrets.<name>.path` = `$HOMEDIR/.config/sops-nix/secrets/<name>` for `github_pat`,
    `openrouter`, `opencode` and `cheaper_inference`.
  - Flake outputs `packages.x86_64-linux.{home-manager,sops,age}`, taken from the locked inputs
    (`home-manager.packages.…home-manager`, `pkgs.sops`, `pkgs.age`). bootstrap uses them before the first switch.
  - `wsl/.sops.yaml` has exactly one creation rule, with `path_regex: secrets/secrets\.yaml$` and a **single-line**
    `age:` value (spec "modules/secrets.nix").

- [ ] **Step 1: Generate this instance's key and the WSL sops files.**
  - Add the `packages` outputs, then `git add wsl/flake.nix`.
  - Create the key: `nix shell ./wsl#age -c age-keygen -o ~/.config/sops/age/keys.txt`. Create the directory first with
    `mkdir -p -m 700`. Refuse if the file already exists, and never print its contents.
  - Write `wsl/.sops.yaml` with this instance's public key (`age-keygen -y ~/.config/sops/age/keys.txt`).
  - Create `wsl/secrets/secrets.yaml`:
    `printf 'github_pat: CHANGEME\nopenrouter: CHANGEME\nopencode: CHANGEME\ncheaper_inference: CHANGEME\n' > wsl/secrets/secrets.yaml`,
    then `nix run ./wsl#sops -- --config wsl/.sops.yaml -e -i wsl/secrets/secrets.yaml`.
  - Verify: `nix run ./wsl#sops -- --config wsl/.sops.yaml -d wsl/secrets/secrets.yaml` prints the 4 `CHANGEME` keys,
    and `grep -c CHANGEME wsl/secrets/secrets.yaml` prints `0` (the file is encrypted).
  - `git add wsl/.sops.yaml wsl/secrets/secrets.yaml`.
  - The user replaces the values with `sops edit` whenever they want. Nothing here depends on the real values.

- [ ] **Step 2: Append the Task 4 assertions.**
  ```bash
  # --- Task 4: secrets + zsh
  U=home-files/.config/systemd/user/sops-nix.service; has_path $U
  M=$(grep -rhoE '/nix/store/[^ "]*manifest[^ "]*\.json' "$GEN/$U" $(grep -oE '/nix/store/[^ "]+' "$GEN/$U") 2>/dev/null | head -1)
  [[ "$(jq -r '.secrets[].name' "$M" | sort | xargs)" == "cheaper_inference github_pat opencode openrouter" ]] || fail "sops secret names"
  [[ -n "$M" && -z "$(jq -r '.secrets[].path' "$M" | grep -vF -- "$HOMEDIR/.config/sops-nix/secrets/")" ]] || fail "sops secret paths"
  Z=home-files/.zshrc
  contains $Z 'home-manager switch --flake ~/dotfiles/wsl#default -b hm-backup --impure --max-jobs 1 --cores 2'
  contains $Z "$HOMEDIR/dotfiles/scripts/tmux-sessionizer.sh"
  contains $Z 'show_eza_tree'
  contains $Z "if [ -f $HOMEDIR/.config/sops-nix/secrets/github_pat ]"   # Review Focus 1
  contains $Z "if [ -f $HOMEDIR/.config/sops-nix/secrets/openrouter ]"
  contains $Z 'GITHUB_PERSONAL_ACCESS_TOKEN'; contains $Z 'OPENROUTER_API'
  contains $Z 'starship init zsh'; contains $Z 'atuin init zsh'
  lacks $Z '/run/secrets'; lacks $Z 'nixos-rebuild'
  ```

- [ ] **Step 3: Run the check.** Expected: FAIL (`has_path …sops-nix.service`).

- [ ] **Step 4: Implement both modules** as in the spec ("modules/secrets.nix", "modules/zsh.nix"), with
  `sops.defaultSopsFile = ../secrets/secrets.yaml`. Write the
  `initContent` secret exports exactly like this, with the paths interpolated from `config.sops.secrets.<name>.path`:
  ```sh
  if [ -f ${gh} ]; then export GITHUB_PERSONAL_ACCESS_TOKEN="$(cat ${gh})"; fi
  if [ -f ${or} ]; then export OPENROUTER_API="$(cat ${or})"; fi
  ```

- [ ] **Step 5: Run the check.** Expected: `OK`. If the manifest's lookup expression doesn't match the pinned
  sops-nix layout, fix the lookup in the test (not the module), and keep both name and path assertions.

- [ ] **Step 6: Commit.** `git commit -m "wsl: sops-nix secrets (per-instance age keys) and WSL zsh"`

### Task 5: overlay-links helper

**Files:**
- Create: `wsl/lib/overlay-links.nix`, `wsl/tests/overlay-links.nix`, plus fixtures under `wsl/tests/fixtures/overlay/`
- Modify: `wsl/flake.nix` (add `checks.x86_64-linux.overlay-links = import ./tests/overlay-links.nix { inherit pkgs; };`)

**Interfaces:**
- Produces (`wsl/lib/overlay-links.nix`):
  ```nix
  { lib }:
  { link, baseSrc, overlaySrc, baseLive, overlayLive, exclude ? [ ] }:
  rel:   # string, e.g. "skills"
  # -> { "<path relative to tree root>" = { source = link "<baseLive|overlayLive>/<path>"; }; … }
  ```
  - `link`: a function from a string to a `source` value.
  - `baseSrc` and `overlaySrc`: paths in the flake source, used for `builtins.readDir` and `builtins.pathExists`.
  - `baseLive` and `overlayLive`: absolute strings.
  - The rules are the spec's "lib/overlay-links.nix" rules.

- [ ] **Step 1: Create the fixtures.** Every file contains its own path as text.
  - `base/`: `top.md`, `dir/keep.md`, `dir/sub/a.md`, `dir/sub/b.md`, `plugins/good.js`, `plugins/bad.js`, `whole/x.md`
  - `overlay/`: `top.md`, `dir/sub/a.md`, `dir/new.md`

- [ ] **Step 2: Write `tests/overlay-links.nix`.** It calls the helper with `link = p: p`, `baseLive = "/B"` and
  `overlayLive = "/O"`. It compares each case with `==`, and on any mismatch it `throw`s
  `builtins.toJSON { inherit case actual expected; }`. Otherwise it returns `pkgs.runCommand "overlay-links-ok" { } "touch $out"`.
  | case | rel | exclude | expected (`path = source`) |
  |---|---|---|---|
  | overlaid top file | `top.md` | – | `top.md=/O/top.md` |
  | untouched dir | `whole` | – | `whole=/B/whole` |
  | deep overlay + new file | `dir` | – | `dir/keep.md=/B/dir/keep.md`, `dir/new.md=/O/dir/new.md`, `dir/sub/a.md=/O/dir/sub/a.md`, `dir/sub/b.md=/B/dir/sub/b.md` |
  | exclude child | `plugins` | `["plugins/bad.js"]` | `plugins/good.js=/B/plugins/good.js` |
  | exclude item | `plugins` | `["plugins"]` | `{}` |
  | missing item | `missing` | – | `{}` |

- [ ] **Step 3: Run the check.** `git add wsl && nix build ./wsl#checks.x86_64-linux.overlay-links --no-link`.
  Expected: FAIL (the helper file is missing).

- [ ] **Step 4: Implement `lib/overlay-links.nix`.** Recurse with `lib.foldl'`/`lib.mergeAttrsList` over the union of
  `builtins.attrNames (builtins.readDir …)` from base and overlay. A path counts as "has an exclude below" when some
  `exclude` entry starts with `"${rel}/"`.

- [ ] **Step 5: Run the check.** Expected: builds successfully.

- [ ] **Step 6: Commit.** `git commit -m "wsl: overlay-links helper with eval tests"`

### Task 6: opencode.jsonc sync script and generated copy

**Files:**
- Create: `wsl/opencode/sync_opencode_jsonc.py`, `wsl/tests/test_sync_opencode_jsonc.py`, `wsl/tests/check-overlay.sh`, `wsl/opencode/opencode.jsonc` (generated)
- Modify: `wsl/flake.nix`: add `checks.x86_64-linux.overlay`, which runs
  `bash ${./tests/check-overlay.sh} ${../my-opencode/v2} ${./opencode} ${./tests}` with `nativeBuildInputs = [ pkgs.python3 ]`

**Interfaces:**
- Produces:
  - `transform(text: str) -> str`.
  - The CLI `sync_opencode_jsonc.py [--check] BASE OUT` writes `transform(BASE)` to `OUT`. With `--check`, it prints
    `stale: OUT` and exits 1 when `OUT` differs.
  - Constants `MOUNT_DIR = "/run/user/*/secrets.d"`, `SOPS_DIR = "~/.config/sops-nix/secrets"`,
    `SHELL_SOPS_DIR = "*/.config/sops-nix/secrets"` and `TILDE_SOPS_DIR = "~/.config/sops-nix/secrets"`.
  - `tests/check-overlay.sh V2_DIR OVERLAY_DIR TESTS_DIR` runs the unit tests and `--check`. Task 7 extends it.

- [ ] **Step 1: Write the unit tests.** Use stdlib `unittest`, and build the fixtures as **pure JSON** strings in the
  v2 layout (tab-indented rule objects `{ "action", "resource", "effect" }` in a `"permissions"` list), so the
  output can be checked with `json.loads`.
  - `test_file_refs_rewritten`:
    - `{file:/run/secrets/openrouter}` becomes `{file:~/.config/sops-nix/secrets/openrouter}`.
    - No `{file:/run/secrets` remains.
  - `test_read_rule_mirrors_follow_source`: `read /run/secrets/** deny` becomes
    `[orig, read /run/user/*/secrets.d/** deny, read ~/.config/sops-nix/secrets/** deny]`, in that order.
  - `test_dot_d_rule_maps_to_same_locations`: `/run/secrets.d/**` gives mirrors `/run/user/*/secrets.d/**` and
    `~/.config/sops-nix/secrets/**`.
  - `test_shell_rule_gets_tilde_variant`: `shell *cat /run/secrets* deny` gives 3 mirrors. The last one is
    `*cat */.config/sops-nix/secrets*`.
  - `test_duplicate_mirrors_skipped`: rules for `/run/secrets/**` and `/run/secrets.d/**` produce
    `/run/user/*/secrets.d/**` exactly once.
  - `test_effect_and_action_preserved`: an `ask` rule mirrors with `ask`.
  - `test_last_rule_in_list`: a secrets rule last in the list still gives a `json.loads`-valid result.
  - `test_unrelated_text_untouched`: a `**/*.key` rule and a `// comment` line are byte-identical in the output.
  - `test_idempotent`: `transform(transform(x)) == transform(x)`.

- [ ] **Step 2: Run the tests.** `python3 -m unittest discover -s wsl/tests -p 'test_*.py' -v`. Expected: FAIL
  (`ModuleNotFoundError`). The test adds `wsl/opencode` to `sys.path`.

- [ ] **Step 3: Implement `sync_opencode_jsonc.py`.** Do a text-level transform that preserves everything outside the
  changed spans. Each mirror copies its source block's exact indentation.

- [ ] **Step 4: Run the tests.** Same command. Expected: all pass.

- [ ] **Step 5: Generate the copy and validate it.**
  ```bash
  python3 wsl/opencode/sync_opencode_jsonc.py my-opencode/v2/opencode.jsonc wsl/opencode/opencode.jsonc
  npx -y json5@2.2.3 --validate wsl/opencode/opencode.jsonc && echo VALID
  npx -y json5@2.2.3 wsl/opencode/opencode.jsonc | python3 -c "import json,sys;d=json.load(sys.stdin);p=d['providers'];S='{file:~/.config/sops-nix/secrets/';assert [p[k]['settings']['apiKey'] for k in ('openrouter','opencode-go','opencode','cheaper-inference')]==[S+'openrouter}',S+'opencode}',S+'opencode}',S+'cheaper_inference}'];r=[x['resource'] for x in d['permissions']];assert sum('/run/secrets' in x for x in r)==29;assert not any('{file:/run/secrets' in json.dumps(v) for v in p.values());print('jsonc OK')"
  ```
  Expected: `VALID` and `jsonc OK`.

- [ ] **Step 6: Write `tests/check-overlay.sh`** (unit tests plus `--check` against `V2_DIR/opencode.jsonc`). Run
  `git add wsl && nix build ./wsl#checks.x86_64-linux.overlay -L --no-link`. Expected: builds successfully.

- [ ] **Step 7: Commit.** `git commit -m "wsl: opencode.jsonc sync (sops paths, mirrored deny rules)"`

### Task 7: Prose overlay copies and drift detection

**Files:**
- Create the copies, at the same relative paths, under `wsl/opencode/`:
  - `CLAUDE.md`
  - `skills/agent-browser/SKILL.md`
  - `skills/webapp-testing/SKILL.md`
  - `skills/webapp-testing/examples/{console_logging,element_discovery,static_html_automation}.py`
  - `skills/web-artifacts-builder/SKILL.md`
  - `skills/pptx/SKILL.md`, `skills/pptx/editing.md`
  - `skills/transcribe-media/SKILL.md`
  - `skills/strategic-compact/SKILL.md`
- Create: `wsl/opencode/BASE.sha256`
- Modify: `wsl/tests/check-overlay.sh`

- [ ] **Step 1: Extend `check-overlay.sh`.**
  - (a) `cd V2_DIR && sha256sum --quiet -c OVERLAY_DIR/BASE.sha256`. For each mismatched file, print
    `drift: <file> changed in my-opencode/v2; re-derive wsl/opencode/<file> and refresh BASE.sha256`, and fail.
  - (b) Every path listed in `BASE.sha256` exists under `OVERLAY_DIR`.
  - (c) Ignoring `opencode.jsonc`, `sync_opencode_jsonc.py` and `BASE.sha256`,
    `grep -rnE '/run/current-system|nix-ld|dotfiles/nixos|NixOS|NixOs' OVERLAY_DIR` must print nothing. Any line it
    prints is a failure.

- [ ] **Step 2: Run the check.** `git add wsl && nix build ./wsl#checks.x86_64-linux.overlay -L --no-link`.
  Expected: FAIL (missing `BASE.sha256`).

- [ ] **Step 3: Copy the originals and record their checksums.**
  ```bash
  cd ~/dotfiles/my-opencode/v2
  F="opencode.jsonc CLAUDE.md skills/agent-browser/SKILL.md skills/webapp-testing/SKILL.md skills/webapp-testing/examples/console_logging.py skills/webapp-testing/examples/element_discovery.py skills/webapp-testing/examples/static_html_automation.py skills/web-artifacts-builder/SKILL.md skills/pptx/SKILL.md skills/pptx/editing.md skills/transcribe-media/SKILL.md skills/strategic-compact/SKILL.md"
  for f in $F; do [ "$f" = opencode.jsonc ] || install -D -m644 "$f" "../../wsl/opencode/$f"; done
  sha256sum $F > ../../wsl/opencode/BASE.sha256
  ```

- [ ] **Step 4: Run the check.** Expected: FAIL. Step (c) lists the NixOS lines.

- [ ] **Step 5: Edit the copies** using the spec's "Prose copies" rules. Per file:
  - `CLAUDE.md:13-15`:
    - 13 → "You're using Ubuntu on WSL with a declarative Nix home-manager setup (flakes enabled). You have the `nixos` MCP to refer to for correct nix commands."
    - 14 → "- The declarative configuration is the home-manager flake in `~/dotfiles/wsl`"
    - 15 → "- The setup is declarative: DO NOT EVER ACT in an imperative manner. (Refer to …)"
  - `agent-browser/SKILL.md`:
    - Heading at :12 → "## WSL host: read this before anything else".
    - :14 → "This machine is **Ubuntu on WSL** with a declarative Nix home-manager setup, and the browser toolchain is already provided declaratively:".
    - :16 → `~/dotfiles/wsl/packages.nix`.
    - :19 → "edit to `~/dotfiles/wsl` (package added to `packages.nix`)".
    - :30-31 → `~/.nix-profile/bin/chromium`.
    - :54 → "keep these host constraints".
  - `webapp-testing/SKILL.md`:
    - :30, :73 and :82: drop the `LD_LIBRARY_PATH=…`/`env LD_LIBRARY_PATH=… \` parts.
    - :33-42 become two bullets:
      - uv-managed Python loads Ubuntu's `libstdc++`, so no prefix is needed.
      - `executable_path` is the Nix chromium plus `--no-sandbox`, because Playwright's downloaded Chromium needs apt system libraries that are missing here. Keep "Do not run `playwright install`".
    - :91 → the Nix chromium path.
    - :95 → "…cannot resolve its shared-library deps on this host."
  - `examples/*.py`: the comment says "required on this host"; `executable_path=os.path.expanduser("~/.nix-profile/bin/chromium")`.
  - `web-artifacts-builder/SKILL.md:73` → "It carries the host-correct invocation: `uv run --with playwright python …`, launching the Nix-provided Chromium at `~/.nix-profile/bin/chromium`."
  - `pptx/SKILL.md`:
    - :13, :23, :150, :158 and :213: drop the prefix. At :213 also drop the parenthetical.
    - :225 and :229: drop the `LD_LIBRARY_PATH=… \` line.
  - `pptx/editing.md:10`: drop the prefix.
  - `transcribe-media/SKILL.md`:
    - :20 and :75-77: drop the prefix.
    - :23 → "On this host `uvx` uses uv-managed Python, so packages pulling numpy load Ubuntu's `libstdc++` directly; no `LD_LIBRARY_PATH` prefix is needed."
    - Delete the bullet at :91.
  - `strategic-compact/SKILL.md:115`: delete the `nix-ld-env.js` bullet.

- [ ] **Step 6: Run the check.** Expected: builds successfully. Also verify that
  `diff <(cd my-opencode/v2 && cat skills/pptx/SKILL.md) wsl/opencode/skills/pptx/SKILL.md` shows only the
  prefix/parenthetical lines.

- [ ] **Step 7: Negative test (Review Focus 4).**
  ```bash
  t=$(mktemp -d) && cp -r my-opencode/v2/. "$t" && echo >> "$t/CLAUDE.md"
  bash wsl/tests/check-overlay.sh "$t" wsl/opencode wsl/tests; echo "exit=$?"; rm -rf "$t"
  ```
  Expected: the output contains `drift: CLAUDE.md`, and `exit=1`.

- [ ] **Step 8: Commit.** `git commit -m "wsl: WSL copies of NixOS-specific v2 docs/skills + drift check"`

### Task 8: opencode and claude-code modules

**Files:**
- Create: `wsl/modules/opencode.nix`, `wsl/modules/claude-code.nix`
- Modify: `wsl/home.nix` (imports), `wsl/tests/check-generation.sh`

**Interfaces:**
- Consumes `lib/overlay-links.nix` (Task 5), with:
  - `baseSrc = ../../my-opencode/v2`, `overlaySrc = ../opencode`
  - `baseLive = "${home}/dotfiles/my-opencode/v2"`, `overlayLive = "${home}/dotfiles/wsl/opencode"`
  - `link = config.lib.file.mkOutOfStoreSymlink`

- [ ] **Step 1: Append the Task 8 assertions.**
  ```bash
  # --- Task 8: opencode + claude-code
  B=$HOMEDIR/dotfiles/my-opencode/v2; O=$HOMEDIR/dotfiles/wsl/opencode; C=.config/opencode
  links_to $C/opencode.jsonc $O/opencode.jsonc; links_to $C/CLAUDE.md $O/CLAUDE.md
  for i in AGENTS.md RIPWIRE.md agents commands instructions prompts scripts tools; do links_to $C/$i $B/$i; done
  is_dir $C/plugins; links_to $C/plugins/herdr-agent-state.js $B/plugins/herdr-agent-state.js
  links_to $C/plugins/strategic-compact.js $B/plugins/strategic-compact.js; lacks_path home-files/$C/plugins/nix-ld-env.js
  is_dir $C/skills; links_to $C/skills/explore-codebase $B/skills/explore-codebase
  links_to $C/skills/pptx/SKILL.md $O/skills/pptx/SKILL.md; links_to $C/skills/pptx/editing.md $O/skills/pptx/editing.md
  links_to $C/skills/agent-browser/SKILL.md $O/skills/agent-browser/SKILL.md
  links_to $C/skills/webapp-testing/examples/console_logging.py $O/skills/webapp-testing/examples/console_logging.py
  links_to $C/skills/webapp-testing/scripts $B/skills/webapp-testing/scripts
  for i in evals package-lock.json vastai; do lacks_path home-files/$C/$i; done
  links_to .agents $HOMEDIR/dotfiles/.agents
  contains home-path/etc/profile.d/hm-session-vars.sh 'OPENCODE_DISABLE_CLAUDE_CODE_SKILLS="true"'
  for s in explore-codebase high-perf-systems download-video; do links_to .claude/skills/$s $B/skills/$s; done
  links_to .claude/skills/transcribe-media/SKILL.md $O/skills/transcribe-media/SKILL.md
  lacks_path home-files/.claude/settings.json; lacks_bin claude opencode
  lacks_path home-files/.config/mcp/mcp.json   # mcpservers.nix is not imported
  ```

- [ ] **Step 2: Run the check.** Expected: FAIL.

- [ ] **Step 3: Implement both modules** as in the spec. The item list and `exclude = [ "plugins/nix-ld-env.js" ]`
  come from the spec's "modules/opencode.nix". Claude Code uses `rel = "skills/<name>"`, mapped to `.claude/<rel>`.

- [ ] **Step 4: Run the full flake check.** `nix flake check ./wsl -L`. Expected: every check passes.

- [ ] **Step 5: Commit.** `git commit -m "wsl: opencode and claude-code config via v2 + overlay"`

### Task 9: bootstrap.sh and README

**Files:**
- Create: `wsl/bootstrap.sh` (mode 755), `wsl/README.md`, `wsl/tests/test-bootstrap.sh`

**Interfaces:**
- Consumes: `packages.x86_64-linux.{home-manager,sops,age}` (Task 4), and `wsl/.sops.yaml`'s single-line `age:` (Task 4).
- Produces:
  - The CLI `bootstrap.sh [--dry-run] [--cleanup] [--add-recipient AGE_PUBKEY] [--help]`. Exit codes follow the
    spec: 0 done, 1 precondition failed, 2 action needed.
  - Env overrides, for tests only: `AGE_KEY_FILE` (default `$HOME/.config/sops/age/keys.txt`),
    `SOPS_CONFIG` (default `<repo>/wsl/.sops.yaml`), `SECRETS_FILE` (default `<repo>/wsl/secrets/secrets.yaml`).
  - Sourceable functions. The script runs `main "$@"` only when `"${BASH_SOURCE[0]}" == "$0"`.
    - `register_recipient PUBKEY SOPS_YAML` appends `,PUBKEY` to the `age:` line when it's missing. It's idempotent.
    - `secrets_status SOPS_YAML SECRETS_FILE` prints exactly one of `ok`, `missing`, `undecryptable` or
      `missing-keys:<comma-separated names>`. It's read-only and uses `SOPS_AGE_KEY_FILE=$AGE_KEY_FILE`.
  - `--dry-run` prints each mutating command as `DRY-RUN: <cmd>` instead of running it, and skips the cleanup prompt.
    Read-only probes, including `secrets_status`, still run.
  - Exit 1 when `$USER`/`$HOME` are missing, the script runs as root, or the script's repo root isn't
    `$HOME/dotfiles`. The message contains `expects the repo at $HOME/dotfiles`.
  - Switch command: `nix run $HOME/dotfiles/wsl#home-manager -- switch --flake $HOME/dotfiles/wsl#default -b hm-backup --impure --max-jobs 1 --cores 2`.
    Use `home-manager switch …` when `home-manager` is on PATH.

- [ ] **Step 1: Write `tests/test-bootstrap.sh`.** It creates a temp dir `$T` with two keys, A and B (made with
  `nix shell ./wsl#age -c age-keygen`). It writes `$T/.sops.yaml` with recipient A, and encrypts `$T/full.yaml`
  (all 4 keys) and `$T/partial.yaml` (no `cheaper_inference`) with `nix run ./wsl#sops -- --config $T/.sops.yaml`.
  - `nix run github:NixOS/nixpkgs/b1b875982b17dabde9b4a37f3e229e74913e6db3#shellcheck -- wsl/bootstrap.sh` exits 0.
  - `bootstrap.sh --help` exits 0 and mentions `--cleanup`, `--dry-run` and `--add-recipient`.
  - Source the script, then check `secrets_status`:
    - with key A: `full` gives `ok`; `partial` gives `missing-keys:cheaper_inference`; `$T/none.yaml` gives `missing`.
    - with key B: `full` gives `undecryptable`.
  - `register_recipient B $T/.sops.yaml` twice: the `age:` line contains B exactly once and A unchanged.
  - `--add-recipient` (run with `SOPS_CONFIG`/`SECRETS_FILE` pointing at `$T`, key A): afterwards key B gets `ok` on `full`.
  - `HOME=/tmp/elsewhere bootstrap.sh --dry-run` exits 1 and prints `expects the repo` (Review Focus 3).
  - `AGE_KEY_FILE=$T/B.txt SECRETS_FILE=$T/full.yaml SOPS_CONFIG=$T/.sops.yaml bootstrap.sh --dry-run`:
    exits 2, prints `--add-recipient age1…` (B's public key), and has no `switch --flake` line (Review Focus 3).
  - `AGE_KEY_FILE=$T/new.txt … --dry-run` (no key yet) prints `DRY-RUN: … age-keygen -o $T/new.txt`.
  - On this instance's real files (key from Task 4), `--dry-run`:
    - exits 0
    - contains `DRY-RUN:` and `switch --flake $HOME/dotfiles/wsl#default -b hm-backup`
    - contains `locale-gen en_US.UTF-8` (missing here)
    - lacks `install.determinate.systems`, `wsl.conf` and `chsh` (already satisfied)
    - a second run gives identical output
  - `--cleanup --dry-run` lists `~/.oh-my-zsh` and `snap nvim` with `DRY-RUN:` removal commands, and `~/.oh-my-zsh`
    still exists afterwards.
  - `rm -rf "$T"` on exit (trap).

- [ ] **Step 2: Run the test.** `bash wsl/tests/test-bootstrap.sh`. Expected: FAIL (no script).

- [ ] **Step 3: Implement `bootstrap.sh`** following the spec's "bootstrap.sh" steps 1-9. Use `set -euo pipefail`, one
  function per step, and a `run()` wrapper that honours `--dry-run`. Pass `--config "$SOPS_CONFIG"` to every sops
  call. Write `README.md` with the spec's "README.md" contents, including the new-instance key flow.

- [ ] **Step 4: Run the test.** Expected: all pass. Then `nix flake check ./wsl -L` still passes.

- [ ] **Step 5: Commit.** `git commit -m "wsl: idempotent bootstrap.sh (key gen, secrets check, --add-recipient, --cleanup), README"`

### Task 10: Live switch on this instance (with the user)

**Files:** Create `wsl/tests/check-live.sh`. It runs as the user, outside the sandbox. It prints `OK`/`FAIL`/`SKIP`
per line and exits 1 on any FAIL.

- [ ] **Step 1: Precondition.** The key from Task 4 exists, and `secrets_status` reports `ok`. Before Step 7's
  provider check, ask the user whether they have replaced the `CHANGEME` values with `sops edit`. The switch itself
  works with placeholders.

- [ ] **Step 2: Write `check-live.sh`.** Every probe runs inside `zsh -lic '…'`, so the login environment is used.
  - For `nvim tmux herdr rg go zig node cargo uv starship atuin chromium claude opencode`, the first `whence -p` hit
    is under `$HOME/.nix-profile/bin/`.
  - `realpath` of `~/.config/{nvim,starship,atuin,uv/uv.toml,herdr/config.toml}` starts with `$HOME/dotfiles/`.
  - `find ~/.config/opencode ~/.claude/skills -xtype l` is empty (no dangling links).
  - `systemctl --user show -p Result sops-nix` = `Result=success`; there are 4 entries in `~/.config/sops-nix/secrets/`;
    `$GITHUB_PERSONAL_ACCESS_TOKEN` is non-empty; `$LD_LIBRARY_PATH` is empty.
  - `uvx --from markitdown markitdown --help` exits 0.
  - `uv tool list` contains `graphifyy`; `ripwire --version` contains `0.6.5`; `orx --help` exits 0;
    `nvim --headless +qa` exits 0 with empty stderr.
  - The `tmux -L hmcheck` server shows `@continuum-restore` in `show-options -g`.
  - `chromium --headless --no-sandbox --disable-gpu --window-size=800,600 --screenshot=$T/s.png 'data:text/html,<h1>Hello WSL</h1>'`
    writes a non-empty PNG; `fc-list` lists Noto; `agent-browser doctor` exits 0.

- [ ] **Step 3: Dry-run switch.**
  `nix run ./wsl#home-manager -- switch --flake $HOME/dotfiles/wsl#default -b hm-backup --impure -n`.
  Compare the "will be moved to …hm-backup" lines with the spec's "Collision handling" list.
  **Checkpoint: show the list to the user and wait for go-ahead.**

- [ ] **Step 4: Real switch.** `bash wsl/bootstrap.sh`. Expected: it finishes with home-manager's activation summary
  and exit 0. The locale step will ask for sudo.

- [ ] **Step 5: Live checks.** `bash wsl/tests/check-live.sh`. Expected: no FAIL lines.

- [ ] **Step 6: Second update (Review Focus 2).** Run `zsh -lic update` twice. Expected: both exit 0.

- [ ] **Step 7: Manual checks with the user.**
  - opencode starts, and a provider that uses an `{file:}` key answers one prompt.
  - In claude, `/model` → change → restart persists.
  - nvim `:checkhealth vim.lsp` reports no errors for a `.py` and a `.go` file.

- [ ] **Step 8: Cleanup, run by the user.** The user runs `bash wsl/bootstrap.sh --cleanup` interactively; don't answer
  the prompt for them. Then re-run `check-live.sh`. Expected: no FAIL lines.

- [ ] **Step 9: Commit.** `git commit -m "wsl: live post-switch checks"`

### Task 11: Fresh-instance acceptance (with the user)

- [ ] **Step 1: Bundle the branch, no push needed.**
  `git -C ~/dotfiles bundle create /mnt/c/Users/andre/dotfiles-wsl.bundle wsl-home-manager`.
- [ ] **Step 2: User, in PowerShell:** `wsl --install Ubuntu-24.04 --name hm-test`. Use the existing WSL user at first launch.
- [ ] **Step 3: In hm-test.**
  `git clone -b wsl-home-manager /mnt/c/Users/andre/dotfiles-wsl.bundle ~/dotfiles && git -C ~/dotfiles submodule update --init`.
- [ ] **Step 4: First bootstrap.** Run `bash ~/dotfiles/wsl/bootstrap.sh`.
  - The first run enables systemd and exits 2. Run `wsl --terminate hm-test` and re-run.
  - The re-run generates a key and exits 2 with `--add-recipient age1…`.
- [ ] **Step 5: Grant access from this instance (Ubuntu-22.04)** on a throwaway branch:
  - `git switch -c hm-test-acceptance`
  - `bash wsl/bootstrap.sh --add-recipient <hm-test pubkey>`, then commit.
  - `git bundle create /mnt/c/Users/andre/dotfiles-wsl.bundle hm-test-acceptance`.
  - In hm-test: `git fetch /mnt/c/Users/andre/dotfiles-wsl.bundle hm-test-acceptance && git checkout FETCH_HEAD -- wsl/.sops.yaml wsl/secrets/secrets.yaml`.
- [ ] **Step 6: Second bootstrap.** Re-run `bash ~/dotfiles/wsl/bootstrap.sh`. Expected: exit 0.
- [ ] **Step 7: Verify.** `bash ~/dotfiles/wsl/tests/check-live.sh`. Expected: no FAIL lines. `claude` and `opencode`
  resolve from the Nix profile.
- [ ] **Step 8: Tear down.**
  - The user runs `wsl --unregister hm-test` and deletes the bundle.
  - Here: `git switch wsl-home-manager && git branch -D hm-test-acceptance`. Confirm with the user first: this
    discards the test recipient, so the real branch never contains hm-test's key.
