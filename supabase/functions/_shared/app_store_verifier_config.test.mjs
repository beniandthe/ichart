import assert from "node:assert/strict";
import test from "node:test";

import {
  appStoreVerifierConfigurationFromEnv,
  appStoreVerifierEnvironmentProduction,
  appStoreVerifierEnvironmentSandbox,
  certificateBase64BodiesFromPEMBundle,
  compactAppStoreJWSVerificationAllowed,
  normalizeAppStoreVerifierEnvironment,
} from "./app_store_verifier_config.mjs";
import {
  appStorePublicProductIDs,
  appStoreStagingProductIDs,
  isAppStoreProductID,
} from "./app_store_product_catalog.mjs";

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
    APP_STORE_BUNDLE_ID: "com.ichart.app",
    APP_STORE_ENVIRONMENT: "Sandbox",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.bundleID, "com.ichart.app");
  assert.equal(result.value.environment, appStoreVerifierEnvironmentSandbox);
  assert.equal(result.value.appAppleID, null);
  assert.deepEqual(result.value.rootCertificateBase64Bodies, [fakeCertificateOne, fakeCertificateTwo]);
  assert.equal(result.value.enableOnlineChecks, false);
  assert.equal(result.value.stagingStoreKitProducts, false);
});

test("isolated product mode requires explicit true, Sandbox, and the fixed staging project", () => {
  const base = {
    APP_STORE_BUNDLE_ID: "com.ichart.app",
    APP_STORE_ENVIRONMENT: "Sandbox",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
    SUPABASE_URL: "https://gfqpbikqvdgtjjgxrkgo.supabase.co",
  };
  const enabled = appStoreVerifierConfigurationFromEnv({ ...base, ICHART_STAGING_STOREKIT_PRODUCTS: "true" });
  assert.equal(enabled.ok, true);
  assert.equal(enabled.value.stagingStoreKitProducts, true);
  for (const override of [
    { ICHART_STAGING_STOREKIT_PRODUCTS: "sometimes" },
    { ICHART_STAGING_STOREKIT_PRODUCTS: "true", APP_STORE_ENVIRONMENT: "Production", APP_STORE_APP_APPLE_ID: "123" },
    { ICHART_STAGING_STOREKIT_PRODUCTS: "true", SUPABASE_URL: "https://production.example.test" },
    { ICHART_STAGING_STOREKIT_PRODUCTS: "true", SUPABASE_URL: "https://gfqpbikqvdgtjjgxrkgo.supabase.co.attacker.test" },
    { ICHART_STAGING_STOREKIT_PRODUCTS: "true", SUPABASE_URL: "" },
  ]) {
    assert.equal(appStoreVerifierConfigurationFromEnv({ ...base, ...override }).ok, false);
  }
  assert.equal(appStoreVerifierConfigurationFromEnv({ ...base, ICHART_STAGING_STOREKIT_PRODUCTS: "false" }).value.stagingStoreKitProducts, false);
});

test("requires App Apple ID for production verification", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.ichart.app",
    APP_STORE_ENVIRONMENT: "Production",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.missing, ["APP_STORE_APP_APPLE_ID"]);
});

test("parses production App Apple ID", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.ichart.app",
    APP_STORE_ENVIRONMENT: "Production",
    APP_STORE_APP_APPLE_ID: "1234567890",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.environment, appStoreVerifierEnvironmentProduction);
  assert.equal(result.value.appAppleID, 1_234_567_890);
  assert.equal(result.value.enableOnlineChecks, true);
});

test("allows explicit online verification check overrides", () => {
  const sandboxResult = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.ichart.app",
    APP_STORE_ENVIRONMENT: "Sandbox",
    APP_STORE_ENABLE_ONLINE_CHECKS: "true",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  });
  const productionResult = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.ichart.app",
    APP_STORE_ENVIRONMENT: "Production",
    APP_STORE_APP_APPLE_ID: "1234567890",
    APP_STORE_ENABLE_ONLINE_CHECKS: "false",
    APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  });

  assert.equal(sandboxResult.ok, true);
  assert.equal(sandboxResult.value.enableOnlineChecks, true);
  assert.equal(productionResult.ok, true);
  assert.equal(productionResult.value.enableOnlineChecks, false);
});

