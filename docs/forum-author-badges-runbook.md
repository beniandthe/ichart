# Forum author badges

Designated iChart operators award and revoke badges through the existing `public.forum_author_badges` table using a privileged database session. A badge describes a contributor's work. The forum access policy governs permissions and moderation.

| Badge | Database value | Award criteria |
| --- | --- | --- |
| Verified Contributor | `verifiedContributor` | An iChart operator reviewed this contributor's published chart work. Confirm the author account and review a published chart before awarding. |
| Trusted Arranger | `trustedArranger` | Recognized for consistently accurate, usable arrangements. Review multiple published arrangements for accuracy and usability. |
| Community Expert | `communityExpert` | Recognized for sharing subject expertise in forum discussions. Review concrete examples from the contributor's discussions. |

Resolve the author from a known forum post's `owner_id`. Confirm that it matches the intended account before changing a badge. Record the decision, supporting post references, and the operator in the team's private moderation record. Leave `note` and `awarded_by` empty for these operations. The table's existing read grant exposes every column to accounts with forum access.

## Award

Replace the author and badge placeholders with the approved UUID and database value. The unique owner and badge pair makes a repeated award safe and preserves the original award time.

```sql
insert into public.forum_author_badges (owner_id, badge_type)
values ('<approved-author-uuid>'::uuid, '<approved-badge-type>')
on conflict (owner_id, badge_type) do nothing;

select id, owner_id, badge_type, awarded_at
from public.forum_author_badges
where owner_id = '<approved-author-uuid>'::uuid
  and badge_type = '<approved-badge-type>';
```

Confirm that the read returns one matching row. Save the badge ID in the moderation record.

## Revoke

Record the reason in the moderation record. Use the current badge ID from the readback so the command targets the reviewed row.

```sql
delete from public.forum_author_badges
where id = '<reviewed-badge-uuid>'::uuid
  and owner_id = '<approved-author-uuid>'::uuid
  and badge_type = '<approved-badge-type>'
returning id, owner_id, badge_type, awarded_at;
```

One returned row confirms the revoke. If the result is empty, read the owner and badge pair again before taking any further action.

## Verify in a test environment

1. Use a published test chart and two signed-in accounts with forum access. Award one badge to the author. Confirm that the author and a second viewer see the badge on the published chart after refreshing or reopening it. Check the badge description in post detail.
2. Confirm that a different unbadged author still appears normally and that the two members have no badge write access. The badge cases in `supabase/tests/rls_smoke.sql` exercise grants and row visibility.
3. Revoke the test badge and repeat the refresh and detail check for both accounts. Confirm that any other badges on the same author remain visible.
