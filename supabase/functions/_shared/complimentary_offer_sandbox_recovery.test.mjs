import test from "node:test";
import assert from "node:assert/strict";
import { complimentaryCampaignConfigurationFromEnv, complimentaryCampaignID, complimentaryOfferIDs,
  handleComplimentaryOfferRequest } from "./complimentary_offer_campaign.mjs";

const qaOwner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const otherOwner = "11111111-1111-4111-8111-111111111111";
const attemptID = "22222222-2222-4222-8222-222222222222";
const otherAttemptID = "33333333-3333-4333-8333-333333333333";
const monthly = "com.ichart.app.pro.monthly";
const annual = "com.ichart.app.pro.annual";
const now = Date.parse("2026-10-09T12:00:00Z");
const cutoff = now + 30 * 60 * 1000;
const offerID = complimentaryOfferIDs[monthly];
const forbiddenSinks = ["reserveCampaignAttempt", "signPromotionalOffer", "writeSubscriptionAuthorityClaim"];

const recoveryConfiguration = (extra = {}) => ({
  campaignID: complimentaryCampaignID, enabled: false, reason: "campaign_disabled",
  startsAt: NaN, endsAt: NaN, bundleID: "com.ichart.app", environment: "sandbox",
  sandboxQAOwnerIDs: [qaOwner], sandboxRecoveryEndsAt: cutoff, ...extra,
});
const ledger = (extra = {}) => ({
  state: "prepared", productID: monthly, attemptID, decision: "scheduledPromotional",
  offerID, authorizedAt: now - 1000, originalTransactionID: null, environment: "sandbox",
  accessStartsAt: null, accessEndsAt: null, ...extra,
});
const transaction = (extra = {}) => ({
  bundleId: "com.ichart.app", productId: monthly, environment: "Sandbox", appAccountToken: qaOwner,
  type: "Auto-Renewable Subscription", inAppOwnershipType: "PURCHASED",
  originalTransactionId: "1000", transactionId: "1001", purchaseDate: now - 10000,
  expiresDate: now + 100000, ...extra,
});
const renewal = (extra = {}) => ({
  productId: monthly, autoRenewProductId: monthly, environment: "Sandbox", appAccountToken: qaOwner,
  originalTransactionId: "1000", autoRenewStatus: 1, renewalDate: now + 100000,
  offerType: 2, offerIdentifier: offerID, offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", renewalPrice: 0,
  ...extra,
});
const snapshot = ({ transactionFields = {}, renewalFields = {}, status = 1 } = {}) => {
  const current = transaction(transactionFields);
  return { history: [current], statuses: [{ status, transaction: current, renewal: renewal(renewalFields) }] };
};

function fixture({ configuration = recoveryConfiguration(), owner = qaOwner, overrides = {}, afterCalls = {} } = {}) {
  let time = now;
  const calls = [];
  const recorded = [];
  const methods = {
    authenticatedUserID: async () => owner,
    readCampaignLedger: async () => ledger(),
    readSubscriptionSeed: async () => ({ originalTransactionID: "1000" }),
    verifyAndDecodeTransaction: async () => transaction(),
    fetchFreshAppleSnapshot: async () => snapshot(),
    recordCampaignBenefit: async (input) => { recorded.push(input); return { ok: true }; },
    reserveCampaignAttempt: async () => { throw new Error("recovery must never reserve"); },
    signPromotionalOffer: async () => { throw new Error("recovery must never sign"); },
    writeSubscriptionAuthorityClaim: async () => { throw new Error("recovery must not change ordinary authority"); },
    ...overrides,
  };
  const dependencies = Object.fromEntries(Object.entries(methods).filter(([, method]) => typeof method === "function")
    .map(([name, method]) => [name, async (...args) => {
    calls.push({ name, args });
    const result = await method(...args);
    afterCalls[name]?.(state);
    return result;
  }]));
  const state = {
    configuration, calls, recorded,
    names: () => calls.map((call) => call.name),
    setTime: (value) => { time = value; },
    request: async (action = "status", extra = {}) => {
      const body = { schemaVersion: 1, action, productID: monthly,
        ...(action === "status" ? {} : { attemptID }),
        ...(action === "confirm" ? { signedTransactionInfo: "synthetic-verified-current-paid-transaction" } : {}), ...extra };
      const response = await handleComplimentaryOfferRequest(new Request("https://example.test", {
        method: "POST", headers: { "x-qa-owner": qaOwner }, body: JSON.stringify(body),
      }), dependencies, configuration, () => time);
      return { status: response.status, body: await response.json() };
    },
  };
  return state;
}

