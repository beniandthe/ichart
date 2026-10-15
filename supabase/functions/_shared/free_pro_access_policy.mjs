// Product policy, not a billing entitlement. No clock, trial expiry, environment
// variable or automatic paid re-enable exists. Ending this phase is a separate
// source/deployment and customer-consent decision. Keep in sync with the guarded
// database migration; never rewrite real subscription/notification evidence.
export const freeProAccessPolicy = Object.freeze({
  policyID: "free-pro-2026-10-15",
  active: true,
});

export function applyFreeProAccessToOfferConfiguration(configuration) {
  if (!freeProAccessPolicy.active) return configuration;
  return { ...configuration, enabled: false, reason: "free_access_active",
    freeAccessPhaseActive: true, accessPolicyID: freeProAccessPolicy.policyID };
}
