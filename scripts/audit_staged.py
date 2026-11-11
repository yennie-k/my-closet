"""Read-only audit of the complete Git index, including unchanged tracked files.

Print file/line/rule only, never matched credential values. This is a focused
portfolio check, not a substitute for a dedicated secret scanner or review.
"""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(
        ["git", "-c", "safe.directory=" + ROOT.as_posix(), *args], cwd=ROOT
    )


def audit():
    files = [name for name in git("ls-files", "-z").decode().split("\0") if name]
    findings = []
    reviewed_negative_test_vectors = 0
    rejected_authority_fixture = "http://" + "127.0.0.1:54321" + "@evil.test"
    rules = {
        "absolute_machine_path": re.compile(r"(?i)\b[a-z]:[\\/]"),
        "private_key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        "secret_or_jwt": re.compile(
            r"\b(?:sb_secret_[A-Za-z0-9_-]{8,}|(?:ghp_|github_pat_|AKIA|ASIA)"
            r"[A-Za-z0-9_]{12,}|eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]+\."
            r"[A-Za-z0-9_-]+)"
        ),
        "literal_public_client_key": re.compile(r"\bsb_publishable_[A-Za-z0-9_-]{12,}"),
        "embedded_image_or_long_base64": re.compile(
            r"data:image/[a-z+]+;base64,[A-Za-z0-9+/=]+|(?<![A-Za-z0-9])[A-Za-z0-9+/]{180,}={0,2}"
        ),
        "credential_in_url": re.compile(r"https?://[^/\s:@]+:[^/\s@]+@"),
    }
    personal_email = re.compile(r"[A-Za-z0-9_.+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
    credential_literal = re.compile(
        r'''(?ix)\b(?:password|passwd|access_token|refresh_token|service_role_key|secret_key)\b["']?\s*[:=]\s*["']([^"'\n]{4,})["']'''
    )
    private_values = []
    for config in ["config/supabase.local.json", "config/supabase.crud.local.json"]:
        path = ROOT / config
        if path.exists():
            for key, value in json.loads(path.read_text(encoding="utf-8-sig")).items():
                if any(word in key.upper() for word in ["KEY", "TOKEN", "PASSWORD"]):
                    if isinstance(value, str) and len(value) > 20 and "REPLACE_" not in value:
                        private_values.append(value)
    for name in files:
        path = Path(name)
        forbidden = (
            (path.name.startswith(".env") and path.name not in [".env.example", ".env.template"])
            or path.name.endswith(".local.json")
            or path.suffix.lower() in [".pem", ".key", ".dump", ".backup", ".bak", ".db", ".sqlite", ".sqlite3"]
            or any(part in ["build", ".dart_tool", "node_modules", "backups", "local-data"] for part in path.parts)
        )
        if forbidden:
            findings.append({"file": name, "line": 0, "rule": "private_or_generated_file"})
        data = git("show", ":" + name)
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            # Only bundled app icons and the documented, self-authored JPEG fixture.
            allowed = (
                name.startswith("android/app/src/main/res/mipmap-") and path.suffix == ".png"
            ) or name in ["web/favicon.png", "test/fixtures/synthetic_restart_422.jpg"] or (
                name.startswith("web/icons/") and path.suffix == ".png"
            )
            if not allowed:
                findings.append({"file": name, "line": 0, "rule": "unreviewed_binary"})
            continue
        for number, line in enumerate(text.splitlines(), 1):
            for rule, pattern in rules.items():
                if pattern.search(line):
                    if (
                        rule == "credential_in_url"
                        and name == "test/auth_test.dart"
                        and f"config(url: '{rejected_authority_fixture}')" in line
                    ):
                        # Deliberate URL-authority spoofing rejection fixture;
                        # not a username/password or a working endpoint.
                        reviewed_negative_test_vectors += 1
                        continue
                    findings.append({"file": name, "line": number, "rule": rule})
            if any(value in line for value in private_values):
                findings.append({"file": name, "line": number, "rule": "private_config_value"})
            emails = personal_email.findall(line)
            if any(not email.endswith((".test", ".invalid", "@example.com")) for email in emails):
                findings.append({"file": name, "line": number, "rule": "non_example_email"})
            # The only literal in the integration source is an intentionally wrong
            # password assertion, not a valid synthetic account credential.
            if any(value != "incorrect-password" for value in credential_literal.findall(line)):
                findings.append({"file": name, "line": number, "rule": "credential_literal"})
    report = {
        "index_files_scanned": len(files),
        "findings_count": len(findings),
        "findings": findings,
        "reviewed_negative_test_vectors": reviewed_negative_test_vectors,
        "scope": "complete current Git index; no network, Git mutation or credential output",
        "limitation": "Heuristic checks plus manual selection; not proof against every possible secret.",
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(audit())
