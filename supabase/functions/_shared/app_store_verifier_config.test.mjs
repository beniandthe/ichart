import assert from "node:assert/strict";
import test from "node:test";

import {
  appStoreVerifierConfigurationFromEnv,
  appStoreVerifierEnvironmentProduction,
  appStoreVerifierEnvironmentSandbox,
  certificateBase64BodiesFromPEMBundle,
  normalizeAppStoreVerifierEnvironment,
} from "./app_store_verifier_config.mjs";

const fakeCertificateOne = "QUJDREVGR0g=";
const fakeCertificateTwo = "SUtMTU5PUFE=";

const fakePEMBundle = `
-----BEGIN CERTIFICATE-----
${fakeCertificateOne}
-----END CERTIFICATE-----

-----BEGIN CERTIFICATE-----
${fakeCertificateTwo.slice(0, 4)}
${fakeCertificateTwo.slice(4)}
-----END CERTIFICATE-----
`;

test("normalizes supported App Store verifier environments", () => {
  assert.equal(normalizeAppStoreVerifierEnvironment("sandbox"), appStoreVerifierEnvironmentSandbox);
  assert.equal(normalizeAppStoreVerifierEnvironment("Sandbox"), appStoreVerifierEnvironmentSandbox);
  assert.equal(normalizeAppStoreVerifierEnvironment("production"), appStoreVerifierEnvironmentProduction);
  assert.equal(normalizeAppStoreVerifierEnvironment("Production"), appStoreVerifierEnvironmentProduction);
  assert.equal(normalizeAppStoreVerifierEnvironment("localtesting"), null);
});

test("extracts base64 bodies from a PEM certificate bundle", () => {
  assert.deepEqual(
    certificateBase64BodiesFromPEMBundle(fakePEMBundle),
    [fakeCertificateOne, fakeCertificateTwo]
  );
});

test("reports missing required verifier environment", () => {
  const result = appStoreVerifierConfigurationFromEnv({});

  assert.equal(result.ok, false);
  assert.deepEqual(result.missing, [
    "APP_STORE_BUNDLE_ID",
    "APP_STORE_ENVIRONMENT",
    "APP_STORE_ROOT_CERTIFICATES_PEM",
  ]);
});

test("allows sandbox configuration without an App Apple ID", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.smartchart.app",
    APP_STORE_ENVIRONMENT: "Sandbox",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.bundleID, "com.smartchart.app");
  assert.equal(result.value.environment, appStoreVerifierEnvironmentSandbox);
  assert.equal(result.value.appAppleID, null);
  assert.deepEqual(result.value.rootCertificateBase64Bodies, [fakeCertificateOne, fakeCertificateTwo]);
});

test("requires App Apple ID for production verification", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.smartchart.app",
    APP_STORE_ENVIRONMENT: "Production",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.missing, ["APP_STORE_APP_APPLE_ID"]);
});

test("parses production App Apple ID", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.smartchart.app",
    APP_STORE_ENVIRONMENT: "Production",
    APP_STORE_APP_APPLE_ID: "1234567890",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.environment, appStoreVerifierEnvironmentProduction);
  assert.equal(result.value.appAppleID, 1_234_567_890);
});

test("rejects invalid verifier environment, app id, and certificate content", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.smartchart.app",
    APP_STORE_ENVIRONMENT: "Xcode",
    APP_STORE_APP_APPLE_ID: "not-a-number",
    APP_STORE_ROOT_CERTIFICATES_PEM: "not a pem bundle",
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.missing, []);
  assert.deepEqual(result.errors, [
    "APP_STORE_ENVIRONMENT must be Sandbox or Production.",
    "APP_STORE_ROOT_CERTIFICATES_PEM must include at least one PEM certificate block.",
    "APP_STORE_APP_APPLE_ID must be a positive integer.",
  ]);
});
