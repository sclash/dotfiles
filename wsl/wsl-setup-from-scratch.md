# WSL setup from scratch (acceptance test procedure)

This procedure brings a brand-new Linux WSL distro (tested on Ubuntu and Arch) up to the `wsl/` home-manager flake, and proves that it works.
Run it as a throwaway test (`hm-test`), or follow it for real on a new machine.

- **Existing instance:** an instance that can already decrypt `wsl/secrets/secrets.yaml` (today: `Ubuntu-22.04`).
- **New instance:** the fresh distro.

## 0. On the existing instance: package the branch

No push is needed. A git bundle on the Windows drive is enough:

```bash
git -C ~/dotfiles bundle create /mnt/c/Users/<you>/dotfiles-wsl.bundle quickshell
```

(Once the branch is pushed or merged, clone from GitHub instead.)

## 1. Windows (PowerShell): create the distro

```powershell
wsl --install Ubuntu-24.04 --name hm-test
```

When it first starts, use the existing WSL user. The flake takes the account name and home directory from
`$USER`/`$HOME`; the repo must be at `~/dotfiles`.

## 2. New instance: clone

```bash
# Ubuntu/Debian:
sudo apt-get update && sudo apt-get install -y git
# Arch:
sudo pacman -S --needed git
git clone -b quickshell /mnt/c/Users/<you>/dotfiles-wsl.bundle ~/dotfiles
git -C ~/dotfiles submodule update --init        # neovimrc (from GitHub)
```

## 3. New instance: first bootstrap runs

```bash
bash ~/dotfiles/wsl/bootstrap.sh
```

Re-run after every `ACTION NEEDED` message, which exits with code 2. Expect, in order:

1. **systemd:** it writes `/etc/wsl.conf` (asking for sudo), then exits 2. From PowerShell, run `wsl --terminate hm-test`,
   reopen the distro, and re-run bootstrap.
2. Next it installs zsh, git and curl from the distro package manager, runs `chsh` and regenerates the locale (sudo),
   then installs Determinate Nix. The step detects the package manager: Arch uses `pacman` (the example above uses
   Ubuntu's `apt`). If it says Nix isn't on PATH yet, open a new shell and re-run.
3. It **generates this instance's age key** (`~/.config/sops/age/keys.txt`), adds its public key to `wsl/.sops.yaml`,
   then exits 2: *"this instance's key cannot decrypt …"*. It prints the exact command to run next:
   `bash ~/dotfiles/wsl/bootstrap.sh --add-recipient age1…`. Copy that public key.

## 4. Existing instance: grant access (throwaway branch for a test)

```bash
cd ~/dotfiles
git switch -c hm-test-acceptance                 # test only; for a real instance stay on the branch
bash wsl/bootstrap.sh --add-recipient age1...    # adds the key, runs sops updatekeys
git add wsl/.sops.yaml wsl/secrets/secrets.yaml
git commit -m "wsl: add hm-test recipient"
git bundle create /mnt/c/Users/<you>/dotfiles-wsl.bundle hm-test-acceptance
```

## 5. New instance: take the re-encrypted secrets and finish

```bash
cd ~/dotfiles
git fetch /mnt/c/Users/<you>/dotfiles-wsl.bundle hm-test-acceptance
git checkout FETCH_HEAD -- wsl/.sops.yaml wsl/secrets/secrets.yaml
bash wsl/bootstrap.sh                            # expected: exit 0, home-manager switch done
```

Note: the new instance's own `wsl/.sops.yaml` edit from step 3 is overwritten here by the version that holds both keys.

If no instance can decrypt the shared file (or you cannot use an existing instance to add the key), use the local
fallback on the new instance instead of steps 4–5:

```bash
bash ~/dotfiles/wsl/bootstrap.sh --new-secrets   # creates the local file with empty values and continues
```

Fill the four values whenever you like, through sops (it opens `$EDITOR`; do not edit the encrypted file directly):

```bash
EDITOR="${EDITOR:-vi}" SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  nix run ~/dotfiles/wsl#sops -- \
  --config ~/dotfiles/wsl/.sops.yaml --filename-override secrets/secrets.yaml \
  ~/.config/sops-nix/wsl-secrets.yaml
```

`update` also uses `~/.config/sops-nix/wsl-secrets.yaml` when it exists. Editing that file directly with `nvim`/`nano`
leaves plaintext values and sops then fails with `Input string ... does not match sops' data format`.

## 6. New instance: verify

Open a **new terminal**, then:

```bash
bash ~/dotfiles/wsl/tests/check-live.sh          # expected: no FAIL lines, then "OK (live)"
```

- `claude` and `opencode` come from `nixpkgs-unstable` and must resolve from the Nix profile.
- Optional manual checks:
  - `nvim`, then `:checkhealth vim.lsp`
  - `opencode`: a provider answers a prompt
  - `nix flake check ~/dotfiles/wsl`
  - `bash ~/dotfiles/wsl/tests/test-bootstrap.sh` (it expects this host's state: locale present, nix installed, …)

A fresh distro has no snaps, nvm or oh-my-zsh, so `--cleanup` should report nothing to remove:

```bash
bash ~/dotfiles/wsl/bootstrap.sh --cleanup
```

## 7. Tear down (test only)

```powershell
wsl --unregister hm-test                         # PowerShell; deletes the test distro
del C:\Users\<you>\dotfiles-wsl.bundle
```

On the existing instance, drop the test recipient so it never reaches the real branch:

```bash
cd ~/dotfiles && git switch quickshell && git branch -D hm-test-acceptance
```

## Troubleshooting

- **Out of memory during the switch:** check `nix build ~/dotfiles/wsl#checks.x86_64-linux.generation --dry-run` for
  derivations that would compile locally. Everything should come from the binary cache, except small glue
  derivations. Or raise the VM's memory in `%UserProfile%\.wslconfig` (`[wsl2]` / `memory=8GB`).
- **`Existing file … would be clobbered`:** an old `*.hm-backup` is in the way. Inspect it, delete it, and re-run.
- **Secrets missing after the switch:** `systemctl --user status sops-nix`. Then check that the key can decrypt:
  `nix run ~/dotfiles/wsl#sops -- --config ~/dotfiles/wsl/.sops.yaml -d ~/dotfiles/wsl/secrets/secrets.yaml >/dev/null`