test("allows compact JWS fallback for production verifier failures", () => {
  assert.equal(compactAppStoreJWSVerificationAllowed({
    environment: appStoreVerifierEnvironmentProduction,
    enableOnlineChecks: true,
  }), true);
  assert.equal(compactAppStoreJWSVerificationAllowed({
    environment: appStoreVerifierEnvironmentProduction,
    enableOnlineChecks: false,
  }), true);
  assert.equal(compactAppStoreJWSVerificationAllowed({
    environment: appStoreVerifierEnvironmentSandbox,
    enableOnlineChecks: false,
  }), true);
  assert.equal(compactAppStoreJWSVerificationAllowed({
    environment: appStoreVerifierEnvironmentSandbox,
    enableOnlineChecks: true,
  }), false);
});

test("rejects invalid verifier environment, app id, and certificate content", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    APP_STORE_BUNDLE_ID: "com.ichart.app",
    APP_STORE_ENVIRONMENT: "Xcode",
    APP_STORE_APP_APPLE_ID: "not-a-number",
    APP_STORE_ENABLE_ONLINE_CHECKS: "sometimes",
    APP_STORE_ROOT_CERTIFICATES_PEM: "not a pem bundle",
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.missing, []);
  assert.deepEqual(result.errors, [
    "APP_STORE_ENVIRONMENT must be Sandbox or Production.",
    "APP_STORE_ROOT_CERTIFICATES_PEM must include at least one PEM certificate block.",
    "APP_STORE_APP_APPLE_ID must be a positive integer.",
    "APP_STORE_ENABLE_ONLINE_CHECKS must be true or false.",
  ]);
});


const productionOrigin = "https://pausvvwoazbvmzyrebwl.supabase.co";
const historicalStagingOrigin = "https://gfqpbikqvdgtjjgxrkgo.supabase.co";
const coordinatedQAOrigin = "https://yiuxduqhhbucsmooevxz.supabase.co";
const coordinatedQABase = {
  APP_STORE_BUNDLE_ID: "com.ichart.app",
  APP_STORE_ENVIRONMENT: "Sandbox",
  APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
  ICHART_STAGING_STOREKIT_PRODUCTS: "true",
  ICHART_COORDINATED_STAGING_QA: "true",
  SUPABASE_URL: coordinatedQAOrigin,
};

test("four verifier lanes preserve environment, endpoint mode and isolated product scope", async (t) => {
  const lanes = [
    { label: "normal production", env: { APP_STORE_ENVIRONMENT: "Production", APP_STORE_APP_APPLE_ID: "6782173484", SUPABASE_URL: productionOrigin }, environment: "Production", isolated: false, coordinated: false },
    { label: "normal Sandbox", env: { APP_STORE_ENVIRONMENT: "Sandbox", SUPABASE_URL: productionOrigin }, environment: "Sandbox", isolated: false, coordinated: false },
    { label: "historical fixed staging", env: { APP_STORE_ENVIRONMENT: "Sandbox", SUPABASE_URL: historicalStagingOrigin, ICHART_STAGING_STOREKIT_PRODUCTS: "true" }, environment: "Sandbox", isolated: true, coordinated: false },
    { label: "coordinated QA", env: coordinatedQABase, environment: "Sandbox", isolated: true, coordinated: true },
  ];
  for (const lane of lanes) {
    await t.test(lane.label, () => {
      const result = appStoreVerifierConfigurationFromEnv({
        APP_STORE_BUNDLE_ID: "com.ichart.app",
        APP_STORE_ROOT_CERTIFICATES_PEM: fakePEMBundle,
        ...lane.env,
      });
      assert.equal(result.ok, true);
      assert.equal(result.value.environment, lane.environment);
      assert.equal(result.value.stagingStoreKitProducts, lane.isolated);
      assert.equal(result.value.coordinatedStagingQA, lane.coordinated);
      for (const product of appStorePublicProductIDs) {
        assert.equal(isAppStoreProductID(product, result.value), !lane.isolated);
      }
      for (const product of appStoreStagingProductIDs) {
        assert.equal(isAppStoreProductID(product, result.value), lane.isolated);
      }
    });
  }
});

