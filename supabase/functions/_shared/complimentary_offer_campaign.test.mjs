import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { Buffer } from "node:buffer";
import { complimentaryCampaignConfigurationFromEnv, complimentaryCampaignID, complimentaryOfferIDs,
  evaluateComplimentaryCampaign, handleComplimentaryOfferRequest } from "./complimentary_offer_campaign.mjs";
import { createLegacyPromotionalOfferSigner, promotionalOfferSignaturePayload } from "./complimentary_offer_signature.mjs";

const owner = "11111111-1111-4111-8111-111111111111";
const attemptID = "22222222-2222-4222-8222-222222222222";
const monthly = "com.ichart.app.pro.monthly";
const annual = "com.ichart.app.pro.annual";
const now = Date.parse("2026-10-08T12:00:00Z");
const configuration = { campaignID: complimentaryCampaignID, enabled: true, startsAt: now - 86400000,
  endsAt: now + 86400000, bundleID: "com.ichart.app", environment: "production" };
const transaction = (extra = {}) => ({ bundleId: "com.ichart.app", productId: monthly, environment: "Production",
  appAccountToken: owner, type: "Auto-Renewable Subscription", inAppOwnershipType: "PURCHASED",
  originalTransactionId: "1000", transactionId: "1001", purchaseDate: now - 10000, expiresDate: now + 100000, ...extra });
const renewal = (extra = {}) => ({ productId: monthly, autoRenewProductId: monthly, environment: "Production",
  originalTransactionId: "1000", autoRenewStatus: 1, renewalDate: now + 100000, ...extra });
const active = (extra = {}, renewalExtra = {}) => ({ status: 1, transaction: transaction(extra), renewal: renewal(renewalExtra) });
const evaluate = (snapshot = {}, extra = {}) => evaluateComplimentaryCampaign({ ownerID: owner, productID: monthly,
  configuration, snapshot, ledger: null, now, ...extra });

