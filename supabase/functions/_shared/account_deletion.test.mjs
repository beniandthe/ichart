import assert from "node:assert/strict";
import test from "node:test";

import {
  createAccountDeletionDependencies,
  handleAccountDeletionRequest,
} from "./account_deletion.mjs";

const confirmation = "DELETE_MY_ICHART_ACCOUNT";
const ownerID = "00000000-0000-4000-8000-000000000001";
const postID = "00000000-0000-4000-8000-000000000101";
const archiveBucket = "ichart-owner-snapshot-archives";
const archiveScopePath = "/rest/v1/rpc/owner_snapshot_archive_deletion_scope";
const archiveListPath = `/storage/v1/object/list/${archiveBucket}`;
const archiveBucketPath = `/storage/v1/bucket/${archiveBucket}`;

test("account deletion rejects non-POST requests", async () => {
  const response = await handleAccountDeletionRequest(new Request("https://example.test", { method: "GET" }));
  const body = await response.json();

  assert.equal(response.status, 405);
  assert.equal(body.accepted, false);
});

test("account deletion requires configured auth resolver", async () => {
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }),
    {}
  );
  const body = await response.json();

  assert.equal(response.status, 501);
  assert.equal(body.error, "Account deletion is not configured.");
});

test("account deletion rejects oversized request bodies", async () => {
  let authCalled = false;
  const response = await handleAccountDeletionRequest(
    new Request("https://example.test", {
      method: "POST",
      body: JSON.stringify({ confirmation, padding: "x".repeat(4096) }),
    }),
    {
      authenticatedUserID: async () => {
        authCalled = true;
        return ownerID;
      },
      deleteAuthUser: async () => {},
    }
  );
  const body = await response.json();

  assert.equal(response.status, 413);
  assert.equal(body.error, "Account deletion request is too large.");
  assert.equal(authCalled, false);
});

test("account deletion rejects oversized content-length before reading auth", async () => {
  let authCalled = false;
  const response = await handleAccountDeletionRequest(
    new Request("https://example.test", {
      method: "POST",
      headers: { "content-length": "4097" },
      body: JSON.stringify({ confirmation }),
    }),
    {
      authenticatedUserID: async () => {
        authCalled = true;
        return ownerID;
      },
      deleteAuthUser: async () => {},
    }
  );
  const body = await response.json();

  assert.equal(response.status, 413);
  assert.equal(body.error, "Account deletion request is too large.");
  assert.equal(authCalled, false);
});

test("account deletion stops reading chunked bodies once the size cap is crossed", async () => {
  let canceled = false;
  let authCalled = false;
  const request = new Request("https://example.test", {
    method: "POST",
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("x".repeat(4097)));
      },
      cancel() {
        canceled = true;
      },
    }),
    duplex: "half",
  });
  const response = await handleAccountDeletionRequest(
    request,
    {
      authenticatedUserID: async () => {
        authCalled = true;
        return ownerID;
      },
      deleteAuthUser: async () => {},
    }
  );
  const body = await response.json();

  assert.equal(response.status, 413);
  assert.equal(body.error, "Account deletion request is too large.");
  assert.equal(authCalled, false);
  assert.equal(canceled, true);
});

test("account deletion rejects malformed JSON", async () => {
  const response = await handleAccountDeletionRequest(
    new Request("https://example.test", {
      method: "POST",
      body: "{",
    }),
    {
      authenticatedUserID: async () => ownerID,
      deleteAuthUser: async () => {},
    }
  );
  const body = await response.json();

  assert.equal(response.status, 400);
  assert.equal(body.error, "Account deletion request must be valid JSON.");
});

test("account deletion requires destructive confirmation", async () => {
  let authCalled = false;
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation: "delete" }),
    {
      authenticatedUserID: async () => {
        authCalled = true;
        return ownerID;
      },
      deleteAuthUser: async () => {},
    }
  );
  const body = await response.json();

  assert.equal(response.status, 400);
  assert.equal(body.error, "Account deletion confirmation is required.");
  assert.equal(authCalled, false);
});

test("account deletion requires a signed-in bearer identity", async () => {
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }),
    {
      authenticatedUserID: async () => null,
      deleteAuthUser: async () => {},
    }
  );
  const body = await response.json();

  assert.equal(response.status, 401);
  assert.equal(body.error, "A signed-in iChart account is required.");
});

