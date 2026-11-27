// Independent PostgreSQL sessions against a NEW synthetic local fixture only.
// The support module requires an explicitly selected local test container and
// never resets the developer's app database or connects to a hosted project.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";
import { createFixture } from "./test_coordinated_paid_activation_support.mjs";

const literal = (value) => `'${String(value).replaceAll("'", "''")}'`;
const digest = "a".repeat(64);
const authenticate = (owner) => `set local role authenticated; set local request.jwt.claim.sub=${literal(owner)};`;
const cas = (revision, enabled) => `public.set_product_access_phase(${revision}::bigint,${enabled})`;
const publish = (row) => `public.publish_forum_chart_post(${literal(row.post)}::uuid,${literal(row.owner)}::uuid,128,${literal(digest)})`;
const choose = (owner, participating) => `public.set_free_pro_beta_participation(${participating},${literal(owner)}::uuid)`;

function json(output) {
  const lines = output.split("\n").filter((line) => line.startsWith("{"));
  assert.equal(lines.length, 1, `Expected one JSON result, received: ${output}`);
  return JSON.parse(lines[0]);
}
function rejected(expression, code) {
  // Catch only the expected SQLSTATE inside the transaction. Any other failure
  // or unexpected success stops psql and fails the test rather than being hidden.
  return `do $$begin perform ${expression}; raise exception 'Expected SQLSTATE ${code}';
    exception when sqlstate '${code}' then null; end $$; select 'denied-${code}';`;
}
async function policy(db) {
  return json(await db.query(`select jsonb_build_object('enabled',enabled,'revision',policy_revision,
    'updated_at',policy_updated_at) from private.ichart_paid_feature_policy where singleton;`));
}
async function selectPhase(db, enabled) {
  const before = await policy(db);
  return json(await db.query(`begin; set local role service_role; select ${cas(before.revision, enabled)}; commit;`));
}
async function blockedBy(db, waiting, holder) {
  assert.notEqual(waiting.pid, holder.pid, "Competing operations require different PostgreSQL backends");
  const deadline = Date.now() + 10_000;
  do {
    const result = await db.query(`select case when exists(select 1 from pg_stat_activity
      where pid=${waiting.pid} and wait_event_type='Lock'
        and ${holder.pid}=any(pg_blocking_pids(pid))) then 'blocked' else 'not-blocked' end;`);
    if (result === "blocked") return;
    await delay(20);
  } while (Date.now() < deadline);
  assert.fail(`Expected backend ${waiting.pid} to wait on backend ${holder.pid}`);
}
async function seed(db, participating = true) {
  const owner = randomUUID(), song = randomUUID(), post = randomUUID();
  await db.query(`insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
    values(${literal(owner)}::uuid,${literal(`${owner}@example.test`)},now(),
      '{"first_name":"Synthetic","last_name":"Activation"}');
    insert into private.free_pro_beta_memberships(owner_id,participating)
      values(${literal(owner)}::uuid,${participating});
    insert into public.forum_songs(id,song_title,artist_name,normalized_song_title,normalized_artist_name,created_by)
      values(${literal(song)}::uuid,${literal(`Synthetic activation ${song}`)},'Synthetic artist',
        ${literal(`synthetic activation ${song}`)},'synthetic artist',${literal(owner)}::uuid);
    insert into public.forum_chart_posts(id,song_id,owner_id,chart_title,arranger_credit,
      creator_display_name,layout_style,pdf_storage_path,status)
      values(${literal(post)}::uuid,${literal(song)}::uuid,${literal(owner)}::uuid,
        'Synthetic chart','Synthetic arranger','Synthetic A.','simpleChordSheet',
        ${literal(`${owner}/${post}.pdf`)},'pending');
    insert into storage.objects(bucket_id,name,owner,owner_id,metadata)
      values('forum_chart_pdfs',${literal(`${owner}/${post}.pdf`)},${literal(owner)}::uuid,
        ${literal(owner)},'{"size":128,"mimetype":"application/pdf"}');`);
  return { owner, song, post };
}
async function postState(db, row) {
  return json(await db.query(`select jsonb_build_object('status',p.status,
    'provenance',p.pdf_provenance_status,'validated_at',p.pdf_validated_at,
    'proof_count',(select count(*) from private.forum_chart_pdf_provenance where post_id=p.id))
    from public.forum_chart_posts p where p.id=${literal(row.post)}::uuid;`));
}
async function membership(db, owner) {
  return json(await db.query(`select to_jsonb(m) from private.free_pro_beta_memberships m
    where owner_id=${literal(owner)}::uuid;`));
}
async function billing(db, owner) {
  return json(await db.query(`select to_jsonb(s) from public.subscriptions s
    where owner_id=${literal(owner)}::uuid;`));
}
async function status(db, owner) {
  return json(await db.query(`begin; ${authenticate(owner)} select public.product_access_status(); rollback;`));
}
async function closeSessions(sessions) {
  await Promise.allSettled(sessions.map((session) => session.close()));
}