function assertNoIssuance(state) {
  for (const name of forbiddenSinks) assert.ok(!state.names().includes(name), name);
}
function assertUnavailable(result, state, { benefitCalls = 0 } = {}) {
  assert.equal(result.body.enabled, false);
  assert.equal(result.body.state, "unavailable");
  assert.equal(result.body.signature, undefined);
  assert.equal(result.body.attemptID, undefined);
  assert.equal(result.body.recoveryOnly, undefined);
  assert.equal(state.calls.filter((call) => call.name === "recordCampaignBenefit").length, benefitCalls);
  assertNoIssuance(state);
}
function assertScheduled(result, state) {
  assert.equal(result.status, 200);
  assert.equal(result.body.enabled, false);
  assert.equal(result.body.recoveryOnly, true);
  assert.equal(result.body.canPrepare, false);
  assert.equal(result.body.state, "scheduled");
  assert.equal(result.body.decision, "scheduledPromotional");
  assert.equal(result.body.activation, "nextBillingEvent");
  assert.equal(result.body.productID, monthly);
  assert.equal(result.body.offerID, offerID);
  assert.equal(result.body.attemptID, attemptID);
  assert.equal(result.body.signature, undefined);
  assert.equal(result.body.accessStartsAt, new Date(now + 100000).toISOString());
  assert.equal(result.body.accessEndsAt, null);
  assert.equal(result.body.accessEndsAtIsEstimated, true);
  assert.equal(state.recorded.length, 1);
  assert.equal(state.recorded[0].ownerID, qaOwner);
  assert.equal(state.recorded[0].campaignID, complimentaryCampaignID);
  assert.equal(state.recorded[0].attemptID, attemptID);
  assert.equal(state.recorded[0].productID, monthly);
  assert.equal(state.recorded[0].originalTransactionID, "1000");
  assert.equal(state.recorded[0].environment, "sandbox");
  assert.equal(state.recorded[0].state, "scheduled");
  assertNoIssuance(state);
}

test("recovery configuration is independent of campaign dates and enablement, only with explicit Sandbox", () => {
  const env = { APP_STORE_ENVIRONMENT: "Production", ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT: "Sandbox",
    APP_STORE_BUNDLE_ID: "com.ichart.app", ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED: "false",
    ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS: JSON.stringify([qaOwner]),
    ICHART_COMPLIMENTARY_SANDBOX_RECOVERY_ENDS_AT: new Date(cutoff).toISOString() };
  for (const input of [env, { get: (key) => env[key] }]) {
    const config = complimentaryCampaignConfigurationFromEnv(input);
    assert.equal(config.enabled, false);
    assert.equal(config.environment, "sandbox");
    assert.equal(config.sandboxRecoveryEndsAt, cutoff);
    assert.deepEqual(config.sandboxQAOwnerIDs, [qaOwner]);
    assert.ok(!Number.isFinite(config.startsAt));
    assert.ok(!Number.isFinite(config.endsAt));
  }
  assert.equal(env.APP_STORE_ENVIRONMENT, "Production");
  for (const explicit of [undefined, "Production", "unexpected"]) {
    const input = { ...env, APP_STORE_ENVIRONMENT: "Sandbox", ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT: explicit };
    assert.ok(!Number.isFinite(complimentaryCampaignConfigurationFromEnv(input).sandboxRecoveryEndsAt));
  }
});

test("Production configuration never reads the Sandbox recovery cutoff", () => {
  const env = { APP_STORE_ENVIRONMENT: "Production", ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED: "false" };
  const config = complimentaryCampaignConfigurationFromEnv({ get: (key) => {
    assert.notEqual(key, "ICHART_COMPLIMENTARY_SANDBOX_RECOVERY_ENDS_AT");
    return env[key];
  } });
  assert.equal(config.enabled, false);
  assert.ok(!Number.isFinite(config.sandboxRecoveryEndsAt));
});

