import assert from "node:assert/strict";
import test from "node:test";

import {
  appStoreStatusFromVerifiedNotification,
  handleAppStoreServerNotificationRequest,
  handleStoreKitSubscriptionClaimRequest,
  iChartProProductIDs,
  subscriptionAuthorityUpdateFromVerifiedNotification,
  subscriptionAuthorityUpdateFromVerifiedTransaction,
} from "./app_store_subscription_authority.mjs";

const now = new Date("2026-06-12T21:30:00.000Z");
const futureExpiration = Date.parse("2026-07-12T21:30:00.000Z");
const futureGrace = Date.parse("2026-06-19T21:30:00.000Z");

test("maps active pro renewal into server-owned subscription authority fields", () => {
  const update = subscriptionAuthorityUpdateFromVerifiedNotification(
    {
      notificationType: "DID_RENEW",
      environment: "Sandbox",
      transactionInfo: {
        productId: iChartProProductIDs[1],
        originalTransactionId: "1000000000000001",
        transactionId: "1000000000000002",
        expiresDate: futureExpiration,
      },
    },
    { now }
  );

  assert.equal(update.provider, "storekit");
  assert.equal(update.plan, "studioSubscription");
  assert.equal(update.status, "active");
  assert.equal(update.storekit_environment, "sandbox");
  assert.equal(update.app_store_status, "active");
  assert.equal(update.entitlement_expires_at, "2026-07-12T21:30:00.000Z");
  assert.equal(update.last_verified_at, now.toISOString());
});

test("maps failed renewal with grace as non-active pro grace state", () => {
  const update = subscriptionAuthorityUpdateFromVerifiedNotification(
    {
      notificationType: "DID_FAIL_TO_RENEW",
      subtype: "GRACE_PERIOD",
      environment: "Production",
      transactionInfo: {
        productId: iChartProProductIDs[0],
        originalTransactionId: "1000000000000001",
        transactionId: "1000000000000003",
        expiresDate: Date.parse("2026-06-11T21:30:00.000Z"),
      },
      renewalInfo: {
        gracePeriodExpiresDate: futureGrace,
      },
    },
    { now }
  );

  assert.equal(update.plan, "free");
  assert.equal(update.status, "inactive");
  assert.equal(update.storekit_environment, "production");
  assert.equal(update.app_store_status, "grace");
  assert.equal(update.grace_period_expires_at, "2026-06-19T21:30:00.000Z");
});

test("maps expired notification to inactive basic authority", () => {
  const update = subscriptionAuthorityUpdateFromVerifiedNotification(
    {
      notificationType: "EXPIRED",
      environment: "Sandbox",
      transactionInfo: {
        productId: iChartProProductIDs[0],
        originalTransactionId: "1000000000000001",
        transactionId: "1000000000000004",
        expiresDate: Date.parse("2026-06-01T21:30:00.000Z"),
      },
    },
    { now }
  );

  assert.equal(update.plan, "free");
  assert.equal(update.status, "inactive");
  assert.equal(update.app_store_status, "expired");
});

test("unknown products never unlock pro even if Apple lifecycle is active", () => {
  const update = subscriptionAuthorityUpdateFromVerifiedNotification(
    {
      notificationType: "DID_RENEW",
      environment: "Sandbox",
      transactionInfo: {
        productId: "com.smartchart.app.unrecognized",
        originalTransactionId: "1000000000000001",
        transactionId: "1000000000000005",
        expiresDate: futureExpiration,
      },
    },
    { now }
  );

  assert.equal(update.plan, "free");
  assert.equal(update.status, "inactive");
  assert.equal(update.app_store_status, "active");
});

test("status mapping keeps billing retry distinct from grace", () => {
  assert.equal(
    appStoreStatusFromVerifiedNotification(
      {
        notificationType: "DID_FAIL_TO_RENEW",
        subtype: "BILLING_RETRY",
      },
      now
    ),
    "billing_retry"
  );
});

test("maps verified transaction claim into active pro authority fields", () => {
  const update = subscriptionAuthorityUpdateFromVerifiedTransaction(
    {
      productId: iChartProProductIDs[0],
      originalTransactionId: "1000000000000100",
      transactionId: "1000000000000101",
      environment: "Sandbox",
      expiresDate: futureExpiration,
    },
    { now }
  );

  assert.equal(update.provider, "storekit");
  assert.equal(update.plan, "studioSubscription");
  assert.equal(update.status, "active");
  assert.equal(update.app_store_notification_type, "TRANSACTION_CLAIM");
  assert.equal(update.app_store_status, "active");
});

