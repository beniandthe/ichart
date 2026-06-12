import { handleAppStoreServerNotificationRequest } from "../_shared/app_store_subscription_authority.mjs";
import { createAppStoreSignedDataVerifiers } from "../_shared/app_store_signed_data_verifier.mjs";

const verifierDependencies = createAppStoreSignedDataVerifiers();

Deno.serve((request) => handleAppStoreServerNotificationRequest(request, verifierDependencies));
