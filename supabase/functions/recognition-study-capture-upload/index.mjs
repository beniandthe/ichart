import { handleRecognitionStudyCaptureUploadRequest } from "../_shared/recognition_study_capture_upload.mjs";
import { createRecognitionStudyCaptureUploadDependencies } from "../_shared/recognition_study_capture_upload_store.mjs";

const dependencies = createRecognitionStudyCaptureUploadDependencies();

Deno.serve((request) => handleRecognitionStudyCaptureUploadRequest(request, dependencies));
