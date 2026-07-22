# iChart Platform Account Setup Checklist

Status: account setup required before native TikTok/Instagram draft preview
Date: 2026-07-19
Applies to: TikTok, Instagram, later Meta Business Suite/Buffer connection

## Goal

Create the public iChart social accounts and make them ready for SM-001 and SM-002 native draft preview, posting, and measurement.

## Handle Priority

Try these in order, keeping the same handle across platforms if possible:

1. `@useichart`
2. `@ichartapp`
3. `@ichartmusic`
4. `@ichartcharts`

Use the same display name everywhere:

- `iChart`

## Profile Basics

Bio option A:

> Handwrite clean music charts at paper speed. Built for iPad, Apple Pencil, and working musicians.

Bio option B:

> iPad chart writing for gigging musicians. Write, transpose, export, and keep clean charts ready for the band.

Link:

- `https://useichart.com`

## Official Email And Forwarding

Use `support@useichart.com` for platform signup and recovery. Incoming mail forwards to:

- `rossmanben@gmail.com`

Implementation status:

- 2026-07-19: IONOS forwarding is set up from `support@useichart.com` to `rossmanben@gmail.com`.
- 2026-07-19: Gmail label `iChart/Instagram` exists in `rossmanben@gmail.com`.
- 2026-07-19: Gmail filter exists for `to:(support@useichart.com) (instagram OR meta OR facebookmail)` with action `Apply label "iChart/Instagram"`.

Recommended routing:

- Keep a copy in the official iChart mailbox.
- Forward all incoming official iChart email to `rossmanben@gmail.com`.
- In `rossmanben@gmail.com`, create a label named `iChart/Instagram`.
- Apply the `iChart/Instagram` label to Instagram/Meta account emails so profile setup, verification, security alerts, and support messages are easy to audit.
- Keep Instagram emails in the inbox during setup; archive them automatically only after the accounts are stable.

Setup path depends on the official email provider:

- If the official email is Gmail or Google Workspace: set forwarding from the official mailbox or Google Admin console.
- If the official email is hosted somewhere else: create a server-side forwarder from that provider's email/admin panel.
- In both cases, confirm the forwarding verification email from `rossmanben@gmail.com`.

Suggested Gmail filter after the first Instagram/Meta email arrives:

- Search or filter criteria: messages to the official iChart email from Instagram/Meta/Facebook senders.
- Action: apply label `iChart/Instagram`.
- Optional later action: skip inbox/archive only after account setup is complete.

Do not use a personal email as the public platform account login unless the official email cannot receive verification messages.

CTA until App Store/public beta path is live:

- `Follow for iPad testing updates.`

Do not use:

- `Download on the App Store`
- `Available now`
- `Join TestFlight`

unless the matching public path is ready and approved for the post.

## Profile Assets

Use the canonical iChart logo export unless a platform crop needs a square adaptation:

- `docs/branding/ichart/exports/ichart-b48a-h1-canon-logo.png`

Profile image requirements:

- Confirm the full `iChart` wordmark is readable after the platform circle crop.
- Use the same full-logo profile image on TikTok and Instagram for launch consistency.

Prepared profile assets:

- Preferred full-logo avatar uploaded to Instagram 2026-07-19: `docs/marketing/social-media/profile-assets/ichart-avatar-full-logo-square-tight-1080.png`
- Looser full-logo alternate if a platform crops too tightly: `docs/marketing/social-media/profile-assets/ichart-avatar-full-logo-square-1080.png`
- Retired test crops: `docs/marketing/social-media/profile-assets/ichart-avatar-c-crop-1150.png`, `docs/marketing/social-media/profile-assets/ichart-avatar-ic-crop-1500.png`
- Instagram processed-thumbnail proof: `docs/marketing/social-media/profile-assets/instagram-current-avatar-150.jpg`

## TikTok Setup

- [x] Official iChart email is ready to receive verification/security emails.
- [x] Official iChart email forwards to `rossmanben@gmail.com`.
- [x] Create or reserve the selected handle: `@useichart`.
- [x] Set display name to `iChart`.
- [x] Add bio: `Handwrite clean music charts at paper speed. Built for working musicians.`
- [ ] Add `useichart.com` link if available for the chosen account type.
- [x] Upload profile image: `docs/marketing/social-media/profile-assets/ichart-avatar-full-logo-square-tight-1080.png`.
- [x] Save public profile proof: `docs/marketing/social-media/profile-assets/tiktok-profile-proof-2026-07-19.png`.
- [ ] Secure the account with a unique password and 2FA.
- [ ] Check account privacy/status so videos can be posted publicly. Public profile verified at `https://www.tiktok.com/@useichart`; private Web Studio staging works, public posting still untested.
- [ ] Decide account type:
  - Business account if link, analytics, scheduler, and commercial music library access matter most.
  - Creator/personal account if access to broader native sounds is more important for early organic tests.
