# Machine-agnostic dotfiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the NixOS and WSL home-manager configuration work for any Linux username and home directory while keeping the repository at `~/dotfiles`.

**Architecture:** One shared `lib/user.nix` resolves `username`, `homeDirectory` and `dotfiles` from the environment (`SUDO_USER` for `sudo nixos-rebuild`, `USER`/`HOME` elsewhere, pure-eval fallback to `asergi`). Both flakes pass those values through `specialArgs`; modules use `config.home.homeDirectory`. opencode configs stay static and portable (`~`/wildcards). WSL installs Claude Code and opencode from `nixpkgs-unstable`. sops keys are per machine.

**Tech Stack:** Nix flakes, home-manager, sops-nix, Bash, Python 3, NixOS and WSL.

> **Commit policy:** this repository is not committed to unless the user explicitly asks. Every "Commit" step from the default plan template is replaced by a **Checkpoint** step (run the verification, leave the working tree dirty).

**Spec:** `docs/superpowers/specs/2026-10-22-agnostic-dotfiles-design.md`

---

## File structure

Created:

- `lib/user.nix` — environment-derived identity helper.
- `tests/test-user.sh` — identity helper tests.
- `nixos/tests/check-generation.sh` — NixOS generation assertions.
- `tests/check-no-hardcoded-home.sh` — repo-wide guard.

Modified:

- `nixos/flake.nix`, `nixos/configuration.nix`, `nixos/sops.nix`, `nixos/home.nix`
- `nixos/programs/{zsh.nix,claude-code/claude-code.nix,opencode/opencode.nix,mcpservers.nix,quickshell.nix,herdr.nix,uv/uv.nix}`
- `wsl/flake.nix`, `wsl/home.nix`, `wsl/packages.nix`, `wsl/bootstrap.sh`
- `wsl/modules/opencode.nix`, `wsl/modules/claude-code.nix`
- `wsl/tests/test-bootstrap.sh`, `wsl/tests/check-generation.sh`, `wsl/tests/check-live.sh`
- `my-opencode/v1/opencode.jsonc`, `my-opencode/v2/opencode.jsonc`
- `wsl/opencode/sync_opencode_jsonc.py`, `wsl/opencode/opencode.jsonc`, `wsl/opencode/BASE.sha256`
- `wsl/tests/test_sync_opencode_jsonc.py`
- `i3/config`, `hypr/hyprpaper.conf`, `ghostty/config`
- READMEs and `my-opencode`/`wsl/opencode` markdown

Deleted:

- `nixos/flake-backup.nix`, `nixos/flake-nixd.nix`, `nixos/flake-working.nix` (stale, unreferenced)

---

## Task 1: Identity helper

**Files:**
- Create: `lib/user.nix`
- Test: `tests/test-user.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-user.sh`:

```bash
#!/usr/bin/env bash
# Tests lib/user.nix identity resolution.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
USER_NIX="$ROOT/lib/user.nix"
failures=0
count=0

check() {
  local desc=$1 field=$2 want=$3
  shift 3
  count=$((count + 1))
  local got
  got=$(env "$@" nix eval --impure --raw --expr "(import $USER_NIX {}).$field" 2>/dev/null)
  [[ "$got" == "$want" ]] || { echo "FAIL $desc: got '$got' want '$want'"; failures=$((failures + 1)); }
}

check_pure() {
  local desc=$1 field=$2 want=$3
  count=$((count + 1))
  local got
  got=$(nix eval --pure-eval --raw --expr "(import $USER_NIX {}).$field" 2>/dev/null)
  [[ "$got" == "$want" ]] || { echo "FAIL $desc: got '$got' want '$want'"; failures=$((failures + 1)); }
}

check_pure "pure user" username asergi
check_pure "pure home" homeDirectory /home/asergi
check "user" username alice -u SUDO_USER USER=alice HOME=/home/alice
check "home" homeDirectory /home/alice -u SUDO_USER USER=alice HOME=/home/alice
check "custom home" homeDirectory /tmp/alice -u SUDO_USER USER=alice HOME=/tmp/alice
check "dotted user" username andrea.sergi -u SUDO_USER USER=andrea.sergi HOME=/home/andrea.sergi
check "sudo user wins" username alice SUDO_USER=alice USER=root HOME=/root
check "sudo home" homeDirectory /home/alice SUDO_USER=alice USER=root HOME=/root
check "root stays root" homeDirectory /root -u SUDO_USER USER=root HOME=/root
check "dotfiles" dotfiles /tmp/alice/dotfiles -u SUDO_USER USER=alice HOME=/tmp/alice
check "override user" username alice -u SUDO_USER DOTFILES_USER=alice USER=root HOME=/root
check "override user wins over sudo" username alice -u SUDO_USER DOTFILES_USER=alice SUDO_USER=root USER=root HOME=/root
check "override home" homeDirectory /data/alice -u SUDO_USER DOTFILES_HOME=/data/alice USER=alice HOME=/home/alice
check "override home under sudo" homeDirectory /data/alice -u SUDO_USER DOTFILES_HOME=/data/alice SUDO_USER=alice USER=root HOME=/root
check "override dotfiles" dotfiles /data/alice/dotfiles -u SUDO_USER DOTFILES_HOME=/data/alice USER=alice HOME=/home/alice

if ((failures)); then
  echo "$failures of $count user tests failed"
  exit 1
fi
echo "OK ($count user tests)"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-user.sh`
Expected: FAIL because `lib/user.nix` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/user.nix`:

```nix
# Identity for this machine, read from the environment.
#
# Switches must pass --impure. Explicit DOTFILES_USER/DOTFILES_HOME overrides
# win over the ambient environment, so sudo (HOME=/root) and the installer keep
# a non-standard account. Pure evaluation (nix flake check) cannot read the
# environment and falls back to the historical asergi layout so checks stay
# deterministic. WSL runs as the existing OS user and inherits it verbatim.
let
  getenv = name: builtins.getEnv name;

  overrideUser = getenv "DOTFILES_USER";
  overrideHome = getenv "DOTFILES_HOME";
  sudoUser = getenv "SUDO_USER";
  envUser = getenv "USER";
  envHome = getenv "HOME";

  username =
    if overrideUser != "" then
      overrideUser
    else if sudoUser != "" && sudoUser != "root" then
      sudoUser
    else if envUser != "" then
      envUser
    else
      "asergi";

  homeDirectory =
    if overrideHome != "" then
      overrideHome
    else if username == "root" then
      "/root"
    else if envHome == "" || envHome == "/root" then
      "/home/${username}"
    else
      envHome;
