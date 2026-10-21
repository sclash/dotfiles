"""Tests for wsl/opencode/sync_opencode_jsonc.py (stdlib unittest)."""

import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
# In the flake check, tests/ and opencode/ are separate store paths.
OPENCODE_DIR = os.environ.get("SYNC_OPENCODE_DIR", os.path.join(HERE, "..", "opencode"))
SCRIPT = os.path.join(OPENCODE_DIR, "sync_opencode_jsonc.py")
sys.path.insert(0, OPENCODE_DIR)

from sync_opencode_jsonc import transform  # noqa: E402

MOUNT = "/run/user/1000/secrets.d"
SOPS = "/home/asergi/.config/sops-nix/secrets"
TILDE = "~/.config/sops-nix/secrets"


def rule(action, resource, effect="deny"):
    return (
        "\t\t{\n"
        f'\t\t\t"action": "{action}",\n'
        f'\t\t\t"resource": "{resource}",\n'
        f'\t\t\t"effect": "{effect}"\n'
        "\t\t}"
    )


def doc(*rules, api_key="{file:/run/secrets/openrouter}"):
    return (
        "{\n"
        '\t"providers": {\n'
        '\t\t"openrouter": {\n'
        f'\t\t\t"settings": {{ "apiKey": "{api_key}" }}\n'
        "\t\t}\n"
        "\t},\n"
        '\t"permissions": [\n' + ",\n".join(rules) + "\n\t]\n"
        "}\n"
    )


def resources(text):
    return [r["resource"] for r in json.loads(text)["permissions"]]


class TransformTest(unittest.TestCase):
    def test_file_refs_rewritten(self):
        out = transform(doc(rule("read", "**/*.key")))
        key = json.loads(out)["providers"]["openrouter"]["settings"]["apiKey"]
        self.assertEqual(key, "{file:/home/asergi/.config/sops-nix/secrets/openrouter}")
        self.assertNotIn("{file:/run/secrets", out)

    def test_read_rule_mirrors_follow_source(self):
        out = transform(doc(rule("read", "/run/secrets/**")))
        self.assertEqual(
            resources(out),
            ["/run/secrets/**", f"{MOUNT}/**", f"{SOPS}/**"],
        )
        self.assertTrue(all(r["action"] == "read" and r["effect"] == "deny"
                            for r in json.loads(out)["permissions"]))

    def test_dot_d_rule_maps_to_same_locations(self):
        out = transform(doc(rule("read", "/run/secrets.d/**")))
        self.assertEqual(
            resources(out),
            ["/run/secrets.d/**", f"{MOUNT}/**", f"{SOPS}/**"],
        )

    def test_shell_rule_gets_tilde_variant(self):
        out = transform(doc(rule("shell", "*cat /run/secrets*")))
        self.assertEqual(
            resources(out),
            [
                "*cat /run/secrets*",
                f"*cat {MOUNT}*",
                f"*cat {SOPS}*",
                f"*cat {TILDE}*",
            ],
        )

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
            ["**/*.p12", "/run/secrets/**", f"{MOUNT}/**", f"{SOPS}/**", f"{TILDE}/**"],
        )

    def test_unrelated_text_untouched(self):
        key_rule = rule("read", "**/*.key")
        text = "{\n\t// keep this comment\n\t\"permissions\": [\n" + key_rule + "\n\t]\n}\n"
        out = transform(text)
        self.assertEqual(out, text)

    def test_idempotent(self):
        once = transform(doc(rule("read", "/run/secrets"), rule("shell", "*cp /run/secrets*")))
        self.assertEqual(transform(once), once)


class CliTest(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)

    def test_writes_and_checks(self):
        with tempfile.TemporaryDirectory() as d:
            base, out = os.path.join(d, "base.jsonc"), os.path.join(d, "out.jsonc")
            with open(base, "w") as f:
                f.write(doc(rule("read", "/run/secrets")))
            self.assertEqual(self.run_cli(base, out).returncode, 0)
            self.assertEqual(self.run_cli("--check", base, out).returncode, 0)
            with open(out, "a") as f:
                f.write("\n")
            stale = self.run_cli("--check", base, out)
            self.assertEqual(stale.returncode, 1)
            self.assertIn("stale: " + out, stale.stdout + stale.stderr)


if __name__ == "__main__":
    unittest.main()