test("expired verified transaction claim records inactive authority", () => {
  const update = subscriptionAuthorityUpdateFromVerifiedTransaction(
    {
      productId: iChartProProductIDs[0],
      originalTransactionId: "1000000000000100",
      transactionId: "1000000000000102",
      environment: "Production",
      expiresDate: Date.parse("2026-06-01T21:30:00.000Z"),
    },
    { now }
  );

  assert.equal(update.plan, "free");
  assert.equal(update.status, "inactive");
  assert.equal(update.storekit_environment, "production");
  assert.equal(update.app_store_status, "expired");
});

test("webhook rejects non-post requests", async () => {
  const response = await handleAppStoreServerNotificationRequest(
    new Request("https://example.test/functions/v1/app-store-server-notifications")
  );
  const body = await response.json();

  assert.equal(response.status, 405);
  assert.equal(body.accepted, false);
});

test("webhook requires signedPayload", async () => {
  const response = await handleAppStoreServerNotificationRequest(
    new Request(
      "https://example.test/functions/v1/app-store-server-notifications",
      {
        method: "POST",
        body: JSON.stringify({}),
      }
    )
  );
  const body = await response.json();

  assert.equal(response.status, 400);
  assert.equal(body.error, "Missing App Store signedPayload.");
});

test("webhook refuses to process signedPayload without verifier", async () => {
  let wroteSubscription = false;
  const response = await handleAppStoreServerNotificationRequest(
    new Request(
      "https://example.test/functions/v1/app-store-server-notifications",
      {
        method: "POST",
        body: JSON.stringify({ signedPayload: "opaque-apple-signed-payload" }),
      }
    ),
    {
      writeSubscriptionAuthority: () => {
        wroteSubscription = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 501);
  assert.equal(body.error, "App Store signedPayload verification is not configured.");
  assert.equal(wroteSubscription, false);
});

test("webhook refuses nested signed payloads until nested verifiers are configured", async () => {
  let wroteSubscription = false;
  const response = await handleAppStoreServerNotificationRequest(
    new Request(
      "https://example.test/functions/v1/app-store-server-notifications",
      {
        method: "POST",
        body: JSON.stringify({ signedPayload: "opaque-apple-signed-payload" }),
      }
    ),
    {
      verifyAndDecodeNotification: async () => ({
        notificationType: "DID_RENEW",
        data: {
          environment: "Sandbox",
          signedTransactionInfo: "opaque-apple-transaction-payload",
        },
      }),
      writeSubscriptionAuthority: () => {
        wroteSubscription = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 501);
  assert.equal(body.error, "Nested App Store signed payload verification is not configured.");
  assert.equal(wroteSubscription, false);
});

test("webhook refuses verified payloads without subscription identity fields", async () => {
  let wroteSubscription = false;
  const response = await handleAppStoreServerNotificationRequest(
    new Request(
      "https://example.test/functions/v1/app-store-server-notifications",
      {
        method: "POST",
        body: JSON.stringify({ signedPayload: "opaque-apple-signed-payload" }),
      }
    ),
    {
      verifyAndDecodeNotification: async () => ({
        notificationType: "DID_RENEW",
        environment: "Sandbox",
        transactionInfo: {
          expiresDate: futureExpiration,
        },
      }),
      writeSubscriptionAuthority: () => {
        wroteSubscription = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 422);
  assert.equal(body.error, "Verified App Store payload is missing subscription identity fields.");
  assert.equal(wroteSubscription, false);
});

test("webhook writes only after verification dependencies succeed", async () => {
  let writtenUpdate = null;
  const response = await handleAppStoreServerNotificationRequest(
    new Request(
      "https://example.test/functions/v1/app-store-server-notifications",
      {
        method: "POST",
        body: JSON.stringify({ signedPayload: "opaque-apple-signed-payload" }),
      }
    ),
    {
      now,
      verifyAndDecodeNotification: async () => ({
        notificationType: "DID_RENEW",
        environment: "Sandbox",
        transactionInfo: {
          productId: iChartProProductIDs[0],
          originalTransactionId: "1000000000000010",
          transactionId: "1000000000000011",
          expiresDate: futureExpiration,
        },
      }),
      writeSubscriptionAuthority: async (update) => {
        writtenUpdate = update;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.accepted, true);
  assert.equal(writtenUpdate.provider, "storekit");
  assert.equal(writtenUpdate.plan, "studioSubscription");
});

test("transaction claim requires signed-in account bearer header", async () => {
  const response = await handleStoreKitSubscriptionClaimRequest(
    new Request(
      "https://example.test/functions/v1/storekit-subscription-claims",
      {
        method: "POST",
        body: JSON.stringify({ signedTransactionInfo: "opaque-apple-transaction-payload" }),
      }
    )
  );
  const body = await response.json();

  assert.equal(response.status, 401);
  assert.equal(body.error, "A signed-in iChart account is required.");
});

test("transaction claim requires signedTransactionInfo", async () => {
  const response = await handleStoreKitSubscriptionClaimRequest(
    new Request(
      "https://example.test/functions/v1/storekit-subscription-claims",
      {
        method: "POST",
        headers: { authorization: "Bearer user-session-token" },
        body: JSON.stringify({}),
      }
    )
  );
  const body = await response.json();

  assert.equal(response.status, 400);
  assert.equal(body.error, "Missing StoreKit signedTransactionInfo.");
});

test("transaction claim refuses to process without verifier", async () => {
  let wroteClaim = false;
  const response = await handleStoreKitSubscriptionClaimRequest(
    new Request(
      "https://example.test/functions/v1/storekit-subscription-claims",
      {
        method: "POST",
        headers: { authorization: "Bearer user-session-token" },
        body: JSON.stringify({ signedTransactionInfo: "opaque-apple-transaction-payload" }),
      }
    ),
    {
      writeSubscriptionAuthorityClaim: () => {
        wroteClaim = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 501);
  assert.equal(body.error, "StoreKit signed transaction verification is not configured.");
  assert.equal(wroteClaim, false);
});

test("transaction claim rejects non-pro products after verification", async () => {
  let wroteClaim = false;
  const response = await handleStoreKitSubscriptionClaimRequest(
    new Request(
      "https://example.test/functions/v1/storekit-subscription-claims",
      {
        method: "POST",
        headers: { authorization: "Bearer user-session-token" },
        body: JSON.stringify({ signedTransactionInfo: "opaque-apple-transaction-payload" }),
      }
    ),
    {
      now,
      verifyAndDecodeTransaction: async () => ({
        productId: "com.smartchart.app.basic",
        originalTransactionId: "1000000000000200",
        transactionId: "1000000000000201",
        expiresDate: futureExpiration,
      }),
      writeSubscriptionAuthorityClaim: () => {
        wroteClaim = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 422);
  assert.equal(body.error, "Verified StoreKit transaction is not an iChart Pro subscription.");
  assert.equal(wroteClaim, false);
});

test("transaction claim refuses verified transactions without identity", async () => {
  let wroteClaim = false;
  const response = await handleStoreKitSubscriptionClaimRequest(
    new Request(
      "https://example.test/functions/v1/storekit-subscription-claims",
      {
        method: "POST",
        headers: { authorization: "Bearer user-session-token" },
        body: JSON.stringify({ signedTransactionInfo: "opaque-apple-transaction-payload" }),
      }
    ),
    {
      now,
      verifyAndDecodeTransaction: async () => ({
        productId: iChartProProductIDs[0],
        transactionId: "1000000000000201",
        expiresDate: futureExpiration,
      }),
      writeSubscriptionAuthorityClaim: () => {
        wroteClaim = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 422);
  assert.equal(body.error, "Verified StoreKit transaction is missing subscription identity fields.");
  assert.equal(wroteClaim, false);
});

test("transaction claim refuses to write without authenticated user resolver", async () => {
  let wroteClaim = false;
  const response = await handleStoreKitSubscriptionClaimRequest(
    new Request(
      "https://example.test/functions/v1/storekit-subscription-claims",
      {
        method: "POST",
        headers: { authorization: "Bearer user-session-token" },
        body: JSON.stringify({ signedTransactionInfo: "opaque-apple-transaction-payload" }),
      }
    ),
    {
      now,
      verifyAndDecodeTransaction: async () => ({
        productId: iChartProProductIDs[0],
        originalTransactionId: "1000000000000200",
        transactionId: "1000000000000201",
        expiresDate: futureExpiration,
      }),
      writeSubscriptionAuthorityClaim: () => {
        wroteClaim = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 501);
  assert.equal(body.error, "Authenticated user resolver is not configured.");
  assert.equal(wroteClaim, false);
});

test("transaction claim writes only after user and transaction are verified", async () => {
  let writtenClaim = null;
  const response = await handleStoreKitSubscriptionClaimRequest(
    new Request(
      "https://example.test/functions/v1/storekit-subscription-claims",
      {
        method: "POST",
        headers: { authorization: "Bearer user-session-token" },
        body: JSON.stringify({ signedTransactionInfo: "opaque-apple-transaction-payload" }),
      }
    ),
    {
      now,
      authenticatedUserID: async () => "00000000-0000-4000-8000-000000000001",
      verifyAndDecodeTransaction: async () => ({
        productId: iChartProProductIDs[1],
        originalTransactionId: "1000000000000200",
        transactionId: "1000000000000201",
        environment: "Sandbox",
        expiresDate: futureExpiration,
      }),
      writeSubscriptionAuthorityClaim: async (claim) => {
        writtenClaim = claim;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.accepted, true);
  assert.equal(writtenClaim.ownerID, "00000000-0000-4000-8000-000000000001");
  assert.equal(writtenClaim.authorityUpdate.plan, "studioSubscription");
});