in
{
  inherit username homeDirectory;
  dotfiles = "${homeDirectory}/dotfiles";
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-user.sh`
Expected: `OK (19 user tests)`

- [ ] **Step 5: Checkpoint**

Run: `bash tests/test-user.sh && env -i nix eval --impure --raw --file lib/user.nix --apply 'u: u.homeDirectory'`
Expected: `OK (19 user tests)`, then `/home/asergi`.

---

## Task 2: Wire identity into the NixOS flake

**Files:**
- Modify: `nixos/flake.nix`
- Modify: `nixos/configuration.nix:126-140,217-236`
- Modify: `nixos/sops.nix`
- Test: `nixos/tests/check-generation.sh` (created in Task 7; evaluate manually here)

- [ ] **Step 1: Add the helper to `nixos/flake.nix`**

In the `let` block (after `pkgs-master = import ...;`, around line 128) replace:

```nix
      username = "asergi";
```

with:

```nix
      user = import ../lib/user.nix;
      inherit (user) username homeDirectory dotfiles;
```

- [ ] **Step 2: Use the derived user in the NixOS system**

Replace, in `nixos/flake.nix`:

```nix
                home-manager.users.asergi = ./home.nix;
```

with:

```nix
                home-manager.users.${username} = ./home.nix;
```

and:

```nix
                home-manager.extraSpecialArgs = {
                  inherit my-dotfiles;
                  # inherit neovimrc;
                  inherit pkgs-unstable;
                  inherit pkgs-master;
                };
```

with:

```nix
                home-manager.extraSpecialArgs = {
                  inherit my-dotfiles;
                  # inherit neovimrc;
                  inherit pkgs-unstable;
                  inherit pkgs-master;
                  inherit (user) username homeDirectory dotfiles;
                };
```

and:

```nix
            specialArgs = {
              username = "asergi";
              inherit pkgs-unstable;
              inherit inputs;
            };
```

with:

```nix
            specialArgs = {
              inherit (user) username homeDirectory dotfiles;
              inherit pkgs-unstable;
              inherit inputs;
            };
```

- [ ] **Step 3: Rename the standalone home output and derive it**

Replace, in `nixos/flake.nix`:

```nix
        homeConfigurations = {
          "asergi@nixos-os" = inputs.home-manager.lib.homeManagerConfiguration {
            pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            # pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
            # imports = [ ./home.nix ];
            modules = [
              ./home.nix
              {
                home.stateVersion = "25.11";
                # home.stateVersion = "25.05";
                home.username = "asergi";
                home.homeDirectory = "/home/asergi";
                nix.package = pkgs.nix;
                # nix.package = pkgs-unstable.nix;
              }
            ];
            extraSpecialArgs = {
              inherit my-dotfiles;
              # inherit neovimrc;
              # inherit pkgs;
              # inherit pkgs-unstable;
            };

          };
        };
```

with:

```nix
        homeConfigurations = {
          default = inputs.home-manager.lib.homeManagerConfiguration {
            pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            modules = [
              ./home.nix
              {
                home.stateVersion = "25.11";
                home.username = username;
                home.homeDirectory = homeDirectory;
                nix.package = pkgs.nix;
              }
            ];
            extraSpecialArgs = {
              inherit my-dotfiles;
              inherit (user) username homeDirectory dotfiles;
            };
          };
        };
```

- [ ] **Step 4: Make `configuration.nix` accept and use the identity**

Change the argument set at the top of `nixos/configuration.nix`:

```nix
{
  config,
  lib,
  inputs,
  pkgs,
  pkgs-unstable,
  nixd,
  ...
}:
```

to:

```nix
{
  config,
  lib,
  inputs,
  pkgs,
  pkgs-unstable,
  nixd,
  username,
  ...
}:
```

Replace `user = "asergi";` (greetd, around line 133) with `user = username;`.

Replace `users.users.asergi = {` (around line 221) with `users.users.${username} = {`.

- [ ] **Step 5: Make `sops.nix` accept and use the identity**

Change the top of `nixos/sops.nix` from:

```nix
{
  sops = {
    age.keyFile = "/home/asergi/.config/sops/age/keys.txt";
```

to:

```nix
{
  username,
  homeDirectory,
  ...
}:
{
  sops = {
    age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";
```

Replace every `owner = "asergi";` in `nixos/sops.nix` with `owner = username;`.

- [ ] **Step 6: Verify the flake evaluates for the current user**

Run: `nix eval --impure --raw ~/dotfiles/nixos#homeConfigurations.default.config.home.homeDirectory`
Expected: `/home/andrea.sergi`

Run: `nix eval --impure --raw ~/dotfiles/nixos#nixosConfigurations.nixos-os.config.sops.age.keyFile`
Expected: `/home/andrea.sergi/.config/sops/age/keys.txt`

- [ ] **Step 7: Checkpoint**

Run: `nix eval --raw ~/dotfiles/nixos#homeConfigurations.default.config.home.homeDirectory`
Expected: `/home/asergi` (flake evaluation is pure by default; fallback still deterministic).

---

## Task 3: Wire identity into WSL and guard the bootstrap

**Files:**
- Modify: `wsl/home.nix`
- Modify: `wsl/bootstrap.sh`
- Modify: `wsl/tests/test-bootstrap.sh`

- [ ] **Step 1: Replace the local `getEnv` block in `wsl/home.nix`**

Replace:

```nix
let
  # Username-agnostic: take the account from the environment. Pure evaluation
  # (nix flake check) cannot read it and falls back to the original asergi
  # layout, so switches must pass --impure (bootstrap.sh and `update` do).
  envHome = builtins.getEnv "HOME";
  envUser = builtins.getEnv "USER";
  homeDirectory = if envHome == "" then "/home/asergi" else envHome;
  username = if envUser == "" then builtins.baseNameOf homeDirectory else envUser;
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  link = config.lib.file.mkOutOfStoreSymlink;
in
```

with:

```nix
let
  user = import ../lib/user.nix;
  dotfiles = user.dotfiles;
  link = config.lib.file.mkOutOfStoreSymlink;
in
```

Replace:

```nix
  home.username = username;
  home.homeDirectory = homeDirectory;
```

with:

```nix
  home.username = user.username;
  home.homeDirectory = user.homeDirectory;
```

- [ ] **Step 2: Add early environment guards to `wsl/bootstrap.sh`**

After `check_location()` add:

```bash
# WSL has an existing OS user that cannot be renamed: inherit it and never
# touch the account.
check_not_root() {
  if ((EUID == 0)); then
    echo "bootstrap: run as the existing WSL user, not root or sudo" >&2
    exit 1
  fi
  if [[ -z "${USER:-}" || -z "${HOME:-}" ]]; then
    echo "bootstrap: USER and HOME must be set; run from the WSL login shell" >&2
    exit 1
  fi
}

# Fail before switching if an impure evaluation does not match this account.
check_identity() {
  local want_user want_home got_user got_home
  want_user=$(id -un)
  want_home=${HOME%/}
  got_user=$(nix eval --raw --impure "$FLAKE#homeConfigurations.default.config.home.username" 2>/dev/null) || {
    action_needed "cannot evaluate the flake identity. Re-run with nix available."
  }
  got_home=$(nix eval --raw --impure "$FLAKE#homeConfigurations.default.config.home.homeDirectory" 2>/dev/null) || {
    action_needed "cannot evaluate the flake identity. Re-run with nix available."
  }
  if [[ "$got_user" != "$want_user" || "${got_home%/}" != "$want_home" ]]; then
    action_needed "flake identity ($got_user, $got_home) does not match this account ($want_user, $want_home). Re-run with --impure from the WSL user."
  fi
}
```

- [ ] **Step 3: Call the guards from `main`**

In `main`, after `check_location` and the `--add-recipient` early return, add `check_not_root` before `ensure_systemd`, and `check_identity` after `ensure_nix`:

```bash
  check_location
  if [[ -n "$recipient" ]]; then
    add_recipient "$recipient"
    return 0
  fi

  check_not_root
  ensure_systemd
  ensure_shell_and_locale
  ensure_nix
  check_identity
  ensure_submodules
  ensure_age_key
  check_secrets
  switch
```

- [ ] **Step 4: Update the bootstrap tests**

In `wsl/tests/test-bootstrap.sh`, add after the `--help` checks (the guards are static text; `EUID` cannot be faked portably):

```bash
body=$(cat "$BOOT")
expect "not-root guard present" has "$body" "EUID == 0"
expect "identity guard present" has "$body" "homeConfigurations.default.config.home.username"
expect "identity guard present (home)" has "$body" "homeConfigurations.default.config.home.homeDirectory"
```

- [ ] **Step 5: Verify**

Run: `bash ~/dotfiles/wsl/bootstrap.sh --dry-run`
Expected: reaches the secrets step (exit 2) on a machine without the WSL key, or completes the dry run where the key is present. No `/home/asergi` in the switch line.

- [ ] **Step 6: Checkpoint**

Run: `bash ~/dotfiles/wsl/tests/test-bootstrap.sh`
Expected: all tests pass.

---

## Task 4: Portable opencode and secret paths

**Files:**
- Modify: `my-opencode/v1/opencode.jsonc`, `my-opencode/v2/opencode.jsonc`
- Modify: `wsl/opencode/sync_opencode_jsonc.py`
- Modify: `wsl/tests/test_sync_opencode_jsonc.py`
- Regenerate: `wsl/opencode/opencode.jsonc`
- Modify: `wsl/opencode/BASE.sha256`

Use opencode's native substitution instead of a renderer: `~` works in
`{file:...}` and in `read`/`edit`/`external_directory` resources; `shell`
resources do not expand, so they use `*` wildcards.

- [ ] **Step 1: Write the failing test expectations**

In `wsl/tests/test_sync_opencode_jsonc.py`, change the constants:

```python
MOUNT = "/run/user/*/secrets.d"
SOPS = "~/.config/sops-nix/secrets"
SHELL_SOPS = "*/.config/sops-nix/secrets"
TILDE = "~/.config/sops-nix/secrets"
```

Replace the `test_file_refs_rewritten`, `test_read_rule_mirrors_follow_source`,
and `test_shell_rule_gets_tilde_variant` methods with:

```python
    def test_file_refs_rewritten(self):
        out = transform(doc(rule("read", "**/*.key")))
        key = json.loads(out)["providers"]["openrouter"]["settings"]["apiKey"]
        self.assertEqual(key, "{file:~/.config/sops-nix/secrets/openrouter}")
        self.assertNotIn("{file:/run/secrets", out)

    def test_read_rule_mirrors_follow_source(self):
        out = transform(doc(rule("read", "/run/secrets/**")))
        self.assertEqual(
            resources(out),
            ["/run/secrets/**", f"{MOUNT}/**", f"{SOPS}/**"],
        )
        self.assertTrue(all(r["action"] == "read" and r["effect"] == "deny"
                            for r in json.loads(out)["permissions"]))

    def test_shell_rule_gets_portable_variants(self):
        out = transform(doc(rule("shell", "*cat /run/secrets*")))
        self.assertEqual(
            resources(out),
            [
                "*cat /run/secrets*",
                f"*cat {MOUNT}*",
                f"*cat {SHELL_SOPS}*",
                f"*cat {TILDE}*",
            ],
        )
```

Update the duplicate/effect/last-rule tests to use `MOUNT`, `SOPS`, `SHELL_SOPS`
and `TILDE` instead of literal `/home/asergi` paths. For example:

```python
    def test_duplicate_mirrors_skipped(self):
        out = transform(doc(rule("read", "/run/secrets/**"), rule("read", "/run/secrets.d/**")))
        res = resources(out)
        self.assertEqual(res.count(f"{MOUNT}/**"), 1)
        self.assertEqual(res.count(f"{SOPS}/**"), 1)
        self.assertEqual(
            res,
            ["/run/secrets/**", f"{MOUNT}/**", f"{SOPS}/**", "/run/secrets.d/**"],
        )

    def test_effect_and_action_preserved(self):
        out = transform(doc(rule("edit", "/run/secrets", effect="ask")))
        perms = json.loads(out)["permissions"]
        self.assertEqual(len(perms), 3)
        self.assertTrue(all(p["action"] == "edit" and p["effect"] == "ask" for p in perms))

    def test_last_rule_in_list(self):
        out = transform(doc(rule("read", "**/*.p12"), rule("shell", "/run/secrets/**")))
        self.assertEqual(
            resources(out),
            ["**/*.p12", "/run/secrets/**", f"{MOUNT}/**", f"{SHELL_SOPS}/**", f"{TILDE}/**"],
        )
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/dotfiles && python3 -m unittest discover -s wsl/tests -p 'test_sync_opencode_jsonc.py' -v`
Expected: FAIL because the script still emits `/home/asergi/...`.

- [ ] **Step 3: Make the sync script emit portable paths**

In `wsl/opencode/sync_opencode_jsonc.py`, replace the constants:

```python
MOUNT_DIR = "/run/user/*/secrets.d"
SOPS_DIR = "~/.config/sops-nix/secrets"
SHELL_SOPS_DIR = "*/.config/sops-nix/secrets"
TILDE_SOPS_DIR = "~/.config/sops-nix/secrets"
```

Replace `mirror_locations`:

```python
def mirror_locations(action):
    if action == "shell":
        return [MOUNT_DIR, SHELL_SOPS_DIR, TILDE_SOPS_DIR]
    return [MOUNT_DIR, SOPS_DIR]
```

`rewrite_file_refs` keeps its shape:

```python
def rewrite_file_refs(text):
    return text.replace("{file:/run/secrets/", "{file:" + SOPS_DIR + "/")
```

- [ ] **Step 4: Make the base configs home-agnostic**

Run:

```bash
cd ~/dotfiles
perl -pi -e 's|/home/asergi/|{env:HOME}/|g' my-opencode/v1/opencode.jsonc my-opencode/v2/opencode.jsonc
```

Only the disabled filesystem MCP arguments change. Verify with:
`grep -n '/home/asergi' my-opencode/v1/opencode.jsonc my-opencode/v2/opencode.jsonc`
Expected: no output.

- [ ] **Step 5: Regenerate the WSL copy**

Run:

```bash
cd ~/dotfiles
python3 wsl/opencode/sync_opencode_jsonc.py my-opencode/v2/opencode.jsonc wsl/opencode/opencode.jsonc
```

- [ ] **Step 6: Refresh the overlay checksum for the changed v2 file**

Run:

```bash
cd ~/dotfiles/my-opencode/v2 && sha256sum $(awk '{print $2}' ../../wsl/opencode/BASE.sha256) > ../../wsl/opencode/BASE.sha256
```

- [ ] **Step 7: Run the tests and overlay check**

Run: `cd ~/dotfiles && python3 -m unittest discover -s wsl/tests -p 'test_sync_opencode_jsonc.py' -v`
Expected: `OK`

Run: `cd ~/dotfiles && bash wsl/tests/check-overlay.sh my-opencode/v2 wsl/opencode wsl/tests`
Expected: `OK (overlay)`

- [ ] **Step 8: Checkpoint**

Run: `grep -rn '/home/asergi' wsl/opencode my-opencode/v1/opencode.jsonc my-opencode/v2/opencode.jsonc`
Expected: no output.

---

## Task 5: WSL apps from nixpkgs-unstable

**Files:**
- Modify: `wsl/packages.nix`
- Modify: `wsl/home.nix`
- Modify: `wsl/modules/opencode.nix`, `wsl/modules/claude-code.nix`
- Modify: `wsl/bootstrap.sh`
- Modify: `wsl/tests/check-generation.sh`, `wsl/tests/check-live.sh`

- [ ] **Step 1: Write the failing generation test**

In `wsl/tests/check-generation.sh`, replace:

```bash
lacks_bin claude opencode
```

with:

```bash
has_bin claude opencode
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ~/dotfiles && nix flake check --impure wsl`
Expected: FAIL with `has_bin claude` / `has_bin opencode`.

- [ ] **Step 3: Add the unstable packages**

In `wsl/packages.nix`, inside the `(with pkgs-unstable; [ ... ])` list, add:

```nix
      claude-code
      opencode
```

Keep the existing unstable packages. `pkgs-unstable` already has
`allowUnfree = true`.

- [ ] **Step 4: Stop pointing PATH at the native install**

In `wsl/home.nix`, replace:

```nix
  # Native installers live here: claude (~/.local/bin), opencode (~/.opencode/bin).
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.opencode/bin"
  ];
```

with:

```nix
  # Claude Code and opencode come from pkgs-unstable; ~/.local/bin is kept for
  # other native tools.
  home.sessionPath = [
    "$HOME/.local/bin"
  ];
```

- [ ] **Step 5: Update the config modules' comments**

In `wsl/modules/opencode.nix`, replace the header:

```nix
# opencode config from my-opencode/v2, with WSL copies from wsl/opencode.
# opencode itself is not installed here: it comes from its native installer
# in ~/.opencode/bin (on PATH via home.sessionPath).
```

with:

```nix
# opencode config from my-opencode/v2, with WSL copies from wsl/opencode.
# opencode itself comes from pkgs-unstable via wsl/packages.nix.
```

In `wsl/modules/claude-code.nix`, replace the header:

```nix
# Claude Code keeps its native, auto-updating install (~/.local/bin/claude)
# and owns ~/.claude/settings.json. Only these skills are linked, from v2 with
# the WSL copies applied.
```

with:

```nix
# Claude Code comes from pkgs-unstable via wsl/packages.nix and owns
# ~/.claude/settings.json. Only these skills are linked, from v2 with the WSL
# copies applied.
```

- [ ] **Step 6: Remove the native binaries during cleanup**

In `wsl/bootstrap.sh`'s `cleanup()` function, after the herdr item, add:

```bash
  [[ -e "$HOME/.local/bin/claude" ]] && item "native claude (~/.local/bin/claude)" "rm -f $HOME/.local/bin/claude"
  [[ -e "$HOME/.opencode/bin/opencode" ]] && item "native opencode (~/.opencode/bin/opencode)" "rm -f $HOME/.opencode/bin/opencode"
```

These remove the launchers, the Claude versions payload, and the native
opencode install root. Auth, settings, and sessions under `~/.claude` and
`~/.local/share/opencode` are left alone.

- [ ] **Step 7: Update the live check**

In `wsl/tests/check-live.sh`, add `claude opencode` to the profile loop and
delete the native-install loop. Replace:

```bash
for b in nvim tmux herdr rg go zig node cargo uv starship atuin chromium; do
  first=$(lz "whence -p $b")
  check "$b from the nix profile (${first:-not found})" starts_with "$first" "$PROFILE"
done
for pair in "claude:$HOME/.local/bin/claude" "opencode:$HOME/.opencode/bin/opencode"; do
  b=${pair%%:*} want=${pair#*:}
  first=$(lz "whence -p $b")
  if [[ -z "$first" ]]; then skip "$b not installed (native installer, outside the flake)"; else
    check "$b is the native install ($first)" [ "$first" = "$want" ]
  fi
done
```

with:

```bash
for b in nvim tmux herdr rg go zig node cargo uv starship atuin chromium claude opencode; do
  first=$(lz "whence -p $b")
  check "$b from the nix profile (${first:-not found})" starts_with "$first" "$PROFILE"
done
```

- [ ] **Step 8: Run the flake check**

Run: `cd ~/dotfiles && nix flake check --impure wsl`
Expected: `all checks passed!`

- [ ] **Step 9: Checkpoint**

Run:

```bash
cd ~/dotfiles
out=$(nix build --impure --no-link --print-out-paths 'wsl#homeConfigurations.default.activationPackage')
test -x "$out/home-path/bin/claude" && test -x "$out/home-path/bin/opencode" && echo "apps OK"
```

Expected: `apps OK`. If `opencode` fails at runtime with the bun 1.4.2
miscompile, revisit the package override in a follow-up; do not silently switch
back to the native installer.

---

## Task 6: Remaining NixOS module paths

**Files:**
- Modify: `nixos/programs/zsh.nix`
- Modify: `nixos/programs/claude-code/claude-code.nix`
- Modify: `nixos/programs/mcpservers.nix`
- Modify: `nixos/programs/opencode/opencode.nix`
- Modify: `nixos/programs/quickshell.nix`
- Modify: `nixos/programs/herdr.nix`
- Modify: `nixos/programs/uv/uv.nix`
- Modify: `nixos/home.nix`

- [ ] **Step 1: Make the zsh aliases dynamic**

In `nixos/programs/zsh.nix`, replace:

```nix
      update = "sudo nixos-rebuild switch --flake /home/asergi/dotfiles/nixos#nixos-os";
      # ftm = "~/tmux-sessionizer.sh";
      ftm = "/home/asergi/dotfiles/scripts/tmux-sessionizer.sh";
```

with:

```nix
      update = "sudo env SUDO_USER=\"$USER\" DOTFILES_HOME=\"$HOME\" nixos-rebuild switch --flake $HOME/dotfiles/nixos#nixos-os --impure";
      ftm = "${config.home.homeDirectory}/dotfiles/scripts/tmux-sessionizer.sh";
```

- [ ] **Step 2: Substitute the remaining module paths**

Run:

```bash
cd ~/dotfiles
perl -pi -e 's|/home/asergi|\${config.home.homeDirectory}|g' \
  nixos/programs/claude-code/claude-code.nix \
  nixos/programs/mcpservers.nix
perl -pi -e 's|/home/asergi/dotfiles|\${config.home.homeDirectory}/dotfiles|g' \
  nixos/programs/opencode/opencode.nix \
  nixos/programs/quickshell.nix \
  nixos/programs/herdr.nix \
  nixos/programs/uv/uv.nix
```

- [ ] **Step 3: Switch NixOS opencode links to v2**

Run:

```bash
cd ~/dotfiles
perl -pi -e 's|my-opencode/v1|my-opencode/v2|g' nixos/programs/opencode/opencode.nix
```

Then add the `RIPWIRE.md` link required by v2's `instructions` list. After the
`.config/opencode/CLAUDE.md` entry in `home.file`, add:

```nix
    ".config/opencode/RIPWIRE.md" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/my-opencode/v2/RIPWIRE.md";
      force = true;
    };
```

Verify: `grep -n 'my-opencode/v1\|RIPWIRE' nixos/programs/opencode/opencode.nix`
Expected: no `v1`; a `RIPWIRE.md` entry present.

- [ ] **Step 4: Make `nixos/home.nix` dynamic**

Change the argument set:

```nix
{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  pkgs-master,
  # neovimrc,
  my-dotfiles,
  ...
}:
```

to:

```nix
{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  pkgs-master,
  # neovimrc,
  my-dotfiles,
  username,
  homeDirectory,
  dotfiles,
  ...
}:
```

Then run:

```bash
cd ~/dotfiles
perl -pi -e 's|/home/asergi/dotfiles|\${dotfiles}|g' nixos/home.nix
perl -ni -e 'print unless m{asergi}' nixos/home.nix
```

Verify with: `grep -n 'asergi' nixos/home.nix`
Expected: no output.

- [ ] **Step 5: Verify the NixOS config still evaluates**

Run: `nix eval --impure ~/dotfiles/nixos#nixosConfigurations.nixos-os.config.system.build.toplevel.drvPath`
Expected: a `/nix/store/...drv` path.

- [ ] **Step 5: Checkpoint**

Run: `grep -rn '/home/asergi' nixos --include='*.nix' | grep -v flake-backup | grep -v flake-nixd | grep -v flake-working`
Expected: no output.

---

## Task 7: NixOS generation check

**Files:**
- Create: `nixos/tests/check-generation.sh`
- Modify: `nixos/flake.nix`

- [ ] **Step 1: Write the check script**

Create `nixos/tests/check-generation.sh`:

```bash
#!/usr/bin/env bash
# Assertions on a built NixOS home-manager generation.
# Usage: check-generation.sh GEN HOMEDIR
set -uo pipefail

GEN=${1:?usage: check-generation.sh GEN HOMEDIR}
HOMEDIR=${2:?usage: check-generation.sh GEN HOMEDIR}
failures=0
count=0

has() {
  count=$((count + 1))
  grep -qF -- "$2" "$GEN/$1" || { echo "FAIL: $1 lacks $2"; failures=$((failures + 1)); }
}

lacks() {
  count=$((count + 1))
  grep -qF -- "$2" "$GEN/$1" && { echo "FAIL: $1 has $2"; failures=$((failures + 1)); }
}

link_target() {
  local p=$1 hops=0
  while [[ -L "$p" && $hops -lt 10 ]]; do
    p=$(readlink "$p")
    [[ "$p" == /nix/store/* ]] || break
    hops=$((hops + 1))
  done
  printf '%s\n' "$p"
}

Z=home-files/.zshrc
has "$Z" 'sudo env SUDO_USER="$USER" DOTFILES_HOME="$HOME" nixos-rebuild switch --flake $HOME/dotfiles/nixos#nixos-os --impure'
has "$Z" "$HOMEDIR/dotfiles/scripts/tmux-sessionizer.sh"
lacks "$Z" /home/asergi

J=home-files/.config/opencode/opencode.jsonc
has "$J" "/run/secrets"
has "$J" "{env:HOME}"
lacks "$J" /home/asergi
count=$((count + 1))
[[ "$(link_target "$GEN/$J")" == "$HOMEDIR/dotfiles/my-opencode/v2/opencode.jsonc" ]] \
  || { echo "FAIL: opencode.jsonc does not link to v2"; failures=$((failures + 1)); }

R=home-files/.config/opencode/RIPWIRE.md
count=$((count + 1))
[[ "$(link_target "$GEN/$R")" == "$HOMEDIR/dotfiles/my-opencode/v2/RIPWIRE.md" ]] \
  || { echo "FAIL: RIPWIRE.md does not link to v2"; failures=$((failures + 1)); }

U=home-files/.config/systemd/user/sops-nix.service
has "$U" "$HOMEDIR/.config/sops/age/keys.txt"
lacks "$U" /home/asergi

# The pure-eval fallback legitimately targets /home/asergi.
if [[ "$HOMEDIR" != /home/asergi ]] && grep -rqF /home/asergi "$GEN"; then
  echo "FAIL: generation contains /home/asergi"
  failures=$((failures + 1))
fi

if ((failures)); then
  echo "$failures of $count nixos generation checks failed"
  exit 1
fi
echo "OK ($count nixos generation checks)"
```

- [ ] **Step 2: Add the check to the flake**

In `nixos/flake.nix`, change:

```nix
      perSystem = { config, ... }: { };
```

to:

```nix
      perSystem =
        { pkgs, self', ... }:
        {
          checks.generation = pkgs.runCommand "nixos-generation-check" { } ''
            bash ${./tests/check-generation.sh} ${self'.homeConfigurations.default.activationPackage} ${homeDirectory}
            touch $out
          '';
        };
```

- [ ] **Step 3: Run the check impurely for the current user**

Run: `cd ~/dotfiles && nix flake check --impure nixos`
Expected: `all checks passed!`

- [ ] **Step 4: Run the check purely**

Run: `cd ~/dotfiles && nix flake check nixos`
Expected: `all checks passed!` with the `/home/asergi` fallback.

- [ ] **Step 5: Checkpoint**

Run: `cd ~/dotfiles && nix flake check nixos && nix flake check --impure nixos`
Expected: both pass.

---

## Task 8: Static configs, markdown, cleanup

**Files:**
- Modify: `i3/config`
- Modify: `hypr/hyprpaper.conf`
- Modify: `ghostty/config`
- Modify: `my-opencode/v1/CLAUDE.md`, `my-opencode/v2/CLAUDE.md`, `wsl/opencode/CLAUDE.md`
- Modify: `my-opencode/*/skills/agent-browser/SKILL.md`, `wsl/opencode/skills/agent-browser/SKILL.md`
- Modify: `wsl/opencode/skills/webapp-testing/*`, `wsl/opencode/skills/web-artifacts-builder/SKILL.md`
- Delete: `nixos/flake-backup.nix`, `nixos/flake-nixd.nix`, `nixos/flake-working.nix`

- [ ] **Step 1: Static configs**

Run:

```bash
cd ~/dotfiles
perl -pi -e 's|/home/asergi/Images|\$HOME/Images|g; s|/home/asergi/\.config|\$HOME/.config|g' i3/config
perl -ni -e 'print unless m{/home/asergi}' hypr/hyprpaper.conf
perl -pi -e 's|/home/andreasergi|\$HOME|g' ghostty/config
```

- [ ] **Step 2: Markdown paths**

Run:

```bash
cd ~/dotfiles
perl -pi -e 's|/home/asergi/dotfiles|~/dotfiles|g' \
  my-opencode/v1/CLAUDE.md my-opencode/v2/CLAUDE.md wsl/opencode/CLAUDE.md \
  my-opencode/v1/skills/agent-browser/SKILL.md my-opencode/v2/skills/agent-browser/SKILL.md \
  wsl/opencode/skills/agent-browser/SKILL.md
perl -pi -e 's|/home/asergi/\.nix-profile|~/.nix-profile|g' \
  wsl/opencode/skills/webapp-testing/SKILL.md \
  wsl/opencode/skills/web-artifacts-builder/SKILL.md \
  wsl/opencode/skills/webapp-testing/examples/console_logging.py \
  wsl/opencode/skills/webapp-testing/examples/element_discovery.py \
  wsl/opencode/skills/webapp-testing/examples/static_html_automation.py
```

Refresh the overlay checksums because `my-opencode/v2/CLAUDE.md` and
`my-opencode/v2/skills/agent-browser/SKILL.md` changed:

```bash
cd ~/dotfiles/my-opencode/v2 && sha256sum $(awk '{print $2}' ../../wsl/opencode/BASE.sha256) > ../../wsl/opencode/BASE.sha256
```

- [ ] **Step 3: Remove the stale backup flakes**

Run:

```bash
cd ~/dotfiles
rm nixos/flake-backup.nix nixos/flake-nixd.nix nixos/flake-working.nix
```

- [ ] **Step 4: Verify**

Run: `grep -rn '/home/asergi' my-opencode wsl/opencode i3 hypr ghostty`
Expected: no output.

- [ ] **Step 5: Checkpoint**

Run: `cd ~/dotfiles && nix flake check --impure ./wsl && nix flake check --impure ./nixos`
Expected: both pass.

---

## Task 9: Repo guard and documentation

**Files:**
- Create: `tests/check-no-hardcoded-home.sh`
- Modify: `README.md`, `wsl/README.md`, `wsl/wsl-setup-from-scratch.md`, `wsl/opencode/CLAUDE.md`
- Modify: `wsl/docs/superpowers/plans/2026-10-20-wsl-home-manager.md`
- Modify: `wsl/tests/check-live.sh`

- [ ] **Step 1: Write the guard**

Create `tests/check-no-hardcoded-home.sh`:

```bash
#!/usr/bin/env bash
# Fail if a functional file still hardcodes the old home directory.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
cd "$ROOT"

hits=$(
  grep -rn --exclude-dir=.git --exclude-dir=docs --exclude-dir=tests \
    --exclude-dir=fixtures --exclude='*.md' --exclude='*.lock' \
    --exclude='lib/user.nix' --exclude='check-no-hardcoded-home.sh' \
    -e '/home/asergi' . || true
)
if [[ -n "$hits" ]]; then
  echo "$hits"
  echo "hardcoded home found; use lib/user.nix or a portable path"
  exit 1
fi
echo "OK (no hardcoded home)"
```

Make it executable: `chmod +x tests/check-no-hardcoded-home.sh`.

- [ ] **Step 2: Run it to verify it passes after the previous tasks**

Run: `bash tests/check-no-hardcoded-home.sh`
Expected: `OK (no hardcoded home)` (or a list of remaining files to fix).

- [ ] **Step 3: Update the documentation**

In `wsl/README.md`:
- prerequisites: "any username" and "repo at `~/dotfiles`" (already updated)
- daily use: `#default` and `--impure` (already updated)
- key registration stays: `bash ~/dotfiles/wsl/bootstrap.sh --add-recipient age1...`
- add: opencode config is static and portable (`~`/wildcards); the sync script is
  a maintainer tool, not part of activation
- prerequisites: Claude Code and opencode come from `nixpkgs-unstable` via the
  flake, not native installers
- replace "Claude Code only gets four skills linked... Its settings stay its
  own." with the same, prefixed by "Claude Code comes from nixpkgs-unstable."

In `README.md` (root):
- clone path stays `~/dotfiles`
- replace `.#nixos-os` rebuild examples with `sudo env SUDO_USER="$USER" DOTFILES_HOME="$HOME" nixos-rebuild switch --flake ~/dotfiles/nixos#nixos-os --impure`
- document the install command as `sudo env DOTFILES_USER=<target-user> DOTFILES_HOME=<target-home> nixos-install --flake ~/dotfiles/nixos#nixos-os --root /mnt --impure`, noting the target is the installed account, not the live ISO user
- add a short "Identity" note: the flake reads `SUDO_USER`/`USER`/`HOME`, with explicit `DOTFILES_USER`/`DOTFILES_HOME` overrides taking highest priority (they survive `sudo` where `HOME=/root`)
- add NixOS key registration:
  `nix shell ~/dotfiles/wsl#age -c age-keygen -o ~/.config/sops/age/keys.txt`,
  append the public key to `.sops.yaml` at the repo root, then from the repo root
  `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt nix run ~/dotfiles/wsl#sops -- --config .sops.yaml updatekeys -y nixos/secrets/secrets.yaml`

In `wsl/wsl-setup-from-scratch.md`:
- replace "create the user `asergi`" with "use the existing WSL user"
- replace "`claude` and `opencode` print **SKIP**: they come from their native
  installers, outside the flake." with "`claude` and `opencode` come from
  `nixpkgs-unstable` and must resolve from the Nix profile."

In `wsl/opencode/CLAUDE.md` and `my-opencode/*/CLAUDE.md`:
- paths already changed to `~/dotfiles` by Task 8

In `wsl/docs/superpowers/plans/2026-10-20-wsl-home-manager.md`:
- update the hard requirements `asergi`, `#asergi` and `/home/asergi` to the new dynamic behavior

- [ ] **Step 4: Update the live check**

In `wsl/tests/check-live.sh`, replace the remaining `/home/asergi` expectations with `$HOME` (Task 3 of the WSL work already did most; verify with `grep -n asergi wsl/tests/check-live.sh`).

- [ ] **Step 5: Checkpoint**

Run: `bash tests/check-no-hardcoded-home.sh && bash tests/test-user.sh && bash wsl/tests/test-bootstrap.sh`
Expected: all pass.

---

## Task 10: Final verification

- [ ] **Step 1: Pure flake checks**

Run: `cd ~/dotfiles && nix flake check ./wsl && nix flake check ./nixos`
Expected: `all checks passed!` for both.

- [ ] **Step 2: Impure flake checks with the current user**

Run: `cd ~/dotfiles && nix flake check --impure ./wsl && nix flake check --impure ./nixos`
Expected: `all checks passed!` for both.

- [ ] **Step 3: Impure flake checks with a synthetic user**

Run:

```bash
cd ~/dotfiles
export XDG_CACHE_HOME=/tmp/nix-cache-alice
USER=alice HOME=/home/alice nix eval --impure --raw ./nixos#homeConfigurations.default.config.home.username
USER=alice HOME=/home/alice nix eval --impure --raw ./nixos#homeConfigurations.default.config.home.homeDirectory
USER=alice HOME=/tmp/alice nix eval --impure --raw ./wsl#homeConfigurations.default.config.home.homeDirectory
```

Expected: `alice`, `/home/alice`, `/tmp/alice`.

- [ ] **Step 4: Portable config sanity**

Run:

```bash
cd ~/dotfiles
grep -qF '{file:~/.config/sops-nix/secrets/openrouter}' wsl/opencode/opencode.jsonc &&
  ! grep -qF /home/asergi wsl/opencode/opencode.jsonc &&
  grep -qF '/run/user/*/secrets.d' wsl/opencode/opencode.jsonc &&
  echo "opencode portable config OK"
```

Expected: `opencode portable config OK`.

- [ ] **Step 5: WSL live check (only on a provisioned WSL machine)**

Run: `bash ~/dotfiles/wsl/tests/check-live.sh`
Expected: `OK (live)`.

- [ ] **Step 6: Checkpoint**

Run: `git -C ~/dotfiles status --short`
Expected: only the intended files changed; no commits made.
