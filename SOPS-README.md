# SOPS with sops-nix — how this repo handles secrets

> One encrypted file in git, decrypted at activation to `/run/secrets/<name>`, inherited by shells and MCP servers. Nothing auto-encrypts — only `sops edit <file>` does (`sops <file>` is shorthand for `sops edit <file>`).

## Contents

- [Components](#components)
- [One-time setup](#one-time-setup)
- [Day-to-day workflows](#day-to-day-workflows)
  - [Rotate an existing value](#rotate-existing-value)
  - [Add a new key for a new service](#add-new-key)
  - [Add a second secrets file](#add-second-file)
- [sops CLI — managing secrets.yaml](#sops-cli)
  - [View / decrypt without editing](#view-decrypt)
  - [Update an existing value](#update-value)
  - [Add a new secret](#add-secret)
  - [Remove a secret](#remove-secret)
  - [Re-encrypt / rekey — sops updatekeys](#reencrypt-updatekeys)
  - [Initial encryption](#initial-encryption)
  - [Other useful invocations](#other-invocations)
- [Rules — what never to do](#rules)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Quick reference](#quick-reference)

<a id="components"></a>
## Components

| File | Role | Consumed by |
|------|------|-------------|
| `.sops.yaml` (repo root) | `creation_rules` → age **pubkey** `age1ntvf6hjhdvgeunxtgwqqf7smlfsdu5l54t27ll8z306488he7q7qyk050s` for `path_regex: nixos/secrets/.*\.ya?ml$` | `sops` CLI on every save |
| `~/.config/sops/age/keys.txt` (0600, **not in git**) | age **private key** | `sops` edits + sops-nix (`sops.age.keyFile = "/home/asergi/.config/sops/age/keys.txt"`) |
| `nixos/sops.nix` | `sops.secrets.<name> = { owner = "asergi"; mode = "0600"; }` → `/run/secrets/<name>` | NixOS activation (`sops-install-secrets`) |
| `nixos/secrets/secrets.yaml` | single encrypted YAML — **tracked** (`nixos/.gitignore` is `secrets/*` + `!secrets/secrets.yaml`) | copied into the Nix store at build time; decrypted from that store copy |
| `nixos/programs/zsh.nix` `initContent` | `cat /run/secrets/github_pat` → `GITHUB_PERSONAL_ACCESS_TOKEN` | every new interactive zsh; opencode's local MCP servers inherit it |
| `my-opencode/opencode.json` github entry | `["nix","run","nixpkgs#github-mcp-server","--","stdio"]`, no `environment` block | opencode (child inherits parent env) |

Why `.sops.yaml` lives at the repo root: `sops` walks upward from the target file to find it.

<a id="one-time-setup"></a>
## One-time setup (already done — recorded for reproducibility)

```bash
mkdir -p ~/.config/sops/age
nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
# pubkey printed by age-keygen goes into .sops.yaml creation_rules
# nixos/flake.nix: sops-nix input + inputs.sops-nix.nixosModules.sops
# nixos/sops.nix: sops = { age.keyFile = "..."; defaultSopsFile = ./secrets/secrets.yaml; secrets.github_pat.owner = "asergi"; }
# nixos/.gitignore: secrets/*  +  !secrets/secrets.yaml

nix shell nixpkgs#sops -c sops encrypt -i nixos/secrets/secrets.yaml
git add .sops.yaml nixos/sops.nix nixos/secrets/secrets.yaml
```

Backup `~/.config/sops/age/keys.txt` somewhere safe (password manager, offline copy) — it is the only way to decrypt.

<a id="day-to-day-workflows"></a>
## Day-to-day workflows

<a id="rotate-existing-value"></a>
### Rotate an existing value (e.g. PAT expired)

```bash
sops edit nixos/secrets/secrets.yaml   # $EDITOR opens decrypted view — edit github_pat: <new>, save → auto re-encrypts
git add nixos/secrets/secrets.yaml
update                            # alias → sudo nixos-rebuild switch --flake ~/dotfiles/nixos#nixos-os
# new shells pick it up automatically; restart opencode
```

<a id="add-new-key"></a>
### Add a new key for a new service

```bash
sops edit nixos/secrets/secrets.yaml   # add line:  my_service_token: <value>
```

Then declare it in `nixos/sops.nix` — **required**, sops-nix only materializes declared keys:

```nix
sops.secrets = {
  github_pat.owner = "asergi";
  my_service_token = { owner = "asergi"; mode = "0600"; };
  # → appears at /run/secrets/my_service_token
};
```

```bash
git add nixos/secrets/secrets.yaml nixos/sops.nix
update
```

<a id="add-second-file"></a>
### Add a second secrets file (optional)

`path_regex` already covers any `nixos/secrets/*.yaml`. If you keep `defaultSopsFile = ./secrets/secrets.yaml`, extra files need a per-secret override:

```nix
sops.secrets.ci_token = {
  sopsFile = ./secrets/ci.yaml;
  owner = "asergi";
};
```

<a id="sops-cli"></a>
## sops CLI — managing `nixos/secrets/secrets.yaml`

All commands below assume `CWD = repo root` (`~/dotfiles`). Use `nix shell nixpkgs#sops -c sops ...` if `sops` is not in `PATH` (it is not installed system-wide unless you add `pkgs.sops` to `environment.systemPackages`). `sops` finds `.sops.yaml` by walking up from the target file, so `nixos/secrets/secrets.yaml` is matched by `path_regex: nixos/secrets/.*\.ya?ml$`.

<a id="view-decrypt"></a>
### View / decrypt without editing

```bash
# decrypted to stdout — does not modify the file
sops --decrypt nixos/secrets/secrets.yaml
sops -d nixos/secrets/secrets.yaml | grep github_pat

# via nix shell if not installed
nix shell nixpkgs#sops -c sops --decrypt nixos/secrets/secrets.yaml
```

<a id="update-value"></a>
### Update an existing value (rotate PAT)

```bash
sops edit nixos/secrets/secrets.yaml
# $EDITOR opens a temporary decrypted YAML
# edit:  github_pat: <new-value>
# :wq  → sops re-encrypts automatically with the key in .sops.yaml
git add nixos/secrets/secrets.yaml
update   # sudo nixos-rebuild switch --flake ~/dotfiles/nixos#nixos-os
```

No regex or flag needed — editing the key in place is the update.

<a id="add-secret"></a>
### Add a new secret

```bash
sops edit nixos/secrets/secrets.yaml
# add a new line:  my_service_token: ENC[...] will be generated on save
# e.g. add:  my_service_token: supersecret123
```

Then **declare** it in `nixos/sops.nix` — sops-nix only materializes declared keys:

```nix
# nixos/sops.nix
{
  sops.secrets = {
    github_pat.owner = "asergi"; # shorthand keeps existing
    my_service_token = { owner = "asergi"; mode = "0600"; };
    # appears at /run/secrets/my_service_token after next switch
  };
}
```

```bash
git add nixos/secrets/secrets.yaml nixos/sops.nix
update
ls -l /run/secrets/my_service_token   # 0600 asergi
```

Expose to a shell if needed (`nixos/programs/zsh.nix:39` pattern):

```zsh
if [ -f /run/secrets/my_service_token ]; then
  export MY_SERVICE_TOKEN="$(cat /run/secrets/my_service_token)"
fi
```

<a id="remove-secret"></a>
### Remove a secret

```bash
sops edit nixos/secrets/secrets.yaml
# delete the line:  github_pat: ENC[...]
# or:  my_service_token: ENC[...]  → remove it
```

Remove its declaration from `nixos/sops.nix` in the same commit, otherwise `sops-install-secrets` will warn about a missing key:

```nix
# remove the entry entirely
sops.secrets.my_service_token = lib.mkForce null; # alternative: just delete the attr
```

```bash
git add nixos/secrets/secrets.yaml nixos/sops.nix
update
# old path disappears on next activation
[ ! -e /run/secrets/my_service_token ] && echo removed
```

<a id="reencrypt-updatekeys"></a>
### Re-encrypt / rekey after `.sops.yaml` or age key changes — `sops updatekeys`

`sops updatekeys` re-encrypts the file's data keys with the **current** `creation_rules` without touching plaintext values. Use it when you:

* change the age pubkey in `.sops.yaml` (e.g. new `age-keygen` on a new machine)
* add a second recipient (`age: age1... , age1...`)
* fix a file that was created before `.sops.yaml` existed

```bash
# 1. edit .sops.yaml — change/add age: age1...
vim .sops.yaml

# 2. apply to the encrypted file (decrypts with old key, re-encrypts with new)
sops updatekeys nixos/secrets/secrets.yaml
# equivalent:  sops --decrypt --encrypt --in-place  or
#              nix shell nixpkgs#sops -c sops updatekeys nixos/secrets/secrets.yaml

# 3. stage both — .sops.yaml must be staged for the next build's creation_rules to match
git add .sops.yaml nixos/secrets/secrets.yaml
update

# force group rekey (alternative, same effect for age)
sops --rotate --in-place nixos/secrets/secrets.yaml
```

`updatekeys` prompts for the old private key if the file was encrypted with it — keep `~/.config/sops/age/keys.txt` (or old `keys.txt`) until re-encryption is done.

<a id="initial-encryption"></a>
### Initial encryption (plaintext → encrypted)

Only needed once when `nixos/secrets/secrets.yaml` is still plaintext (`github_pat: fica` without `ENC[`):

```bash
sops --encrypt --in-place nixos/secrets/secrets.yaml
# checks .sops.yaml creation_rules for the recipient
git add nixos/secrets/secrets.yaml
update
```

<a id="other-invocations"></a>
### Other useful invocations

```bash
# edit with a specific editor
EDITOR=nvim sops edit nixos/secrets/secrets.yaml
SOPS_EDITOR="code --wait" sops edit nixos/secrets/secrets.yaml

# run a command with secrets as env/file without writing /run/secrets
sops exec-env nixos/secrets/secrets.yaml 'env | grep GITHUB'
sops exec-file nixos/secrets/secrets.yaml 'cat {} | head'

# encrypt a single value to paste into YAML manually
echo -n "myvalue" | sops --encrypt --age age1ntvf6hjhdvgeunxtgwqqf7smlfsdu5l54t27ll8z306488he7q7qyk050s --in-place /dev/stdin

# verify recipients embedded in the file
sops --decrypt --output /dev/null nixos/secrets/secrets.yaml && echo ok
grep -q 'age1ntvf6' nixos/secrets/secrets.yaml && echo "recipient present"
```

<a id="rules"></a>
## Rules — what never to do

1. **Only edit through `sops edit <file>`** (`sops <file>` works as shorthand) — plain editors write plaintext that `sops-install-secrets` cannot decrypt.
2. **`git add` after every `sops` edit** — flakes evaluate the **git index**, not the worktree. Unstaged ciphertext is invisible to the next build. The pre-commit hook enforces rule #1; nothing enforces #2, so make it muscle memory.
3. **Rebuild after staging** — `sops-nix` decrypts the **store copy** baked at build time, not your working tree.

<a id="verification"></a>
## Verification

```bash
# file is actually encrypted (contains ENC[ blocks)
grep -q 'ENC\[' nixos/secrets/secrets.yaml && echo ok

# decrypt round-trip (needs age private key)
nix shell nixpkgs#sops -c sops -d nixos/secrets/secrets.yaml | head

# after rebuild
ls -l /run/secrets/github_pat          # expect 0600 asergi
sudo cat /run/secrets/github_pat | wc -c
zsh -c 'echo ${GITHUB_PERSONAL_ACCESS_TOKEN:+SET}'   # fresh shell
```

<a id="troubleshooting"></a>
## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Edited but not encrypted | edited with plain editor | `sops edit <file>` is the only writer (`sops <file>` shorthand) |
| Not in `/run/secrets` after `update` | forgot `git add`, or plaintext in file → decrypt fails at activation | `sops` edit → `git add` → `update` |
| Flake says `access to absolute path ... forbidden in pure evaluation` | `home.file` / `builtins.readFile` with absolute `/home/...` outside the flake | use `./relative` or `config.lib.file.mkOutOfStoreSymlink "/home/..."` (see `home.nix`, `tmux.nix` fixes) |
| `Error installing file '.config/swaync/config.json' outside $HOME` | dir-level `.config/swaync` symlink colliding with `services.swaync` generated `config.json` | per-file symlinks for `style.css`/`refresh.sh` instead of a dir symlink |

<a id="quick-reference"></a>
## Quick reference

- Private key: `~/.config/sops/age/keys.txt` (also `sops.age.keyFile`)
- Public key: `age1ntvf6hjhdvgeunxtgwqqf7smlfsdu5l54t27ll8z306488he7q7qyk050s` (in `.sops.yaml`)
- Secret path: `/run/secrets/github_pat` — from key name `github_pat` in `secrets.yaml`
- Update command: `update` (`nixos/programs/zsh.nix`)
