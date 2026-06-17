export const storeKitProvider = "storekit";

export const iChartProProductIDs = Object.freeze([
  "com.smartchart.app.pro.monthly",
  "com.smartchart.app.pro.annual",
]);

const activeNotificationTypes = new Set([
  "DID_CHANGE_RENEWAL_PREF",
  "DID_CHANGE_RENEWAL_STATUS",
  "DID_RECOVER",
  "DID_RENEW",
  "OFFER_REDEEMED",
  "PRICE_INCREASE",
  "REFUND_REVERSED",
  "RENEWAL_EXTENDED",
  "SUBSCRIBED",
]);

export function isIChartProProductID(productID) {
  return iChartProProductIDs.includes(normalizedString(productID));
}

export function normalizeStoreKitEnvironment(environment) {
  const value = normalizedString(environment).toLowerCase();

  if (value === "sandbox") {
    return "sandbox";
  }

  if (value === "production") {
    return "production";
  }

  return null;
}

export function appleDateToISOString(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (value instanceof Date) {
    return validDateISOString(value);
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    return validDateISOString(dateFromAppleTimestamp(value));
  }

  const stringValue = normalizedString(value);
  if (stringValue.length === 0) {
    return null;
  }

  if (/^\d+$/.test(stringValue)) {
    return validDateISOString(dateFromAppleTimestamp(Number(stringValue)));
  }

  return validDateISOString(new Date(stringValue));
}

export function appStoreStatusFromVerifiedNotification(notification, now = new Date()) {
  const notificationType = normalizedUpper(notification?.notificationType);
  const subtype = normalizedUpper(notification?.subtype);
  const gracePeriodExpiresAt = appleDateToISOString(notification?.gracePeriodExpiresAt);
  const expiresAt = appleDateToISOString(notification?.expiresAt);
  const revokedAt = appleDateToISOString(notification?.revokedAt);
  const nowTime = dateFromInput(now).getTime();

  if (notificationType === "REFUND") {
    return "refunded";
  }

  if (notificationType === "REVOKE" || revokedAt !== null) {
    return "revoked";
  }

  if (notificationType === "EXPIRED" || notificationType === "GRACE_PERIOD_EXPIRED") {
    return "expired";
  }

  if (notificationType === "DID_FAIL_TO_RENEW") {
    if (subtype === "GRACE_PERIOD" || isFuture(gracePeriodExpiresAt, nowTime)) {
      return "grace";
    }

    return "billing_retry";
  }

  if (activeNotificationTypes.has(notificationType) && isFuture(expiresAt, nowTime)) {
    return "active";
  }

  if (isFuture(expiresAt, nowTime)) {
    return "active";
  }

  return "expired";
}

export function subscriptionAuthorityUpdateFromVerifiedNotification(notification, options = {}) {
  if (!notification || typeof notification !== "object") {
    throw new TypeError("A verified App Store notification object is required.");
  }

  const now = dateFromInput(options.now ?? new Date());
  const nowISOString = now.toISOString();
  const transactionInfo = notification.transactionInfo ?? notification.data?.transactionInfo ?? {};
  const renewalInfo = notification.renewalInfo ?? notification.data?.renewalInfo ?? {};
  const productID = normalizedString(
    transactionInfo.productId
      ?? transactionInfo.productID
      ?? transactionInfo.product_id
      ?? notification.productId
      ?? notification.productID
  );
  const originalTransactionID = normalizedString(
    transactionInfo.originalTransactionId
      ?? transactionInfo.originalTransactionID
      ?? transactionInfo.original_transaction_id
  );
  const transactionID = normalizedString(
    transactionInfo.transactionId
      ?? transactionInfo.transactionID
      ?? transactionInfo.transaction_id
  );
  const environment = normalizeStoreKitEnvironment(
    notification.environment
      ?? notification.data?.environment
      ?? transactionInfo.environment
  );
  const expiresAt = appleDateToISOString(
    transactionInfo.expiresDate
      ?? transactionInfo.expiresDateMs
      ?? transactionInfo.expirationDate
      ?? notification.expiresAt
  );
  const gracePeriodExpiresAt = appleDateToISOString(
    renewalInfo.gracePeriodExpiresDate
      ?? renewalInfo.gracePeriodExpiresAt
      ?? transactionInfo.gracePeriodExpiresDate
      ?? notification.gracePeriodExpiresAt
  );
  const revokedAt = appleDateToISOString(
    transactionInfo.revocationDate
      ?? notification.revokedAt
  );
  const appStoreStatus = appStoreStatusFromVerifiedNotification(
    {
      notificationType: notification.notificationType,
      subtype: notification.subtype,
      expiresAt,
      gracePeriodExpiresAt,
      revokedAt,
    },
    now
  );
  const grantsActivePro = isIChartProProductID(productID)
    && appStoreStatus === "active"
    && isFuture(expiresAt, now.getTime());

  return {
    provider: storeKitProvider,
    plan: grantsActivePro ? "studioSubscription" : "free",
    status: grantsActivePro ? "active" : "inactive",
    storekit_product_id: productID.length > 0 ? productID : null,
    storekit_original_transaction_id: originalTransactionID.length > 0 ? originalTransactionID : null,
    storekit_environment: environment,
    app_store_status: appStoreStatus,
    app_store_notification_type: normalizedString(notification.notificationType) || null,
    app_store_last_transaction_id: transactionID.length > 0 ? transactionID : null,
    current_period_end: expiresAt ?? gracePeriodExpiresAt,
    entitlement_expires_at: expiresAt,
    grace_period_expires_at: gracePeriodExpiresAt,
    revoked_at: revokedAt,
    last_verified_at: nowISOString,
  };
}

