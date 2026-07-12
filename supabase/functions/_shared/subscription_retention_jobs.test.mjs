import assert from "node:assert/strict";
import test from "node:test";

import {
  createSubscriptionRetentionJobDependencies,
  handleSubscriptionRetentionJobRequest,
} from "./subscription_retention_jobs.mjs";

test("retention job rejects non-post requests", async () => {
  const response = await handleSubscriptionRetentionJobRequest(
    new Request("https://example.test/retention", { method: "GET" }),
    { jobSecret: "secret" }
  );

  assert.equal(response.status, 405);
});

test("retention job requires configured secret", async () => {
  const response = await handleSubscriptionRetentionJobRequest(
    new Request("https://example.test/retention", { method: "POST" }),
    { jobSecret: "" }
  );

  assert.equal(response.status, 401);
});

test("retention job runs cleanup and queues email when provider is unavailable", async () => {
  const calls = [];
  const response = await handleSubscriptionRetentionJobRequest(
    new Request("https://example.test/retention", {
      method: "POST",
      headers: {
        "x-ichart-retention-job-secret": "secret",
      },
    }),
    {
      jobSecret: "secret",
      emailProviderConfigured: false,
      runRetentionJobs: async () => {
        calls.push("run");
        return { cloud_deleted_events: 1 };
      },
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.deepEqual(calls, ["run"]);
  assert.equal(body.email_status, "not_configured");
  assert.equal(body.emails_attempted, 0);
});

test("retention job dispatches claimed email events and marks successes", async () => {
  const sent = [];
  const marked = [];
  const response = await handleSubscriptionRetentionJobRequest(
    new Request("https://example.test/retention", {
      method: "POST",
      headers: {
        authorization: "Bearer secret",
      },
      body: JSON.stringify({ batch_limit: 1 }),
    }),
    {
      jobSecret: "secret",
      emailProviderConfigured: true,
      runRetentionJobs: async () => ({ expiration_warning_events: 1 }),
      claimEmailEvents: async (batchLimit) => {
        assert.equal(batchLimit, 1);
        return [
          {
            id: "event-1",
            recipient_email: "player@example.test",
            subject: "Your iChart Pro access ends soon",
            body: "Your iChart Pro subscription is scheduled to end soon.",
          },
        ];
      },
      sendEmail: async (event) => sent.push(event.id),
      markEmailEventSent: async (eventID) => marked.push(eventID),
      markEmailEventFailed: async () => assert.fail("expected email to succeed"),
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.deepEqual(sent, ["event-1"]);
  assert.deepEqual(marked, ["event-1"]);
  assert.equal(body.emails_sent, 1);
  assert.equal(body.emails_failed, 0);
});

test("retention job marks email provider failures", async () => {
  const failed = [];
  const response = await handleSubscriptionRetentionJobRequest(
    new Request("https://example.test/retention", {
      method: "POST",
      headers: {
        "x-ichart-retention-job-secret": "secret",
      },
    }),
    {
      jobSecret: "secret",
      emailProviderConfigured: true,
      runRetentionJobs: async () => ({}),
      claimEmailEvents: async () => [
        {
          id: "event-2",
          recipient_email: "player@example.test",
          subject: "Your iChart cloud backup was removed",
          body: "Cloud backup is no longer available.",
        },
      ],
      sendEmail: async () => {
        throw new Error("provider down");
      },
      markEmailEventSent: async () => assert.fail("expected email to fail"),
      markEmailEventFailed: async (eventID, errorMessage) => failed.push([eventID, errorMessage]),
    }
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.deepEqual(failed, [["event-2", "provider down"]]);
  assert.equal(body.emails_sent, 0);
  assert.equal(body.emails_failed, 1);
});

test("retention job dependencies call expected Supabase RPC and Resend endpoints", async () => {
  const requests = [];
  const dependencies = createSubscriptionRetentionJobDependencies(
    {
      SUPABASE_URL: "https://project.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "service-key",
      ICHART_RETENTION_JOB_SECRET: "job-secret",
      RESEND_API_KEY: "resend-key",
      ICHART_RETENTION_EMAIL_FROM: "iChart <support@useichart.com>",
    },
    {
      fetch: async (url, options) => {
        requests.push({ url: String(url), options });
        if (String(url).includes("resend.com")) {
          return new Response(JSON.stringify({ id: "email-1" }), { status: 200 });
        }
        return new Response(JSON.stringify([]), { status: 200 });
      },
    }
  );

  assert.equal(dependencies.jobSecret, "job-secret");
  assert.equal(dependencies.emailProviderConfigured, true);
  await dependencies.runRetentionJobs("2026-07-11T15:00:00.000Z");
  await dependencies.runRetentionJobs();
  await dependencies.claimEmailEvents(99);
  await dependencies.markEmailEventSent("event-1");
  await dependencies.markEmailEventFailed("event-2", "failure");
  await dependencies.sendEmail({
    recipient_email: "player@example.test",
    subject: "Subject",
    body: "Body",
  });

  assert.equal(requests[0].url, "https://project.supabase.co/rest/v1/rpc/run_subscription_retention_jobs");
  assert.deepEqual(JSON.parse(requests[0].options.body), { run_at: "2026-07-11T15:00:00.000Z" });
  assert.equal(requests[1].url, "https://project.supabase.co/rest/v1/rpc/run_subscription_retention_jobs");
  assert.deepEqual(JSON.parse(requests[1].options.body), {});
  assert.equal(requests[2].url, "https://project.supabase.co/rest/v1/rpc/claim_subscription_retention_events");
  assert.deepEqual(JSON.parse(requests[2].options.body), { batch_limit: 50 });
  assert.equal(requests[5].url, "https://api.resend.com/emails");
});