test("account deletion requires configured database preparation", async () => {
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }),
    {
      authenticatedUserID: async () => ownerID,
      deleteAuthUser: async () => {},
    }
  );
  const body = await response.json();

  assert.equal(response.status, 501);
  assert.equal(body.error, "Account deletion database preparation is not configured.");
});

test("account deletion prepares forum rows before deleting storage and auth user", async () => {
  const calls = [];
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }),
    {
      authenticatedUserID: async () => ownerID,
      listForumPDFStoragePaths: async () => [
        `${ownerID}/pending.pdf`,
        `${ownerID}/published.pdf`,
      ],
      listOwnerSnapshotArchiveStoragePaths: async () => [],
      prepareAccountDeletion: async (userID) => {
        calls.push(["prepare", userID]);
      },
      deleteForumPDFStoragePaths: async (paths) => {
        calls.push(["storage", paths]);
      },
      deleteAuthUser: async (userID) => {
        calls.push(["auth", userID]);
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.accepted, true);
  assert.equal(body.account_deleted, true);
  assert.equal(body.forum_pdf_storage_paths_deleted, 2);
  assert.deepEqual(calls, [
    ["prepare", ownerID],
    ["storage", [`${ownerID}/pending.pdf`, `${ownerID}/published.pdf`]],
    ["auth", ownerID],
  ]);
});

test("account deletion still deletes auth user when there are no forum PDFs", async () => {
  let deletedUserID = null;
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }),
    {
      authenticatedUserID: async () => ownerID,
      listForumPDFStoragePaths: async () => [],
      listOwnerSnapshotArchiveStoragePaths: async () => [],
      prepareAccountDeletion: async () => {},
      deleteForumPDFStoragePaths: async () => {
        throw new Error("should not delete storage");
      },
      deleteAuthUser: async (userID) => {
        deletedUserID = userID;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.forum_pdf_storage_paths_deleted, 0);
  assert.equal(deletedUserID, ownerID);
});

test("account deletion fails closed if database preparation fails", async () => {
  const calls = [];
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }),
    {
      authenticatedUserID: async () => ownerID,
      listForumPDFStoragePaths: async () => [`${ownerID}/published.pdf`],
      listOwnerSnapshotArchiveStoragePaths: async () => [],
      prepareAccountDeletion: async () => {
        calls.push("prepare");
        throw new Error("prepare failed");
      },
      deleteForumPDFStoragePaths: async () => {
        calls.push("storage");
      },
      deleteAuthUser: async () => {
        calls.push("auth");
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 502);
  assert.equal(body.accepted, false);
  assert.deepEqual(calls, ["prepare"]);
});

test("account deletion fails closed if storage cleanup fails", async () => {
  let authDeleted = false;
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }),
    {
      authenticatedUserID: async () => ownerID,
      listForumPDFStoragePaths: async () => [`${ownerID}/published.pdf`],
      listOwnerSnapshotArchiveStoragePaths: async () => [],
      prepareAccountDeletion: async () => {},
      deleteForumPDFStoragePaths: async () => {
        throw new Error("storage failed");
      },
      deleteAuthUser: async () => {
        authDeleted = true;
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 502);
  assert.equal(body.accepted, false);
  assert.equal(authDeleted, false);
});

test("account deletion reports failure if auth deletion fails", async () => {
  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }),
    {
      authenticatedUserID: async () => ownerID,
      listForumPDFStoragePaths: async () => [],
      listOwnerSnapshotArchiveStoragePaths: async () => [],
      prepareAccountDeletion: async () => {},
      deleteAuthUser: async () => {
        throw new Error("auth failed");
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 502);
  assert.equal(body.error, "Account deletion could not be completed. Try again or contact support.");
});