export function subscriptionAuthorityUpdateFromVerifiedTransaction(transactionInfo, options = {}) {
  if (!transactionInfo || typeof transactionInfo !== "object") {
    throw new TypeError("A verified StoreKit transaction object is required.");
  }

  const now = dateFromInput(options.now ?? new Date());
  const nowISOString = now.toISOString();
  const productID = normalizedString(
    transactionInfo.productId
      ?? transactionInfo.productID
      ?? transactionInfo.product_id
  );
  const originalTransactionID = normalizedString(
    transactionInfo.originalTransactionId
      ?? transactionInfo.originalTransactionID
      ?? transactionInfo.original_transaction_id
  );
  const transactionID = normalizedString(
    transactionInfo.transactionId
      ?? transactionInfo.transactionID
      ?? transactionInfo.transaction_id
  );
  const environment = normalizeStoreKitEnvironment(transactionInfo.environment);
  const expiresAt = appleDateToISOString(
    transactionInfo.expiresDate
      ?? transactionInfo.expiresDateMs
      ?? transactionInfo.expirationDate
  );
  const revokedAt = appleDateToISOString(transactionInfo.revocationDate);
  const appStoreStatus = revokedAt !== null
    ? "revoked"
    : isFuture(expiresAt, now.getTime()) ? "active" : "expired";
  const grantsActivePro = isIChartProProductID(productID)
    && appStoreStatus === "active"
    && isFuture(expiresAt, now.getTime());

  return {
    provider: storeKitProvider,
    plan: grantsActivePro ? "studioSubscription" : "free",
    status: grantsActivePro ? "active" : "inactive",
    storekit_product_id: productID.length > 0 ? productID : null,
    storekit_original_transaction_id: originalTransactionID.length > 0 ? originalTransactionID : null,
    storekit_environment: environment,
    app_store_status: appStoreStatus,
    app_store_notification_type: normalizedString(options.source) || "TRANSACTION_CLAIM",
    app_store_last_transaction_id: transactionID.length > 0 ? transactionID : null,
    current_period_end: expiresAt,
    entitlement_expires_at: expiresAt,
    grace_period_expires_at: null,
    revoked_at: revokedAt,
    last_verified_at: nowISOString,
  };
}

export async function handleAppStoreServerNotificationRequest(request, dependencies = {}) {
  if (request.method !== "POST") {
    return jsonResponse(405, {
      accepted: false,
      error: "Use POST for App Store Server Notifications.",
    });
  }

  const body = await readJSON(request);
  if (!body.ok) {
    return jsonResponse(400, {
      accepted: false,
      error: "Request body must be valid JSON.",
    });
  }

  const signedPayload = body.value?.signedPayload;
  if (typeof signedPayload !== "string" || signedPayload.trim().length === 0) {
    return jsonResponse(400, {
      accepted: false,
      error: "Missing App Store signedPayload.",
    });
  }

  if (typeof dependencies.verifyAndDecodeNotification !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "App Store signedPayload verification is not configured.",
    });
  }

  let decodedNotification;
  try {
    decodedNotification = await dependencies.verifyAndDecodeNotification(signedPayload);
  } catch {
    return jsonResponse(401, {
      accepted: false,
      error: "App Store signedPayload verification failed.",
    });
  }

  let transactionInfo;
  let renewalInfo;
  try {
    transactionInfo = await decodeNestedSignedPayload(
      decodedNotification?.data?.signedTransactionInfo,
      dependencies.verifyAndDecodeTransaction,
      decodedNotification?.transactionInfo
    );
    renewalInfo = await decodeNestedSignedPayload(
      decodedNotification?.data?.signedRenewalInfo,
      dependencies.verifyAndDecodeRenewalInfo,
      decodedNotification?.renewalInfo
    );
  } catch {
    return jsonResponse(501, {
      accepted: false,
      error: "Nested App Store signed payload verification is not configured.",
    });
  }

  const authorityUpdate = subscriptionAuthorityUpdateFromVerifiedNotification(
    {
      ...decodedNotification,
      transactionInfo,
      renewalInfo,
    },
    { now: dependencies.now ?? new Date() }
  );

  if (
    authorityUpdate.storekit_product_id === null
    || authorityUpdate.storekit_original_transaction_id === null
  ) {
    return jsonResponse(422, {
      accepted: false,
      error: "Verified App Store payload is missing subscription identity fields.",
    });
  }

  if (typeof dependencies.writeSubscriptionAuthority !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "Subscription authority writer is not configured.",
      app_store_status: authorityUpdate.app_store_status,
    });
  }

  const writeResult = await dependencies.writeSubscriptionAuthority(authorityUpdate);

  return jsonResponse(202, {
    accepted: true,
    app_store_status: authorityUpdate.app_store_status,
    stored: writeResult?.stored ?? true,
    mapping_status: writeResult?.mapping_status ?? "updated",
    subscription: writeResult?.subscription ?? null,
  });
}

