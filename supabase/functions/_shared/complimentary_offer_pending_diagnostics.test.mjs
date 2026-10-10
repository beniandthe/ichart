import test from 'node:test';
import assert from 'node:assert/strict';
import { complimentaryCampaignConfigurationFromEnv, complimentaryCampaignID, complimentaryOfferIDs,
  handleComplimentaryOfferRequest, pendingCampaignVerificationChecks, pendingCampaignDiscountCategory } from './complimentary_offer_campaign.mjs';

const owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const attempt = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const product = 'com.ichart.app.pro.monthly';
const now = Date.parse('2026-10-09T19:00:00Z');
const config = { campaignID: complimentaryCampaignID, enabled: false, reason: 'campaign_disabled',
  bundleID: 'com.ichart.app', environment: 'sandbox', sandboxQAOwnerIDs: [owner], sandboxDiagnosticEndsAt: now + 600000 };
const ledger = { state: 'prepared', productID: product, environment: 'sandbox', attemptID: attempt,
  decision: 'scheduledPromotional', offerID: complimentaryOfferIDs[product], authorizedAt: now - 1000 };
const entry = { status: 1, transaction: { bundleId: 'com.ichart.app', productId: product, environment: 'Sandbox',
  appAccountToken: owner, type: 'Auto-Renewable Subscription', inAppOwnershipType: 'PURCHASED',
  originalTransactionId: '1000', transactionId: '1001', expiresDate: now + 86400000 },
  renewal: { productId: product, autoRenewProductId: product, offerType: 2, offerIdentifier: complimentaryOfferIDs[product],
    offerDiscountType: 'FREE_TRIAL', offerPeriod: 'P1M', renewalPrice: 0, autoRenewStatus: 1, renewalDate: now + 86400000 } };

async function run({ configuration = config, user = owner, action = 'status', saved = ledger,
  seed = { originalTransactionID: '1000' }, statuses = [entry], fetchError, advance = false, advanceDuringRead } = {}) {
  const calls = [];
  const events = [];
  let time = now;
  const deps = {
    authenticatedUserID: async () => { calls.push('auth'); return user; },
    readCampaignLedger: async () => { calls.push('ledger'); if (advanceDuringRead === 'ledger') time = configuration.sandboxDiagnosticEndsAt; return saved; },
    readSubscriptionSeed: async () => { calls.push('seed'); if (advanceDuringRead === 'seed') time = configuration.sandboxDiagnosticEndsAt; return seed; },
    fetchFreshAppleSnapshot: async input => {
      calls.push('apple'); assert.equal(input.ownerID.toLowerCase(), owner);
      assert.equal(input.originalTransactionID, '1000'); assert.equal(input.environment, 'sandbox');
      if (fetchError) throw fetchError;
      if (advance) time = configuration.sandboxDiagnosticEndsAt;
      return { history: [], statuses };
    },
    recordPendingVerificationDiagnostic: checks => { calls.push('log'); events.push(checks); },
    recordCampaignBenefit: async () => assert.fail('No benefit may be recorded'),
    reserveCampaignAttempt: async () => assert.fail('No attempt may be prepared'),
    signPromotionalOffer: async () => assert.fail('No signature may be issued'),
    verifyAndDecodeTransaction: async () => assert.fail('Client JWS cannot be used as a diagnostic seed'),
  };
  const response = await handleComplimentaryOfferRequest(new Request('https://example.test', { method: 'POST',
    body: JSON.stringify({ schemaVersion: 1, action, productID: product, signedTransactionInfo: 'ignored-client-JWS',
      ...(action !== 'status' ? { attemptID: attempt } : {}) }) }), deps, configuration, () => time);
  const body = await response.json();
  assert.equal(response.status, 200); assert.equal(body.enabled, false);
  assert.equal(body.state, 'unavailable'); assert.equal(body.reason, 'campaign_disabled');
  assert.equal(body.attemptID, undefined); assert.equal(body.signature, undefined);
  return { calls, events, body };
}

