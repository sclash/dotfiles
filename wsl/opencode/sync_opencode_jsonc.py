#!/usr/bin/env python3
"""Regenerate wsl/opencode/opencode.jsonc from my-opencode/v2/opencode.jsonc.

On WSL, sops-nix's home-manager module puts secrets under ~/.config/sops-nix
(backed by /run/user/<uid>/secrets.d) instead of /run/secrets. The transform is
text-level so comments and formatting outside the changed spans survive:

  * {file:/run/secrets/<name>} becomes {file:<SOPS_DIR>/<name>}.
  * Every permission rule whose resource mentions /run/secrets(.d) is kept and
    immediately followed by mirrors, skipping mirrors that already exist:
    - read, edit, and external_directory resources get the literal ~ mirror.
    - shell, glob, and grep resources get the wildcard mirror because opencode
      does not home-expand them.
    - shell resources also get the literal ~ mirror.

Usage: sync_opencode_jsonc.py [--check] BASE OUT
"""

import re
import sys

MOUNT_DIR = "/run/user/*/secrets.d"
SOPS_DIR = "~/.config/sops-nix/secrets"
SHELL_SOPS_DIR = "*/.config/sops-nix/secrets"
TILDE_SOPS_DIR = SOPS_DIR

SECRETS = re.compile(r"/run/secrets(?:\.d)?")
RULE = re.compile(
    r'(?P<indent>[ \t]*)\{\s*"action":\s*"(?P<action>[^"]*)",'
    r'\s*"resource":\s*"(?P<resource>[^"]*)",'
    r'\s*"effect":\s*"(?P<effect>[^"]*)"\s*\}(?P<comma>,?)'
)


def mirror_locations(action):
    if action == "shell":
        return [MOUNT_DIR, SHELL_SOPS_DIR, TILDE_SOPS_DIR]
    if action in {"glob", "grep"}:
        return [MOUNT_DIR, SHELL_SOPS_DIR]
    return [MOUNT_DIR, SOPS_DIR]


def mirror_secret_rules(text):
    existing = {(m["action"], m["resource"], m["effect"]) for m in RULE.finditer(text)}

    def expand(m):
        if not SECRETS.search(m["resource"]):
            return m.group(0)
        block = m.group(0)[: len(m.group(0)) - len(m["comma"])]
        mirrors = []
        for location in mirror_locations(m["action"]):
            resource = SECRETS.sub(location, m["resource"])
            key = (m["action"], resource, m["effect"])
            if key in existing:
                continue
            existing.add(key)
            mirrors.append(block.replace(f'"resource": "{m["resource"]}"', f'"resource": "{resource}"', 1))
        if not mirrors:
            return m.group(0)
        return ",\n".join([block, *mirrors]) + m["comma"]

    return RULE.sub(expand, text)


def rewrite_file_refs(text):
    return text.replace("{file:/run/secrets/", "{file:" + SOPS_DIR + "/")


def transform(text):
    return mirror_secret_rules(rewrite_file_refs(text))


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if len(args) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    base, out = args
    with open(base, encoding="utf-8") as f:
        wanted = transform(f.read())
    if check:
        try:
            with open(out, encoding="utf-8") as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        if current != wanted:
            print(f"stale: {out}")
            return 1
        return 0
    with open(out, "w", encoding="utf-8") as f:
        f.write(wanted)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
