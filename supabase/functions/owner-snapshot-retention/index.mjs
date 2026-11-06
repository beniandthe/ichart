import {
  createOwnerSnapshotRetentionDependencies,
  handleOwnerSnapshotRetentionRequest,
} from "../_shared/owner_snapshot_retention.mjs";

const dependencies = createOwnerSnapshotRetentionDependencies();
Deno.serve(request => handleOwnerSnapshotRetentionRequest(request, dependencies));
