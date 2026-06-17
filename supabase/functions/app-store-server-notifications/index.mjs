import { handleAppStoreServerNotificationRequest } from "../_shared/app_store_subscription_authority.mjs";
import { createAppStoreSignedDataVerifiers } from "../_shared/app_store_signed_data_verifier.mjs";
import { createSupabaseSubscriptionAuthorityDependencies } from "../_shared/supabase_subscription_authority_store.mjs";

const dependencies = {
  ...createAppStoreSignedDataVerifiers(),
  ...createSupabaseSubscriptionAuthorityDependencies(),
};

Deno.serve((request) => handleAppStoreServerNotificationRequest(request, dependencies));
