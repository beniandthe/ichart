import {
  createTelemetryIngestDependencies,
  handleTelemetryIngestRequest,
} from "../_shared/telemetry_ingest.mjs";

const dependencies = createTelemetryIngestDependencies();

Deno.serve((request) => handleTelemetryIngestRequest(request, dependencies));
