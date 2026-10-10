import {
  isIChartProProductID,
  normalizeStoreKitEnvironment,
} from "./app_store_subscription_authority.mjs";
import { createComplimentaryAppStoreAPITokenSigner } from "./complimentary_offer_api_token.mjs";

const maximumHistoryPages = 50;
const maximumTransactionsPerPage = 20;
const maximumStatusItems = 200;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const transactionIDPattern = /^\d{1,64}$/;

// No secret, JWS, Apple response body, or SDK error is included in public errors.
export class ComplimentaryAppleSnapshotError extends Error {
  constructor() {
    super("apple_snapshot_unavailable");
    this.name = "ComplimentaryAppleSnapshotError";
  }
}

/**
 * Fetches Apple history and status, not a cached entitlement/database estimate.
 * Every payload is verified before non-Pro products are discarded. The API calls
 * are not an atomic Apple snapshot; callers must still recheck before signing.
 */
export async function fetchAndVerifyFreshComplimentaryAppleSnapshot(input, options) {
  try {
    return await fetchAndVerifySnapshot(input, options);
  } catch {
    throw new ComplimentaryAppleSnapshotError();
  }
}

async function fetchAndVerifySnapshot(input, options) {
  const ownerID = requiredUUID(input?.ownerID);
  const originalTransactionID = requiredTransactionID(input?.originalTransactionID);
  const environment = normalizeStoreKitEnvironment(input?.environment);
  const expectedEnvironment = normalizeStoreKitEnvironment(options?.environment);
  const bundleID = requiredString(options?.bundleID);
  const client = options?.client;
  const verifiers = options?.verifiers;
  const maxPages = options?.maxPages ?? maximumHistoryPages;
  if (
    environment === null || environment !== expectedEnvironment
    || typeof client?.getAllSubscriptionStatuses !== "function"
    || typeof client?.getTransactionHistory !== "function"
    || typeof verifiers?.verifyAndDecodeTransaction !== "function"
    || typeof verifiers?.verifyAndDecodeRenewalInfo !== "function"
    || !Number.isSafeInteger(maxPages) || maxPages < 1 || maxPages > maximumHistoryPages
  ) {
    throw new ComplimentaryAppleSnapshotError();
  }

  // Get status first, then complete unfiltered history. Do not exclude revoked,
  // expired, or unfinished transactions, which can contain a prior benefit.
  const response = await client.getAllSubscriptionStatuses(originalTransactionID);
  validateResponseScope(response, bundleID, environment);
  if (!Array.isArray(response.data) || response.data.length > maximumStatusItems) {
    throw new ComplimentaryAppleSnapshotError();
  }

  const statuses = [];
  let statusItemCount = 0;
  for (const group of response.data) {
    if (!Array.isArray(group?.lastTransactions)) {
      throw new ComplimentaryAppleSnapshotError();
    }
    for (const item of group.lastTransactions) {
      statusItemCount += 1;
      if (statusItemCount > maximumStatusItems || !Number.isInteger(item?.status)
        || item.status < 1 || item.status > 5) {
        throw new ComplimentaryAppleSnapshotError();
      }
      const transaction = await verifiers.verifyAndDecodeTransaction(requiredString(item.signedTransactionInfo));
      const renewal = await verifiers.verifyAndDecodeRenewalInfo(requiredString(item.signedRenewalInfo));
      validateTransaction(transaction, { bundleID, environment, ownerID });
      validateRenewal(renewal, transaction, { bundleID, environment, ownerID });
      if (requiredTransactionID(item.originalTransactionId) !== transaction.originalTransactionId) {
        throw new ComplimentaryAppleSnapshotError();
      }
      if (isIChartProProductID(transaction.productId)) {
        if (group.subscriptionGroupIdentifier !== undefined
          && transaction.subscriptionGroupIdentifier !== undefined
          && group.subscriptionGroupIdentifier !== transaction.subscriptionGroupIdentifier) {
          throw new ComplimentaryAppleSnapshotError();
        }
        statuses.push({ status: item.status, transaction, renewal });
      }
    }
  }

  const history = [];
  const revisions = new Set();
  let revision = null;
  let historyComplete = false;
  for (let pageNumber = 0; pageNumber < maxPages; pageNumber += 1) {
    const page = await client.getTransactionHistory(
      originalTransactionID,
      revision,
      {},
      options.historyVersion ?? "v2",
    );
    validateResponseScope(page, bundleID, environment);
    if (typeof page.hasMore !== "boolean" || !Array.isArray(page.signedTransactions)
      || page.signedTransactions.length > maximumTransactionsPerPage) {
      throw new ComplimentaryAppleSnapshotError();
    }
    for (const signedTransaction of page.signedTransactions) {
      const transaction = await verifiers.verifyAndDecodeTransaction(requiredString(signedTransaction));
      validateTransaction(transaction, { bundleID, environment, ownerID });
      if (isIChartProProductID(transaction.productId)) {
        history.push(transaction);
      }
    }
    if (!page.hasMore) {
      historyComplete = true;
      break;
    }
    const nextRevision = requiredString(page.revision);
    if (page.signedTransactions.length === 0 || revisions.has(nextRevision)) {
      throw new ComplimentaryAppleSnapshotError();
    }
    revisions.add(nextRevision);
    revision = nextRevision;
  }
  if (!historyComplete || history.length === 0 || statuses.length === 0
    || ![...history, ...statuses.map((item) => item.transaction)]
      .some((transaction) => transaction.originalTransactionId === originalTransactionID)) {
    throw new ComplimentaryAppleSnapshotError();
  }

  return { history, statuses, environment };
}