test("coordinated QA requires explicitly enabled isolated products and Sandbox", () => {
  for (const stagingFlag of [undefined, "", "false", "0", "no", "sometimes"]) {
    const env = { ...coordinatedQABase, ICHART_STAGING_STOREKIT_PRODUCTS: stagingFlag };
    const result = appStoreVerifierConfigurationFromEnv(env);
    assert.equal(result.ok, false, `Invalid isolated product flag: ${stagingFlag}`);
  }
  for (const environment of [undefined, "", "Production", "Xcode", "LocalTesting"]) {
    const result = appStoreVerifierConfigurationFromEnv({
      ...coordinatedQABase, APP_STORE_ENVIRONMENT: environment, APP_STORE_APP_APPLE_ID: "6782173484",
    });
    assert.equal(result.ok, false, `Invalid coordinated QA environment: ${environment}`);
  }
});

test("coordinated QA rejects production, historical, missing and altered origins", () => {
  for (const origin of [
    undefined, "", productionOrigin, historicalStagingOrigin,
    "http://yiuxduqhhbucsmooevxz.supabase.co", coordinatedQAOrigin + "/",
    coordinatedQAOrigin + "/functions/v1", coordinatedQAOrigin + "?project=other",
    coordinatedQAOrigin + "#fragment", coordinatedQAOrigin + ":443",
    coordinatedQAOrigin + ".attacker.invalid", "https://user@yiuxduqhhbucsmooevxz.supabase.co",
  ]) {
    const result = appStoreVerifierConfigurationFromEnv({ ...coordinatedQABase, SUPABASE_URL: origin });
    assert.equal(result.ok, false, `Invalid coordinated QA origin: ${origin}`);
  }
});

test("coordinated QA origin fails closed with missing false or malformed QA flag", () => {
  for (const qaFlag of [undefined, "", "false", "0", "no", "sometimes"]) {
    for (const stagingFlag of [undefined, "false", "true"]) {
      const result = appStoreVerifierConfigurationFromEnv({
        ...coordinatedQABase, ICHART_COORDINATED_STAGING_QA: qaFlag,
        ICHART_STAGING_STOREKIT_PRODUCTS: stagingFlag,
      });
      assert.equal(result.ok, false, `Invalid QA/product flag pair: ${qaFlag}/${stagingFlag}`);
    }
  }
});

test("historical staging flag alone cannot select the new coordinated origin", () => {
  const legacy = appStoreVerifierConfigurationFromEnv({
    ...coordinatedQABase, ICHART_COORDINATED_STAGING_QA: undefined, SUPABASE_URL: historicalStagingOrigin,
  });
  assert.equal(legacy.ok, true);
  assert.equal(legacy.value.coordinatedStagingQA, false);
  const explicitLegacy = appStoreVerifierConfigurationFromEnv({
    ...coordinatedQABase, ICHART_COORDINATED_STAGING_QA: "false", SUPABASE_URL: historicalStagingOrigin,
  });
  assert.equal(explicitLegacy.ok, true);
  assert.equal(explicitLegacy.value.stagingStoreKitProducts, true);
  assert.equal(explicitLegacy.value.coordinatedStagingQA, false);
});

test("malformed QA flag also fails closed outside the coordinated project", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    ...coordinatedQABase, ICHART_STAGING_STOREKIT_PRODUCTS: "false",
    ICHART_COORDINATED_STAGING_QA: "not-a-boolean", SUPABASE_URL: productionOrigin,
  });
  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("ICHART_COORDINATED_STAGING_QA must be true or false."));
});

test("Deno style trusted environment reader selects coordinated QA without client inputs", () => {
  const result = appStoreVerifierConfigurationFromEnv({ get: (key) => coordinatedQABase[key] });
  assert.equal(result.ok, true);
  assert.equal(result.value.coordinatedStagingQA, true);
  assert.equal(result.value.stagingStoreKitProducts, true);
});

test("request-like account or header fields cannot enable the trusted QA mode", () => {
  const result = appStoreVerifierConfigurationFromEnv({
    ...coordinatedQABase,
    ICHART_COORDINATED_STAGING_QA: undefined,
    owner_id: "synthetic-qa-owner",
    headers: { "ICHART_COORDINATED_STAGING_QA": "true" },
    user_metadata: { coordinated_staging_qa: true },
  });
  assert.equal(result.ok, false);
});
