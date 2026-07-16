# iChart — V1 Production Deployment Plan

Status: Active for v1 planning
Source of truth: `docs/core-design-document.md`
Current release-gate source of truth: `docs/ichart-v1-final-release-gate.md`

## 1. Purpose

This document defines how iChart should move from internal build to TestFlight to public v1 launch.

The goal of v1 deployment is not just to publish an app. It is to ship a stable iPad experience for working musicians, validate the core workflow with real users, and keep operations simple enough that the product can continue iterating quickly.

## 2. Release strategy

### Recommended launch shape
- **Platform:** iPad-only public release for v1
- **Distribution:** Public App Store release after TestFlight validation
- **Support posture:** account-backed app with local-first chart authoring
- **Business model for launch:** Basic account plus Pro subscription for cloud chart services

### Why this launch shape
- iPad is the correct authoring surface for Pencil-first charting.
- Mandatory accounts create a recoverable trust layer for email verification, password recovery, profile, subscription status, and support.
- A narrower platform target keeps QA and support manageable.
- Basic local authoring keeps chart creation usable while Pro funds cloud chart backup/sync and other ongoing-service costs.

## 3. Environments

### Development
- debug builds
- local sample charts
- logging enabled
- mock purchase state if needed

### Internal QA / dogfood
- stable enough for daily testing
- release-like configuration
- crash reporting enabled
- feature flags if needed for incomplete areas

### External beta
- onboarding copy
- in-app feedback path or support email
- known-issues list
- instrument/background diversity across testers

### Production
- release configuration
- crash instrumentation finalized
- purchase flow validated if monetized
- export flow validated end-to-end
- App Store metadata complete

## 4. Distribution path

### Phase 1 — internal testing
- build directly from Xcode / CI
- distribute via internal TestFlight group
- validate the core chart creation loop
- fix crashes, data-loss bugs, and layout regressions first

### Phase 2 — curated musician beta
- move to external TestFlight
- recruit targeted testers: bandleaders, rhythm section players, teachers
- collect structured feedback on speed, correction friction, output trust, rhythm sufficiency, and missing chart symbols

### Phase 3 — public v1 launch
- launch as an iPad-only public App Store release
- keep marketing and support intentionally moderate
- monitor crash rate, export reliability, purchase conversion if monetized, and early reviews

### Phase 4 — post-launch stabilization
- patch recognition pain points
- tighten layout edge cases
- prioritize the most requested supported chart symbols and rhythm improvements

## 5. Release gating criteria

A production build should not ship until these are true.

### Functional
- user can create a chart from scratch
- user can set or change meter reliably
- user can place two or more chord events inside a measure with clear rhythmic intent
- user can edit and reinterpret objects reliably
- concert / Bb / Eb views are correct for tested cases
- PDF export works consistently
- autosave and chart reopen are reliable

### Quality
- no known data-loss bugs
- no repeatable export corruption bugs
- no major layout corruption for supported chart types
- acceptable crash rate in beta
- onboarding is understandable enough for first-time users

### Product
- at least a small set of beta testers say the app is faster than their current rough-chart workflow
- at least a small set of beta testers say the limited rhythm support covers common real-world needs
- at least a small set of beta testers say exported charts are usable in practice

## 6. Observability and support

### Minimum v1 observability
- crash reporting
- app version/build tracking
- basic funnel awareness only if privacy and implementation cost are reasonable

### Suggested support channels
- support email
- lightweight in-app feedback action
- TestFlight feedback during beta

## 7. Monetization deployment guidance

If monetization is included in v1, keep it operationally simple.

### Recommendation
- require account creation/sign-in for production use
- launch with Basic account access for local-first chart authoring
- ship a Pro subscription around cloud chart services and other real ongoing-service value

### Basic account recommendation
- 3-chart local library cap
- complete local chart-writing tool access
- PDF export and sharing
- verified email, password recovery, profile, and subscription identity

### Pro subscription recommendation
- cloud chart backup
- chart restore after reinstall or new iPad sign-in
- future cross-device chart sync
- unlimited local charts
- Forums access

### Later Pro expansion candidates
Only add these after the core cloud backup/sync promise is stable:
- cross-device organization beyond backup/restore
- shared band libraries
- setlists
- version history
- AI-assisted cleanup or recognition upgrades

### Operational rules
- restore purchases must work reliably
- StoreKit purchases must bind to the signed-in iChart account with `appAccountToken`, and server-side claims must reject missing/mismatched tokens, cross-owner original transactions, and stale transaction replay
- App Store Server Notifications must be verified, idempotent by notification UUID, and unable to rewind subscription authority with stale signed dates
- local charts must remain accessible after purchase restore or app reinstall
- canceled but still paid-through Pro should remain full Pro until `entitlement_expires_at`
- Apple billing grace should keep local chart access available while cloud backup and Forums pause until payment recovers
- expired Pro should lock over-cap local chart access until the user prunes down to the 3-chart Basic cap
- chart cloud backup/sync and Forums should pause clearly when Pro is inactive
- chart cloud backup must be enforced by Supabase RLS, not only by client UI gates
- automatic chart backup should only upload charts with chart-level cloud backup
  intent/provenance; legacy local charts stay local-only until the user taps
  `Back Up Now`
