import assert from "node:assert/strict";
import test from "node:test";
import {
  appStorePublicProductIDs,
  appStoreStagingProductIDs,
  appStorePayloadProductScopeAllowed,
  isAppStoreProductID,
} from "./app_store_product_catalog.mjs";

test("public defaults and isolated staging product scopes are disjoint fixed allowlists", () => {
  assert.deepEqual(appStorePublicProductIDs, ["com.ichart.app.pro.monthly", "com.ichart.app.pro.annual"]);
  assert.deepEqual(appStoreStagingProductIDs, ["com.ichart.app.staging.fix036.monthly", "com.ichart.app.staging.fix036.annual"]);
  for (const product of appStorePublicProductIDs) {
    assert.equal(isAppStoreProductID(product), true);
    assert.equal(isAppStoreProductID(product, { stagingStoreKitProducts: true }), false);
  }
  for (const product of appStoreStagingProductIDs) {
    assert.equal(isAppStoreProductID(product), false);
    assert.equal(isAppStoreProductID(product, { stagingStoreKitProducts: true }), true);
  }
  assert.equal(isAppStoreProductID("com.ichart.app.staging.fix036.monthly.other", { stagingStoreKitProducts: true }), false);
  assert.equal(isAppStoreProductID(" com.ichart.app.staging.fix036.monthly ", { stagingStoreKitProducts: true }), false);
});

test("staging verifies both renewal products and the Sandbox environment", () => {
  const config = { stagingStoreKitProducts: true };
  for (const productId of appStoreStagingProductIDs) {
    const payload = { productId, environment: "Sandbox" };
    assert.equal(appStorePayloadProductScopeAllowed(payload, config, "transaction"), true);
    assert.equal(appStorePayloadProductScopeAllowed(payload, config, "renewalInfo"), true);
    assert.equal(appStorePayloadProductScopeAllowed({ ...payload, environment: "Production" }, config, "transaction"), false);
    assert.equal(appStorePayloadProductScopeAllowed({ ...payload, autoRenewProductId: appStorePublicProductIDs[0] }, config, "renewalInfo"), false);
    assert.equal(appStorePayloadProductScopeAllowed({ ...payload, autoRenewProductId: appStoreStagingProductIDs[1] }, config, "renewalInfo"), true);
  }
  assert.equal(appStorePayloadProductScopeAllowed({}, config, "transaction"), false);
  assert.equal(appStorePayloadProductScopeAllowed({ productId: appStorePublicProductIDs[0], environment: "Sandbox" }, config, "transaction"), false);
  assert.equal(appStorePayloadProductScopeAllowed({}, {}, "transaction"), true);
});
