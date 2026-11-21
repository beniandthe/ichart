export const appStorePublicProductIDs = Object.freeze([
  "com.ichart.app.pro.monthly",
  "com.ichart.app.pro.annual",
]);

export const appStoreStagingProductIDs = Object.freeze([
  "com.ichart.app.staging.fix036.monthly",
  "com.ichart.app.staging.fix036.annual",
]);

export function isAppStoreProductID(productID, config = {}) {
  const products = config.stagingStoreKitProducts === true
    ? appStoreStagingProductIDs
    : appStorePublicProductIDs;
  return typeof productID === "string" && products.includes(
    config.stagingStoreKitProducts === true ? productID : productID.trim()
  );
}

// Public verification retains its existing product handling. The isolated staging
// deployment accepts only Sandbox transactions for its dedicated product group.
export function appStorePayloadProductScopeAllowed(payload, config, payloadKind) {
  if (config?.stagingStoreKitProducts !== true || payloadKind === "notification") {
    return true;
  }
  if (payload?.environment !== "Sandbox" || !isAppStoreProductID(payload?.productId, config)) {
    return false;
  }
  return payloadKind !== "renewalInfo"
    || payload?.autoRenewProductId === undefined
    || payload?.autoRenewProductId === null
    || isAppStoreProductID(payload.autoRenewProductId, config);
}