- downgraded Basic accounts over the 3-chart cap must choose which local charts to remove until only 3 remain
- downgrade pruning is local-only and must not create cloud deletion tombstones
- users should be reminded before cancellation/expiration that cloud backups will no longer be maintained and critical charts should be exported
- remote chart backups should remain through the paid-through date or Apple billing grace deadline, then be deleted by server-side retention cleanup unless Pro renews first
- cloud retention cleanup must never silently delete local device charts
- scheduled retention email/deletion jobs must run with a server-only job secret and email-provider secrets, never from the app bundle

## 8. App Store positioning

iChart should be positioned as:
- an iPad chart creation tool for musicians
- faster than typed chart builders for rough-to-clean workflows
- rhythm-aware enough to show chord placement and hits
- more structured than plain annotation
- not full notation software

Metadata priorities:
- very clear subtitle/value proposition
- screenshots showing Pencil-to-clean-chart workflow
- screenshots showing beat-aware chord placement where it matters
- one short demo video if feasible
- keywords focused on charting, lead sheets, chord charts, rehearsal charts, rhythm charts, and transposition

## 9. CI/CD recommendation

### Source control
- GitHub as source of truth
- protected `main` branch once team workflow begins

### Build/release automation
Recommended starting options:
- Xcode Cloud if simplest for the Apple-native pipeline
- GitHub Actions + Fastlane later if more control is needed

### Minimum automation goals
- build on pull requests / main merges
- produce signed beta builds for TestFlight
- tag release builds
- track version/build numbers consistently

## 10. QA matrix

### Device focus
At minimum test:
- recent iPad Pro
- recent iPad Air
- entry-level iPad if supported

### Input focus
Test with:
- Apple Pencil
- finger-only fallback editing/navigation
- the Sprint 42 real Pencil protocol in `docs/ichart-real-life-testing-readiness-2026-05-25.md`, without turning observations into a personal handwriting training loop

### Workflow focus
Test heavily:
- new chart creation
- meter entry and meter changes
- object correction
- syncopated or split-measure chord placement
- chart reopen/autosave
- transposition
- PDF export/share
- strong one-page charts

Basic overflow beyond one page can be evaluated as a non-blocking enhancement if it arrives without destabilizing the core editor.

## 11. Security and privacy posture

### V1 recommendation
- collect as little user data as possible
- require account/auth only for identity, recovery, subscription, and support needs
- publish a simple clear privacy policy
- be explicit if analytics or crash reporting are used

With mandatory accounts, the privacy story needs to be explicit: account/profile data is cloud-backed, charts are local-first, and chart cloud backup/sync is a Pro service.

Auth callback handling should remain custom-scheme based for TestFlight, with local pending-flow state and nonce validation before accepting signup or password-reset callbacks. Universal links are the production follow-up once iChart has a stable associated domain.

Forum publishing should keep attribution and PDF provenance server-owned: creator display names come from locked account profile names, pending submissions stay owner-scoped, and published PDF downloads require validated post-bound storage paths.

## 12. Launch checklist

### Product
- [ ] Pencil workflow stable
- [ ] common chart creation path validated
- [ ] meter and chord timing workflow validated
- [ ] export quality acceptable
- [ ] transposition validated for tested chords
- [ ] empty/error states reviewed

### Technical
- [ ] release build configuration finalized
- [ ] crash reporting tested
- [ ] analytics tested if present
- [ ] Pro purchase and restore flows tested if present
- [ ] versioning/build numbering strategy in place

### App Store
- [ ] app record created
- [ ] screenshots prepared
- [ ] description/subtitle/keywords finalized
- [ ] privacy policy URL available
- [ ] support URL available
- [ ] review notes written
- [ ] beta info written for TestFlight

### Operations
- [ ] support email monitored
- [ ] release notes template prepared
- [ ] triage workflow for bugs/feedback prepared

## 13. Post-launch priorities

### First 30 days
- crash fixes
- export reliability
- layout edge cases
- recognition pain points
- usability fixes around correction and reinterpretation

### First 60–90 days
Possible additions:
- chart templates
- chart library polish
- improved roadmap symbol coverage
- broader limited rhythm coverage
- better manual layout controls
- evaluate iPhone companion scope

## 14. Apple distribution constraints to plan around

Current Apple distribution assumptions:
- create the app record in App Store Connect
- use TestFlight for internal and external beta
- submit the approved build for public App Store release

For external TestFlight, additional beta test information is required, including a beta description and feedback email. External testing supports invitation by email or public link, and builds remain testable for a limited period. Public App Store release remains the correct v1 path for iChart; private or unlisted distribution should be treated as later special cases, not the main launch path.

## 15. Deployment summary

The cleanest v1 deployment strategy for iChart is:
- launch iPad-first
- keep the app local-first
- require recoverable account identity for Basic and Pro users
- validate through internal then external TestFlight
- ship publicly only after the core charting loop is clearly useful and reliable
- use Basic account access plus a Pro subscription for cloud chart services
- avoid cloud chart dependency in the editor even while account/auth remains mandatory