for (const action of ["status", "confirm"]) {
  test("disabled no-date " + action + " recovers the existing scheduled attempt without authorization", async () => {
    const state = fixture();
    assertScheduled(await state.request(action), state);
    assert.deepEqual(state.names(), ["authenticatedUserID", "readCampaignLedger", "readSubscriptionSeed",
      ...(action === "confirm" ? ["verifyAndDecodeTransaction"] : []), "fetchFreshAppleSnapshot", "recordCampaignBenefit"]);
  });
}

test("status ignores client JWS and uses only the stored owned seed", async () => {
  const state = fixture({ overrides: { verifyAndDecodeTransaction: async () => {
    throw new Error("client-selected JWS must not be used by recovery status");
  } } });
  assertScheduled(await state.request("status", { signedTransactionInfo: "untrusted-other-chain-JWS" }), state);
  const fetch = state.calls.find((call) => call.name === "fetchFreshAppleSnapshot");
  assert.deepEqual(fetch.args[0], { ownerID: qaOwner, originalTransactionID: "1000", environment: "sandbox" });
  assert.ok(!state.names().includes("verifyAndDecodeTransaction"));
});

test("scheduled ledger state and case-canonicalized authenticated owner retain recovery", async () => {
  const state = fixture({ owner: qaOwner.toUpperCase(),
    overrides: { readCampaignLedger: async () => ledger({ state: "scheduled", originalTransactionID: "1000" }) } });
  const result = await state.request("status");
  assert.equal(result.body.state, "scheduled");
  assert.equal(result.body.recoveryOnly, true);
  assert.equal(state.recorded[0].attemptID, attemptID);
  assertNoIssuance(state);
});

test("the inclusive one-hour recovery ceiling is accepted", async () => {
  const state = fixture({ configuration: recoveryConfiguration({ sandboxRecoveryEndsAt: now + 3600000 }) });
  assertScheduled(await state.request(), state);
});

test("PAY_UP_FRONT for a known promotional P1M numeric-zero renewal can recover scheduled evidence", async () => {
  const state = fixture({ overrides: { fetchFreshAppleSnapshot: async () => snapshot({
    renewalFields: { offerDiscountType: "PAY_UP_FRONT" },
  }) } });
  assertScheduled(await state.request(), state);
});

test("prepare stays disabled even for the approved recovery owner and valid cutoff", async () => {
  const state = fixture();
  assertUnavailable(await state.request("prepare"), state);
  assert.deepEqual(state.names(), ["authenticatedUserID"]);
});

test("recovery without a valid cutoff, Sandbox scope, or exact singleton owner never reads a ledger", async (t) => {
  const invalidConfigurations = [
    ["missing cutoff", { sandboxRecoveryEndsAt: undefined }],
    ["null cutoff", { sandboxRecoveryEndsAt: null }],
    ["NaN cutoff", { sandboxRecoveryEndsAt: NaN }],
    ["infinite cutoff", { sandboxRecoveryEndsAt: Infinity }],
    ["string cutoff", { sandboxRecoveryEndsAt: String(cutoff) }],
    ["expired cutoff", { sandboxRecoveryEndsAt: now - 1 }],
    ["at cutoff", { sandboxRecoveryEndsAt: now }],
    ["beyond one hour", { sandboxRecoveryEndsAt: now + 3600001 }],
    ["Production", { environment: "production" }],
    ["noncanonical Sandbox alias", { environment: "Sandbox" }],
    ["whitespace Sandbox alias", { environment: " sandbox " }],
    ["missing environment", { environment: undefined }],
    ["unknown environment", { environment: "unexpected" }],
    ["missing QA list", { sandboxQAOwnerIDs: undefined }],
    ["null QA list", { sandboxQAOwnerIDs: null }],
    ["empty QA list", { sandboxQAOwnerIDs: [] }],
    ["two QA owners", { sandboxQAOwnerIDs: [qaOwner, otherOwner] }],
    ["duplicate QA owner", { sandboxQAOwnerIDs: [qaOwner, qaOwner.toUpperCase()] }],
    ["wildcard QA owner", { sandboxQAOwnerIDs: ["*"] }],
    ["whitespace QA owner", { sandboxQAOwnerIDs: [qaOwner + " "] }],
    ["wrong bundle", { bundleID: "com.other.app" }],
    ["wrong campaign", { campaignID: "unrelated-campaign" }],
  ];
  const sparse = [qaOwner];
  sparse.length = 2;
  invalidConfigurations.push(["sparse QA list", { sandboxQAOwnerIDs: sparse }]);
  for (const action of ["status", "confirm"]) {
    for (const [name, fields] of invalidConfigurations) {
      await t.test(action + ": " + name, async () => {
        const state = fixture({ configuration: recoveryConfiguration(fields) });
        assertUnavailable(await state.request(action), state);
        assert.deepEqual(state.names(), ["authenticatedUserID"]);
      });
    }
    await t.test(action + ": ordinary owner", async () => {
      const state = fixture({ owner: otherOwner });
      assertUnavailable(await state.request(action), state);
      assert.deepEqual(state.names(), ["authenticatedUserID"]);
    });
  }
});

