import {
  createSubscriptionRetentionJobDependencies,
  handleSubscriptionRetentionJobRequest,
} from "../_shared/subscription_retention_jobs.mjs";

const dependencies = createSubscriptionRetentionJobDependencies();

Deno.serve((request) => handleSubscriptionRetentionJobRequest(request, dependencies));
