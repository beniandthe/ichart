import assert from "node:assert/strict";
import test from "node:test";

import {
  createForumPostActionDependencies,
  forumPostMetadataErrors,
  handleForumPostActionRequest,
} from "./forum_post_actions.mjs";

const ownerID = "00000000-0000-4000-8000-000000000001";
const otherOwnerID = "00000000-0000-4000-8000-000000000002";
const postID = "10000000-0000-4000-8000-000000000001";
const songID = "20000000-0000-4000-8000-000000000001";
const validSHA256 = "a".repeat(64);
const legacyAnonKey = `header.${Buffer.from(JSON.stringify({ role: "anon" })).toString("base64url")}.signature`;

test("forum post actions require an authenticated account", async () => {
  const response = await handleForumPostActionRequest(
    request({ action: "remove", post_id: postID }),
    {
      authenticatedUserID: async () => null,
      fetchPost: async () => post(),
    }
  );

  assert.equal(response.status, 401);
  const body = await response.json();
  assert.equal(body.error, "A signed-in iChart account is required.");
});

test("forum post actions reject cross-owner access", async () => {
  const response = await handleForumPostActionRequest(
    request({ action: "remove", post_id: postID }),
    {
      authenticatedUserID: async () => ownerID,
      fetchPost: async () => post({ owner_id: otherOwnerID }),
    }
  );

  assert.equal(response.status, 403);
  const body = await response.json();
  assert.equal(body.error, "Forum post belongs to a different iChart account.");
});

test("publish rejects metadata that is missing or garbage", async () => {
  const response = await handleForumPostActionRequest(
    request({ action: "publish", post_id: postID, byte_size: 32000, sha256: validSHA256 }),
    {
      authenticatedUserID: async () => ownerID,
      hasForumAccess: async () => true,
      fetchPost: async () => post({ chart_title: "!!!!!!!!", arranger_credit: "aaaaaa" }),
      fetchSong: async () => song({ song_title: "", artist_name: "/////" }),
      finalizePostPDF: async () => assert.fail("invalid metadata must not finalize"),
      updatePostStatus: async () => assert.fail("invalid metadata must not publish"),
    }
  );

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.error, "Forum post metadata is not ready to publish.");
  assert.deepEqual(body.metadata_errors.sort(), [
    "arranger_credit",
    "artist_name",
    "chart_title",
    "song_title",
  ]);
});

test("publish finalizes provenance and marks an owned pending post published", async () => {
  const calls = [];
  const response = await handleForumPostActionRequest(
    request({ action: "publish", post_id: postID, byte_size: 32000, sha256: validSHA256 }),
    {
      authenticatedUserID: async () => ownerID,
      hasForumAccess: async () => true,
      fetchPost: async () => post(),
      fetchSong: async () => song(),
      finalizePostPDF: async (payload) => calls.push(["finalize", payload]),
      updatePostStatus: async (payload) => {
        calls.push(["update", payload]);
        return post({ status: payload.status, published_at: payload.publishedAt });
      },
    }
  );

  assert.equal(response.status, 202);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.state, "published");
  assert.equal(body.post.status, "published");
  assert.equal(calls[0][0], "finalize");
  assert.deepEqual(calls[0][1], { postID, byteSize: 32000, sha256: validSHA256 });
  assert.equal(calls[1][0], "update");
  assert.equal(calls[1][1].postID, postID);
  assert.equal(calls[1][1].status, "published");
  assert.equal(calls[1][1].expectedStatus, "pending");
});

test("publish returns conflict instead of fabricating success when its conditional update matches no row", async () => {
  const response = await handleForumPostActionRequest(
    request({ action: "publish", post_id: postID, byte_size: 32000, sha256: validSHA256 }),
    {
      authenticatedUserID: async () => ownerID,
      hasForumAccess: async () => true,
      fetchPost: async () => post(),
      fetchSong: async () => song(),
      finalizePostPDF: async () => {},
      updatePostStatus: async (payload) => {
        assert.equal(payload.expectedStatus, "pending");
        return null;
      },
    }
  );

  assert.equal(response.status, 409);
  const body = await response.json();
  assert.equal(body.accepted, false);
  assert.match(body.error, /changed before it could be published/);
  assert.equal(body.post, undefined);
  assert.equal(body.state, undefined);
});

