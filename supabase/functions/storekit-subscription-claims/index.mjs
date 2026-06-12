import { handleStoreKitSubscriptionClaimRequest } from "../_shared/app_store_subscription_authority.mjs";

Deno.serve((request) => handleStoreKitSubscriptionClaimRequest(request));
