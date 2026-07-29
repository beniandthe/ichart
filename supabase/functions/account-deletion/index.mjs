import {
  createAccountDeletionDependencies,
  handleAccountDeletionRequest,
} from "../_shared/account_deletion.mjs";

const dependencies = createAccountDeletionDependencies();

Deno.serve((request) => handleAccountDeletionRequest(request, dependencies));
