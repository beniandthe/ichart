#!/usr/bin/env python3
"""Scan tracked/non-ignored source while allowing exact, path-scoped test literals."""

import argparse
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
RULES = (
    ("supabase-secret-key", re.compile(r"sb_secret_[A-Za-z0-9_-]+")),
    ("stripe-live-key", re.compile(r"sk_live_[A-Za-z0-9]+")),
    ("service-role-assignment", re.compile(r"SUPABASE_SERVICE_ROLE_KEY\s*=\s*[^\s<]+")),
    ("jwt-secret-assignment", re.compile(r"JWT_SECRET\s*=\s*[^\s<]+")),
    ("jwt-token", re.compile(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}")),
    ("postgres-password-url", re.compile(r"postgres(?:ql)?://[^\s]+:[^\s@]+@")),
)

# Match the complete quoted source literal, including the hostname/path or key
# suffix. Splitting these declarations prevents the scanner from finding its own
# allowlist as credentials. Only these two existing test files receive exceptions.
SYNTHETIC_LITERALS = {
    "scripts/test_telemetry_work_queue.py": (
        '"' + "postgresql" + "://person:" + "DO_NOT_EXPOSE" + "@database.example/private" + '"',
        '"' + "postgresql" + "://user:" + "secret" + "@host/db" + '"',
    ),
    "supabase/functions/_shared/forum_post_actions.test.mjs": (
        '"' + "sb_" + "secret_not_a_public_key" + '"',
    ),
}


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str


def scan_text(path: str, text: str) -> list:
    path = PurePosixPath(path).as_posix()
    findings = []
    for line_number, line in enumerate(text.splitlines(), 1):
        allowed_spans = []
        for literal in SYNTHETIC_LITERALS.get(path, ()):
            allowed_spans.extend((match.start(), match.end())
                                 for match in re.finditer(re.escape(literal), line))
        for rule, pattern in RULES:
            position = 0
            while (match := pattern.search(line, position)) is not None:
                # An assignment's non-whitespace value can consume a second
                # adjacent assignment. Revisit nested starts before exempting a
                # dynamic template, so it cannot hide that second credential.
                position = match.start() + 1 if rule.endswith("-assignment") else match.end()
                if any(start <= match.start() and match.end() <= end for start, end in allowed_spans):
                    continue
                # Preserve the existing dynamic-assignment exception per match.
                # A template elsewhere on this line cannot hide another secret.
                if rule in ("service-role-assignment", "jwt-secret-assignment") \
                        and re.match(r'\s*"?[$<]', match.group().partition("=")[2]):
                    continue
                findings.append(Finding(path, line_number, rule))
    return findings


def scan_paths(root: Path, paths: list) -> list:
    findings = []
    for path in paths:
        source = root / path
        if not source.is_file():
            continue
        data = source.read_bytes()
        # Preserve grep -I's existing binary-file policy.
        if b"\0" not in data:
            findings.extend(scan_text(path, data.decode("utf-8", errors="replace")))
    return findings


def repository_paths(root: Path) -> list:
    result = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                            cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return [path.decode("utf-8", errors="surrogateescape") for path in result.stdout.split(b"\0") if path]


def format_findings(findings: list) -> str:
    # Never print matching line text, credential values or URL components.
    return "\n".join(f"{finding.path}:{finding.line}: possible secret ({finding.rule}; value redacted)"
                     for finding in findings)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Repository root (also supports isolated fixtures)")
    arguments = parser.parse_args()
    try:
        findings = scan_paths(arguments.root, repository_paths(arguments.root))
    except (OSError, subprocess.CalledProcessError):
        print("error: could not enumerate or read repository files", file=sys.stderr)
        return 2
    if findings:
        print(format_findings(findings), file=sys.stderr)
        print("error: possible secret material found in tracked or non-ignored files", file=sys.stderr)
        return 1
    print("Secret scan passed (exact path-scoped synthetic fixtures only).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