test("account deletion wired dependencies verify bearer and delete owned server records", async () => {
  const requests = [];
  const dependencies = createAccountDeletionDependencies(
    {
      SUPABASE_URL: "https://project.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",
    },
    {
      fetch: async (url, init) => {
        const path = `${url.pathname}${url.search}`;
        requests.push([init.method, path, init.headers.authorization]);

        if (path === "/auth/v1/user") {
          assert.equal(init.headers.authorization, "Bearer user-token");
          return jsonResponse(200, { id: ownerID });
        }

        if (path === "/rest/v1/rpc/owner_snapshot_archive_deletion_scope") {
          assert.deepEqual(JSON.parse(init.body), { p_owner_id: ownerID });
          return jsonResponse(200, { applies: false });
        }

        if (url.pathname === "/rest/v1/forum_chart_posts") {
          assert.equal(url.searchParams.get("owner_id"), `eq.${ownerID}`);
          assert.equal(url.searchParams.get("select"), "id,pdf_storage_path");
          assert.equal(url.searchParams.get("order"), "id.asc");
          assert.equal(url.searchParams.get("limit"), "1000");
          if (url.searchParams.has("id")) {
            assert.equal(url.searchParams.get("id"), `gt.${postID}`);
            return jsonResponse(200, []);
          }
          return jsonResponse(200, [
            { id: postID, pdf_storage_path: `${ownerID}/published.pdf` },
          ]);
        }

        if (path === "/storage/v1/object/list/forum_chart_pdfs") {
          const body = JSON.parse(init.body);
          assert.deepEqual(body, {
            prefix: `${ownerID}/`,
            limit: 1000,
            offset: body.offset,
            sortBy: { column: "name", order: "asc" },
          });
          if (body.offset === 1) return jsonResponse(200, []);
          assert.equal(body.offset, 0);
          return jsonResponse(200, [
            { name: "pending.pdf" },
          ]);
        }

        if (path === "/rest/v1/rpc/prepare_account_deletion") {
          assert.deepEqual(JSON.parse(init.body), {
            target_owner_id: ownerID,
          });
          return jsonResponse(200, {
            reassigned_forum_songs: 1,
            deleted_forum_posts: 1,
            deleted_orphan_forum_songs: 0,
          });
        }

        if (path === `/storage/v1/object/forum_chart_pdfs/${ownerID}/published.pdf`) {
          return jsonResponse(200, {});
        }

        if (path === `/storage/v1/object/forum_chart_pdfs/${ownerID}/pending.pdf`) {
          return jsonResponse(404, {});
        }

        if (path === `/auth/v1/admin/users/${ownerID}`) {
          return jsonResponse(200, {});
        }

        return jsonResponse(500, { error: `unexpected ${path}` });
      },
    }
  );

  const response = await handleAccountDeletionRequest(
    deletionRequest({ confirmation }, { authorization: "Bearer user-token" }),
    dependencies
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.accepted, true);
  assert.equal(body.forum_pdf_storage_paths_deleted, 2);
  assert.deepEqual(requests, [
    ["GET", "/auth/v1/user", "Bearer user-token"],
    ["GET", `/rest/v1/forum_chart_posts?owner_id=eq.${ownerID}&select=id%2Cpdf_storage_path&order=id.asc&limit=1000`, "Bearer service-role-test-key"],
    ["GET", `/rest/v1/forum_chart_posts?owner_id=eq.${ownerID}&select=id%2Cpdf_storage_path&order=id.asc&limit=1000&id=gt.${postID}`, "Bearer service-role-test-key"],
    ["POST", "/storage/v1/object/list/forum_chart_pdfs", "Bearer service-role-test-key"],
    ["POST", "/storage/v1/object/list/forum_chart_pdfs", "Bearer service-role-test-key"],
    ["POST", "/rest/v1/rpc/owner_snapshot_archive_deletion_scope", "Bearer service-role-test-key"],
    ["POST", "/rest/v1/rpc/prepare_account_deletion", "Bearer service-role-test-key"],
    ["DELETE", `/storage/v1/object/forum_chart_pdfs/${ownerID}/published.pdf`, "Bearer service-role-test-key"],
    ["DELETE", `/storage/v1/object/forum_chart_pdfs/${ownerID}/pending.pdf`, "Bearer service-role-test-key"],
    ["DELETE", `/auth/v1/admin/users/${ownerID}`, "Bearer service-role-test-key"],
  ]);
});

