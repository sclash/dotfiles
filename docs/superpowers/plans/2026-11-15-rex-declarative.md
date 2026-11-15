# Rex Declarative Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the imperative `nix profile add` of Rex with a flake input plus the vendor's home-manager module, running the server as a systemd user service.

**Architecture:** `rex` becomes a direct flake input (tarball URL, pinned by narHash in `flake.lock`). Its own home-manager module is imported from a new `nixos/programs/rex.nix`, which enables `programs.rex` (binary, terminfo, ssh guard) and `services.rex` (systemd user service, `X-SwitchMethod = keep-old`). Configuration lives in `dotfiles/rex/init.lua`, symlinked to `~/.config/rex` so edits are live, as with herdr. No linger for now; the user service starts on login (including SSH) and restarts via pam_systemd.

**Tech Stack:** Nix flakes, flake-parts, home-manager, systemd user units.

**Spec:** this plan (design agreed in session; no separate spec file).

## Global Constraints

- All edits happen in the worktree `/home/asergi/.local/share/opencode/worktree/b53491/rex` on branch `rex-nix`; never in `~/dotfiles`.
- `flake.lock` must be committed: `nix flake check --no-write-lock-file` fails on an unlocked input.
- No machine-specific values (repo rules): no usernames, hostnames, paths, or UIDs hardcoded.
- Channel stays `snapshot` as the user ran it; `nix flake update rex` is the only intended way to move it.
- Do not commit, merge, rebuild, or write to `/etc/nixos` without the user's explicit permission.

## Review Focus

- **Unfree package:** `rex` is `meta.license = unfree`. It must evaluate through the vendor flake's own `allowUnfreePredicate`; do not set global `allowUnfree` for it.
- **Home config collision:** `~/.config/rex` is a symlink to the repo. `programs.rex.config` must stay `null`, or home-manager writes into the repo through the symlink.
- **SSH config ownership:** `~/.ssh/config` does not exist today. `programs.ssh.enable = true` with `enableDefaultConfig = false` must produce only the rex `Include` line.
- **Service lifetime:** the user unit stops with the user manager (no linger). This is intended; do not add linger.
- **Saved sessions:** Rex saves on SIGTERM and restores on the next start; the plan must not add anything that kills the server without SIGTERM (`KillMode`, `RuntimeDirectoryPreserve` come from the vendor module).

---

### Task 1: Flake input and module plumbing

**Files:**
- Modify: `nixos/flake.nix` (inputs block; `home-manager.extraSpecialArgs`; both `homeConfigurations.*.extraSpecialArgs`)
- Modify: `nixos/flake.lock` (generated)

**Interfaces:**
- Produces: `inputs.rex` available in every home-manager module evaluated from this flake.

- [ ] **Step 1: Add the input**

After the `opencode-src` block in `nixos/flake.nix`:

```nix
    rex = {
      url = "https://pkgs.superlogical.com/rex/nix/snapshot.tar.gz";
    };
```

- [ ] **Step 2: Pass `inputs` to home-manager**

Add `inherit inputs;` to `home-manager.extraSpecialArgs` and to both `homeConfigurations.default.extraSpecialArgs` and `homeConfigurations.check.extraSpecialArgs`.

- [ ] **Step 3: Lock**

Run: `nix flake lock ./nixos`
Expected: `nixos/flake.lock` gains a `rex` node.

- [ ] **Step 4: Verify the pin**

Run: `nix flake metadata ./nixos --json | jq -r '.locks.nodes.rex.locked.url'`
Expected: an immutable URL like `https://pkgs.superlogical.com/rex/nix/snapshot/0.0.<timestamp>-g<rev>.tar.gz`.

---

### Task 2: Module and config directory

**Files:**
- Create: `nixos/programs/rex.nix`
- Create: `rex/init.lua`
- Modify: `nixos/home.nix` (imports list)

**Interfaces:**
- Consumes: `inputs.rex.homeManagerModules.default` from Task 1.
- Produces: `programs.rex.enable`, `services.rex.enable`, `~/.config/rex` symlink.

- [ ] **Step 1: Create `nixos/programs/rex.nix`**

```nix
{
  config,
  inputs,
  ...
}:

{
  imports = [ inputs.rex.homeManagerModules.default ];

  programs.rex.enable = true;
  services.rex.enable = true;

  programs.ssh.enable = true;
  programs.ssh.enableDefaultConfig = false;

  home.file.".config/rex".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/rex";
}
```

- [ ] **Step 2: Create `rex/init.lua`**

```lua
-- Rex configuration. nixos/programs/rex.nix symlinks this directory to
-- ~/.config/rex, so edits apply after `rex config reload`.
```

- [ ] **Step 3: Import the module**

Add `./programs/rex.nix` to the `imports` list in `nixos/home.nix`.

- [ ] **Step 4: Track new files and evaluate**

Run: `git add nixos/programs/rex.nix rex/init.lua nixos/home.nix nixos/flake.nix nixos/flake.lock`
Run: `nix flake check ./nixos --no-write-lock-file`
Expected: PASS (checks `generation`, `portable`, `identity`).

---

### Task 3: Build gates

- [ ] **Step 1: Dry-build the machine**

Run: `nixos-rebuild dry-build --flake ./nixos#default --impure`
Expected: builds the system and home-manager closures with no error.

- [ ] **Step 2: Repo checks**

Run: `bash tests/check-no-hardcoded-home.sh && bash tests/test-user.sh && bash tests/test-guard.sh`
Expected: PASS.

- [ ] **Step 3: Report**

Report the exact commands and outputs. Ask the user before committing or rebuilding.

---

### Task 4: After the user rebuilds

- [ ] **Step 1: Service and terminfo**

Run: `systemctl --user status rex --no-pager`, `infocmp xterm-rex >/dev/null && echo ok`, `cat ~/.ssh/config`, `ls -l ~/.config/rex`
Expected: unit active; `ok`; only the rex `Include`; symlink into the repo.

- [ ] **Step 2: Remote attach**

From asus: `ssh hp-845-g8 -t rex ls`; create a session, detach, log out and back in, `rex ls` again.
Expected: the session is listed after the new login (saved and restored).

- [ ] **Step 3: Decide on linger**

Only if the server must exist with nobody logged in: add `users.users.${username}.linger = true` in `nixos/configuration.nix`.