function validateResponseScope(response, bundleID, environment) {
  if (response?.bundleId !== bundleID
    || normalizeStoreKitEnvironment(response?.environment) !== environment) {
    throw new ComplimentaryAppleSnapshotError();
  }
}

function validateTransaction(transaction, { bundleID, environment, ownerID }) {
  if (transaction?.bundleId !== bundleID
    || normalizeStoreKitEnvironment(transaction?.environment) !== environment) {
    throw new ComplimentaryAppleSnapshotError();
  }
  requiredTransactionID(transaction.transactionId);
  requiredTransactionID(transaction.originalTransactionId);
  requiredString(transaction.productId);
  if (isIChartProProductID(transaction.productId)) {
    if (requiredUUID(transaction.appAccountToken) !== ownerID
      || transaction.inAppOwnershipType !== "PURCHASED") {
      throw new ComplimentaryAppleSnapshotError();
    }
  }
}

function validateRenewal(renewal, transaction, { bundleID, environment, ownerID }) {
  if (normalizeStoreKitEnvironment(renewal?.environment) !== environment
    || requiredTransactionID(renewal?.originalTransactionId) !== transaction.originalTransactionId
    || renewal?.productId !== transaction.productId
    || (renewal.bundleId !== undefined && renewal.bundleId !== bundleID)) {
    throw new ComplimentaryAppleSnapshotError();
  }
  if (isIChartProProductID(transaction.productId)
    && renewal.appAccountToken !== undefined
    && requiredUUID(renewal.appAccountToken) !== ownerID) {
    throw new ComplimentaryAppleSnapshotError();
  }
}

/**
 * Runtime-only imports are lazy so the pure verifier can be tested in Node with
 * mocks. This uses the same pinned Apple library as the existing claim verifier.
 * Missing configuration disables the dependency; it never guesses environments.
 */
export function createFreshComplimentaryAppleDependencies(env = globalThis.Deno?.env, options = {}) {
  const bundleID = envString(env, "APP_STORE_BUNDLE_ID");
  const environment = normalizeStoreKitEnvironment(options.environment === undefined
    ? envString(env, "APP_STORE_ENVIRONMENT") : options.environment);
  const privateKey = envString(env, "APP_STORE_SUBSCRIPTION_KEY_P8").replace(/\\n/g, "\n");
  const keyID = envString(env, "APP_STORE_SUBSCRIPTION_KEY_ID");
  const issuerID = envString(env, "APP_STORE_ISSUER_ID");
  if (bundleID.length === 0 || environment === null || privateKey.length === 0
    || keyID.length === 0 || issuerID.length === 0) {
    return {};
  }

  let runtimePromise;
  function runtimeDependencies() {
    runtimePromise ??= (async () => {
      let client = options.client;
      let historyVersion = "v2";
      if (client === undefined) {
        const signBearerToken = createComplimentaryAppStoreAPITokenSigner({
          bundleID, keyID, issuerID, privateKeyPEM: privateKey, clock: options.clock ?? Date.now,
        });
        const sdk = await import("npm:@apple/app-store-server-library@3.1.0");
        // Pinned SDK 3.1.0 emits createBearerToken as an overridable JS method.
        // Override only this offer client's JWT creation; retain the SDK's transport,
        // environment selection and API methods. Recheck this seam before upgrading.
        class ComplimentaryAppStoreServerAPIClient extends sdk.AppStoreServerAPIClient {
          createBearerToken() { return signBearerToken(); }
        }
        client = new ComplimentaryAppStoreServerAPIClient(
          privateKey,
          keyID,
          issuerID,
          bundleID,
          environment === "production" ? sdk.Environment.PRODUCTION : sdk.Environment.SANDBOX,
        );
        historyVersion = sdk.GetTransactionHistoryVersion.V2;
      }
      let verifiers = options.verifiers;
      if (verifiers === undefined) {
        const verifierModule = await import("./app_store_signed_data_verifier.mjs");
        verifiers = verifierModule.createAppStoreSignedDataVerifiers(env);
      }
      return { client, verifiers, bundleID, environment, historyVersion };
    })();
    return runtimePromise;
  }

  return {
    async fetchFreshAppleSnapshot(input) {
      try {
        return await fetchAndVerifyFreshComplimentaryAppleSnapshot(input, {
          ...await runtimeDependencies(),
          maxPages: options.maxPages,
        });
      } catch {
        throw new ComplimentaryAppleSnapshotError();
      }
    },
  };
}

function envString(env, key) {
  const value = typeof env?.get === "function" ? env.get(key) : env?.[key];
  return typeof value === "string" ? value.trim() : "";
}

function requiredString(value) {
  if (typeof value !== "string" || value.length === 0 || value !== value.trim()) {
    throw new ComplimentaryAppleSnapshotError();
  }
  return value;
}

function requiredUUID(value) {
  const uuid = requiredString(value);
  if (!uuidPattern.test(uuid)) {
    throw new ComplimentaryAppleSnapshotError();
  }
  return uuid.toLowerCase();
}

function requiredTransactionID(value) {
  const transactionID = requiredString(value);
  if (!transactionIDPattern.test(transactionID)) {
    throw new ComplimentaryAppleSnapshotError();
  }
  return transactionID;
}