test("account deletion inventories more than1000 posts and orphan PDFs before bounded cleanup", async () => {
  const posts = Array.from({ length: 1001 }, (_, index) => ({
    id: fixtureUUID(index + 1), pdf_storage_path: `${ownerID}/post-${index}.pdf`,
  }));
  const objects = Array.from({ length: 1001 }, (_, index) => ({ name: `orphan-${index}.pdf` }));
  const offsets = [];
  const seenPostCursors = [];
  const deletedPaths = [];
  let activeDeletes = 0;
  let maximumActiveDeletes = 0;
  let prepared = false;
  let authDeleted = false;
  const dependencies = createWiredDependencies(async (url, init) => {
    if (url.pathname === "/auth/v1/user") return jsonResponse(200, { id: ownerID });
    if (url.pathname === "/rest/v1/forum_chart_posts") {
      assert.equal(prepared, false);
      const cursor = url.searchParams.get("id")?.slice(3) ?? null;
      seenPostCursors.push(cursor);
      // A lower API cap must not make the inventory look complete early.
      return jsonResponse(200, posts.filter((row) => cursor === null || row.id > cursor).slice(0, 333));
    }
    if (url.pathname === "/storage/v1/object/list/forum_chart_pdfs") {
      assert.equal(prepared, false);
      const body = JSON.parse(init.body);
      assert.equal(body.prefix, `${ownerID}/`);
      assert.equal(body.limit, 1000);
      assert.deepEqual(body.sortBy, { column: "name", order: "asc" });
      offsets.push(body.offset);
      return jsonResponse(200, objects.slice(body.offset, body.offset + 1000));
    }
    if (url.pathname === "/rest/v1/rpc/prepare_account_deletion") {
      prepared = true;
      return jsonResponse(200, {});
    }
    if (init.method === "DELETE" && url.pathname.startsWith(`/storage/v1/object/forum_chart_pdfs/${ownerID}/`)) {
      assert.equal(prepared, true);
      assert.equal(authDeleted, false);
      activeDeletes += 1;
      maximumActiveDeletes = Math.max(maximumActiveDeletes, activeDeletes);
      await new Promise((resolve) => setImmediate(resolve));
      deletedPaths.push(url.pathname);
      activeDeletes -= 1;
      return jsonResponse(200, {});
    }
    if (url.pathname === `/auth/v1/admin/users/${ownerID}`) {
      assert.equal(activeDeletes, 0);
      assert.equal(deletedPaths.length, 2002);
      authDeleted = true;
      return jsonResponse(200, {});
    }
    throw new Error("Unexpected fixture request");
  });
  const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
  const body = await response.json();
  assert.equal(response.status, 202);
  assert.equal(body.forum_pdf_storage_paths_deleted, 2002);
  assert.deepEqual(offsets, [0, 1000, 1001]);
  assert.equal(seenPostCursors.length, 5);
  assert.equal(authDeleted, true);
  assert.equal(new Set(deletedPaths).size, 2002);
  assert.ok(maximumActiveDeletes > 1 && maximumActiveDeletes <= 10);
});

test("account deletion stops before preparation or Auth deletion when a storage listing fails", async () => {
  const mutations = [];
  const dependencies = createWiredDependencies(async (url, init) => {
    if (url.pathname === "/auth/v1/user") return jsonResponse(200, { id: ownerID });
    if (url.pathname === "/rest/v1/forum_chart_posts") return jsonResponse(200, []);
    if (url.pathname === "/storage/v1/object/list/forum_chart_pdfs") return jsonResponse(503, { error: "fixture failure" });
    mutations.push([init.method, url.pathname]);
    return jsonResponse(200, {});
  });
  const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
  assert.equal(response.status, 502);
  assert.equal((await response.json()).accepted, false);
  assert.deepEqual(mutations, []);
});

test("account deletion rejects malformed, nested and unowned paths before mutation", async () => {
  const invalidPaths = [
    `${fixtureUUID(999)}/other.pdf`, `${ownerID}/../escape.pdf`, `${ownerID}/nested/file.pdf`,
    `${ownerID}/encoded%2fpath.pdf`, `${ownerID}/query.pdf?x=1`, `${ownerID}/not-pdf.txt`,
    null, { path: `${ownerID}/object.pdf` },
  ];
  for (const path of invalidPaths) {
    const calls = [];
    const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }), {
      authenticatedUserID: async () => ownerID,
      listForumPDFStoragePaths: async () => [path],
      listOwnerSnapshotArchiveStoragePaths: async () => [],
      prepareAccountDeletion: async () => calls.push("prepare"),
      deleteForumPDFStoragePaths: async () => calls.push("storage"),
      deleteAuthUser: async () => calls.push("auth"),
    });
    assert.equal(response.status, 502);
    assert.deepEqual(calls, []);
  }
});

