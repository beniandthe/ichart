# Normal public beta release: 1.9.4 (199) candidate

This is the ordinary production-backed free-beta candidate. Check the final
merged source, current App Store Connect build availability, signing and CI
receipts before archiving or delivering it. This procedure is not a delivery receipt.

This is the ordinary production-backed free beta. Free Pro remains on. It uses
`com.ichart.app`, the existing public library/preferences/auth namespace, and
production project `pausvvwoazbvmzyrebwl`. It does not enable the paid subscription
policy, isolated staging products, local plan previews, or personal ML comparison.
The Internal QA group is the intended TestFlight audience for this release.

The separate FIX-036 Build 173 paid-staging archive and its internal-only export
are historical evidence. Do not reuse that IPA, its xcconfig, or its ExportOptions.
The staged FIX-036 backend was deleted after billing verification; it is not a
release endpoint. Packaging does not change server policy or Apple product prices.

## Build and pin

Use a clean committed checkout and new local scratch directories outside iCloud.
`project.yml` remains authoritative. Its iChart Release target selects manual
`Apple Distribution` signing and the `iChart App Store` profile for team
`N6G8X4K46U`. The default project supplies the production URL and publishable
client key. The verifier records only the key's SHA-256, never its value.

Set `S` to the isolated source checkout and `R` to a new release evidence folder.
Run the commands sequentially and retain full Xcode output privately. Do not use
`-quiet`: the guard needs actual app Swift driver commands, response files and
native Release build-request metadata. Do not override Swift condition settings
globally, since package dependencies need their own build flags.

```sh
xcodegen generate --spec "$S/project.yml"
python3 "$S/scripts/verify_public_beta_archive.py" pin \
  --source "$S" --output "$R/public-source-pin.json"

env -u XCODE_XCCONFIG_FILE -u SWIFT_ACTIVE_COMPILATION_CONDITIONS \
  -u OTHER_SWIFT_FLAGS -u SUPABASE_URL -u SUPABASE_PUBLISHABLE_KEY \
  -u SUPABASE_ANON_KEY -u ICHART_INCLUDE_PERSONAL_ML_COMPARISON \
  xcodebuild archive -project "$S/iChart.xcodeproj" -scheme iChart \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$R/DerivedData" \
  -clonedSourcePackagesDirPath "$R/SourcePackages" \
  -archivePath "$R/iChart-1.9.4-199.xcarchive" \
  -resultBundlePath "$R/archive.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile \
  MARKETING_VERSION=1.9.4 CURRENT_PROJECT_VERSION=199 \
  ICHART_INCLUDE_PERSONAL_ML_COMPARISON=NO > "$R/archive.log" 2>&1
```

The operator must check the archive command's exit status before exporting.
Also clear injected `DYLD_INSERT_LIBRARIES`, `SIMCTL_CHILD_*`, alternate backend
URL/key environment variables and personal comparison input variables in the
actual runner. Do not source credentials or a staging environment file.
The source pin includes the generated project, tracked package lock, app code,
resources, package declaration and scripts. Verify that those inputs remain
unchanged through archive/export. A source edit requires a new committed pin
and a new archive; no verifier flag waives that check.

## Export and verify

Write a fresh `ExportOptions.plist` with these values:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>destination</key><string>export</string>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>teamID</key><string>N6G8X4K46U</string>
  <key>provisioningProfiles</key><dict>
    <key>com.ichart.app</key><string>iChart App Store</string>
  </dict>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>generateAppStoreInformation</key><false/>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadSymbols</key><true/>
  <key>testFlightInternalTestingOnly</key><false/>
</dict></plist>
```

```sh
xcodebuild -exportArchive \
  -archivePath "$R/iChart-1.9.4-199.xcarchive" \
  -exportPath "$R/export" -exportOptionsPlist "$R/ExportOptions.plist" \
  > "$R/export.log" 2>&1

python3 "$S/scripts/verify_public_beta_archive.py" verify \
  --source "$S" --source-pin "$R/public-source-pin.json" \
  --archive "$R/iChart-1.9.4-199.xcarchive" \
  --derived-data "$R/DerivedData" --build-log "$R/archive.log" \
  --export-options "$R/ExportOptions.plist" --ipa "$R/export/iChart.ipa" \
  --output "$R/public-distribution-verification.json"
```

Check both commands' exit status. The guard verifies the exact committed source
and build inputs, real optimized native Release compiler evidence, absence of
paid/staging/Debug/preview defines, production Info values and key hash, public
namespace source contract, and absence of staging StoreKit IDs in the executable.
It checks package paths for parked ML/research and QA/test payloads, strict
archive/IPA signatures, active DER entitlements, unexpired App Store profiles
without device scope, matching archive/IPA/dSYM UUIDs, and export resource/code
changes limited to verified reserialization or existing code signatures.

Both archive and export must be Apple Distribution signed on this manual route.
An automatically development-signed archive is not accepted by this procedure;
use the declared Release settings and investigate signing discrepancies rather
than weakening the exported-IPA checks. `get-task-allow` must be false and
`beta-reports-active` true. `testFlightInternalTestingOnly=false` removes the
internal-only package restriction. It does not publish the build, select testers,
complete Apple processing, or establish external beta approval. Distribution to
Internal QA remains a separate App Store Connect action.

## Release evidence and installation

Retain the clean source refs, source pin, commands and exit statuses, locked
package graph, Xcode log/result, archive with dSYMs, export options, final IPA hash,
verification receipt and CI results in a private durable packet. Record a fresh
aggregate backend readback separately: global free-beta/free-Pro enabled,
production paid rollout absent, parked retention still paused, and expected
workers unchanged. A previously saved readback is time-bound evidence.

The verifier never uploads, queries the backend, signs into an account, or changes
an iPad. Before any in-place install or potentially automatic TestFlight update,
follow the fresh saved-state and two independent stopped-app backup procedure.
Verify public chart, source ink, projects, PDFs and setlists after installation and
a controlled relaunch, and classify startup metadata separately. The staging QA
namespace must also remain recoverable. Installing an older writer requires a
separate saved-format compatibility check; install success alone is insufficient.

Run focused packaging checks with:

```sh
PYTHONPYCACHEPREFIX="$R/python-cache" \
  python3 "$S/scripts/test_public_beta_packaging.py"
```

The packaging guard does not change editor tools. This release also aligns the
Forum entry gate, recovery hint, Plan row and How To with the deployed free-beta
policy: voluntary Basic members rejoin free Pro before using Forums.

The existing CI packaging entry point, `test_internal_paid_staging_packaging.py`, also imports the public guard test class. This runs both packaging lanes without changing workflow permissions. The notification-ledger SQL controls remain separately recorded local validation; no hosted migration deployment is part of this release.
