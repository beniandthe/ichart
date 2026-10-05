import { handleRecognitionStudyCaptureGrantRequest } from "../_shared/recognition_study_collection_authority.mjs";
import { createRecognitionStudyCollectionDependencies } from "../_shared/recognition_study_collection_store.mjs";

const dependencies = createRecognitionStudyCollectionDependencies();

Deno.serve((request) => handleRecognitionStudyCaptureGrantRequest(request, dependencies));