test("wired conditional publish cannot resurrect a withdrawal completed during PDF finalization", async () => {
  let savedPost = post();
  const patchCalls = [];
  let withdrawalBody;
  const dependencies = createForumPostActionDependencies({
    SUPABASE_URL: "https://synthetic.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key",
    SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test_key",
  }, { fetch: async (url, options) => {
    const target = new URL(url);
    if (target.pathname === "/auth/v1/user") return Response.json({ id: ownerID });
    if (target.pathname === "/rest/v1/rpc/current_user_has_active_pro") return Response.json(true);
    if (target.pathname === "/rest/v1/forum_songs") return Response.json([song()]);
    if (target.pathname === "/rest/v1/rpc/finalize_forum_chart_post_pdf") {
      // Finish the real withdrawal handler before the suspended publish reaches
      // its PATCH. This ordering is deterministic, with no timers or sleeps.
      const withdrawal = await handleForumPostActionRequest(
        request({ action: "withdraw", post_id: postID }), dependencies
      );
      assert.equal(withdrawal.status, 202);
      withdrawalBody = await withdrawal.json();
      assert.equal(savedPost.status, "removed");
      return new Response(null, { status: 204 });
    }
    if (target.pathname === "/rest/v1/forum_chart_posts") {
      assert.equal(target.searchParams.get("id"), `eq.${postID}`);
      if (options.method === "GET") return Response.json([{ ...savedPost }]);
      assert.equal(options.method, "PATCH");
      assert.equal(options.headers.prefer, "return=representation");
      const update = JSON.parse(options.body);
      patchCalls.push({ target, update });
      const expected = target.searchParams.get("status");
      if (expected !== null && expected !== `eq.${savedPost.status}`) return Response.json([]);
      savedPost = { ...savedPost, ...update };
      return Response.json([{ ...savedPost }]);
    }
    assert.fail(`Unexpected request ${options.method} ${target.pathname}`);
  } });

  const publish = await handleForumPostActionRequest(
    request({ action: "publish", post_id: postID, byte_size: 32000, sha256: validSHA256 }), dependencies
  );
  assert.equal(withdrawalBody.state, "removed");
  assert.equal(patchCalls.length, 2);
  assert.equal(patchCalls[0].update.status, "removed");
  assert.equal(patchCalls[0].target.searchParams.get("status"), null);
  assert.equal(patchCalls[1].update.status, "published");
  assert.equal(patchCalls[1].target.searchParams.get("status"), "eq.pending");
  assert.equal(savedPost.status, "removed");
  assert.equal(publish.status, 409);
  const body = await publish.json();
  assert.equal(body.accepted, false);
  assert.equal(body.post, undefined);
  assert.equal(body.state, undefined);
});

test("withdraw removes only pending owner submissions", async () => {
  const updates = [];
  const response = await handleForumPostActionRequest(
    request({ action: "withdraw", post_id: postID }),
    {
      authenticatedUserID: async () => ownerID,
      fetchPost: async () => post(),
      updatePostStatus: async (payload) => {
        updates.push(payload);
        return post({ status: payload.status });
      },
    }
  );

  assert.equal(response.status, 202);
  const body = await response.json();
  assert.equal(body.state, "removed");
  assert.deepEqual(updates, [{ postID, status: "removed" }]);
});

test("remove hides published posts from forums without requiring public moderation grants", async () => {
  const updates = [];
  const response = await handleForumPostActionRequest(
    request({ action: "remove", post_id: postID }),
    {
      authenticatedUserID: async () => ownerID,
      fetchPost: async () => post({ status: "published" }),
      updatePostStatus: async (payload) => {
        updates.push(payload);
        return post({ status: payload.status });
      },
    }
  );

  assert.equal(response.status, 202);
  const body = await response.json();
  assert.equal(body.state, "removed");
  assert.deepEqual(updates, [{ postID, status: "removed" }]);
});

test("metadata validation allows common music names and rejects obvious spam", () => {
  assert.deepEqual(forumPostMetadataErrors({ post: post(), song: song() }), []);
  assert.deepEqual(
    forumPostMetadataErrors({
      post: post({ tags: ["standard", "/////"] }),
      song: song(),
    }),
    ["tags"]
  );
});

for (const scenario of ["opted-out Basic", "active-paid but opted-out Basic", "banned", "unconfirmed"]) {
  test(`publish denies ${scenario} before reading/finalizing/updating a post`, async () => {
    const unexpected = () => assert.fail("Denied publish must not read or mutate posts.");
    const response = await handleForumPostActionRequest(
      request({ action: "publish", post_id: postID, byte_size: 32000, sha256: validSHA256 }),
      { authenticatedUserID: async () => ownerID, hasForumAccess: async () => false,
        fetchPost: unexpected, fetchSong: unexpected, finalizePostPDF: unexpected, updatePostStatus: unexpected }
    );
    assert.equal(response.status, 403);
    assert.equal((await response.json()).accepted, false);
  });
}