test("missing or invalid authentication cannot enter recovery", async (t) => {
  for (const owner of [undefined, null, "", "not-an-owner"]) {
    await t.test(String(owner), async () => {
      const state = fixture({ overrides: { authenticatedUserID: async () => owner } });
      assertUnavailable(await state.request(), state);
      assert.deepEqual(state.names(), ["authenticatedUserID"]);
    });
  }
});

test("missing recovery dependencies fail before ledger access", async (t) => {
  for (const action of ["status", "confirm"]) {
    for (const name of ["readCampaignLedger", "readSubscriptionSeed", "fetchFreshAppleSnapshot", "recordCampaignBenefit",
      ...(action === "confirm" ? ["verifyAndDecodeTransaction"] : [])]) {
      await t.test(action + ": missing " + name, async () => {
        const state = fixture({ overrides: { [name]: undefined } });
        assertUnavailable(await state.request(action), state);
        assert.deepEqual(state.names(), ["authenticatedUserID"]);
      });
    }
  }
});

test("failed admitted recovery cannot fall through to a second disabled Apple diagnostic", async (t) => {
  for (const [name, overrides, expectedFetches] of [
    ["missing ledger", { readCampaignLedger: async () => null }, 0],
    ["unverifiable pending terms", { fetchFreshAppleSnapshot: async () => snapshot({ renewalFields: { renewalPrice: 1 } }) }, 1],
  ]) {
    await t.test(name, async () => {
      const state = fixture({ configuration: recoveryConfiguration({ sandboxDiagnosticEndsAt: cutoff }),
        overrides: { ...overrides, recordPendingVerificationDiagnostic: async () => {
          throw new Error("admitted recovery must terminate without diagnostic fallthrough");
        } } });
      assertUnavailable(await state.request(), state);
      assert.equal(state.calls.filter((call) => call.name === "fetchFreshAppleSnapshot").length, expectedFetches);
      assert.ok(!state.names().includes("recordPendingVerificationDiagnostic"));
    });
  }
});

test("no ledger or an invalid current-attempt ledger blocks seed and Apple access", async (t) => {
  const invalidLedgers = [
    ["absent", null],
    ["redeemed", ledger({ state: "redeemed" })],
    ["unknown state", ledger({ state: "available" })],
    ["missing attempt", ledger({ attemptID: null })],
    ["invalid attempt", ledger({ attemptID: "untrusted-attempt" })],
    ["other product", ledger({ productID: annual })],
    ["Production", ledger({ environment: "production" })],
    ["other decision", ledger({ decision: "promotional" })],
    ["introductory decision", ledger({ decision: "introductory", offerID: null })],
    ["missing offer", ledger({ offerID: null })],
    ["other offer", ledger({ offerID: complimentaryOfferIDs[annual] })],
    ["missing authorization", ledger({ authorizedAt: undefined })],
    ["null authorization", ledger({ authorizedAt: null })],
    ["zero authorization", ledger({ authorizedAt: 0 })],
    ["negative authorization", ledger({ authorizedAt: -1 })],
    ["future authorization", ledger({ authorizedAt: now + 1 })],
    ["NaN authorization", ledger({ authorizedAt: NaN })],
    ["infinite authorization", ledger({ authorizedAt: Infinity })],
    ["string authorization", ledger({ authorizedAt: String(now - 1000) })],
  ];
  for (const action of ["status", "confirm"]) {
    for (const [name, value] of invalidLedgers) {
      await t.test(action + ": " + name, async () => {
        const state = fixture({ overrides: { readCampaignLedger: async () => value } });
        assertUnavailable(await state.request(action), state);
        assert.deepEqual(state.names(), ["authenticatedUserID", "readCampaignLedger"]);
      });
    }
  }
});

