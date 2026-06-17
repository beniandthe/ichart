export const appStoreVerifierEnvironmentSandbox = "Sandbox";
export const appStoreVerifierEnvironmentProduction = "Production";

export const appStoreVerifierEnvironmentKeys = Object.freeze({
  bundleID: "APP_STORE_BUNDLE_ID",
  environment: "APP_STORE_ENVIRONMENT",
  appAppleID: "APP_STORE_APP_APPLE_ID",
  rootCertificatesPEM: "APP_STORE_ROOT_CERTIFICATES_PEM",
});

export function appStoreVerifierConfigurationFromEnv(env) {
  const bundleID = envString(env, appStoreVerifierEnvironmentKeys.bundleID);
  const environmentValue = envString(env, appStoreVerifierEnvironmentKeys.environment);
  const rootCertificatesPEM = envString(env, appStoreVerifierEnvironmentKeys.rootCertificatesPEM);
  const appAppleIDValue = envString(env, appStoreVerifierEnvironmentKeys.appAppleID);
  const missing = [];
  const errors = [];

  if (bundleID.length === 0) {
    missing.push(appStoreVerifierEnvironmentKeys.bundleID);
  }

  if (environmentValue.length === 0) {
    missing.push(appStoreVerifierEnvironmentKeys.environment);
  }

  if (rootCertificatesPEM.length === 0) {
    missing.push(appStoreVerifierEnvironmentKeys.rootCertificatesPEM);
  }

  const environment = normalizeAppStoreVerifierEnvironment(environmentValue);
  if (environmentValue.length > 0 && environment === null) {
    errors.push(`${appStoreVerifierEnvironmentKeys.environment} must be Sandbox or Production.`);
  }

  const rootCertificateBase64Bodies = certificateBase64BodiesFromPEMBundle(rootCertificatesPEM);
  if (rootCertificatesPEM.length > 0 && rootCertificateBase64Bodies.length === 0) {
    errors.push(`${appStoreVerifierEnvironmentKeys.rootCertificatesPEM} must include at least one PEM certificate block.`);
  }

  const appAppleID = parseOptionalAppAppleID(appAppleIDValue);
  if (appAppleIDValue.length > 0 && appAppleID === null) {
    errors.push(`${appStoreVerifierEnvironmentKeys.appAppleID} must be a positive integer.`);
  }

  if (environment === appStoreVerifierEnvironmentProduction && appAppleID === null) {
    missing.push(appStoreVerifierEnvironmentKeys.appAppleID);
  }

  if (missing.length > 0 || errors.length > 0) {
    return {
      ok: false,
      missing: Array.from(new Set(missing)),
      errors,
    };
  }

  return {
    ok: true,
    value: {
      bundleID,
      environment,
      appAppleID,
      rootCertificateBase64Bodies,
    },
  };
}

export function normalizeAppStoreVerifierEnvironment(environment) {
  const value = normalizedString(environment).toLowerCase();

  if (value === "sandbox") {
    return appStoreVerifierEnvironmentSandbox;
  }

  if (value === "production") {
    return appStoreVerifierEnvironmentProduction;
  }

  return null;
}

export function certificateBase64BodiesFromPEMBundle(pemBundle) {
  const value = normalizedString(pemBundle);
  if (value.length === 0) {
    return [];
  }

  const matches = Array.from(value.matchAll(
    /-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----/g
  ));

  return matches
    .map((match) => normalizedBase64Body(match[1]))
    .filter((body) => body.length > 0 && isBase64CertificateBody(body));
}

function envString(env, key) {
  if (typeof env?.get === "function") {
    return normalizedString(env.get(key));
  }

  return normalizedString(env?.[key]);
}

function parseOptionalAppAppleID(value) {
  const stringValue = normalizedString(value);
  if (stringValue.length === 0) {
    return null;
  }

  if (!/^\d+$/.test(stringValue)) {
    return null;
  }

  const numberValue = Number(stringValue);
  if (!Number.isSafeInteger(numberValue) || numberValue <= 0) {
    return null;
  }

  return numberValue;
}

function normalizedBase64Body(value) {
  return normalizedString(value).replace(/\s+/g, "");
}

function isBase64CertificateBody(value) {
  return /^[A-Za-z0-9+/]+={0,2}$/.test(value) && value.length % 4 === 0;
}

function normalizedString(value) {
  if (value === null || value === undefined) {
    return "";
  }

  return String(value).trim();
}
