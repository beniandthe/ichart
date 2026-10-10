import { handleComplimentaryOfferRequest } from "../_shared/complimentary_offer_campaign.mjs";
import { createComplimentaryOfferRuntime } from "../_shared/complimentary_offer_runtime.mjs";

const { dependencies, configuration } = createComplimentaryOfferRuntime();
Deno.serve((request) => handleComplimentaryOfferRequest(request, dependencies, configuration));
