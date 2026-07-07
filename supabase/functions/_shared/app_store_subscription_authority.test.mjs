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

function oversizedStream(firstChunkBytes, secondChunkBytes) {
  let pulls = 0;
  return {
    body: new ReadableStream({
      pull(controller) {
        pulls += 1;
        if (pulls === 1) {
          controller.enqueue(new Uint8Array(firstChunkBytes));
          return;
        }
        if (pulls === 2) {
          controller.enqueue(new Uint8Array(secondChunkBytes));
          return;
        }
        throw new Error("bounded body reader should stop after the size cap is crossed");
      },
    }),
    pulls: () => pulls,
  };
}

test("maps active pro renewal into server-owned subscription authority fields", () => {
  const update = subscriptionAuthorityUpdateFromVerifiedNotification(
    {
      notificationType: "DID_RENEW",
      environment: "Sandbox",
      transactionInfo: {
        productId: iChartProProductIDs[1],
        originalTransactionId: "1000000000000001",
        transactionId: "1000000000000002",
        appAccountToken: "00000000-0000-4000-8000-000000000001",
        signedDate: Date.parse("2026-06-12T21:29:00.000Z"),
        expiresDate: futureExpiration,
      },
      notificationUUID: "notification-0001",
      signedDate: Date.parse("2026-06-12T21:29:30.000Z"),
    },
    { now }
  );

  assert.equal(update.provider, "storekit");
  assert.equal(update.plan, "studioSubscription");
  assert.equal(update.status, "active");
  assert.equal(update.storekit_environment, "sandbox");
  assert.equal(update.storekit_app_account_token, "00000000-0000-4000-8000-000000000001");
  assert.equal(update.app_store_status, "active");
  assert.equal(update.app_store_notification_uuid, "notification-0001");
  assert.equal(update.app_store_signed_at, "2026-06-12T21:29:30.000Z");
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
        productId: "com.ichart.app.unrecognized",
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
      appAccountToken: "00000000-0000-4000-8000-000000000001",
      environment: "Sandbox",
      signedDate: Date.parse("2026-06-12T21:29:00.000Z"),
      expiresDate: futureExpiration,
    },
    { now }
  );

  assert.equal(update.provider, "storekit");
  assert.equal(update.plan, "studioSubscription");
  assert.equal(update.status, "active");
  assert.equal(update.storekit_app_account_token, "00000000-0000-4000-8000-000000000001");
  assert.equal(update.app_store_notification_type, "TRANSACTION_CLAIM");
  assert.equal(update.app_store_status, "active");
  assert.equal(update.app_store_signed_at, "2026-06-12T21:29:00.000Z");
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

test("webhook rejects oversized request bodies before verification", async () => {
  let verifiedPayload = false;
  const response = await handleAppStoreServerNotificationRequest(
    new Request(
      "https://example.test/functions/v1/app-store-server-notifications",
      {
        method: "POST",
        headers: { "content-length": "128001" },
        body: JSON.stringify({ signedPayload: "opaque-apple-signed-payload" }),
      }
    ),
    {
      verifyAndDecodeNotification: () => {
        verifiedPayload = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 413);
  assert.equal(body.error, "App Store notification payload is too large.");
  assert.equal(verifiedPayload, false);
});

test("webhook rejects streamed oversized request bodies before reading the full stream", async () => {
  let verifiedPayload = false;
  const oversized = oversizedStream(127_999, 2);
  const response = await handleAppStoreServerNotificationRequest(
    new Request(
      "https://example.test/functions/v1/app-store-server-notifications",
      {
        method: "POST",
        body: oversized.body,
        duplex: "half",
      }
    ),
    {
      verifyAndDecodeNotification: () => {
        verifiedPayload = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 413);
  assert.equal(body.error, "App Store notification payload is too large.");
  assert.equal(verifiedPayload, false);
  assert.equal(oversized.pulls(), 2);
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
          appAccountToken: "00000000-0000-4000-8000-000000000001",
          signedDate: Date.parse("2026-06-12T21:29:00.000Z"),
          expiresDate: futureExpiration,
        },
        notificationUUID: "notification-0010",
        signedDate: Date.parse("2026-06-12T21:29:30.000Z"),
      }),
      writeSubscriptionAuthority: async (update) => {
        writtenUpdate = update;
        return {
          stored: true,
          mapping_status: "updated",
          subscription: {
            owner_id: "00000000-0000-4000-8000-000000000001",
            provider: "storekit",
          },
        };
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.accepted, true);
  assert.equal(body.stored, true);
  assert.equal(body.mapping_status, "updated");
  assert.equal(body.subscription.provider, "storekit");
  assert.equal(writtenUpdate.provider, "storekit");
  assert.equal(writtenUpdate.plan, "studioSubscription");
  assert.equal(writtenUpdate.app_store_notification_uuid, "notification-0010");
  assert.equal(writtenUpdate.app_store_signed_at, "2026-06-12T21:29:30.000Z");
});

test("webhook accepts verified unmapped transactions without inventing ownership", async () => {
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
          originalTransactionId: "1000000000000999",
          transactionId: "1000000000001000",
          appAccountToken: "00000000-0000-4000-8000-000000000001",
          signedDate: Date.parse("2026-06-12T21:29:00.000Z"),
          expiresDate: futureExpiration,
        },
        notificationUUID: "notification-0999",
        signedDate: Date.parse("2026-06-12T21:29:30.000Z"),
      }),
      writeSubscriptionAuthority: async () => ({
        stored: false,
        mapping_status: "unmapped_original_transaction",
      }),
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.accepted, true);
  assert.equal(body.stored, false);
  assert.equal(body.mapping_status, "unmapped_original_transaction");
  assert.equal(body.subscription, null);
});

