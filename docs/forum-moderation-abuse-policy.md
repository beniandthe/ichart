# Forum Moderation Abuse Policy

Status: V1 policy note; server-side enforcement follow-up.

## Existing Guardrails

- Forum access is Pro-gated.
- Votes are one per user per chart post.
- Downvotes have small negative weight in ranking.
- Downvote-heavy posts are flagged for community review.
- Reports, comments, uploads, and PDF provenance are tied to verified account identity.

## Downvote Bombing Signal

If one user downvotes 4 separate chart posts within 2 minutes, create a moderation watch event for that account. This should not automatically remove access because a user may legitimately review several bad or duplicate charts quickly.

## Escalation

1. First signal: add the account to a watch list and preserve the vote events for moderator review.
2. Second similar signal within 7 days, or a broader pattern of low-value negative voting: send a written warning and keep the account on watch.
3. Third confirmed abuse pattern: remove forum access while preserving normal app/account/subscription access unless a separate Terms issue exists.

## Safeguards

- Apply escalation to behavior across separate posts, not repeated taps on one post.
- Do not expose watch-list status in the app UI.
- Do not punish a user solely because they downvoted a low-quality or policy-violating chart.
- Prefer moderator review before forum-access removal.
- Keep future enforcement server-owned; the client should only send the vote action.