test("coordinated paid activation serializes with real CAS, publication and membership transactions", {
  timeout: 180_000,
}, async (t) => {
  const db = await createFixture();
  let success = true;
  async function scenario(name, body) {
    await t.test(name, async () => {
      try { await body(); } catch (error) { success = false; throw error; }
    });
  }
  try {
    t.diagnostic(`Isolated database ${db.database}; ${db.applied.length} hashed migration inputs`);
    await scenario("same-revision service CAS has one winner and one deterministic PT409", async () => {
      await selectPhase(db, false);
      const before = await policy(db);
      const first = await db.session("cas-first"), second = await db.session("cas-second");
      try {
        const winner = json(await first.command(`begin; set local role service_role;
          select ${cas(before.revision, true)};`));
        assert.equal(winner.phase, "paid");
        assert.equal(winner.policy_revision, before.revision + 1);
        const losing = second.command(`begin; set local role service_role;
          ${rejected(cas(before.revision, true), "PT409")} commit;`);
        await blockedBy(db, second, first);
        await first.command("commit;");
        assert.equal(await losing, "denied-PT409");
        assert.equal((await policy(db)).revision, before.revision + 1);
      } finally { await closeSessions([first, second]); }
    });
    await scenario("activation waits for a publication holding policy SHARE until publication commits", async () => {
      await selectPhase(db, false);
      const row = await seed(db), before = await policy(db);
      const publisher = await db.session("publish-before-cutover"), admin = await db.session("cutover-after-publish");
      try {
        const published = json(await publisher.command(`begin; set local role service_role; select ${publish(row)};`));
        assert.equal(published.status, "published");
        const switching = admin.command(`begin; set local role service_role; select ${cas(before.revision, true)}; commit;`);
        await blockedBy(db, admin, publisher);
        assert.deepEqual(await postState(db, row), { status: "pending", provenance: "pending", validated_at: null, proof_count: 0 });
        await publisher.command("commit;");
        assert.equal(json(await switching).phase, "paid");
        const after = await postState(db, row);
        assert.equal(after.status, "published");
        assert.equal(after.provenance, "validated");
        assert.equal(after.proof_count, 1);
        assert.ok(after.validated_at);
      } finally { await closeSessions([publisher, admin]); }
    });
    await scenario("publication waiting behind completed activation rechecks paid authority and stays pending", async () => {
      await selectPhase(db, false);
      const row = await seed(db), before = await policy(db);
      const admin = await db.session("cutover-before-publish"), publisher = await db.session("publish-after-cutover");
      try {
        const unchanged = await postState(db, row), priorMembership = await membership(db, row.owner);
        await admin.command(`begin; set local role service_role; select ${cas(before.revision, true)};`);
        const publishing = publisher.command(`begin; set local role service_role;
          ${rejected(publish(row), "42501")} commit;`);
        await blockedBy(db, publisher, admin);
        await admin.command("commit;");
        assert.equal(await publishing, "denied-42501");
        assert.deepEqual(await postState(db, row), unchanged);
        assert.deepEqual(await membership(db, row.owner), priorMembership);
      } finally { await closeSessions([admin, publisher]); }
    });
    for (const selected of [false, true]) {
      await scenario(`a completed beta ${selected ? "rejoin" : "leave"} precedes waiting activation without a lock-order cycle`, async () => {
        await selectPhase(db, false);
        const row = await seed(db, !selected), before = await policy(db);
        const setter = await db.session(`membership-first-${selected}`), admin = await db.session(`cutover-after-membership-${selected}`);
        try {
          const priorBilling = await billing(db, row.owner);
          const chosen = json(await setter.command(`begin; ${authenticate(row.owner)} select ${choose(row.owner, selected)};`));
          assert.equal(chosen.participating, selected);
          const switching = admin.command(`begin; set local role service_role; select ${cas(before.revision, true)}; commit;`);
          await blockedBy(db, admin, setter);
          assert.equal((await membership(db, row.owner)).participating, !selected, "Uncommitted membership stays invisible");
          await setter.command("commit;");
          assert.equal(json(await switching).phase, "paid");
          assert.equal((await membership(db, row.owner)).participating, selected);
          assert.deepEqual(await billing(db, row.owner), priorBilling);
        } finally { await closeSessions([setter, admin]); }
      });
      await scenario(`a beta ${selected ? "rejoin" : "leave"} waiting behind activation rejects without any membership write`, async () => {
        await selectPhase(db, false);
        const row = await seed(db, !selected), before = await policy(db);
        const admin = await db.session(`cutover-first-${selected}`), setter = await db.session(`membership-after-cutover-${selected}`);
        try {
          const priorMembership = await membership(db, row.owner), priorBilling = await billing(db, row.owner);
          await admin.command(`begin; set local role service_role; select ${cas(before.revision, true)};`);
          const choosing = setter.command(`begin; ${authenticate(row.owner)} ${rejected(choose(row.owner, selected), "55000")} commit;`);
          await blockedBy(db, setter, admin);
          await admin.command("commit;");
          assert.equal(await choosing, "denied-55000");
          assert.deepEqual(await membership(db, row.owner), priorMembership);
          assert.deepEqual(await billing(db, row.owner), priorBilling);
        } finally { await closeSessions([admin, setter]); }
      });
    }
    await scenario("concurrent reads return coherent committed phase and revision across activation and rollback", async () => {
      await selectPhase(db, false);
      const row = await seed(db), before = await policy(db);
      const admin = await db.session("phase-reader-control");
      try {
        await admin.command(`begin; set local role service_role; select ${cas(before.revision, true)};`);
        const old = await status(db, row.owner);
        assert.equal(old.phase, "free_beta");
        assert.equal(old.policy_revision, before.revision);
        assert.equal(old.free_pro_access, true);
        await admin.command("commit;");
        const paid = await status(db, row.owner);
        assert.equal(paid.phase, "paid");
        assert.equal(paid.policy_revision, before.revision + 1);
        assert.equal(paid.beta_available, false);
        assert.equal(paid.free_pro_access, false);
        await admin.command(`begin; set local role service_role; select ${cas(paid.policy_revision, false)};`);
        const stillPaid = await status(db, row.owner);
        assert.equal(stillPaid.phase, "paid");
        assert.equal(stillPaid.policy_revision, paid.policy_revision);
        await admin.command("commit;");
        const rolledBack = await status(db, row.owner);
        assert.equal(rolledBack.phase, "free_beta");
        assert.equal(rolledBack.policy_revision, before.revision + 2);
        assert.equal(rolledBack.free_pro_access, true);
      } finally { await closeSessions([admin]); }
    });
  } finally { await db.close(success); }
});