test("campaign is disabled by default and incomplete enabled config fails closed", () => {
  assert.equal(complimentaryCampaignConfigurationFromEnv({}).enabled, false);
  assert.equal(complimentaryCampaignConfigurationFromEnv({ ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED: "true" }).reason, "campaign_not_configured");
});
test("complete explicit server config enables only fixed campaign", () => {
  const configured = complimentaryCampaignConfigurationFromEnv({ ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED: "true",
    ICHART_COMPLIMENTARY_CAMPAIGN_STARTS_AT: "2026-10-01T00:00:00Z", ICHART_COMPLIMENTARY_CAMPAIGN_ENDS_AT: "2026-11-01T00:00:00Z",
    APP_STORE_BUNDLE_ID: "com.ichart.app", APP_STORE_ENVIRONMENT: "Production", APP_STORE_SUBSCRIPTION_KEY_ID: "ABCDEFGHIJ",
    APP_STORE_SUBSCRIPTION_KEY_P8: "-----BEGIN PRIVATE KEY-----", APP_STORE_ISSUER_ID: owner });
  assert.equal(configured.enabled, true);
  assert.equal(configured.campaignID, complimentaryCampaignID);
});
test("campaign Sandbox override does not change global production setting; invalid override fails closed", () => {
  const env = { APP_STORE_ENVIRONMENT: "Production", ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT: "Sandbox",
    ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED: "true", APP_STORE_BUNDLE_ID: "com.ichart.app",
    ICHART_COMPLIMENTARY_CAMPAIGN_STARTS_AT: "2026-10-01T00:00:00Z", ICHART_COMPLIMENTARY_CAMPAIGN_ENDS_AT: "2026-11-01T00:00:00Z",
    APP_STORE_SUBSCRIPTION_KEY_ID: "ABCDEFGHIJ", APP_STORE_SUBSCRIPTION_KEY_P8: "-----BEGIN PRIVATE KEY-----", APP_STORE_ISSUER_ID: owner,
    ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS: JSON.stringify([owner]) };
  assert.equal(complimentaryCampaignConfigurationFromEnv(env).environment, "sandbox");
  assert.equal(complimentaryCampaignConfigurationFromEnv(env).enabled, true);
  assert.equal(env.APP_STORE_ENVIRONMENT, "Production");
  env.ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT = "unexpected";
  env.ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED = "true";
  assert.equal(complimentaryCampaignConfigurationFromEnv(env).enabled, false);
  assert.equal(complimentaryCampaignConfigurationFromEnv(env).environment, null);
});
test("new customer gets conditional intro metadata, not a promotional signature", () => {
  assert.equal(evaluate().decision, "introductory");
  assert.equal(evaluate().offerID, undefined);
});
test("campaign window is half-open", () => {
  assert.equal(evaluate({}, { now: configuration.startsAt - 1 }).reason, "campaign_not_started");
  assert.equal(evaluate({}, { now: configuration.endsAt }).reason, "campaign_ended");
});
for (const productID of [monthly, annual]) {
  test(`active ${productID} schedules only same product at next billing event`, () => {
    const entry = active({ productId: productID }, { productId: productID, autoRenewProductId: productID });
    const result = evaluate({ history: [entry.transaction], statuses: [entry] }, { productID });
    assert.equal(result.decision, "scheduledPromotional");
    assert.equal(result.activation, "nextBillingEvent");
    assert.equal(result.offerID, complimentaryOfferIDs[productID]);
    const other = productID === monthly ? annual : monthly;
    assert.equal(evaluate({ statuses: [entry] }, { productID: other }).reason, "active_subscription_same_product_required");
  });
}
test("canceled but unexpired same-product subscription still requires explicit scheduled purchase", () => {
  assert.equal(evaluate({ statuses: [active({}, { autoRenewStatus: 0 })] }).decision, "scheduledPromotional");
});
test("lapsed prior introductory user can receive signed promotional offer", () => {
  const expired = transaction({ expiresDate: now - 1, purchaseDate: configuration.startsAt - 10000, offerType: 1 });
  const result = evaluate({ history: [expired], statuses: [{ status: 2, transaction: expired,
    renewal: renewal({ autoRenewStatus: 0, renewalDate: now - 1, offerType: 1 }) }] });
  assert.equal(result.decision, "promotional");
});
for (const status of [3, 4, 5, 99]) {
  test(`subscription status ${status} cannot receive a signature`, () => {
    assert.equal(evaluate({ statuses: [{ ...active(), status }] }).state, "unavailable");
  });
}
test("conflicting current or upcoming offer and crossgrade fail closed", () => {
  assert.equal(evaluate({ statuses: [active({}, { offerIdentifier: "another-offer" })] }).state, "unavailable");
  assert.equal(evaluate({ statuses: [active({ offerType: 1 })] }).state, "unavailable");
  assert.equal(evaluate({ statuses: [active({}, { autoRenewProductId: annual })] }).state, "unavailable");
});
test("tokenless, different-owner, Family Sharing, wrong environment and scope reject", () => {
  for (const fields of [{ appAccountToken: undefined }, { appAccountToken: attemptID }, { inAppOwnershipType: "FAMILY_SHARED" },
    { environment: "Sandbox" }, { bundleId: "another.app" }, { type: "Non-Consumable" }]) {
    assert.throws(() => evaluate({ history: [transaction(fields)] }), /ownership_or_scope/);
  }
});
test("verified pending Free P1M zero-price renewal establishes scheduled benefit", () => {
  const result = evaluate({ statuses: [active({}, { offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly],
    offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", renewalPrice: 0 })] });
  assert.equal(result.state, "scheduled");
  assert.equal(result.benefit.state, "scheduled");
  assert.equal(result.accessStartsAt, new Date(now + 100000).toISOString());
  assert.equal(result.accessEndsAt, null);
  assert.equal(result.estimatedAccessEndsAt, "2026-11-08T12:01:40.000Z");
  assert.equal(result.accessEndsAtIsEstimated, true);
});
test("issued ledger alone cannot claim scheduled benefit", () => {
  assert.equal(evaluate({}, { ledger: { state: "prepared", attemptID } }).state, "available");
});
test("verified one-month zero-priced upfront pending offer schedules only the known same-product benefit", () => {
  for (const productID of [monthly, annual]) {
    const entry = active({ productId: productID }, { productId: productID, autoRenewProductId: productID,
      offerType: 2, offerIdentifier: complimentaryOfferIDs[productID], offerDiscountType: "PAY_UP_FRONT",
      offerPeriod: "P1M", renewalPrice: 0 });
    const result = evaluate({ statuses: [entry] }, { productID });
    assert.equal(result.state, "scheduled"); assert.equal(result.decision, "scheduledPromotional");
    assert.equal(result.activation, "nextBillingEvent"); assert.equal(result.accessEndsAt, null);
    assert.equal(result.accessEndsAtIsEstimated, true); assert.equal(result.benefit.state, "scheduled");
    assert.equal(entry.renewal.offerDiscountType, "PAY_UP_FRONT");
  }
});
test("upfront pending quote cannot pass with missing, positive, multi-period or unrecognized terms", () => {
  for (const fields of [{ renewalPrice: undefined }, { renewalPrice: null }, { renewalPrice: '0' },
    { renewalPrice: 1 }, { renewalPrice: -1 }, { offerPeriod: undefined }, { offerPeriod: 'P2M' },
    { offerDiscountType: 'PAY_AS_YOU_GO' }, { offerDiscountType: 'ONE_TIME' },
    { offerDiscountType: 'pay_up_front' }, { offerDiscountType: undefined }, { autoRenewStatus: 0 },
    { autoRenewProductId: annual }, { offerIdentifier: complimentaryOfferIDs[annual] },
    { renewalDate: now - 1 }, { renewalDate: undefined }]) {
    const result = evaluate({ statuses: [active({}, { offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly],
      offerDiscountType: "PAY_UP_FRONT", offerPeriod: "P1M", renewalPrice: 0, ...fields })] });
    assert.equal(result.state, "unavailable");
    assert.equal(result.benefit, undefined);
  }
});
for (const productID of [monthly, annual]) {
  for (const offerDiscountType of ["FREE_TRIAL", "PAY_UP_FRONT"]) {
    test(`completed ${productID} ${offerDiscountType} uses actual zero-charge promotional transaction dates`, () => {
      const gift = transaction({ productId: productID, offerType: 2, offerIdentifier: complimentaryOfferIDs[productID],
        offerDiscountType, offerPeriod: "P1M", price: 0 });
      for (const ledger of [null, { state: "scheduled", productID, decision: "scheduledPromotional",
        offerID: complimentaryOfferIDs[productID] }]) {
        const result = evaluate({ history: [gift] }, { productID, ledger });
        assert.equal(result.state, "redeemed");
        assert.equal(result.decision, ledger ? "scheduledPromotional" : "promotional");
        assert.equal(result.activation, ledger ? "nextBillingEvent" : "immediate");
        assert.equal(result.accessStartsAt, new Date(gift.purchaseDate).toISOString());
        assert.equal(result.accessEndsAt, new Date(gift.expiresDate).toISOString());
        assert.equal(result.benefit.transactionID, gift.transactionId);
        assert.equal(result.benefit.state, "redeemed");
        assert.equal(result.estimatedAccessEndsAt, undefined);
        assert.equal(result.accessEndsAtIsEstimated, undefined);
        assert.equal(gift.offerDiscountType, offerDiscountType);
      }
    });
  }
  test(`completed ${productID} upfront offer rejects unverified price, duration, mode and product offer`, () => {
    const other = productID === monthly ? annual : monthly;
    for (const fields of [{ price: undefined }, { price: null }, { price: "0" }, { price: 1 }, { price: -1 },
      { price: NaN }, { price: Infinity }, { offerPeriod: undefined }, { offerPeriod: null }, { offerPeriod: "P2M" },
      { offerPeriod: "P2W" }, { offerDiscountType: undefined }, { offerDiscountType: null },
      { offerDiscountType: "PAY_AS_YOU_GO" }, { offerDiscountType: "ONE_TIME" }, { offerDiscountType: "pay_up_front" },
      { offerIdentifier: complimentaryOfferIDs[other] }]) {
      const gift = transaction({ productId: productID, offerType: 2, offerIdentifier: complimentaryOfferIDs[productID],
        offerDiscountType: "PAY_UP_FRONT", offerPeriod: "P1M", price: 0, ...fields });
      const result = evaluate({ history: [gift] }, { productID });
      assert.equal(result.state, "unavailable");
      assert.equal(result.reason, "verified_offer_terms_mismatch");
      assert.equal(result.benefit.state, "redeemed");
    }
    for (const offerIdentifier of [undefined, null, "unrecognized-offer"]) {
      const gift = transaction({ productId: productID, offerType: 2, offerIdentifier,
        offerDiscountType: "PAY_UP_FRONT", offerPeriod: "P1M", price: 0 });
      const result = evaluate({ history: [gift], statuses: [active(gift)] }, { productID });
      assert.equal(result.state, "unavailable");
      assert.equal(result.benefit, undefined);
    }
  });
  test(`completed ${productID} introductory offer still requires FREE_TRIAL`, () => {
    const gift = transaction({ productId: productID, offerType: 1, offerDiscountType: "PAY_UP_FRONT", offerPeriod: "P1M", price: 0 });
    const result = evaluate({ history: [gift] }, { productID });
    assert.equal(result.state, "unavailable");
    assert.equal(result.benefit, undefined);
  });
  test(`completed ${productID} upfront offer remains consumed after expiry, refund, upgrade or duplicate`, () => {
    const gift = transaction({ productId: productID, offerType: 2, offerIdentifier: complimentaryOfferIDs[productID],
      offerDiscountType: "PAY_UP_FRONT", offerPeriod: "P1M", price: 0 });
    const ended = { ...gift, expiresDate: now - 1 };
    const duplicate = { ...gift, transactionId: "1002", purchaseDate: now - 1000 };
    const result = evaluate({ history: [duplicate, ended] }, { productID, now: configuration.endsAt + 1 });
    assert.equal(result.state, "redeemed");
    assert.equal(result.accessStartsAt, new Date(ended.purchaseDate).toISOString());
    assert.equal(result.accessEndsAt, new Date(ended.expiresDate).toISOString());
    assert.equal(result.benefit.transactionID, ended.transactionId);
    const other = productID === monthly ? annual : monthly;
    assert.equal(evaluate({ history: [gift] }, { productID: other }).reason, "campaign_already_used_on_other_product");
    for (const fields of [{ revocationDate: now - 1 }, { isUpgraded: true }]) {
      const unavailable = evaluate({ history: [{ ...gift, ...fields }, duplicate] }, { productID });
      assert.equal(unavailable.state, "unavailable");
      assert.equal(unavailable.reason, "campaign_already_used");
      assert.equal(unavailable.benefit.state, "redeemed");
      assert.equal(unavailable.benefit.transactionID, gift.transactionId);
    }
  });
}
test("prospective zero-charge renewal price cannot substitute for completed transaction price", () => {
  const gift = transaction({ offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly],
    offerDiscountType: "PAY_UP_FRONT", offerPeriod: "P1M", renewalPrice: 0 });
  const result = evaluate({ history: [gift] });
  assert.equal(result.state, "unavailable");
  assert.equal(result.reason, "verified_offer_terms_mismatch");
});
test("completed promotional dates require finite numeric in-range ordered Apple timestamps", () => {
  for (const productID of [monthly, annual]) {
    for (const offerDiscountType of ["FREE_TRIAL", "PAY_UP_FRONT"]) {
      const gift = transaction({ productId: productID, offerType: 2, offerIdentifier: complimentaryOfferIDs[productID],
        offerDiscountType, offerPeriod: "P1M", price: 0 });
      const invalidDates = [undefined, null, String(now), NaN, Infinity, -1, 0, 8640000000000001];
      for (const fields of [...invalidDates.map(purchaseDate => ({ purchaseDate })),
        ...invalidDates.map(expiresDate => ({ expiresDate })),
        { expiresDate: gift.purchaseDate }, { expiresDate: gift.purchaseDate - 1 }]) {
        const result = evaluate({ history: [{ ...gift, ...fields }] }, { productID });
        assert.equal(result.state, "unavailable");
        assert.equal(result.reason, "verified_offer_terms_mismatch");
        assert.equal(result.benefit.state, "redeemed");
      }
    }
  }
});
test("pending zero-charge offer requires finite unexpired transaction evidence", () => {
  for (const expiresDate of [undefined, null, NaN, Infinity, String(now + 1000), now - 1]) {
    const result = evaluate({ statuses: [active({ expiresDate }, { offerType: 2,
      offerIdentifier: complimentaryOfferIDs[monthly], offerDiscountType: 'PAY_UP_FRONT',
      offerPeriod: 'P1M', renewalPrice: 0 })] });
    assert.equal(result.state, 'unavailable'); assert.equal(result.benefit, undefined);
  }
});
test("pending zero-price mismatch cannot claim a free month", () => {
  for (const fields of [{ renewalPrice: 1 }, { offerPeriod: "P2W" }, { offerDiscountType: "PAY_AS_YOU_GO" },
    { autoRenewStatus: 0 }, { autoRenewProductId: annual }]) {
    const result = evaluate({ statuses: [active({}, { offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly],
      offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", renewalPrice: 0, ...fields })] });
    assert.equal(result.state, "unavailable");
  }
});
test("verified current free month reports actual Apple transaction dates", () => {
  const gift = transaction({ offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly], offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 });
  const result = evaluate({ history: [gift] });
  assert.equal(result.state, "redeemed");
  assert.equal(result.accessEndsAt, new Date(gift.expiresDate).toISOString());
});
test("formerly scheduled gift preserves prepared decision when it becomes active", () => {
  const gift = transaction({ offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly], offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 });
  const result = evaluate({ history: [gift] }, { ledger: { state: "scheduled", productID: monthly,
    decision: "scheduledPromotional", offerID: complimentaryOfferIDs[monthly] } });
  assert.equal(result.state, "redeemed");
  assert.equal(result.decision, "scheduledPromotional");
  assert.equal(result.activation, "nextBillingEvent");
});
test("expired unrevoked gift remains redeemed with original ended dates and no new eligibility", () => {
  for (const offerType of [1, 2]) {
    const gift = transaction({ expiresDate: now - 1, offerType,
      ...(offerType === 2 ? { offerIdentifier: complimentaryOfferIDs[monthly] } : {}),
      offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 });
    const result = evaluate({ history: [gift] }, { now: configuration.endsAt + 1 });
    assert.equal(result.state, "redeemed");
    assert.equal(result.accessStartsAt, new Date(gift.purchaseDate).toISOString());
    assert.equal(result.accessEndsAt, new Date(gift.expiresDate).toISOString());
    assert.equal(result.benefit.transactionID, gift.transactionId);
    assert.equal(evaluate({ history: [gift] }, { productID: annual }).state, "unavailable");
    for (const fields of [{ price: 1 }, { offerPeriod: "P2W" }, { offerDiscountType: "PAY_AS_YOU_GO" }]) {
      assert.equal(evaluate({ history: [{ ...gift, ...fields }] }).state, "unavailable");
    }
  }
});
test("revoked or upgraded gift remains consumed and unavailable", () => {
  for (const fields of [{ revocationDate: now - 1 }, { isUpgraded: true }]) {
    const gift = transaction({ offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly], offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0, ...fields });
    const result = evaluate({ history: [gift] });
    assert.equal(result.state, "unavailable");
    assert.equal(result.benefit.state, "redeemed");
  }
});
test("benefit ledger prevents another product or reinstall benefit", () => {
  assert.equal(evaluate({}, { ledger: { state: "redeemed", productID: annual } }).reason, "campaign_already_used");
});
test("first verified gift remains consumed rather than selecting a later duplicate", () => {
  const first = transaction({ transactionId: "1001", purchaseDate: now - 50000, expiresDate: now - 1,
    offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly], offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 });
  const duplicate = { ...first, transactionId: "1002", purchaseDate: now - 10000, expiresDate: now + 100000 };
  const result = evaluate({ history: [duplicate, first] });
  assert.equal(result.state, "redeemed");
  assert.equal(result.accessStartsAt, new Date(first.purchaseDate).toISOString());
  assert.equal(result.accessEndsAt, new Date(first.expiresDate).toISOString());
  assert.equal(result.benefit.transactionID, "1001");
});
test("late introductory completion uses current trusted predeadline authorization without a grace deadline", () => {
  const approvedAt = configuration.endsAt + 14 * 86400000;
  const gift = transaction({ purchaseDate: approvedAt, expiresDate: approvedAt + 30 * 86400000,
    offerType: 1, offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 });
  const ledger = { state: "prepared", attemptID, productID: monthly, decision: "introductory", offerID: null,
    environment: "production", authorizedAt: now };
  const result = evaluate({ history: [gift], statuses: [{ status: 1, transaction: gift, renewal: {} }] }, { ledger, now: approvedAt + 1 });
  assert.equal(result.state, "redeemed");
  assert.equal(result.accessStartsAt, new Date(approvedAt).toISOString());
  for (const mutation of [{ attemptID: null }, { environment: "sandbox" }, { productID: annual },
    { authorizedAt: configuration.endsAt }, { authorizedAt: configuration.startsAt - 1 }, { decision: "promotional" }]) {
    assert.equal(evaluate({ history: [gift] }, { ledger: { ...ledger, ...mutation }, now: approvedAt + 1 }).state, "unavailable");
  }
});
test("late introductory receipt with wrong terms or predating authorization never consumes campaign", () => {
  const ledger = { state: "prepared", attemptID, productID: monthly, decision: "introductory", offerID: null,
    environment: "production", authorizedAt: now };
  const gift = transaction({ purchaseDate: configuration.endsAt + 1, expiresDate: configuration.endsAt + 100000,
    offerType: 1, offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 });
  for (const mutation of [{ offerPeriod: "P2W" }, { price: 1 }, { purchaseDate: configuration.startsAt - 1 }]) {
    const result = evaluate({ history: [{ ...gift, ...mutation }] }, { ledger, now: configuration.endsAt + 2 });
    assert.equal(result.state, "unavailable");
    assert.equal(result.benefit, undefined);
  }
});

function handlerFixture(extra = {}) {
  const calls = [];
  let ledger = null;
  const dependencies = {
    authenticatedUserID: async () => owner,
    readCampaignLedger: async () => ledger,
    readSubscriptionSeed: async () => null,
    verifyAndDecodeTransaction: async () => transaction(),
    fetchFreshAppleSnapshot: async () => ({ history: [], statuses: [] }),
    reserveCampaignAttempt: async (input) => { calls.push(input); ledger = { state: "prepared", attemptID: input.attemptID,
      productID: input.productID, decision: input.decision, offerID: input.offerID, environment: input.environment, authorizedAt: input.timestamp };
      return { ok: true, attempt: { ...input } }; },
    recordCampaignBenefit: async (input) => { calls.push(input); return { ok: true }; },
    signPromotionalOffer: async (input) => { calls.push(input); return { keyID: "ABCDEFGHIJ", signature: "test", ...input }; },
    ...extra,
  };
  const request = async (body, clock = () => now) => {
    const response = await handleComplimentaryOfferRequest(new Request("https://example.test", { method: "POST", body: JSON.stringify({ schemaVersion: 1, productID: monthly, ...body }) }), dependencies, configuration, clock);
    return { status: response.status, body: await response.json() };
  };
  return { calls, request };
}
test("status never issues a signature or consumes preparation", async () => {
  const fixture = handlerFixture();
  const result = await fixture.request({ action: "status" });
  assert.equal(result.body.state, "available");
  assert.equal(result.body.signature, undefined);
  assert.equal(fixture.calls.length, 0);
});
test("disabled campaign requires real auth but never touches missing ledger or Apple configuration", async () => {
  const dependencies = { authenticatedUserID: async () => owner,
    readCampaignLedger: async () => { throw new Error("migration not deployed"); },
    readSubscriptionSeed: async () => { throw new Error("do not read"); },
    fetchFreshAppleSnapshot: async () => { throw new Error("do not fetch"); } };
  const request = new Request("https://example.test", { method: "POST", body: JSON.stringify({ schemaVersion: 1, action: "status", productID: monthly }) });
  const response = await handleComplimentaryOfferRequest(request, dependencies,
    { ...configuration, enabled: false, reason: "campaign_disabled" }, () => now);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).reason, "campaign_disabled");
});
test("new prepare at cutoff refuses independently before reading a recoverable ledger or signing", async () => {
  const dependencies = { authenticatedUserID: async () => owner,
    readCampaignLedger: async () => { throw new Error("must not read"); },
    signPromotionalOffer: async () => { throw new Error("must not sign"); } };
  const response = await handleComplimentaryOfferRequest(new Request("https://example.test", { method: "POST",
    body: JSON.stringify({ schemaVersion: 1, action: "prepare", productID: monthly, attemptID }) }), dependencies, configuration, () => configuration.endsAt);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.reason, "campaign_ended");
  assert.equal(body.state, "unavailable");
  assert.equal(body.signature, undefined);
});
test("prepare arriving before cutoff but completing checks at cutoff issues no authorization", async () => {
  const times = [configuration.endsAt - 1, configuration.endsAt];
  const dependencies = { authenticatedUserID: async () => owner, readCampaignLedger: async () => null,
    readSubscriptionSeed: async () => null, reserveCampaignAttempt: async () => { throw new Error("must not reserve"); } };
  const response = await handleComplimentaryOfferRequest(new Request("https://example.test", { method: "POST",
    body: JSON.stringify({ schemaVersion: 1, action: "prepare", productID: monthly, attemptID }) }), dependencies, configuration, () => times.shift());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).reason, "campaign_ended");
});
for (const decision of ["introductory", "promotional"]) {
  test(`async ${decision} reservation crossing cutoff preserves recovery but returns no authorization`, async () => {
    let time = configuration.endsAt - 1;
    let persisted;
    let signerCalls = 0;
    const expired = transaction({ expiresDate: now - 1 });
    const fixture = handlerFixture({
      readCampaignLedger: async () => persisted ?? null,
      readSubscriptionSeed: async () => decision === "promotional" ? { originalTransactionID: "1000" } : null,
      fetchFreshAppleSnapshot: async () => ({ history: [expired], statuses: [{ status: 2, transaction: expired,
        renewal: renewal({ autoRenewStatus: 0, renewalDate: now - 1 }) }] }),
      reserveCampaignAttempt: async (input) => {
        await Promise.resolve();
        persisted = { state: "prepared", attemptID: input.attemptID, productID: input.productID,
          decision: input.decision, offerID: input.offerID, environment: input.environment, authorizedAt: input.timestamp };
        time = configuration.endsAt;
        return { ok: true, attempt: { ...input } };
      },
      signPromotionalOffer: async () => { signerCalls += 1; throw new Error("must not sign after cutoff"); },
    });
    const result = await fixture.request({ action: "prepare", attemptID }, () => time);
    assert.equal(result.status, 200);
    assert.equal(result.body.state, "unavailable");
    assert.equal(result.body.reason, "campaign_ended");
    assert.equal(result.body.canPrepare, false);
    assert.equal(result.body.signature, undefined);
    assert.equal(result.body.serverTime, new Date(configuration.endsAt).toISOString());
    assert.equal(signerCalls, 0);
    assert.equal(persisted.authorizedAt, configuration.endsAt - 1);
    const recovery = await fixture.request({ action: "status" }, () => time);
    assert.equal(recovery.body.state, "prepared");
    assert.equal(recovery.body.reason, "prepared_recovery_only");
    assert.equal(recovery.body.decision, decision);
    assert.equal(recovery.body.attemptID, attemptID);
    assert.equal(recovery.body.canPrepare, false);
    assert.equal(recovery.body.signature, undefined);
  });
}
test("async promotional signing crossing cutoff withholds completed signature and preserves recovery", async () => {
  let time = configuration.endsAt - 1;
  let signerCalls = 0;
  const expired = transaction({ expiresDate: now - 1 });
  const fixture = handlerFixture({ readSubscriptionSeed: async () => ({ originalTransactionID: "1000" }),
    fetchFreshAppleSnapshot: async () => ({ history: [expired], statuses: [{ status: 2, transaction: expired,
      renewal: renewal({ autoRenewStatus: 0, renewalDate: now - 1 }) }] }),
    signPromotionalOffer: async (input) => {
      signerCalls += 1;
      await Promise.resolve();
      time = configuration.endsAt;
      return { keyID: "ABCDEFGHIJ", signature: "must-not-be-returned", ...input };
    },
  });
  const result = await fixture.request({ action: "prepare", attemptID }, () => time);
  assert.equal(result.status, 200);
  assert.equal(result.body.state, "unavailable");
  assert.equal(result.body.reason, "campaign_ended");
  assert.equal(result.body.canPrepare, false);
  assert.equal(result.body.signature, undefined);
  assert.equal(result.body.serverTime, new Date(configuration.endsAt).toISOString());
  assert.equal(signerCalls, 1);
  assert.equal(fixture.calls[0].timestamp, configuration.endsAt - 1);
  const recovery = await fixture.request({ action: "status" }, () => time);
  assert.equal(recovery.body.state, "prepared");
  assert.equal(recovery.body.reason, "prepared_recovery_only");
  assert.equal(recovery.body.decision, "promotional");
  assert.equal(recovery.body.attemptID, attemptID);
  assert.equal(recovery.body.canPrepare, false);
  assert.equal(recovery.body.signature, undefined);
});
test("fresh intro prepare reserves attempt without signature", async () => {
  const fixture = handlerFixture();
  const result = await fixture.request({ action: "prepare", attemptID });
  assert.equal(result.body.state, "prepared");
  assert.equal(result.body.attemptID, attemptID);
  assert.equal(result.body.signature, undefined);
  assert.equal(fixture.calls.length, 1);
});
test("prepared status exposes matching recovery metadata but never signature", async () => {
  const fixture = handlerFixture({ readCampaignLedger: async () => ({ state: "prepared", attemptID,
    productID: monthly, decision: "introductory", offerID: null, environment: "production", authorizedAt: now }) });
  const result = await fixture.request({ action: "status" });
  assert.equal(result.body.state, "prepared");
  assert.equal(result.body.attemptID, attemptID);
  assert.equal(result.body.signature, undefined);
});
test("explicit separate promotional attempts use fresh nonces", async () => {
  const expired = transaction({ expiresDate: now - 1 });
  const fixture = handlerFixture({ readSubscriptionSeed: async () => ({ originalTransactionID: "1000" }),
    fetchFreshAppleSnapshot: async () => ({ history: [expired], statuses: [{ status: 2, transaction: expired, renewal: renewal({ autoRenewStatus: 0, renewalDate: now - 1 }) }] }) });
  await fixture.request({ action: "prepare", attemptID });
  await fixture.request({ action: "prepare", attemptID: owner, previousAttemptID: attemptID });
  assert.notEqual(fixture.calls[0].nonce, fixture.calls[2].nonce);
  assert.equal(fixture.calls[1].appAccountToken, owner);
});
test("confirm requires successful existing authority claim and current attempt", async () => {
  const fixture = handlerFixture();
  const result = await fixture.request({ action: "confirm", attemptID, signedTransactionInfo: "verified" });
  assert.equal(result.status, 409);
  assert.equal(result.body.reason, "verified_subscription_claim_required");
});
test("confirmed scheduled offer requires fresh Apple renewal not mere preparation", async () => {
  const fixture = handlerFixture({ readSubscriptionSeed: async () => ({ originalTransactionID: "1000" }),
    readCampaignLedger: async () => ({ state: "prepared", attemptID, decision: "scheduledPromotional", environment: "production" }),
    fetchFreshAppleSnapshot: async () => ({ history: [], statuses: [active({}, { offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly],
      offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", renewalPrice: 0 })] }) });
  const result = await fixture.request({ action: "confirm", attemptID, signedTransactionInfo: "verified" });
  assert.equal(result.status, 200);
  assert.equal(result.body.state, "scheduled");
  assert.equal(result.body.signature, undefined);
  assert.equal(result.body.attemptID, attemptID);
});
for (const productID of [monthly, annual]) {
  test(`completed ${productID} upfront scheduled purchase confirms with actual dates and same attempt`, async () => {
    const gift = transaction({ productId: productID, offerType: 2, offerIdentifier: complimentaryOfferIDs[productID],
      offerDiscountType: "PAY_UP_FRONT", offerPeriod: "P1M", price: 0 });
    const fixture = handlerFixture({
      readSubscriptionSeed: async () => ({ originalTransactionID: gift.originalTransactionId }),
      readCampaignLedger: async () => ({ state: "scheduled", attemptID, productID, decision: "scheduledPromotional",
        offerID: complimentaryOfferIDs[productID], environment: "production", authorizedAt: now - 10000 }),
      verifyAndDecodeTransaction: async () => gift,
      fetchFreshAppleSnapshot: async () => ({ history: [gift], statuses: [{ status: 1, transaction: gift, renewal: {} }] }),
      reserveCampaignAttempt: async () => { throw new Error("completed gift must not reserve"); },
      signPromotionalOffer: async () => { throw new Error("completed gift must not sign"); },
    });
    const result = await fixture.request({ action: "confirm", productID, attemptID, signedTransactionInfo: "verified-upfront-gift" });
    assert.equal(result.status, 200);
    assert.equal(result.body.state, "redeemed");
    assert.equal(result.body.decision, "scheduledPromotional");
    assert.equal(result.body.activation, "nextBillingEvent");
    assert.equal(result.body.attemptID, attemptID);
    assert.equal(result.body.accessStartsAt, new Date(gift.purchaseDate).toISOString());
    assert.equal(result.body.accessEndsAt, new Date(gift.expiresDate).toISOString());
    assert.equal(result.body.estimatedAccessEndsAt, undefined);
    assert.equal(result.body.signature, undefined);
    assert.equal(fixture.calls.length, 1);
    assert.equal(fixture.calls[0].state, "redeemed");
    assert.equal(fixture.calls[0].transactionID, gift.transactionId);
    assert.equal(fixture.calls[0].accessEndsAt, result.body.accessEndsAt);
  });
}
test("completed known campaign transaction with invalid terms remains consumed without successful confirmation", async () => {
  for (const fields of [{ price: "0" }, { offerPeriod: "P2M" }, { expiresDate: now - 10000 }]) {
    const gift = transaction({ offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly],
      offerDiscountType: "PAY_UP_FRONT", offerPeriod: "P1M", price: 0, ...fields });
    const fixture = handlerFixture({
      readSubscriptionSeed: async () => ({ originalTransactionID: gift.originalTransactionId }),
      readCampaignLedger: async () => ({ state: "scheduled", attemptID, productID: monthly,
        decision: "scheduledPromotional", offerID: complimentaryOfferIDs[monthly], environment: "production" }),
      verifyAndDecodeTransaction: async () => gift,
      fetchFreshAppleSnapshot: async () => ({ history: [gift], statuses: [] }),
    });
    const result = await fixture.request({ action: "confirm", attemptID, signedTransactionInfo: "verified-invalid-gift" });
    assert.equal(result.status, 409);
    assert.equal(result.body.state, "unavailable");
    assert.equal(result.body.reason, "verified_offer_terms_mismatch");
    assert.equal(result.body.signature, undefined);
    assert.equal(fixture.calls.length, 1);
    assert.equal(fixture.calls[0].state, "redeemed");
    assert.equal(fixture.calls[0].transactionID, gift.transactionId);
  }
});
test("ended verified gift can finish recovery without a new authorization or duplicate benefit", async () => {
  const gift = transaction({ expiresDate: now - 1, offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly],
    offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 });
  const duplicate = { ...gift, transactionId: "1002", purchaseDate: now - 1000, expiresDate: now + 100000 };
  let reservations = 0;
  let signatures = 0;
  const fixture = handlerFixture({
    readSubscriptionSeed: async () => ({ originalTransactionID: gift.originalTransactionId }),
    readCampaignLedger: async () => ({ state: "prepared", attemptID, productID: monthly,
      decision: "promotional", offerID: complimentaryOfferIDs[monthly], environment: "production", authorizedAt: now - 10000 }),
    verifyAndDecodeTransaction: async () => gift,
    fetchFreshAppleSnapshot: async () => ({ history: [duplicate, gift], statuses: [] }),
    reserveCampaignAttempt: async () => { reservations += 1; throw new Error("consumed campaign must not reserve"); },
    signPromotionalOffer: async () => { signatures += 1; throw new Error("consumed campaign must not sign"); },
  });
  const result = await fixture.request({ action: "confirm", attemptID, signedTransactionInfo: "verified-ended-gift" },
    () => configuration.endsAt + 1);
  assert.equal(result.status, 200);
  assert.equal(result.body.state, "redeemed");
  assert.equal(result.body.accessStartsAt, new Date(gift.purchaseDate).toISOString());
  assert.equal(result.body.accessEndsAt, new Date(gift.expiresDate).toISOString());
  assert.ok(Date.parse(result.body.accessEndsAt) < Date.parse(result.body.serverTime));
  assert.equal(result.body.signature, undefined);
  assert.equal(fixture.calls[0].transactionID, gift.transactionId);
  assert.equal(fixture.calls[0].accessEndsAt, result.body.accessEndsAt);
  const consumed = await fixture.request({ action: "prepare", attemptID: owner, previousAttemptID: attemptID });
  assert.equal(consumed.body.state, "redeemed");
  assert.equal(consumed.body.accessEndsAt, result.body.accessEndsAt);
  assert.equal(consumed.body.signature, undefined);
  assert.equal(fixture.calls[1].transactionID, gift.transactionId);
  const closed = await fixture.request({ action: "prepare", attemptID: owner, previousAttemptID: attemptID },
    () => configuration.endsAt + 1);
  assert.equal(closed.body.state, "unavailable");
  assert.equal(closed.body.reason, "campaign_ended");
  assert.equal(reservations, 0);
  assert.equal(signatures, 0);
});
test("server strips upstream secret-bearing errors", async () => {
  const fixture = handlerFixture({ readCampaignLedger: async () => { throw new Error("secret signature private key"); } });
  const result = await fixture.request({ action: "status" });
  assert.equal(result.status, 503);
  assert.equal(JSON.stringify(result.body).includes("private key"), false);
});
test("client identity and invalid attempts are rejected", async () => {
  const fixture = handlerFixture();
  assert.equal((await fixture.request({ action: "prepare", attemptID: "not-a-uuid" })).status, 400);
  assert.equal((await fixture.request({ action: "status", ownerID: owner })).status, 400);
});
test("oversized body fails before auth, ledger or Apple reads", async () => {
  const request = new Request("https://example.test", { method: "POST", body: "x".repeat(65537) });
  const response = await handleComplimentaryOfferRequest(request,
    { authenticatedUserID: async () => { throw new Error("must not authenticate oversized body"); } }, configuration, () => now);
  assert.equal(response.status, 413);
});
test("malformed JSON has a bounded invalid-request response", async () => {
  const response = await handleComplimentaryOfferRequest(new Request("https://example.test", { method: "POST", body: "{" }), {}, configuration, () => now);
  assert.equal(response.status, 400);
});
test("legacy signature payload lowercases UUIDs, uses U+2063 and verifies DER SHA256", () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const signer = createLegacyPromotionalOfferSigner({ bundleID: "com.ichart.app", keyID: "ABCDEFGHIJ",
    privateKeyPEM: privateKey.export({ format: "pem", type: "pkcs8" }) });
  const fields = { productID: monthly, offerID: complimentaryOfferIDs[monthly], appAccountToken: owner.toUpperCase(), nonce: attemptID.toUpperCase(), timestamp: now };
  const signed = signer(fields);
  const payload = promotionalOfferSignaturePayload({ bundleID: "com.ichart.app", keyID: "ABCDEFGHIJ", ...fields });
  assert.equal(payload.split("\u2063").length, 7);
  assert.equal(signed.nonce, attemptID);
  assert.equal(Buffer.from(signed.signature, "base64")[0], 0x30);
  assert.equal(verify("sha256", Buffer.from(payload), { key: publicKey, dsaEncoding: "der" }, Buffer.from(signed.signature, "base64")), true);
});
