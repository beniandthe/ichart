import assert from "node:assert/strict";
import test from "node:test";

import {
  createAccountDeletionDependencies,
  handleAccountDeletionRequest,
} from "./account_deletion.mjs";

const confirmation = "DELETE_MY_ICHART_ACCOUNT";
const ownerID = "00000000-0000-4000-8000-000000000001";

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

        if (path === `/rest/v1/forum_chart_posts?owner_id=eq.${ownerID}&select=pdf_storage_path`) {
          return jsonResponse(200, [
            { pdf_storage_path: `${ownerID}/published.pdf` },
          ]);
        }

        if (path === "/storage/v1/object/list/forum_chart_pdfs") {
          assert.deepEqual(JSON.parse(init.body), {
            prefix: `${ownerID}/`,
            limit: 1000,
            offset: 0,
          });
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
    ["GET", `/rest/v1/forum_chart_posts?owner_id=eq.${ownerID}&select=pdf_storage_path`, "Bearer service-role-test-key"],
    ["POST", "/storage/v1/object/list/forum_chart_pdfs", "Bearer service-role-test-key"],
    ["POST", "/rest/v1/rpc/prepare_account_deletion", "Bearer service-role-test-key"],
    ["DELETE", `/storage/v1/object/forum_chart_pdfs/${ownerID}/published.pdf`, "Bearer service-role-test-key"],
    ["DELETE", `/storage/v1/object/forum_chart_pdfs/${ownerID}/pending.pdf`, "Bearer service-role-test-key"],
    ["DELETE", `/auth/v1/admin/users/${ownerID}`, "Bearer service-role-test-key"],
  ]);
});

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
