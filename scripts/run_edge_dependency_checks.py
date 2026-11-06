#!/usr/bin/env python3
"""Check frozen Edge graphs and run real-package crypto tests without live services."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FUNCTIONS = ("app-store-server-notifications", "storekit-subscription-claims", "storekit-complimentary-offers")
TESTS = ["supabase/functions/_shared/app_store_signed_data_verifier.deno-test.mjs",
         "supabase/functions/_shared/complimentary_offer_api_client.deno-test.mjs"]


def run_checks(deno: Path, cache: Path) -> dict:
    cache.mkdir(parents=True, exist_ok=True)
    runtime_home = cache / "isolated-runtime-home"
    runtime_config = runtime_home / "config"
    runtime_config.mkdir(parents=True, exist_ok=True)
    (runtime_home / ".npmrc").write_text("")
    # Do not inherit service keys, npm credentials, or the caller's application environment.
    # These home/config directories belong only to the Deno child process; the
    # host environment is unchanged. Deno discovers home .npmrc directly.
    environment = {"PATH": os.defpath, "DENO_DIR": str(cache), "DENO_NO_UPDATE_CHECK": "1",
                   "NO_COLOR": "1", "HOME": str(runtime_home), "XDG_CONFIG_HOME": str(runtime_config)}

    def invoke(*arguments: str, expect_failure: bool = False) -> subprocess.CompletedProcess:
        result = subprocess.run([str(deno), *arguments], cwd=ROOT, env=environment,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if (result.returncode == 0) == expect_failure:
            raise RuntimeError(f"Deno command returned unexpected status {result.returncode}:\n{result.stdout}")
        return result

    toolchain = json.loads((ROOT / "scripts/edge_dependency_toolchain.json").read_text())
    version = invoke("--version").stdout
    if version.splitlines()[0].split()[1] != toolchain["denoVersion"]:
        raise RuntimeError(f"Use exact Deno {toolchain['denoVersion']}; observed:\n{version}")

    graphs = {}
    for name in FUNCTIONS:
        directory = ROOT / "supabase/functions" / name
        config = json.loads((directory / "deno.json").read_text())
        if config.get("lock") != {"path": "./deno.lock", "frozen": True}:
            raise RuntimeError(f"{name}: per-function frozen lock configuration is required")
        lock = json.loads((directory / "deno.lock").read_text())
        if lock.get("version") != "5":
            raise RuntimeError(f"{name}: expected reviewed Deno v5 lock format")
        for specifier, value in {"npm:@apple/app-store-server-library@3.1.0": "3.1.0",
                                 "npm:jsrsasign@11.1.5": "11.1.5"}.items():
            if lock.get("specifiers", {}).get(specifier) != value:
                raise RuntimeError(f"{name}: unexpected direct version for {specifier}")
        packages = lock.get("npm", {})
        if [key for key in packages if key.startswith("jsrsasign@")] != ["jsrsasign@11.1.5"]:
            raise RuntimeError(f"{name}: all direct and transitive jsrsasign copies must be 11.1.5")
        apple = packages.get("@apple/app-store-server-library@3.1.0", {})
        if "jsrsasign" not in apple.get("dependencies", []):
            raise RuntimeError(f"{name}: Apple SDK dependency edge was not established")
        graphs[name] = {"sha256": hashlib.sha256((directory / "deno.lock").read_bytes()).hexdigest(),
                        "npmEntries": len(packages), "jsrsasign": "11.1.5", "appleSDK": "3.1.0"}
        # Cache is a preparation step only. No --allow-scripts or application execution.
        invoke("cache", f"--config={directory / 'deno.json'}", "--frozen-lockfile",
               str(directory / "index.mjs"), *TESTS)
        invoke("check", f"--config={directory / 'deno.json'}", "--frozen-lockfile", "--cached-only",
               str(directory / "index.mjs"))

    # Establish that the actual pinned runtime rejects a graph requiring a lock update.
    with tempfile.TemporaryDirectory(prefix="frozen-lock-negative-", dir=cache) as negative:
        directory = Path(negative)
        source = ROOT / "supabase/functions/storekit-complimentary-offers"
        lock = json.loads((source / "deno.lock").read_text())
        del lock["specifiers"]["npm:jsrsasign@11.1.5"]
        (directory / "deno.lock").write_text(json.dumps(lock, indent=2) + "\n")
        (directory / "deno.json").write_text(json.dumps({"lock": {"path": "./deno.lock", "frozen": True}}))
        rejection = invoke("check", f"--config={directory / 'deno.json'}", "--frozen-lockfile",
                           "--cached-only", str(ROOT / "supabase/functions/_shared/app_store_signed_data_verifier.mjs"),
                           expect_failure=True)
        if "lockfile is out of date" not in rejection.stdout.lower():
            raise RuntimeError(f"Negative control failed for an unrelated reason:\n{rejection.stdout}")

    config = ROOT / "supabase/functions/storekit-complimentary-offers/deno.json"
    result = invoke("test", f"--config={config}", "--frozen-lockfile", "--cached-only",
                    "--deny-net", "--no-prompt", *TESTS)
    print(result.stdout, end="")
    counts = re.search(r"ok \| (\d+) passed \| 0 failed", result.stdout)
    if counts is None or int(counts[1]) < 15:
        raise RuntimeError("Expected at least 15 actual-version tests, with no failures")
    for name, graph in graphs.items():
        path = ROOT / "supabase/functions" / name / "deno.lock"
        if hashlib.sha256(path.read_bytes()).hexdigest() != graph["sha256"]:
            raise RuntimeError(f"{name}: validation unexpectedly changed the committed lock")
    return {"observedAt": datetime.now(timezone.utc).isoformat(), "denoVersion": toolchain["denoVersion"],
            "graphs": graphs, "testsPassed": int(counts[1]), "frozenNegativeControlRejected": True,
            "frozenNegativeControl": {"exitCode": rejection.returncode,
                                      "diagnostic": rejection.stdout[rejection.stdout.lower().index("error:"):].strip()},
            "execution": "cached-only, deny-net, no-prompt; no env/read/write/run grants",
            "productionAccess": False, "hostedBundlerLockEnforcement": "not verified"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deno", type=Path, required=True, help="Path to the exact verified Deno runtime")
    parser.add_argument("--cache-dir", type=Path, help="Isolated public-package cache; otherwise temporary")
    parser.add_argument("--receipt", type=Path)
    arguments = parser.parse_args()
    try:
        deno = arguments.deno.resolve(strict=True)
        with tempfile.TemporaryDirectory(prefix="ichart-edge-checks-") as temporary:
            cache = (arguments.cache_dir or Path(temporary)).resolve()
            receipt = run_checks(deno, cache)
        if arguments.receipt:
            arguments.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
        print("Frozen Edge dependency checks passed; deployed functions were not contacted or changed.")
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        raise SystemExit(str(error))