test("account deletion fails closed when post or storage pages repeat without progress", async () => {
  for (const repeatingTable of ["posts", "storage"]) {
    const mutations = [];
    const dependencies = createWiredDependencies(async (url, init) => {
      if (url.pathname === "/auth/v1/user") return jsonResponse(200, { id: ownerID });
      if (url.pathname === "/rest/v1/forum_chart_posts") return jsonResponse(200, repeatingTable === "posts"
        ? [{ id: postID, pdf_storage_path: `${ownerID}/post.pdf` }] : []);
      if (url.pathname === "/storage/v1/object/list/forum_chart_pdfs") return jsonResponse(200, [{ name: "orphan.pdf" }]);
      mutations.push([init.method, url.pathname]);
      return jsonResponse(200, {});
    });
    const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
    assert.equal(response.status, 502);
    assert.deepEqual(mutations, []);
  }
});

test("account deletion preserves case of owned legacy PDF object names", async () => {
  const paths = [];
  const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }), {
    authenticatedUserID: async () => ownerID,
    listForumPDFStoragePaths: async () => [`${ownerID}/Legacy Chart.PDF`, `${ownerID}/Legacy Chart.PDF`],
    listOwnerSnapshotArchiveStoragePaths: async () => [],
    prepareAccountDeletion: async () => {},
    deleteForumPDFStoragePaths: async (values) => paths.push(...values),
    deleteAuthUser: async () => {},
  });
  assert.equal(response.status, 202);
  assert.deepEqual(paths, [`${ownerID}/Legacy Chart.PDF`]);
});

test("account deletion requires archive inventory authority before any mutation", async () => {
  const mutations = [];
  const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }), {
    authenticatedUserID: async () => ownerID,
    prepareAccountDeletion: async () => mutations.push("prepare"),
    deleteAuthUser: async () => mutations.push("auth"),
  });
  assert.equal(response.status, 501);
  assert.deepEqual(mutations, []);
});

test("other-account deletion scopes only the verified bearer and never touches archive Storage", async () => {
  const calls = [];
  const dependencies = createArchiveWiredDependencies(async (url, init) => {
    calls.push([init.method, url.pathname]);
    if (url.pathname === archiveScopePath) {
      assert.equal(init.headers.authorization, "Bearer service-role-test-key");
      assert.deepEqual(JSON.parse(init.body), { p_owner_id: ownerID });
      return jsonResponse(200, { applies: false });
    }
    if (url.pathname === "/rest/v1/rpc/prepare_account_deletion" || url.pathname === `/auth/v1/admin/users/${ownerID}`) {
      return jsonResponse(200, {});
    }
    throw new Error("Other accounts must not inspect or delete archive Storage");
  }, [], () => { throw new Error("Other accounts must not inspect archive bucket metadata"); });
  const response = await handleAccountDeletionRequest(deletionRequest({
    confirmation, owner_id: fixtureUUID(999), bucket: "unrelated", prefix: "/",
  }, { authorization: "Bearer user-token" }), dependencies);
  assert.equal(response.status, 202);
  assert.deepEqual(calls, [
    ["POST", archiveScopePath], ["POST", "/rest/v1/rpc/prepare_account_deletion"],
    ["DELETE", `/auth/v1/admin/users/${ownerID}`],
  ]);
});

