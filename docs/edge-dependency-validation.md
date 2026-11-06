# Frozen Edge dependency validation

The three StoreKit Edge functions each have a function-local `deno.json` and
committed `deno.lock`. The audited graph pins Apple server library **3.1.0** and
both the direct and Apple-transitive jsrsasign copies to **11.1.5**. All npm
entries have generated integrity records. Do not edit lock hashes by hand.

`scripts/edge_dependency_toolchain.json` pins Deno **2.9.8** and the official
release archive SHA-256 values for macOS arm64 and Linux x86-64. The separate
**Frozen Edge dependencies** workflow verifies the Linux archive before execution;
it does not install a global runtime or deploy functions. The source of the
checks is `scripts/run_edge_dependency_checks.py`.

## Run locally

Use an isolated, checksum-verified runtime matching the toolchain file:

```sh
python3 scripts/run_edge_dependency_checks.py \
  --deno /absolute/path/to/verified/deno \
  --cache-dir /private/tmp/ichart-edge-public-package-cache \
  --receipt /private/tmp/ichart-frozen-edge-dependencies.json
```

The preparation step downloads public npm dependencies into that cache with the
committed locks frozen. It enables no npm lifecycle scripts and executes no
application entrypoints. The runner gives Deno a clean environment without
service keys, user npm configuration or production settings. Its child process
uses a task-owned home/config directory and an empty `.npmrc`; the host home and
environment are unchanged. Preparation and the
stale-lock negative control may consult the public npm registry; application tests
execute separately with network denied and cached-only resolution.

Validation checks every actual entrypoint against its own frozen lock, rejects
any extra/older jsrsasign copy and establishes Apple's dependency edge. A negative
control removes a required specifier from a temporary lock and requires Deno to
reject the stale graph. The committed locks must remain byte-for-byte unchanged.

The execution step uses `--cached-only --deny-net --no-prompt`, with no environment,
file, subprocess or broad permission grants. It requires at least 15 passing tests:

- The real Apple SDK creates and signs synthetic ES256 requests through its
  intercepted transport; no request goes to Apple or Supabase.
- An independently OpenSSL-encoded test CA/intermediate/leaf exercises the actual
  patched X509 parser, Apple-specific OIDs, chain, date, JWS and payload-scope checks.
- Controlled unsupported platform-key behavior exercises the real KJUR fallback,
  including rejection of a corrupted signature and an untrusted root.
- Malformed DER, incomplete chains, missing OIDs, non-CA intermediates, unsupported
  algorithms, wrong bundle/environment/date and tampered signatures are rejected
  at their expected verification stages.

The committed private key is prominently marked **public synthetic test material**.
Its root is supplied only to the test configuration. Never add it to production
trust or use the key outside these tests. The offline signed date lies within the
fixture's recorded validity period, so tests do not depend on wall-clock expiry.
To deliberately generate replacement fixtures, use OpenSSL and write a new file:

```sh
python3 scripts/generate_app_store_verifier_fixture.py \
  --output /private/tmp/new-public-synthetic-verifier-fixture.json
```

Review replacement provenance before changing the committed fixture. Generation
uses no Apple certificates, customer data or production signing material.

## Deployment boundary and remaining lifecycle debt

This gate proves the checked source's frozen dependency graph and offline crypto
controls. It does not prove the provenance of existing deployed bundles or that
every hosted deployment path enforces these locks. Supabase CLI **2.109.0** source
uploads configuration and local imports without explicitly adding `deno.lock`;
its local Edge Runtime has lock discovery and v5 compatibility. Hosted packaging
and stale-lock rejection must be verified before claiming deployment
reproducibility. Do not bypass this limit by silently changing verification
algorithms, roots or fallback eligibility.

jsrsasign support ended August 14, 2026. Its final patched release removes the
currently catalogued affected versions; it does not restore maintenance. Apple's
latest published Node SDK is still 3.1.0 and itself uses jsrsasign for certificate
extensions and OCSP. A complete replacement requires a separately validated SDK
release or reviewed replacement of both dependency paths. This patch keeps the
current certificate and signature verification behavior unchanged. A transitive
`punycode` deprecation warning is currently emitted during the offline SDK tests.

Primary references: [official Deno release](https://github.com/denoland/deno/releases/tag/v2.9.8),
[Deno frozen locks](https://docs.deno.com/runtime/reference/deno_json/#lockfile),
[Supabase per-function dependencies](https://supabase.com/docs/guides/functions/dependencies),
[CLI upload implementation](https://github.com/supabase/cli/blob/v2.109.0/apps/cli/src/shared/functions/deploy.ts#L978),
[Edge Runtime lock support](https://github.com/supabase/edge-runtime/blob/v1.73.13/deno/args/lockfile.rs#L136),
[jsrsasign support notice](https://github.com/kjur/jsrsasign), and
[Apple 3.1.0 dependency manifest](https://github.com/apple/app-store-server-library-node/blob/v3.1.0/package.json).