test("confirm refuses a mismatched current attempt before verification or fetch", async () => {
  const state = fixture();
  assertUnavailable(await state.request("confirm", { attemptID: otherAttemptID }), state);
  assert.ok(!state.names().includes("verifyAndDecodeTransaction"));
  assert.ok(!state.names().includes("fetchFreshAppleSnapshot"));
});

test("wrong requested product cannot reuse the approved ledger", async () => {
  const state = fixture();
  assertUnavailable(await state.request("status", { productID: annual }), state);
  assert.deepEqual(state.names(), ["authenticatedUserID", "readCampaignLedger"]);
});

test("missing, malformed, or ledger-conflicting owned seeds never reach Apple or supplied JWS", async (t) => {
  for (const [name, seed, existing] of [
    ["absent", null, ledger()],
    ["missing chain", {}, ledger()],
    ["invalid chain", { originalTransactionID: "untrusted-chain" }, ledger()],
    ["conflicting ledger chain", { originalTransactionID: "1000" }, ledger({ originalTransactionID: "9999" })],
  ]) {
    for (const action of ["status", "confirm"]) {
      await t.test(action + ": " + name, async () => {
        const state = fixture({ overrides: { readCampaignLedger: async () => existing, readSubscriptionSeed: async () => seed } });
        assertUnavailable(await state.request(action), state);
        assert.ok(!state.names().includes("verifyAndDecodeTransaction"));
        assert.ok(!state.names().includes("fetchFreshAppleSnapshot"));
      });
    }
  }
});

test("confirm requires a supplied verified transaction after trusted seed resolution", async () => {
  const state = fixture();
  assertUnavailable(await state.request("confirm", { signedTransactionInfo: undefined }), state);
  assert.ok(!state.names().includes("verifyAndDecodeTransaction"));
  assert.ok(!state.names().includes("fetchFreshAppleSnapshot"));
});

test("confirm rejects verified transaction ownership, chain, product, and scope mismatches", async (t) => {
  for (const [name, fields] of [
    ["other chain", { originalTransactionId: "9999" }],
    ["other product", { productId: annual }],
    ["other owner", { appAccountToken: otherOwner }],
    ["missing token", { appAccountToken: undefined }],
    ["Family Sharing", { inAppOwnershipType: "FAMILY_SHARED" }],
    ["Production", { environment: "Production" }],
    ["other bundle", { bundleId: "com.other.app" }],
    ["other type", { type: "Non-Consumable" }],
  ]) {
    await t.test(name, async () => {
      const state = fixture({ overrides: { verifyAndDecodeTransaction: async () => transaction(fields) } });
      assertUnavailable(await state.request("confirm"), state);
      assert.ok(!state.names().includes("fetchFreshAppleSnapshot"));
      assert.ok(state.names().indexOf("readSubscriptionSeed") < state.names().indexOf("verifyAndDecodeTransaction"));
    });
  }
});

test("fresh evidence must establish the same owned chain and requested product", async (t) => {
  for (const [name, value] of [
    ["empty evidence", { history: [], statuses: [] }],
    ["another chain", snapshot({ transactionFields: { originalTransactionId: "9999" }, renewalFields: { originalTransactionId: "9999" } })],
    ["another product", snapshot({ transactionFields: { productId: annual }, renewalFields: {
      productId: annual, autoRenewProductId: annual, offerIdentifier: complimentaryOfferIDs[annual],
    } })],
    ["another owner", snapshot({ transactionFields: { appAccountToken: otherOwner } })],
    ["missing owner token", snapshot({ transactionFields: { appAccountToken: undefined } })],
    ["Production transaction", snapshot({ transactionFields: { environment: "Production" } })],
    ["another bundle", snapshot({ transactionFields: { bundleId: "com.other.app" } })],
    ["Family Sharing", snapshot({ transactionFields: { inAppOwnershipType: "FAMILY_SHARED" } })],
  ]) {
    await t.test(name, async () => {
      const state = fixture({ overrides: { fetchFreshAppleSnapshot: async () => value } });
      assertUnavailable(await state.request(), state);
    });
  }
});

