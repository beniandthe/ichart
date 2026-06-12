import { handleAppStoreServerNotificationRequest } from "../_shared/app_store_subscription_authority.mjs";

Deno.serve((request) => handleAppStoreServerNotificationRequest(request));
