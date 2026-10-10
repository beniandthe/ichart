import { complimentaryCampaignConfigurationFromEnv } from "./complimentary_offer_campaign.mjs";
import { createLegacyPromotionalOfferSigner } from "./complimentary_offer_signature.mjs";
import { createAppStoreSignedDataVerifiers } from "./app_store_signed_data_verifier.mjs";
import { createFreshComplimentaryAppleDependencies } from "./complimentary_offer_apple_client.mjs";
import { createSupabaseComplimentaryOfferDependencies } from "./supabase_complimentary_offer_store.mjs";

export function createComplimentaryOfferRuntime(env = globalThis.Deno?.env) {
  let configuration = complimentaryCampaignConfigurationFromEnv(env);
  const store = createSupabaseComplimentaryOfferDependencies(env);
  // Keep global claim verification unchanged, including its existing production
  // -> Sandbox signature-verification fallback. Only this campaign's API target
  // and policy use the separate, explicitly selected environment.
  const verifiers = createAppStoreSignedDataVerifiers(env);
  const apple = createFreshComplimentaryAppleDependencies(env, { verifiers, environment: configuration.environment });
  let signPromotionalOffer;
  if (configuration.enabled) {
    try {
      signPromotionalOffer = createLegacyPromotionalOfferSigner({ bundleID: configuration.bundleID,
        keyID: configuration.keyID, privateKeyPEM: configuration.privateKeyPEM.replace(/\\n/g, "\n") });
    } catch {
      configuration = { ...configuration, enabled: false, reason: "campaign_not_configured" };
    }
    if (typeof store.authenticatedUserID !== "function" || typeof verifiers.verifyAndDecodeTransaction !== "function"
        || typeof verifiers.verifyAndDecodeRenewalInfo !== "function" || typeof apple.fetchFreshAppleSnapshot !== "function") {
      configuration = { ...configuration, enabled: false, reason: "campaign_not_configured" };
    }
  }
  return { configuration, dependencies: { ...store, ...verifiers, ...apple, signPromotionalOffer,
    recordPendingVerificationDiagnostic: (checks, discountCategory) => console.log(JSON.stringify({
      event: "complimentary_pending_verification_v1", checks, discountCategory,
    })) } };
}
