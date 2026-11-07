# SOPS with sops-nix: how this repo handles secrets

> A template in this repo lists the credential names. Every NixOS machine has its own age key and its own encrypted secrets file, created from that template, and neither is in git. You fill in the values on each machine. At activation, sops-nix decrypts each filled-in value to `/run/secrets/<name>`.

WSL has its own setup. See [wsl/README.md](wsl/README.md).

## Contents

- [Components](#components)
- [A new machine](#a-new-machine)
- [Day-to-day](#day-to-day)
- [A machine not set up by the installer](#a-machine-not-set-up-by-the-installer)
- [Backups](#backups)
- [Rules](#rules)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Components

| File | Role |
|------|------|
| `nixos/secrets/template.yaml` (public) | The credential names, as `name: null` lines. Never holds a real value |
| `~/.config/sops/age/keys.txt` (0600, not in git) | This machine's age private key |
| `~/.config/sops/secrets.yaml` (0600, not in git) | This machine's credentials, encrypted to that key alone |
| `nixos/sops.nix` | Installs each template name that has a value in this machine's file |
| `nixos/sync-secrets.sh` | Runs before every `update`. Adds new template names to this machine's file as `null` |
| `/run/secrets/<name>` (0600, your user) | The decrypted values, recreated at every activation |
| `nixos/programs/zsh.nix` | Exports `github_pat` and `openrouter` to every new zsh |
| `my-opencode/v2/opencode.jsonc` | Reads `openrouter`, `opencode` and `cheaper_inference` |

sops-nix reads the secrets file at activation, so its values never enter the Nix store. sops leaves names and `null` readable in the encrypted file, which is how a rebuild can tell what's filled in without the key.

## A new machine

The installer's first-boot step creates the age key, then encrypts the template to it as the machine's secrets file. After the first reboot into your desktop, enter your values and apply them:

```bash
sops edit ~/.config/sops/secrets.yaml
update
```

You can fill them in over time. A `null` value is skipped: it has no `/run/secrets/<name>` yet, and the others install normally. `update` lists whatever is still unset.

## Day-to-day

### Change a value

```bash
sops edit ~/.config/sops/secrets.yaml
update
```

Open a new terminal and restart opencode so they pick up the new value. Other machines aren't affected, since each has its own file.

### Add a credential

1. Add a line to `nixos/secrets/template.yaml`, then commit and push:
   ```yaml
   my_service_token: null
   ```
2. On each machine, run `git pull && update`. This adds `my_service_token: null` to that machine's file and leaves the existing values alone.
3. On each machine that needs it, enter the value and apply it:
   ```bash
   sops edit ~/.config/sops/secrets.yaml
   update
   ```
   The value appears at `/run/secrets/my_service_token`.

To expose it to shells, follow the pattern in `nixos/programs/zsh.nix`. Machines installed later get the new name from the template.

### Remove a credential

Delete its line from `nixos/secrets/template.yaml`, commit and push, then run `git pull && update` on each machine. It stops being installed. Its value stays in each machine's file until you delete it with `sops edit`.

## A machine not set up by the installer

Generate a key, then let the sync script create the file from the template:

```bash
mkdir -p -m 700 ~/.config/sops/age
(umask 077; nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt)
bash ~/dotfiles/nixos/sync-secrets.sh
```

An age key that didn't come from `age-keygen` needs its `# public key: age1...` comment line, because that's how the script finds the public key.

## Backups

Both files exist only on the machine. If you lose its disk, generate new credentials and set the machine up again.

To keep a machine's secrets across a reinstall, back up both files somewhere safe. After reinstalling, copy them back to `~/.config/sops/` and run `update`.

## Rules

1. **Never put a real value in the template.** It's public. The pre-commit hook and the build both refuse anything but `name: null`. `sync-secrets.sh` turns the hook on for each clone.
2. **Only edit the real file through `sops edit`.** A plain editor writes values in the clear, and sops rejects the file.
3. **Run `update` after every edit.** A rebuild decides which secrets to install, and the values in `/run/secrets` only change at activation.
4. **Never copy a key or secrets file between machines.** Each machine gets its own.

## Verification

```bash
# The file is encrypted: filled-in values show as ENC[...], and unset ones as null
grep -E '^[a-z_]+:' ~/.config/sops/secrets.yaml | cut -c1-40

# This machine's key can open it
sops -d ~/.config/sops/secrets.yaml >/dev/null && echo ok

# After update: one file per filled-in name, owned by you, mode 600
ls -l /run/secrets/

# In a new terminal
zsh -c 'echo ${GITHUB_PERSONAL_ACCESS_TOKEN:+SET}'
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| A secret is missing from `/run/secrets` | Its value is still `null`, or you haven't run `update` since filling it in | `sops edit` if needed, then `update` |
| `the value of key '...' is not a string` | A value was set back to `null` after the last `update` | Run `update` |
| `nixos/secrets/template.yaml: every line must be` | A template line isn't `name: null` | Fix the line. If a real credential was committed, revoke it |
| `sync-secrets: no age key` | This machine has no age key | See [A machine not set up by the installer](#a-machine-not-set-up-by-the-installer) |
| `Failed to get the data key` or `... is unchanged` | The file was encrypted to a different key | Restore this machine's key, or move the file aside and run `sync-secrets.sh` to start a new one |
| `no matching creation rules found` | `sops` created a file from a folder with an unrelated `.sops.yaml` | Use `sync-secrets.sh`, which avoids this |
| Flake says `access to absolute path ... forbidden in pure evaluation` | `home.file` or `builtins.readFile` with an absolute `$HOME/...` path outside the flake | Use `./relative` or `config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/..."` |
| `Error installing file '.config/swaync/config.json' outside $HOME` | A directory symlink for `.config/swaync` collides with the `config.json` generated by `services.swaync` | Use per-file symlinks for `style.css` and `refresh.sh` |