test("configured-owner deletion fully inventories short archive pages before bounded deletion and Auth", async () => {
  const objects = Array.from({ length: 1001 }, (_, index) => ({ name: `${fixtureUUID(index + 1)}.jsonl.gz` }));
  const offsets = [];
  const deleted = [];
  let inventoryComplete = false;
  let prepared = false;
  let activeDeletes = 0;
  let maximumActiveDeletes = 0;
  let authDeleted = false;
  let forumDeleted = false;
  const dependencies = createArchiveWiredDependencies(async (url, init) => {
    if (url.pathname === archiveScopePath) return jsonResponse(200, matchingArchiveScope());
    if (url.pathname === archiveListPath) {
      assert.equal(prepared, false);
      assert.equal(activeDeletes, 0);
      const body = JSON.parse(init.body);
      assert.deepEqual(body, { prefix: `${ownerID}/`, limit: 1000, offset: body.offset,
        sortBy: { column: "name", order: "asc" } });
      offsets.push(body.offset);
      const page = objects.slice(body.offset, body.offset + 333);
      if (page.length === 0) inventoryComplete = true;
      return jsonResponse(200, page);
    }
    if (url.pathname === "/rest/v1/rpc/prepare_account_deletion") {
      assert.equal(inventoryComplete, true);
      prepared = true;
      return jsonResponse(200, {});
    }
    if (init.method === "DELETE" && url.pathname === `/storage/v1/object/forum_chart_pdfs/${ownerID}/owned.pdf`) {
      assert.equal(inventoryComplete, true);
      assert.equal(prepared, true);
      forumDeleted = true;
      return jsonResponse(200, {});
    }
    if (init.method === "DELETE" && url.pathname.startsWith(`/storage/v1/object/${archiveBucket}/${ownerID}/`)) {
      assert.equal(prepared, true);
      assert.equal(inventoryComplete, true);
      assert.equal(authDeleted, false);
      activeDeletes += 1;
      maximumActiveDeletes = Math.max(maximumActiveDeletes, activeDeletes);
      await new Promise((resolve) => setImmediate(resolve));
      deleted.push(url.pathname);
      activeDeletes -= 1;
      return jsonResponse(deleted.length === 1 ? 404 : 200, {});
    }
    if (url.pathname === `/auth/v1/admin/users/${ownerID}`) {
      assert.equal(activeDeletes, 0);
      assert.equal(deleted.length, objects.length);
      assert.equal(forumDeleted, true);
      authDeleted = true;
      return jsonResponse(200, {});
    }
    throw new Error("Unexpected archive cleanup request");
  }, [{ name: "owned.pdf" }]);
  const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
  assert.equal(response.status, 202);
  assert.deepEqual(offsets, [0, 333, 666, 999, 1001]);
  assert.equal(new Set(deleted).size, objects.length);
  assert.ok(maximumActiveDeletes > 1 && maximumActiveDeletes <= 10);
  assert.equal(authDeleted, true);
});

test("busy archive fence stops before archive inventory and all destructive operations", async () => {
  const calls = [];
  const dependencies = createArchiveWiredDependencies(async (url, init) => {
    calls.push([init.method, url.pathname]);
    if (url.pathname === archiveScopePath) return jsonResponse(200, matchingArchiveScope({ ready: false }));
    throw new Error("A leased archive must drain before inventory or destruction");
  }, [], () => { throw new Error("Busy archive scopes must not inspect bucket metadata"); });
  const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { accepted: false, error: "Account deletion is temporarily busy. Try again shortly." });
  assert.deepEqual(calls, [["POST", archiveScopePath]]);
});

test("missing malformed or unowned archive scopes fail before storage inventory or destruction", async () => {
  const scopes = [null, [], {}, { applies: "false" }, matchingArchiveScope({ ready: undefined }),
    matchingArchiveScope({ owner_id: fixtureUUID(999) }), matchingArchiveScope({ bucket: "forum_chart_pdfs" }),
    matchingArchiveScope({ prefix: "" }), matchingArchiveScope({ prefix: "/" }),
    matchingArchiveScope({ prefix: `${fixtureUUID(999)}/` })];
  for (const scope of scopes) {
    const calls = [];
    const dependencies = createArchiveWiredDependencies(async (url, init) => {
      calls.push([init.method, url.pathname]);
      if (url.pathname === archiveScopePath) return jsonResponse(scope === null ? 404 : 200, scope);
      throw new Error("Invalid scope cannot authorize storage or deletion");
    }, [{ name: "owned.pdf" }]);
    const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
    assert.equal(response.status, 502);
    assert.deepEqual(calls, [["POST", archiveScopePath]]);
  }
});

