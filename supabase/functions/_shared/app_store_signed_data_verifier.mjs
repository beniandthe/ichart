import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";

import {
  appStoreVerifierConfigurationFromEnv,
  appStoreVerifierEnvironmentProduction,
} from "./app_store_verifier_config.mjs";

export function createAppStoreSignedDataVerifiers(env = Deno.env) {
  const config = appStoreVerifierConfigurationFromEnv(env);
  if (!config.ok) {
    return {};
  }

  try {
    const verifier = new SignedDataVerifier(
      config.value.rootCertificateBase64Bodies.map((body) => Buffer.from(body, "base64")),
      true,
      appStoreLibraryEnvironment(config.value.environment),
      config.value.bundleID,
      config.value.appAppleID ?? undefined
    );

    return {
      verifyAndDecodeNotification: (signedPayload) => verifier.verifyAndDecodeNotification(signedPayload),
      verifyAndDecodeTransaction: (signedTransactionInfo) => verifier.verifyAndDecodeTransaction(signedTransactionInfo),
      verifyAndDecodeRenewalInfo: (signedRenewalInfo) => verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo),
    };
  } catch {
    return {};
  }
}

function appStoreLibraryEnvironment(environment) {
  if (environment === appStoreVerifierEnvironmentProduction) {
    return Environment.PRODUCTION;
  }

  return Environment.SANDBOX;
}