export async function handleStoreKitSubscriptionClaimRequest(request, dependencies = {}) {
  if (request.method !== "POST") {
    return jsonResponse(405, {
      accepted: false,
      error: "Use POST to claim a StoreKit subscription transaction.",
    });
  }

  if (!hasBearerAuthorization(request)) {
    return jsonResponse(401, {
      accepted: false,
      error: "A signed-in iChart account is required.",
    });
  }

  const body = await readJSON(request);
  if (!body.ok) {
    return jsonResponse(400, {
      accepted: false,
      error: "Request body must be valid JSON.",
    });
  }

  const signedTransactionInfo = body.value?.signedTransactionInfo;
  if (typeof signedTransactionInfo !== "string" || signedTransactionInfo.trim().length === 0) {
    return jsonResponse(400, {
      accepted: false,
      error: "Missing StoreKit signedTransactionInfo.",
    });
  }

  if (typeof dependencies.verifyAndDecodeTransaction !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "StoreKit signed transaction verification is not configured.",
    });
  }

  let transactionInfo;
  try {
    transactionInfo = await dependencies.verifyAndDecodeTransaction(signedTransactionInfo);
  } catch {
    return jsonResponse(401, {
      accepted: false,
      error: "StoreKit signed transaction verification failed.",
    });
  }

  const authorityUpdate = subscriptionAuthorityUpdateFromVerifiedTransaction(
    transactionInfo,
    { now: dependencies.now ?? new Date() }
  );

  if (!isIChartProProductID(authorityUpdate.storekit_product_id)) {
    return jsonResponse(422, {
      accepted: false,
      error: "Verified StoreKit transaction is not an iChart Pro subscription.",
    });
  }

  if (
    authorityUpdate.storekit_product_id === null
    || authorityUpdate.storekit_original_transaction_id === null
  ) {
    return jsonResponse(422, {
      accepted: false,
      error: "Verified StoreKit transaction is missing subscription identity fields.",
    });
  }

  if (typeof dependencies.authenticatedUserID !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "Authenticated user resolver is not configured.",
    });
  }

  const ownerID = await dependencies.authenticatedUserID(request);
  if (typeof ownerID !== "string" || ownerID.trim().length === 0) {
    return jsonResponse(401, {
      accepted: false,
      error: "A signed-in iChart account is required.",
    });
  }

  if (typeof dependencies.writeSubscriptionAuthorityClaim !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "Subscription authority claim writer is not configured.",
      app_store_status: authorityUpdate.app_store_status,
    });
  }

  const claimResult = await dependencies.writeSubscriptionAuthorityClaim({
    ownerID: ownerID.trim(),
    authorityUpdate,
  });

  return jsonResponse(202, {
    accepted: true,
    app_store_status: authorityUpdate.app_store_status,
    stored: claimResult?.stored ?? true,
    mapping_status: claimResult?.mapping_status ?? "claimed",
    subscription: claimResult?.subscription ?? null,
  });
}

async function decodeNestedSignedPayload(signedPayload, decoder, fallback) {
  if (typeof signedPayload === "string" && signedPayload.length > 0) {
    if (typeof decoder !== "function") {
      throw new Error("Nested App Store signed payload decoder is not configured.");
    }

    return decoder(signedPayload);
  }

  return fallback ?? {};
}

async function readJSON(request) {
  try {
    return {
      ok: true,
      value: await request.json(),
    };
  } catch {
    return {
      ok: false,
      value: null,
    };
  }
}

function jsonResponse(status, body) {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
    },
  });
}

function hasBearerAuthorization(request) {
  const authorization = request.headers.get("authorization") ?? "";
  return /^Bearer\s+\S+/i.test(authorization);
}

function normalizedString(value) {
  if (value === null || value === undefined) {
    return "";
  }

  return String(value).trim();
}

function normalizedUpper(value) {
  return normalizedString(value).toUpperCase();
}

function dateFromInput(value) {
  if (value instanceof Date) {
    return value;
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new TypeError("A valid date is required.");
  }

  return date;
}

function dateFromAppleTimestamp(value) {
  const milliseconds = value < 10_000_000_000 ? value * 1_000 : value;
  return new Date(milliseconds);
}

function validDateISOString(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString();
}

function isFuture(isoString, nowTime) {
  if (isoString === null) {
    return false;
  }

  return new Date(isoString).getTime() > nowTime;
}
