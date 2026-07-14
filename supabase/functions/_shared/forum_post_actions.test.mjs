import assert from "node:assert/strict";
import test from "node:test";

import {
  forumPostMetadataErrors,
  handleForumPostActionRequest,
} from "./forum_post_actions.mjs";

const ownerID = "00000000-0000-4000-8000-000000000001";
const otherOwnerID = "00000000-0000-4000-8000-000000000002";
const postID = "10000000-0000-4000-8000-000000000001";
const songID = "20000000-0000-4000-8000-000000000001";
const validSHA256 = "a".repeat(64);

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