test("pending offer mismatches cannot be converted into a scheduled benefit", async (t) => {
  const cases = [
    ["paid renewal", { renewalPrice: 1 }],
    ["string zero", { renewalPrice: "0" }],
    ["missing zero", { renewalPrice: undefined }],
    ["wrong period", { offerPeriod: "P2M" }],
    ["missing period", { offerPeriod: undefined }],
    ["pay as you go", { offerDiscountType: "PAY_AS_YOU_GO" }],
    ["missing discount mode", { offerDiscountType: undefined }],
    ["unknown offer", { offerIdentifier: "other-offer" }],
    ["wrong known offer", { offerIdentifier: complimentaryOfferIDs[annual] }],
    ["wrong offer type", { offerType: 1 }],
    ["renewal off", { autoRenewStatus: 0 }],
    ["other renewal product", { productId: annual }],
    ["crossgrade", { autoRenewProductId: annual }],
    ["past renewal date", { renewalDate: now - 1 }],
    ["missing renewal date", { renewalDate: undefined }],
    ["infinite renewal date", { renewalDate: Infinity }],
  ];
  for (const discountMode of ["FREE_TRIAL", "PAY_UP_FRONT"]) {
    for (const [name, fields] of cases) {
      await t.test(discountMode + ": " + name, async () => {
        const state = fixture({ overrides: { fetchFreshAppleSnapshot: async () => snapshot({
          renewalFields: { offerDiscountType: discountMode, ...fields },
        }) } });
        assertUnavailable(await state.request(), state);
      });
    }
  }
  for (const [name, fields, status] of [
    ["expired", { expiresDate: now - 1 }, 1],
    ["revoked", { revocationDate: now - 1 }, 1],
    ["billing retry", {}, 3],
  ]) {
    await t.test(name, async () => {
      const state = fixture({ overrides: { fetchFreshAppleSnapshot: async () => snapshot({ transactionFields: fields, status }) } });
      assertUnavailable(await state.request(), state);
    });
  }
});

test("cutoff expiry after each completed I/O blocks the next I/O and all writes", async (t) => {
  for (const action of ["status", "confirm"]) {
    const stages = ["authenticatedUserID", "readCampaignLedger", "readSubscriptionSeed",
      ...(action === "confirm" ? ["verifyAndDecodeTransaction"] : []), "fetchFreshAppleSnapshot"];
    for (const stage of stages) {
      await t.test(action + ": expires after " + stage, async () => {
        const state = fixture({ afterCalls: { [stage]: (current) => current.setTime(cutoff) } });
        assertUnavailable(await state.request(action), state);
        assert.deepEqual(state.names(), stages.slice(0, stages.indexOf(stage) + 1));
      });
    }
  }
});

test("expiry during the permitted in-flight benefit write suppresses scheduled success", async (t) => {
  for (const action of ["status", "confirm"]) {
    await t.test(action, async () => {
      const state = fixture({ afterCalls: { recordCampaignBenefit: (current) => current.setTime(cutoff) } });
      assertUnavailable(await state.request(action), state, { benefitCalls: 1 });
      assert.equal(state.recorded.length, 1);
      assert.equal(state.recorded[0].attemptID, attemptID);
    });
  }
});

test("retired attempt or persistence conflict cannot report recovered scheduling", async (t) => {
  for (const action of ["status", "confirm"]) {
    for (const reason of ["attempt_retired", "attempt_conflict", "campaign_benefit_conflict"]) {
      await t.test(action + ": " + reason, async () => {
        const state = fixture({ overrides: { recordCampaignBenefit: async (input) => {
          assert.equal(input.attemptID, attemptID);
          return { ok: false, reason };
        } } });
        assertUnavailable(await state.request(action), state, { benefitCalls: 1 });
        assert.equal(state.recorded.length, 0);
      });
    }
  }
});

test("dependency failures remain unavailable without exposing upstream error text", async (t) => {
  for (const action of ["status", "confirm"]) {
    const stages = ["readCampaignLedger", "readSubscriptionSeed",
      ...(action === "confirm" ? ["verifyAndDecodeTransaction"] : []), "fetchFreshAppleSnapshot", "recordCampaignBenefit"];
    for (const stage of stages) {
      await t.test(action + ": " + stage, async () => {
        const state = fixture({ overrides: { [stage]: async () => { throw new Error("private-upstream-body-JWS-sentinel"); } } });
        const result = await state.request(action);
        assertUnavailable(result, state, { benefitCalls: stage === "recordCampaignBenefit" ? 1 : 0 });
        assert.ok(!JSON.stringify(result.body).includes("private-upstream-body-JWS-sentinel"));
        assert.equal(state.recorded.length, 0);
      });
    }
  }
});