test("archive inventory rejects unsafe paths and later failed malformed or repeated pages before mutation", async () => {
  const validName = `${fixtureUUID(1)}.jsonl.gz`;
  const cases = [
    { rows: [{ name: `${fixtureUUID(999)}/${validName}` }] },
    { rows: [{ name: `../${validName}` }] }, { rows: [{ name: `nested/${validName}` }] },
    { rows: [{ name: `${fixtureUUID(1)}%2f.jsonl.gz` }] }, { rows: [{ name: `${validName}?x=1` }] },
    { rows: [{ name: "unknown.json" }] }, { rows: [{ name: null }] },
    { rows: [{ name: validName, id: null }] },
    { laterStatus: 503 }, { laterRows: {} }, { laterRows: [{ name: validName }] },
  ];
  for (const scenario of cases) {
    const mutations = [];
    const dependencies = createArchiveWiredDependencies(async (url, init) => {
      if (url.pathname === archiveScopePath) return jsonResponse(200, matchingArchiveScope());
      if (url.pathname === archiveListPath) {
        const { offset } = JSON.parse(init.body);
        return offset === 0 ? jsonResponse(200, scenario.rows ?? [{ name: validName }])
          : jsonResponse(scenario.laterStatus ?? 200, scenario.laterRows ?? []);
      }
      mutations.push([init.method, url.pathname]);
      return jsonResponse(200, {});
    }, [{ name: "owned.pdf" }]);
    const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
    assert.equal(response.status, 502);
    assert.deepEqual(mutations, []);
  }
});

test("archive deletion failure waits for its batch and retry inventories remaining owned objects before Auth", async () => {
  const names = [1, 2, 3].map((index) => `${fixtureUUID(index)}.jsonl.gz`);
  const remaining = new Set(names);
  let failOnce = true;
  let activeDeletes = 0;
  let authDeleteCount = 0;
  let inventoryStarts = 0;
  const dependencies = createArchiveWiredDependencies(async (url, init) => {
    if (url.pathname === archiveScopePath) return jsonResponse(200, matchingArchiveScope());
    if (url.pathname === archiveListPath) {
      const { offset } = JSON.parse(init.body);
      if (offset === 0) inventoryStarts += 1;
      return jsonResponse(200, Array.from(remaining).sort().slice(offset).map((name) => ({ name })));
    }
    if (url.pathname === "/rest/v1/rpc/prepare_account_deletion") return jsonResponse(200, {});
    if (init.method === "DELETE" && url.pathname.startsWith(`/storage/v1/object/${archiveBucket}/${ownerID}/`)) {
      activeDeletes += 1;
      await new Promise((resolve) => setImmediate(resolve));
      const name = url.pathname.split("/").at(-1);
      const failed = name === names[1] && failOnce;
      if (failed) failOnce = false;
      else remaining.delete(name);
      activeDeletes -= 1;
      return jsonResponse(failed ? 503 : 200, {});
    }
    if (url.pathname === `/auth/v1/admin/users/${ownerID}`) {
      assert.equal(activeDeletes, 0);
      assert.equal(remaining.size, 0);
      authDeleteCount += 1;
      return jsonResponse(200, {});
    }
    throw new Error("Unexpected archive retry request");
  });
  const first = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
  assert.equal(first.status, 502);
  assert.equal(activeDeletes, 0);
  assert.equal(authDeleteCount, 0);
  assert.deepEqual(Array.from(remaining), [names[1]]);
  const retried = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
  assert.equal(retried.status, 202);
  assert.equal(inventoryStarts, 2);
  assert.equal(authDeleteCount, 1);
});

test("archive deletion authority validates every captured key before sending its first DELETE", async () => {
  const requests = [];
  const dependencies = createArchiveWiredDependencies(async (url, init) => {
    requests.push([init.method, url.pathname]);
    return jsonResponse(200, {});
  });
  await assert.rejects(dependencies.deleteOwnerSnapshotArchiveStoragePaths(ownerID, [
    `${ownerID}/${fixtureUUID(1)}.jsonl.gz`, `${fixtureUUID(999)}/${fixtureUUID(2)}.jsonl.gz`,
  ]));
  assert.deepEqual(requests, []);
});

