export const storeKitProvider = "storekit";

export const iChartProProductIDs = Object.freeze([
  "com.ichart.app.pro.monthly",
  "com.ichart.app.pro.annual",
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
  const signedAt = appleDateToISOString(
    notification.signedDate
      ?? notification.signedDateMs
      ?? transactionInfo.signedDate
      ?? transactionInfo.signedDateMs
      ?? transactionInfo.signed_date
  );
  const notificationUUID = normalizedString(
    notification.notificationUUID
      ?? notification.notificationUuid
      ?? notification.notification_uuid
  );
  const appAccountToken = normalizedUUIDString(
    transactionInfo.appAccountToken
      ?? transactionInfo.appAccountTokenUUID
      ?? transactionInfo.app_account_token
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
  const autoRenewStatus = normalizedAutoRenewStatus(
    renewalInfo.autoRenewStatus
      ?? renewalInfo.autoRenewStatusRaw
      ?? renewalInfo.auto_renew_status
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
  const cloudRetentionDeadline = cloudRetentionDeadlineForAuthority({
    appStoreStatus,
    expiresAt,
    gracePeriodExpiresAt,
    revokedAt,
    now,
  });

  return {
    provider: storeKitProvider,
    plan: grantsActivePro ? "studioSubscription" : "free",
    status: grantsActivePro ? "active" : "inactive",
    storekit_product_id: productID.length > 0 ? productID : null,
    storekit_original_transaction_id: originalTransactionID.length > 0 ? originalTransactionID : null,
    storekit_app_account_token: appAccountToken,
    storekit_environment: environment,
    app_store_status: appStoreStatus,
    app_store_auto_renew_status: autoRenewStatus,
    app_store_notification_type: normalizedString(notification.notificationType) || null,
    app_store_notification_uuid: notificationUUID.length > 0 ? notificationUUID : null,
    app_store_last_transaction_id: transactionID.length > 0 ? transactionID : null,
    app_store_signed_at: signedAt,
    current_period_end: expiresAt ?? gracePeriodExpiresAt,
    entitlement_expires_at: expiresAt,
    grace_period_expires_at: gracePeriodExpiresAt,
    cloud_retention_deadline: cloudRetentionDeadline,
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
  const appAccountToken = normalizedUUIDString(
    transactionInfo.appAccountToken
      ?? transactionInfo.appAccountTokenUUID
      ?? transactionInfo.app_account_token
  );
  const signedAt = appleDateToISOString(
    transactionInfo.signedDate
      ?? transactionInfo.signedDateMs
      ?? transactionInfo.signed_date
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
  const cloudRetentionDeadline = cloudRetentionDeadlineForAuthority({
    appStoreStatus,
    expiresAt,
    gracePeriodExpiresAt: null,
    revokedAt,
    now,
  });

  return {
    provider: storeKitProvider,
    plan: grantsActivePro ? "studioSubscription" : "free",
    status: grantsActivePro ? "active" : "inactive",
    storekit_product_id: productID.length > 0 ? productID : null,
    storekit_original_transaction_id: originalTransactionID.length > 0 ? originalTransactionID : null,
    storekit_app_account_token: appAccountToken,
    storekit_environment: environment,
    app_store_status: appStoreStatus,
    app_store_auto_renew_status: null,
    app_store_notification_type: normalizedString(options.source) || "TRANSACTION_CLAIM",
    app_store_last_transaction_id: transactionID.length > 0 ? transactionID : null,
    app_store_signed_at: signedAt,
    app_store_notification_uuid: null,
    current_period_end: expiresAt,
    entitlement_expires_at: expiresAt,
    grace_period_expires_at: null,
    cloud_retention_deadline: cloudRetentionDeadline,
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

  const body = await readJSON(request, { maxBytes: 128_000 });
  if (!body.ok) {
    return jsonResponse(body.tooLarge ? 413 : 400, {
      accepted: false,
      error: body.tooLarge
        ? "App Store notification payload is too large."
        : "Request body must be valid JSON.",
    });
  }

  const signedPayload = body.value?.signedPayload;
  if (typeof signedPayload !== "string" || signedPayload.trim().length === 0) {
    return jsonResponse(400, {
      accepted: false,
      error: "Missing App Store signedPayload.",
    });
  }
  if (signedPayload.length > 100_000) {
    return jsonResponse(413, {
      accepted: false,
      error: "App Store signedPayload is too large.",
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

  const responseStatus = writeResult?.stored === false
    && staleOrDuplicateMappingStatuses.has(writeResult?.mapping_status)
    ? 202
    : 202;

  return jsonResponse(responseStatus, {
    accepted: true,
    app_store_status: authorityUpdate.app_store_status,
    stored: writeResult?.stored ?? true,
    mapping_status: writeResult?.mapping_status ?? "updated",
    subscription: responseSubscription(writeResult, staleOrDuplicateMappingStatuses),
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
    logStoreKitClaimRejection("missing_bearer");
    return jsonResponse(401, {
      accepted: false,
      error: "A signed-in iChart account is required.",
    });
  }

  const body = await readJSON(request, { maxBytes: 32_000 });
  if (!body.ok) {
    return jsonResponse(body.tooLarge ? 413 : 400, {
      accepted: false,
      error: body.tooLarge
        ? "StoreKit transaction claim payload is too large."
        : "Request body must be valid JSON.",
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
  } catch (error) {
    logStoreKitClaimRejection("transaction_verification_failed", safeVerificationErrorMetadata(error));
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
    logStoreKitClaimRejection("invalid_bearer");
    return jsonResponse(401, {
      accepted: false,
      error: "A signed-in iChart account is required.",
    });
  }

  if (authorityUpdate.storekit_app_account_token === null) {
    return jsonResponse(422, {
      accepted: false,
      error: "Verified StoreKit transaction is missing app account binding.",
    });
  }

  if (authorityUpdate.storekit_app_account_token !== normalizedUUIDString(ownerID)) {
    return jsonResponse(403, {
      accepted: false,
      error: "Verified StoreKit transaction belongs to a different iChart account.",
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

  const responseStatus = claimResult?.stored === false
    && rejectedClaimMappingStatuses.has(claimResult?.mapping_status)
    ? 409
    : 202;

  return jsonResponse(responseStatus, {
    accepted: true,
    app_store_status: authorityUpdate.app_store_status,
    stored: claimResult?.stored ?? true,
    mapping_status: claimResult?.mapping_status ?? "claimed",
    subscription: responseSubscription(claimResult, rejectedClaimMappingStatuses),
  });
}

const staleOrDuplicateMappingStatuses = new Set([
  "duplicate_notification",
  "stale_notification",
]);

const rejectedClaimMappingStatuses = new Set([
  "original_transaction_owner_conflict",
  "stale_transaction_claim",
]);

function logStoreKitClaimRejection(reason, metadata = {}) {
  console.warn(JSON.stringify({
    event: "storekit_subscription_claim_rejected",
    reason,
    ...metadata,
  }));
}

function safeVerificationErrorMetadata(error) {
  const status = Number(error?.status);
  if (!Number.isInteger(status)) {
    return {};
  }

  return {
    verification_status: verificationStatusName(status),
  };
}

function verificationStatusName(status) {
  switch (status) {
    case 1:
      return "verification_failure";
    case 2:
      return "retryable_verification_failure";
    case 3:
      return "invalid_app_identifier";
    case 4:
      return "invalid_environment";
    case 5:
      return "invalid_chain_length";
    case 6:
      return "invalid_certificate";
    case 7:
      return "failure";
    case 11:
      return "sandbox_fallback_not_allowed";
    case 12:
      return "sandbox_fallback_non_string";
    case 13:
      return "sandbox_fallback_compact_parts";
    case 14:
      return "sandbox_fallback_decode";
    case 15:
      return "sandbox_fallback_chain_length";
    case 16:
      return "sandbox_fallback_certificate_parse";
    case 17:
      return "sandbox_fallback_root_mismatch";
    case 18:
      return "sandbox_fallback_leaf_mismatch";
    case 19:
      return "sandbox_fallback_intermediate_not_ca";
    case 20:
      return "sandbox_fallback_leaf_oid";
    case 21:
      return "sandbox_fallback_intermediate_oid";
    case 22:
      return "sandbox_fallback_certificate_date";
    case 23:
      return "sandbox_fallback_algorithm";
    case 24:
      return "sandbox_fallback_signature";
    case 25:
      return "sandbox_fallback_app_identifier";
    case 26:
      return "sandbox_fallback_environment";
    case 27:
      return "sandbox_fallback_root_check";
    case 28:
      return "sandbox_fallback_leaf_check";
    default:
      return "unknown";
  }
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

async function readJSON(request, options = {}) {
  const maxBytes = options.maxBytes ?? 32_000;
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    return {
      ok: false,
      value: null,
      tooLarge: true,
    };
  }

  try {
    const readResult = await readBoundedText(request, maxBytes);
    if (!readResult.ok) {
      return {
        ok: false,
        value: null,
        tooLarge: true,
      };
    }

    return {
      ok: true,
      value: JSON.parse(readResult.text),
    };
  } catch {
    return {
      ok: false,
      value: null,
      tooLarge: false,
    };
  }
}

async function readBoundedText(request, maxBytes) {
  if (request.body === null) {
    return {
      ok: true,
      text: "",
    };
  }

  const reader = request.body.getReader();
  const chunks = [];
  let totalBytes = 0;

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    if (value === undefined) {
      continue;
    }

    const chunk = value instanceof Uint8Array ? value : new Uint8Array(value);
    totalBytes += chunk.byteLength;
    if (totalBytes > maxBytes) {
      try {
        await reader.cancel();
      } catch {
        // The response is already decided; stream cancellation is best effort.
      }
      return {
        ok: false,
        text: "",
      };
    }

    chunks.push(chunk);
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return {
    ok: true,
    text: new TextDecoder().decode(body),
  };
}

function responseSubscription(result, rejectionStatuses) {
  if (
    result?.stored === false
    && rejectionStatuses.has(result?.mapping_status)
  ) {
    return null;
  }

  return result?.subscription ?? null;
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

function normalizedUUIDString(value) {
  const candidate = normalizedString(value).toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(candidate)
    ? candidate
    : null;
}

function normalizedAutoRenewStatus(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (typeof value === "boolean") {
    return value;
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    return value === 1 ? true : value === 0 ? false : null;
  }

  const candidate = normalizedString(value).toLowerCase();
  if (["1", "true", "on", "enabled", "auto_renew_on"].includes(candidate)) {
    return true;
  }

  if (["0", "false", "off", "disabled", "auto_renew_off"].includes(candidate)) {
    return false;
  }

  return null;
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

function cloudRetentionDeadlineForAuthority({
  appStoreStatus,
  expiresAt,
  gracePeriodExpiresAt,
  revokedAt,
  now,
}) {
  if (appStoreStatus === "active") {
    return null;
  }

  if (appStoreStatus === "grace" || appStoreStatus === "billing_retry") {
    return gracePeriodExpiresAt ?? expiresAt ?? now.toISOString();
  }

  if (appStoreStatus === "revoked" || appStoreStatus === "refunded") {
    const basis = revokedAt === null ? now : new Date(revokedAt);
    const deletionAfter = Number.isNaN(basis.getTime()) ? now : basis;
    return new Date(deletionAfter.getTime() + 24 * 60 * 60 * 1_000).toISOString();
  }

  return expiresAt ?? now.toISOString();
}