for (const [label, checker] of [["missing checker", undefined], ["unavailable checker", async () => { throw new Error("upstream secret must not leak"); }],
  ["malformed checker result", async () => "true"]]) {
  test(`publish fails closed with ${label} and no privileged writes`, async () => {
    const unexpected = () => assert.fail("Unavailable access check must not touch posts.");
    const response = await handleForumPostActionRequest(request({ action: "publish", post_id: postID }),
      { authenticatedUserID: async () => ownerID, hasForumAccess: checker,
        fetchPost: unexpected, finalizePostPDF: unexpected, updatePostStatus: unexpected });
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error, "Forum publishing access could not be verified.");
  });
}

test("free beta account needs no paid receipt; leaving denies publishing and rejoining restores it", async () => {
  let access = true;
  const writes = [];
  const dependencies = { authenticatedUserID: async () => ownerID, hasForumAccess: async () => access,
    fetchPost: async () => post(), fetchSong: async () => song(),
    finalizePostPDF: async () => writes.push("finalize"), updatePostStatus: async () => {
      writes.push("publish");
      return post({ status: "published" });
    } };
  const publish = () => handleForumPostActionRequest(request({ action: "publish", post_id: postID,
    byte_size: 32000, sha256: validSHA256 }), dependencies);
  assert.equal((await publish()).status, 202);
  access = false; assert.equal((await publish()).status, 403);
  assert.deepEqual(writes, ["finalize", "publish"]);
  access = true; assert.equal((await publish()).status, 202);
  assert.deepEqual(writes, ["finalize", "publish", "finalize", "publish"]);
});

test("eligible caller still cannot publish another owner's post", async () => {
  const response = await handleForumPostActionRequest(request({ action: "publish", post_id: postID }),
    { authenticatedUserID: async () => ownerID, hasForumAccess: async () => true,
      fetchPost: async () => post({ owner_id: otherOwnerID }),
      finalizePostPDF: () => assert.fail("Cross-owner publish must not finalize"),
      updatePostStatus: () => assert.fail("Cross-owner publish must not update") });
  assert.equal(response.status, 403);
});

for (const action of ["withdraw", "remove"]) {
  test(`Basic user retains owned ${action} cleanup without a publishing grant`, async () => {
    const response = await handleForumPostActionRequest(request({ action, post_id: postID }),
      { authenticatedUserID: async () => ownerID,
        hasForumAccess: () => assert.fail("Cleanup must not require Pro"),
        fetchPost: async () => post({ status: action === "withdraw" ? "pending" : "published" }),
        updatePostStatus: async () => post({ status: "removed" }) });
    assert.equal(response.status, 202);
  });
}

test("wired publish check pins the verified incoming bearer to authenticated RPC, never service authorization", async () => {
  const calls = [];
  const env = { SUPABASE_URL: "https://synthetic.invalid", SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key",
    SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test_key" };
  const dependencies = createForumPostActionDependencies(env, { fetch: async (url, options) => {
    calls.push({ url, options });
    if (String(url).endsWith("/auth/v1/user")) return Response.json({ id: ownerID });
    if (String(url).endsWith("/rpc/current_user_has_active_pro")) return Response.json(true);
    assert.fail("Only authentication and access RPC are expected");
  } });
  const incoming = request({});
  assert.equal(await dependencies.authenticatedUserID(incoming), ownerID);
  assert.equal(await dependencies.hasForumAccess(incoming), true);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.headers.authorization, "Bearer user-session-token");
  assert.equal(calls[1].options.headers.authorization, calls[0].options.headers.authorization);
  assert.equal(calls[1].options.headers.apikey, "sb_publishable_test_key");
  assert.equal(calls[1].options.method, "POST");
  assert.equal(calls[1].options.body, "{}");
  assert.notEqual(calls[1].options.headers.authorization, "Bearer server-only-test-key");
});

