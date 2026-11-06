#!/usr/bin/env python3
"""Create public, synthetic offline crypto fixtures with an independent encoder.

Never supplies Apple certificates, production signing material, or credentials.
Output is exclusive: choose a new file and review before replacing a fixture.
"""

import argparse
import base64
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def generate(output: Path) -> None:
    openssl = shutil.which("openssl")
    if openssl is None:
        raise SystemExit("OpenSSL is required to generate synthetic fixtures.")
    with tempfile.TemporaryDirectory(prefix="ichart-synthetic-certificates-") as temporary:
        folder = Path(temporary)

        def run(*arguments: str) -> str:
            return subprocess.run(
                [openssl, *arguments], cwd=folder, check=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            ).stdout.strip()

        for name in ("root", "intermediate", "leaf", "other-root"):
            run("genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256",
                "-out", f"{name}.key")
            run("req", "-new", "-key", f"{name}.key", "-subj",
                f"/CN=iChart Synthetic Offline Test {name}/O=Public Test Fixture",
                "-out", f"{name}.csr")

        root_extensions = "\n".join([
            "basicConstraints=critical,CA:TRUE,pathlen:1",
            "keyUsage=critical,keyCertSign,cRLSign",
            "subjectKeyIdentifier=hash", "",
        ])
        (folder / "root.ext").write_text(root_extensions)
        for serial, name in enumerate(("root", "other-root"), 1):
            run("x509", "-req", "-in", f"{name}.csr", "-signkey", f"{name}.key",
                "-set_serial", str(serial), "-days", "7300", "-sha256",
                "-extfile", "root.ext", "-out", f"{name}.pem")

        for name, is_ca in (("intermediate", True), ("intermediate-no-ca", False)):
            extensions = [
                f"basicConstraints=critical,CA:{'TRUE,pathlen:0' if is_ca else 'FALSE'}",
                "keyUsage=critical,keyCertSign,cRLSign",
                "subjectKeyIdentifier=hash", "authorityKeyIdentifier=keyid,issuer",
                "1.2.840.113635.100.6.2.1=ASN1:NULL", "",
            ]
            (folder / f"{name}.ext").write_text("\n".join(extensions))
            run("x509", "-req", "-in", "intermediate.csr", "-CA", "root.pem",
                "-CAkey", "root.key", "-set_serial", "10" if is_ca else "11",
                "-days", "3650", "-sha256", "-extfile", f"{name}.ext",
                "-out", f"{name}.pem")

        for serial, (name, include_oid) in enumerate((("leaf", True), ("leaf-no-oid", False)), 20):
            extensions = [
                "basicConstraints=critical,CA:FALSE", "keyUsage=critical,digitalSignature",
                "subjectKeyIdentifier=hash", "authorityKeyIdentifier=keyid,issuer",
            ]
            if include_oid:
                extensions.append("1.2.840.113635.100.6.11.1=ASN1:NULL")
            (folder / f"{name}.ext").write_text("\n".join(extensions) + "\n")
            run("x509", "-req", "-in", "leaf.csr", "-CA", "intermediate.pem",
                "-CAkey", "intermediate.key", "-set_serial", str(serial),
                "-days", "1825", "-sha256", "-extfile", f"{name}.ext",
                "-out", f"{name}.pem")

        certificates = {}
        for name in ("root", "other-root", "intermediate", "intermediate-no-ca", "leaf", "leaf-no-oid"):
            run("x509", "-in", f"{name}.pem", "-outform", "DER", "-out", f"{name}.der")
            certificates[name] = base64.b64encode((folder / f"{name}.der").read_bytes()).decode()
        now = datetime.now(timezone.utc)
        value = {
            "notice": "PUBLIC SYNTHETIC TEST MATERIAL ONLY. Never trust this root or use this private key outside offline tests.",
            "generator": "scripts/generate_app_store_verifier_fixture.py",
            "opensslVersion": run("version"),
            "generatedAt": now.isoformat(),
            "signedDate": int((now + timedelta(minutes=5)).timestamp() * 1000),
            "expiredSignedDate": int((now + timedelta(days=8000)).timestamp() * 1000),
            "rootPEM": (folder / "root.pem").read_text(),
            "otherRootPEM": (folder / "other-root.pem").read_text(),
            "leafPrivateKeyPEM": (folder / "leaf.key").read_text(),
            "certificates": certificates,
        }
        with output.open("x") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    generate(parser.parse_args().output)
