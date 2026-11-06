"""Synthetic scanner controls; no production secrets or service access."""

from pathlib import Path
import subprocess
import tempfile
import unittest

import scan_repository_secrets as scanner


TELEMETRY_PATH = "scripts/test_telemetry_work_queue.py"
FORUM_PATH = "supabase/functions/_shared/forum_post_actions.test.mjs"


def dsn(user="person", password="DO_NOT_EXPOSE", host="database.example", database="private"):
    return "postgres" + "ql://" + user + ":" + password + "@" + host + "/" + database


def key(suffix="not_a_public_key"):
    return "sb_" + "secret_" + suffix


def quoted(value):
    return '"' + value + '"'


class RepositorySecretScannerTests(unittest.TestCase):
    def test_only_the_three_exact_existing_literals_are_allowed_at_their_paths(self):
        for value in (dsn(), dsn("user", "secret", "host", "db")):
            self.assertEqual(scanner.scan_text(TELEMETRY_PATH, "value = " + quoted(value)), [])
        self.assertEqual(scanner.scan_text(FORUM_PATH, "const value = " + quoted(key())), [])

    def test_identical_literals_in_any_other_path_are_rejected(self):
        self.assertTrue(scanner.scan_text("scripts/other.py", quoted(dsn())))
        self.assertTrue(scanner.scan_text("supabase/functions/other.mjs", quoted(key())))
        self.assertTrue(scanner.scan_text(FORUM_PATH, quoted(dsn())))

    def test_dsn_near_matches_in_allowed_path_are_rejected(self):
        for value in (dsn(password="DO_NOT_EXPOSE_2"), dsn(host="other.example"),
                      dsn(database="private-extra"), dsn() + "/extra"):
            with self.subTest(value=value):
                self.assertTrue(scanner.scan_text(TELEMETRY_PATH, quoted(value)))

    def test_key_prefix_or_suffix_changes_in_allowed_path_are_rejected(self):
        for value in ("X" + key(), key() + "_actual", key("not_a_public_key2")):
            self.assertTrue(scanner.scan_text(FORUM_PATH, quoted(value)))

    def test_unquoted_examples_are_not_the_allowlisted_source_literals(self):
        self.assertTrue(scanner.scan_text(TELEMETRY_PATH, dsn()))
        self.assertTrue(scanner.scan_text(FORUM_PATH, key()))

    def test_allowed_dsn_does_not_hide_another_dsn_on_the_same_line(self):
        findings = scanner.scan_text(TELEMETRY_PATH,
            "first = " + quoted(dsn()) + "; second = " + quoted(dsn("other", "SyntheticPassword")))
        self.assertEqual([finding.rule for finding in findings], ["postgres-password-url"])

    def test_allowed_key_does_not_hide_another_key_on_the_same_line(self):
        findings = scanner.scan_text(FORUM_PATH, "keys = [" + quoted(key()) + "," + quoted(key("actual_value")) + "]")
        self.assertEqual([finding.rule for finding in findings], ["supabase-secret-key"])

    def test_allowed_literal_does_not_hide_a_different_secret_type(self):
        findings = scanner.scan_text(TELEMETRY_PATH,
            quoted(dsn()) + "; other = " + quoted("sk_" + "live_" + "SyntheticValue123"))
        self.assertEqual([finding.rule for finding in findings], ["stripe-live-key"])

    def test_dynamic_assignment_exemption_cannot_hide_a_secret_elsewhere_on_line(self):
        template = "JWT_" + 'SECRET="$FROM_ENV"'
        self.assertEqual(scanner.scan_text("example.sh", template), [])
        findings = scanner.scan_text("example.sh", template + "; value=" + quoted(key("actual_value")))
        self.assertEqual([finding.rule for finding in findings], ["supabase-secret-key"])

    def test_dynamic_assignment_cannot_consume_and_hide_adjacent_same_rule_assignment(self):
        for name, rule in (("JWT_" + "SECRET", "jwt-secret-assignment"),
                           ("SUPABASE_SERVICE_" + "ROLE_KEY", "service-role-assignment")):
            template = name + '="$FROM_ENV"'
            literal = name + "=SyntheticValue123"
            for line in (template + ";" + literal, literal + ";" + template):
                findings = scanner.scan_text("example.sh", line)
                self.assertEqual([finding.rule for finding in findings], [rule])

    def test_all_six_existing_detection_rules_remain_active(self):
        values = (key("actual_value"), "sk_" + "live_" + "SyntheticValue123",
                  "SUPABASE_SERVICE_" + "ROLE_KEY=" + "SyntheticValue123",
                  "JWT_" + "SECRET=" + "SyntheticValue123",
                  "eyJ" + "a" * 24 + "." + "b" * 24 + "." + "c" * 24,
                  dsn("other", "SyntheticPassword"))
        for value, (rule, _) in zip(values, scanner.RULES):
            self.assertIn(rule, [finding.rule for finding in scanner.scan_text("example.txt", value)])

    def test_diagnostics_include_path_line_and_rule_but_never_secret_contents(self):
        secret = dsn("sensitive-user", "SyntheticPassword", "private.example")
        findings = scanner.scan_text("example.py", "safe\nvalue = " + quoted(secret))
        text = scanner.format_findings(findings)
        self.assertIn("example.py:2:", text)
        self.assertIn("postgres-password-url", text)
        for fragment in (secret, "SyntheticPassword", "sensitive-user", "private.example"):
            self.assertNotIn(fragment, text)

    def test_binary_skip_and_readable_text_behavior_match_existing_policy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "binary.bin").write_bytes(b"\0" + key("actual_value").encode())
            (root / "source.txt").write_text(key("actual_value"))
            findings = scanner.scan_paths(root, ["binary.bin", "source.txt"])
            self.assertEqual([finding.path for finding in findings], ["source.txt"])

    def test_repository_discovery_includes_tracked_and_untracked_but_not_ignored(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            (root / ".gitignore").write_text("ignored.txt\n")
            for name in ("tracked.txt", "untracked.txt", "ignored.txt"):
                (root / name).write_text(key("actual_value"))
            subprocess.run(["git", "add", "tracked.txt", ".gitignore"], cwd=root, check=True)
            findings = scanner.scan_paths(root, scanner.repository_paths(root))
            self.assertEqual({finding.path for finding in findings}, {"tracked.txt", "untracked.txt"})


if __name__ == "__main__":
    unittest.main()