test("webhook does not echo subscription rows for duplicate writer rejections", async () => {
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
          originalTransactionId: "1000000000000999",
          transactionId: "1000000000001000",
          appAccountToken: "00000000-0000-4000-8000-000000000001",
          signedDate: Date.parse("2026-06-12T21:29:00.000Z"),
          expiresDate: futureExpiration,
        },
        notificationUUID: "notification-0999",
        signedDate: Date.parse("2026-06-12T21:29:30.000Z"),
      }),
      writeSubscriptionAuthority: async () => ({
        stored: false,
        mapping_status: "duplicate_notification",
        subscription: {
          owner_id: "00000000-0000-4000-8000-000000000002",
          provider: "storekit",
        },
      }),
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.stored, false);
  assert.equal(body.mapping_status, "duplicate_notification");
  assert.equal(body.subscription, null);
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

test("transaction claim rejects streamed oversized request bodies before verification", async () => {
  let resolvedUser = false;
  let verifiedTransaction = false;
  const oversized = oversizedStream(31_999, 2);
  const response = await handleStoreKitSubscriptionClaimRequest(
    new Request(
      "https://example.test/functions/v1/storekit-subscription-claims",
      {
        method: "POST",
        headers: { authorization: "Bearer user-session-token" },
        body: oversized.body,
        duplex: "half",
      }
    ),
    {
      authenticatedUserID: async () => {
        resolvedUser = true;
      },
      verifyAndDecodeTransaction: async () => {
        verifiedTransaction = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 413);
  assert.equal(body.error, "StoreKit transaction claim payload is too large.");
  assert.equal(resolvedUser, false);
  assert.equal(verifiedTransaction, false);
  assert.equal(oversized.pulls(), 2);
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
        productId: "com.ichart.app.basic",
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
        appAccountToken: "00000000-0000-4000-8000-000000000001",
        environment: "Sandbox",
        signedDate: Date.parse("2026-06-12T21:29:00.000Z"),
        expiresDate: futureExpiration,
      }),
      writeSubscriptionAuthorityClaim: async (claim) => {
        writtenClaim = claim;
        return {
          stored: true,
          mapping_status: "claimed",
          subscription: {
            owner_id: "00000000-0000-4000-8000-000000000001",
            provider: "storekit",
            plan: "studioSubscription",
            status: "active",
          },
        };
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.accepted, true);
  assert.equal(body.stored, true);
  assert.equal(body.mapping_status, "claimed");
  assert.equal(body.subscription.plan, "studioSubscription");
  assert.equal(writtenClaim.ownerID, "00000000-0000-4000-8000-000000000001");
  assert.equal(writtenClaim.authorityUpdate.plan, "studioSubscription");
  assert.equal(writtenClaim.authorityUpdate.storekit_app_account_token, "00000000-0000-4000-8000-000000000001");
});

test("transaction claim rejects verified transactions without app account token", async () => {
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
      authenticatedUserID: async () => "00000000-0000-4000-8000-000000000001",
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

  assert.equal(response.status, 422);
  assert.equal(body.error, "Verified StoreKit transaction is missing app account binding.");
  assert.equal(wroteClaim, false);
});

test("transaction claim rejects app account token mismatch", async () => {
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
      authenticatedUserID: async () => "00000000-0000-4000-8000-000000000001",
      verifyAndDecodeTransaction: async () => ({
        productId: iChartProProductIDs[0],
        originalTransactionId: "1000000000000200",
        transactionId: "1000000000000201",
        appAccountToken: "00000000-0000-4000-8000-000000000002",
        expiresDate: futureExpiration,
      }),
      writeSubscriptionAuthorityClaim: () => {
        wroteClaim = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 403);
  assert.equal(body.error, "Verified StoreKit transaction belongs to a different iChart account.");
  assert.equal(wroteClaim, false);
});

test("transaction claim returns conflict for stale writer rejections", async () => {
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
        productId: iChartProProductIDs[0],
        originalTransactionId: "1000000000000200",
        transactionId: "1000000000000201",
        appAccountToken: "00000000-0000-4000-8000-000000000001",
        signedDate: Date.parse("2026-06-12T21:29:00.000Z"),
        expiresDate: futureExpiration,
      }),
      writeSubscriptionAuthorityClaim: async () => ({
        stored: false,
        mapping_status: "stale_transaction_claim",
        subscription: {
          owner_id: "00000000-0000-4000-8000-000000000001",
          provider: "storekit",
        },
      }),
    }
  );
  const body = await response.json();

  assert.equal(response.status, 409);
  assert.equal(body.stored, false);
  assert.equal(body.mapping_status, "stale_transaction_claim");
  assert.equal(body.subscription, null);
});