test('disabled QA diagnostic is explicit, bounded, Sandbox-only and read-only', async () => {
  for (const state of ['prepared', 'scheduled']) {
    const result = await run({ saved: { ...ledger, state } });
    assert.deepEqual(result.calls, ['auth', 'ledger', 'seed', 'apple', 'log']);
    assert.equal(result.events.length, 1);
    assert.equal(Object.keys(result.events[0]).length, 16);
    assert.ok(Object.values(result.events[0]).every(value => typeof value === 'boolean'));
    assert.equal(result.events[0].one_month, true); assert.equal(result.events[0].zero_price, true);
    assert.equal(result.events[0].price_positive, false);
    assert.deepEqual(result.body.pendingVerificationChecks, result.events[0]);
  }
});
test('all other disabled requests retain the authentication-only short circuit', async () => {
  for (const mutation of [
    { sandboxDiagnosticEndsAt: undefined }, { sandboxDiagnosticEndsAt: NaN }, { sandboxDiagnosticEndsAt: now },
    { sandboxDiagnosticEndsAt: now + 3600001 }, { environment: 'production' }, { environment: undefined },
    { sandboxQAOwnerIDs: [] }, { sandboxQAOwnerIDs: [owner, other] }, { sandboxQAOwnerIDs: [other] },
    { sandboxQAOwnerIDs: ['*'] }, { bundleID: 'another.app' },
  ]) {
    const result = await run({ configuration: { ...config, ...mutation } });
    assert.deepEqual(result.calls, ['auth']); assert.equal(result.body.pendingVerificationChecks, undefined);
  }
  assert.deepEqual((await run({ user: other })).calls, ['auth']);
  for (const action of ['prepare', 'confirm']) assert.deepEqual((await run({ action })).calls, ['auth']);
});
test('missing or mismatching saved preparation cannot cause an Apple diagnostic call', async () => {
  for (const saved of [null, ...[
    { state: 'redeemed' }, { attemptID: null }, { productID: 'com.ichart.app.pro.annual' },
    { environment: 'production' }, { decision: 'promotional' }, { offerID: 'unknown' },
    { authorizedAt: null }, { authorizedAt: now + 1 }, { authorizedAt: 0 },
  ].map(mutation => ({ ...ledger, ...mutation }))]) {
    assert.deepEqual((await run({ saved })).calls, ['auth', 'ledger']);
  }
  assert.deepEqual((await run({ seed: null })).calls, ['auth', 'ledger', 'seed']);
  assert.deepEqual((await run({ saved: { ...ledger, originalTransactionID: 'other' } })).calls, ['auth', 'ledger', 'seed']);
});
test('unverified, ambiguous or unlinked Apple data and cutoff crossings emit nothing', async () => {
  for (const advanceDuringRead of ['ledger', 'seed']) {
    const result = await run({ advanceDuringRead });
    assert.ok(!result.calls.includes('apple')); assert.equal(result.events.length, 0);
  }
  for (const options of [
    { fetchError: new Error('credential-private-JWS') }, { advance: true }, { statuses: [] },
    { statuses: [entry, entry] },
    { statuses: [{ ...entry, transaction: { ...entry.transaction, appAccountToken: other } }] },
    { statuses: [{ ...entry, transaction: { ...entry.transaction, productId: 'com.ichart.app.pro.annual' } }] },
    { statuses: [{ ...entry, transaction: { ...entry.transaction, originalTransactionId: '1002' } }] },
    { statuses: [{ ...entry, renewal: { ...entry.renewal, offerIdentifier: 'other-offer' } }] },
  ]) {
    const result = await run(options); assert.equal(result.events.length, 0);
    assert.ok(!JSON.stringify(result.body).includes('credential-private-JWS'));
  }
});
test('absent or contradictory terms are distinguished, not coerced into verified terms', () => {
  const missing = pendingCampaignVerificationChecks({ ...entry, renewal: {
    ...entry.renewal, offerPeriod: undefined, offerDiscountType: undefined, renewalPrice: undefined } }, now);
  for (const key of ['one_month', 'free_trial', 'zero_price', 'period_present', 'discount_present', 'price_present']) {
    assert.equal(missing[key], false);
  }
  const wrong = pendingCampaignVerificationChecks({ ...entry, renewal: {
    ...entry.renewal, offerPeriod: 'P2W', offerDiscountType: 'PAY_AS_YOU_GO', renewalPrice: 7990 } }, now);
  for (const key of ['one_month', 'free_trial', 'zero_price']) assert.equal(wrong[key], false);
  for (const key of ['period_present', 'discount_present', 'price_present', 'price_positive']) assert.equal(wrong[key], true);
});
test('each pending predicate is diagnosed independently without private values', () => {
  const cases = [
    ['status_active', { status: 2 }], ['unrevoked', { transaction: { revocationDate: now } }],
    ['unexpired', { transaction: { expiresDate: now } }],
    ['current_product_match', { renewal: { productId: 'other' } }],
    ['renewal_product_match', { renewal: { autoRenewProductId: 'other' } }],
    ['configured_offer_match', { renewal: { offerIdentifier: 'other' } }],
    ['free_trial', { renewal: { offerDiscountType: 'other' } }],
    ['one_month', { renewal: { offerPeriod: 'P2W' } }], ['zero_price', { renewal: { renewalPrice: '0' } }],
    ['auto_renew_on', { renewal: { autoRenewStatus: 0 } }],
    ['renewal_date_valid', { renewal: { renewalDate: undefined } }],
  ];
  for (const [key, mutation] of cases) {
    const checks = pendingCampaignVerificationChecks({ ...entry, ...mutation,
      transaction: { ...entry.transaction, ...mutation.transaction }, renewal: { ...entry.renewal, ...mutation.renewal } }, now);
    assert.equal(checks[key], false); assert.ok(Object.values(checks).every(value => typeof value === 'boolean'));
    assert.ok(!JSON.stringify(checks).includes(owner)); assert.ok(!JSON.stringify(checks).includes('1001'));
  }
});
test('configuration reads a diagnostic deadline only for explicitly selected Sandbox', () => {
  const env = { ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED: 'false', APP_STORE_ENVIRONMENT: 'Sandbox',
    ICHART_COMPLIMENTARY_SANDBOX_DIAGNOSTIC_ENDS_AT: new Date(now + 1000).toISOString() };
  assert.ok(Number.isNaN(complimentaryCampaignConfigurationFromEnv(env).sandboxDiagnosticEndsAt));
  const selected = complimentaryCampaignConfigurationFromEnv({ ...env, ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT: 'Sandbox' });
  assert.equal(selected.enabled, false); assert.equal(selected.sandboxDiagnosticEndsAt, now + 1000);
  assert.ok(Number.isNaN(complimentaryCampaignConfigurationFromEnv({ ...env,
    ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT: 'Production' }).sandboxDiagnosticEndsAt));
});

test('payment mode diagnostics classify exact enums only and never emit raw values', async () => {
  const cases = [
    ['FREE_TRIAL', 'free_trial'], ['PAY_AS_YOU_GO', 'pay_as_you_go'], ['PAY_UP_FRONT', 'pay_up_front'],
    ['ONE_TIME', 'one_time'], [undefined, 'missing'], [null, 'null_value'], [0, 'invalid_type'],
    ['FreeTrial', 'other_string'], ['private-apple-value', 'other_string'], [' FREE_TRIAL', 'other_string'],
  ];
  for (const [value, expected] of cases) {
    assert.equal(pendingCampaignDiscountCategory(value), expected);
    const result = await run({ statuses: [{ ...entry, renewal: { ...entry.renewal, offerDiscountType: value } }] });
    assert.equal(result.body.pendingDiscountCategory, expected);
    assert.equal(result.body.pendingVerificationChecks.free_trial, value === 'FREE_TRIAL');
    assert.ok(!JSON.stringify(result.body).includes('private-apple-value'));
  }
});
