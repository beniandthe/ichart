# Smart Chart — V1 Production Deployment Plan

Status: Active for V1 planning  
Source of truth: `docs/core-design-document.md`

## 1. Purpose

This document defines how Smart Chart should move from internal build to TestFlight to public v1 launch.

The goal of v1 deployment is not just to publish an app. It is to ship a stable iPad experience for working musicians, validate the core workflow with real users, and keep operations simple enough that the product can continue iterating quickly.

## 2. Release strategy

### Recommended launch shape
- **Platform:** iPad-only public release for v1
- **Distribution:** Public App Store release after TestFlight validation
- **Support posture:** local-first app with minimal backend dependencies
- **Business model for launch:** paid upfront, or free plus a simple Pro unlock if monetization is ready without major state complexity

### Why this launch shape
- iPad is the correct authoring surface for Pencil-first charting.
- Avoiding a required backend reduces launch risk and operational load.
- A narrower platform target keeps QA and support manageable.

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
- collect structured feedback on speed, correction friction, output trust, and missing symbols

### Phase 3 — public v1 launch
- launch as an iPad-only public App Store release
- keep marketing and support intentionally moderate
- monitor crash rate, export reliability, purchase conversion if monetized, and early reviews

### Phase 4 — post-launch stabilization
- patch recognition pain points
- tighten layout edge cases
- prioritize the most requested supported chart symbols/features

## 5. Release gating criteria

A production build should not ship until these are true.

### Functional
- user can create a chart from scratch
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

### Option A — paid upfront
- simplest operational model
- no purchase state complexity beyond App Store purchase itself

### Option B — free app + one Pro unlock or subscription
- better for user acquisition
- requires robust StoreKit testing, entitlement handling, restore purchases, and App Store Connect configuration

### Recommendation
If product validation is still the main goal, prefer the simplest monetization that does not add major state-management risk.

## 8. App Store positioning

Smart Chart should be positioned as:
- an iPad chart creation tool for musicians
- faster than typed chart builders for rough-to-clean workflows
- more structured than plain annotation
- not full notation software

Metadata priorities:
- very clear subtitle/value proposition
- screenshots showing Pencil-to-clean-chart workflow
- one short demo video if feasible
- keywords focused on charting, lead sheets, chord charts, rehearsal charts, and transposition

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

### Workflow focus
Test heavily:
- new chart creation
- object correction
- chart reopen/autosave
- transposition
- PDF export/share
- strong one-page charts

Basic overflow beyond one page can be evaluated as a non-blocking enhancement if it arrives without destabilizing the core editor.

## 11. Security and privacy posture

### V1 recommendation
- collect as little user data as possible
- avoid mandatory accounts
- publish a simple clear privacy policy
- be explicit if analytics or crash reporting are used

Without cloud sync, the privacy story stays simpler and more trustworthy.

## 12. Launch checklist

### Product
- [ ] Pencil workflow stable
- [ ] common chart creation path validated
- [ ] export quality acceptable
- [ ] transposition validated for tested chords
- [ ] empty/error states reviewed

### Technical
- [ ] release build configuration finalized
- [ ] crash reporting tested
- [ ] analytics tested if present
- [ ] purchase flows tested if present
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
- most-requested missing supported roadmap elements
- usability fixes around correction and reinterpretation

### First 60–90 days
Possible additions:
- chart templates
- chart library polish
- improved roadmap symbol coverage
- better manual layout controls
- evaluate iPhone companion scope

## 14. Apple distribution constraints to plan around

Current Apple distribution assumptions:
- create the app record in App Store Connect
- use TestFlight for internal and external beta
- submit the approved build for public App Store release

For external TestFlight, additional beta test information is required, including a beta description and feedback email. External testing supports invitation by email or public link, and builds remain testable for a limited period. Public App Store release remains the correct v1 path for Smart Chart; private or unlisted distribution should be treated as later special cases, not the main launch path.

## 15. Deployment summary

The cleanest v1 deployment strategy for Smart Chart is:
- launch iPad-first,
- keep the app local-first,
- validate through internal then external TestFlight,
- ship publicly only after the core charting loop is clearly useful and reliable,
- avoid backend or platform complexity that does not directly improve chart creation.