test("wired gate accepts only boolean true, supports anon-key fallback, and fails closed on RPC outage", async () => {
  for (const value of [false, "true", null]) {
    const dependencies = createForumPostActionDependencies({ SUPABASE_URL: "https://synthetic.invalid",
      SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key", SUPABASE_ANON_KEY: legacyAnonKey },
    { fetch: async (_url, options) => {
      assert.equal(options.headers.apikey, legacyAnonKey);
      return Response.json(value);
    } });
    if (value === false) assert.equal(await dependencies.hasForumAccess(request({})), false);
    else await assert.rejects(dependencies.hasForumAccess(request({})));
  }
  for (const response of [new Response("unavailable", { status: 503 }), new Response("not-json")]) {
    const dependencies = createForumPostActionDependencies({ SUPABASE_URL: "https://synthetic.invalid",
      SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key", SUPABASE_ANON_KEY: legacyAnonKey },
    { fetch: async () => response });
    await assert.rejects(dependencies.hasForumAccess(request({})));
  }
  const missingKey = createForumPostActionDependencies({ SUPABASE_URL: "https://synthetic.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key" }, { fetch: () => assert.fail("Missing public key must not send request") });
  await assert.rejects(missingKey.hasForumAccess(request({})));
});

test("standard plural publishable-key dictionary selects default with no singular or legacy key", async () => {
  const env = new Map(Object.entries({ SUPABASE_URL: "https://synthetic.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ alternate: "sb_publishable_alternate", default: "sb_publishable_default" }) }));
  const dependencies = createForumPostActionDependencies(env, { fetch: async (_url, options) => {
    assert.equal(options.headers.apikey, "sb_publishable_default");
    assert.equal(options.headers.authorization, "Bearer user-session-token");
    return Response.json(true);
  } });
  assert.equal(await dependencies.hasForumAccess(request({})), true);
});

test("named-only publishable-key dictionary has a deterministic bounded fallback", async () => {
  const dependencies = createForumPostActionDependencies({ SUPABASE_URL: "https://synthetic.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ zeta: "sb_publishable_zeta", alpha: "sb_publishable_alpha" }) },
  { fetch: async (_url, options) => {
    assert.equal(options.headers.apikey, "sb_publishable_alpha");
    return Response.json(true);
  } });
  assert.equal(await dependencies.hasForumAccess(request({})), true);
});

for (const [label, plural] of [
  ["malformed JSON", "{"], ["null dictionary", "null"], ["array", "[]"], ["empty dictionary", "{}"],
  ["non-string env", 12], ["non-string default", JSON.stringify({ default: 12 })],
  ["object default", JSON.stringify({ default: { nested: "sb_publishable_invalid" } })],
  ["mixed non-string entry", JSON.stringify({ default: "sb_publishable_default", other: false })],
  ["empty entry", JSON.stringify({ default: "" })], ["oversized input", " ".repeat(32769)],
  ["too many keys", JSON.stringify(Object.fromEntries(Array.from({ length: 33 }, (_, i) => [String(i), `sb_publishable_${i}`])))],
  ["oversized value", JSON.stringify({ default: `sb_publishable_${"a".repeat(8192)}` })],
]) {
  test(`plural publishable configuration rejects ${label} before any network or legacy fallback`, async () => {
    const dependencies = createForumPostActionDependencies({ SUPABASE_URL: "https://synthetic.invalid",
      SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key", SUPABASE_PUBLISHABLE_KEYS: plural,
      SUPABASE_PUBLISHABLE_KEY: "sb_publishable_would_mask_error", SUPABASE_ANON_KEY: legacyAnonKey },
    { fetch: () => assert.fail("Malformed explicit dictionary must not perform a lookup") });
    await assert.rejects(dependencies.hasForumAccess(request({})));
  });
}

for (const key of ["sb_secret_not_a_public_key", "server-only-test-key",
  `header.${Buffer.from(JSON.stringify({ role: "service_role" })).toString("base64url")}.signature`,
  `header.${Buffer.from(JSON.stringify({ role: "authenticated" })).toString("base64url")}.signature`]) {
  test("user-context RPC never accepts a secret/service-role key from public configuration", async () => {
    for (const configuration of [{ SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: key }) },
      { SUPABASE_PUBLISHABLE_KEY: key }, { SUPABASE_ANON_KEY: key }]) {
      const dependencies = createForumPostActionDependencies({ SUPABASE_URL: "https://synthetic.invalid",
        SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key", ...configuration },
      { fetch: () => assert.fail("Privileged key must never be sent as a user-context apikey") });
      await assert.rejects(dependencies.hasForumAccess(request({})));
    }
  });
}

function request(body) {
  return new Request("https://project.supabase.co/functions/v1/forum-post-actions", {
    method: "POST",
    headers: {
      authorization: "Bearer user-session-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function post(overrides = {}) {
  return {
    id: postID,
    song_id: songID,
    owner_id: ownerID,
    chart_title: "Blue Bossa",
    arranger_credit: "Beni Rossman",
    creator_display_name: "Beni R.",
    tags: ["standard", "latin"],
    version_note: "Clean rhythm chart.",
    pdf_storage_path: `${ownerID}/${postID}.pdf`,
    status: "pending",
    ...overrides,
  };
}

function song(overrides = {}) {
  return {
    id: songID,
    song_title: "Blue Bossa",
    artist_name: "Kenny Dorham",
    ...overrides,
  };
}
