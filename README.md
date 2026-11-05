# Primary working source archive

This is a source-only archival record of selected non-ML work from the primary
checkout, based on commit `ad6cbeeb0173f096f73c4f00b68e71498d7f5d51` and the local
branch `codex/notation-readability`. It preserves original file bytes without
changing the original checkout.

This archive is **not an active app, integration, or release candidate**. The
current integration/main line has newer and adapted readability, rendering,
persistence, and workflow implementations. In particular, the integration
checkpoint `42d423f2130295b9d41e16a55480a5a7523518ec` already contains these
readability concepts and additional tests. Do not overwrite that line with
these older whole files or blindly apply them: an old patch can duplicate a
method already present in the newer source.

## Contents and reconstruction

- `original/` contains 13 original app/test files and six original guidance or
  document files. Every file has the same bytes as the selected primary copy.
- To reconstruct this selected historical working state, start from the base
  commit above and overlay `original/` at its repository-relative paths. This
  reconstructs the selected files only, not the complete primary checkout.
- `derived-docs/` contains two clearly marked public derivatives of dated
  planning/intake notes. One private local path and one device-identifying line
  were replaced. These derivatives are not byte-identical original documents.
- `PUBLIC-MANIFEST.json` lists only the selected public paths, hashes, and copy
  type. It contains no private inventory or excluded-file names.

The documents retain their historical dates and draft/plan context. Archiving
marketing or App Store wording does not publish a post, change a listing or
policy, implement a planned feature, or establish present product behavior.

Detailed case dossiers, private drawings and saved-state captures, device/QA
artifacts, generated PNG/PDF output, credentials, and parked recognition/ML,
Graph/MyScript or vendor material are intentionally absent. Original files and
parked work remain untouched.

## Bounded text review

The selected originals and sanitized derivatives were screened for private-key
headers, credential/token literals, private home/temp paths, device identifiers,
case UUID literals and large encoded payloads. None remained in this selection.
The source/tests use programmatic synthetic controls; no captured handwriting
or saved customer state is embedded here. This was a source/privacy review,
not a new build, test, simulator, device or release verification.