test("definitively absent fixed archive bucket permits account deletion without object inventory", async () => {
  const absentResponses = [
    () => jsonResponse(404, {}),
    () => jsonResponse(400, { statusCode: "404", code: "NoSuchBucket", error: "Bucket not found", message: "Bucket not found" }),
    () => jsonResponse(400, { statusCode: 404, error: "Bucket not found", message: "Bucket not found" }),
  ];
  for (const absentResponse of absentResponses) {
    const calls = [];
    let scopeReady = false;
    const dependencies = createArchiveWiredDependencies(async (url, init) => {
      calls.push([init.method, url.pathname]);
      if (url.pathname === archiveScopePath) {
        scopeReady = true;
        return jsonResponse(200, matchingArchiveScope());
      }
      if (url.pathname === "/rest/v1/rpc/prepare_account_deletion"
          || url.pathname === `/storage/v1/object/forum_chart_pdfs/${ownerID}/owned.pdf`
          || url.pathname === `/auth/v1/admin/users/${ownerID}`) return jsonResponse(200, {});
      throw new Error("An absent archive bucket must not trigger object listing or deletion");
    }, [{ name: "owned.pdf" }], (url, init) => {
      assert.equal(scopeReady, true);
      assert.equal(init.method, "GET");
      assert.equal(init.headers.authorization, "Bearer service-role-test-key");
      calls.push([init.method, url.pathname]);
      return absentResponse();
    });
    const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
    assert.equal(response.status, 202);
    assert.deepEqual(calls, [
      ["POST", archiveScopePath], ["GET", archiveBucketPath],
      ["POST", "/rest/v1/rpc/prepare_account_deletion"],
      ["DELETE", `/storage/v1/object/forum_chart_pdfs/${ownerID}/owned.pdf`],
      ["DELETE", `/auth/v1/admin/users/${ownerID}`],
    ]);
  }
});

test("unknown bucket errors object-missing authorization and transport failures still stop all destruction", async () => {
  const invalidResponses = [
    () => jsonResponse(400, { statusCode: "404", code: "NoSuchKey", error: "not_found", message: "Object not found" }),
    () => jsonResponse(400, { message: "Bucket not found" }),
    () => jsonResponse(400, { statusCode: 404, error: "Bucket not found", message: "Object not found" }),
    () => jsonResponse(401, { statusCode: 404, code: "NoSuchBucket" }),
    () => jsonResponse(403, { error: "Unauthorized" }),
    () => jsonResponse(503, { error: "Unavailable" }),
    () => new Response("invalid JSON", { status: 400 }),
    () => { throw new Error("Transport unavailable"); },
  ];
  for (const invalidResponse of invalidResponses) {
    const mutations = [];
    let lookups = 0;
    const dependencies = createArchiveWiredDependencies(async (url, init) => {
      if (url.pathname === archiveScopePath) return jsonResponse(200, matchingArchiveScope());
      mutations.push([init.method, url.pathname]);
      return jsonResponse(200, {});
    }, [{ name: "owned.pdf" }], () => { lookups += 1; return invalidResponse(); });
    const response = await handleAccountDeletionRequest(deletionRequest({ confirmation }, { authorization: "Bearer user-token" }), dependencies);
    assert.equal(response.status, 502);
    assert.equal(lookups, 1);
    assert.deepEqual(mutations, []);
  }
});

function matchingArchiveScope(changes = {}) {
  return { applies: true, ready: true, owner_id: ownerID, bucket: archiveBucket, prefix: `${ownerID}/`, ...changes };
}

function createArchiveWiredDependencies(fetcher, forumObjects = [],
  bucketLookup = () => jsonResponse(200, { id: archiveBucket, public: false })) {
  return createAccountDeletionDependencies({ SUPABASE_URL: "https://project.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key" }, {
    fetch: (url, init) => {
      if (url.pathname === "/auth/v1/user") return jsonResponse(200, { id: ownerID });
      if (url.pathname === "/rest/v1/forum_chart_posts") {
        return jsonResponse(200, []);
      }
      if (url.pathname === "/storage/v1/object/list/forum_chart_pdfs") {
        const { offset } = JSON.parse(init.body);
        return jsonResponse(200, forumObjects.slice(offset, offset + 1000));
      }
      if (url.pathname === archiveBucketPath) return bucketLookup(url, init);
      return fetcher(url, init);
    },
  });
}

function fixtureUUID(value) {
  return `00000000-0000-4000-8000-${String(value).padStart(12, "0")}`;
}

function createWiredDependencies(fetcher) {
  return createAccountDeletionDependencies({ SUPABASE_URL: "https://project.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key" }, {
    fetch: (url, init) => url.pathname === "/rest/v1/rpc/owner_snapshot_archive_deletion_scope"
      ? jsonResponse(200, { applies: false }) : fetcher(url, init),
  });
}

function deletionRequest(body, headers = {}) {
  return new Request("https://example.test", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
