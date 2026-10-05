import { handleRecognitionStudyConsentRequest } from "../_shared/recognition_study_consent.mjs";
import { createRecognitionStudyConsentDependencies } from "../_shared/recognition_study_consent_store.mjs";

const dependencies = createRecognitionStudyConsentDependencies();

Deno.serve((request) => handleRecognitionStudyConsentRequest(request, dependencies));