- [ ] Confirm the account can create drafts and select covers. 2026-07-20: Web Studio allowed private `Only you` staging and feed preview, but exposed only `Post` and `Discard`; no true draft-save action found. Cover frame selection also needs native/mobile recheck.
- [x] Add SM-001 as a private/draft preview in TikTok Web Studio staging. Not posted. Preview proof: `docs/marketing/social-media/assets/sm-001-funk-groove/review/sm-001-tiktok-draft-preview-2026-07-20.png`.
- [ ] Add SM-002 as a private/draft preview.

## Instagram Setup

- [x] Official iChart email is ready to receive verification/security emails.
- [x] Official iChart email forwards to `rossmanben@gmail.com`.
- [x] `iChart/Instagram` label or folder exists in `rossmanben@gmail.com`.
- [x] Instagram/Meta emails are filtered into `iChart/Instagram`.
- [x] Create or reserve the selected handle: `@useichart`.
- [x] Set display name to `iChart`.
- [x] Add bio.
- [ ] Add `useichart.com` link. Instagram web editor says links can only be changed in the mobile app.
- [x] Upload profile image: `docs/marketing/social-media/profile-assets/ichart-avatar-full-logo-square-tight-1080.png`.
- [ ] Secure the account with a unique password and 2FA.
- [x] Switch to a professional account for insights, contact controls, and business/creator tools.
- [x] Choose creator vs business based on early use:
  - Creator is usually enough for founder-led product content and Reels insights.
  - Business is useful once Meta Business Suite, ads, or broader team management become active.
  - Selected 2026-07-19: Creator, category `Product/service`, category hidden from public profile.
- [ ] Confirm Reels drafts, cover selection, and Story repost tools are available.
- [ ] Add SM-001 as a private/draft preview.
- [ ] Add SM-002 as a private/draft preview.

## Account Safety And Ownership

- [ ] Use a company/product email rather than a personal throwaway where possible.
- [ ] Store login details in the chosen password manager.
- [ ] Enable 2FA before uploading drafts.
- [ ] Confirm recovery email/phone is current.
- [ ] Avoid granting scheduler/app access until the first manual posts are tested.
- [ ] Keep personal/private photos, contacts, and notifications out of screen recordings.

## Draft Preview Checklist

For each platform and each video:

- [ ] Upload video as draft/private preview.
- [ ] Confirm the cover image can be applied or selected cleanly.
- [ ] Confirm spoken word captions are not covered by account/caption UI.
- [ ] Confirm launch end card text remains readable: `Follow @useichart`, `TikTok + Instagram`, `useichart.com`, `Available on the App Store`.
- [ ] Confirm no bottom progress/loading rail appears in the uploaded file.
- [ ] Confirm the app frame is not hidden by right-side controls.
- [ ] Confirm post caption does not cover the video text too aggressively.
- [ ] Confirm the link/bio CTA path is ready.
- [ ] Save screenshots or notes if platform UI changes the layout.

## Current Assets For First Draft Preview

SM-001:

- Primary: `docs/marketing/social-media/assets/sm-001-funk-groove/editions/sm-001-vertical-edition-vX-penultimate-outro-01.mp4`
- TikTok cover: `docs/marketing/social-media/assets/sm-001-funk-groove/publish/sm-001-cover-vX-bb-version-49s.png`
- Instagram cover: `docs/marketing/social-media/assets/sm-001-funk-groove/publish/sm-001-cover-vX-chart-written-31s.png`

SM-002:

- Primary: `docs/marketing/social-media/assets/sm-002-wedding-key-changes/editions/sm-002-vertical-edition-vJ-sm001-style-lifted-01.mp4`
- TikTok cover: `docs/marketing/social-media/assets/sm-002-wedding-key-changes/publish/sm-002-cover-vJ-transpose-menu-26s.png`
- Instagram cover: `docs/marketing/social-media/assets/sm-002-wedding-key-changes/publish/sm-002-cover-vJ-final-chart-45s.png`

## Exit Criteria

- TikTok account exists and is secured.
- Instagram account exists and is secured.
- Handles, display names, bio copy, profile images, and website link are consistent.
- SM-001 has been checked as a native TikTok and Instagram draft.
- SM-002 has been checked as a native TikTok and Instagram draft.
- Any platform UI issues are written back into the matching publish packet before posting.

## Official References

- TikTok Business Account: `https://getstarted.tiktok.com/Business-accounts`
- TikTok Business Center setup: `https://ads.tiktok.com/help/article/create-tiktok-business-center`
- TikTok business registration: `https://ads.tiktok.com/help/article/about-business-registration`
- Gmail forwarding for Google Workspace admins: `https://knowledge.workspace.google.com/admin/gmail/advanced/redirect-or-forward-gmail-messages-to-another-user`
- Gmail API forwarding/filtering behavior: `https://developers.google.com/workspace/gmail/api/guides/forwarding_settings`
- Gmail labels: `https://support.google.com/mail/answer/118708`
- Instagram professional accounts: `https://help.instagram.com/138925576505882/`
- Instagram professional account setup: `https://help.instagram.com/502981923235522/`
- Meta Business Suite: `https://business.meta.com/`
