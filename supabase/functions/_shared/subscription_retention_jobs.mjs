import { supabaseSecretKeyFromEnv } from "./supabase_subscription_authority_store.mjs";

const defaultEmailBatchLimit = 25;
const maxEmailBatchLimit = 50;

export function createSubscriptionRetentionJobDependencies(env = globalThis.Deno?.env, options = {}) {
  const supabaseURL = normalizedString(envValue(env, "SUPABASE_URL")).replace(/\/+$/, "");
  const secretKey = supabaseSecretKeyFromEnv(env);
  const jobSecret = normalizedString(envValue(env, "ICHART_RETENTION_JOB_SECRET"));
  const resendAPIKey = normalizedString(envValue(env, "RESEND_API_KEY"));
  const emailFrom = normalizedString(envValue(env, "ICHART_RETENTION_EMAIL_FROM"));
  const fetcher = options.fetch ?? fetch;

  return {
    jobSecret,
    emailProviderConfigured: resendAPIKey.length > 0 && emailFrom.length > 0,
    runRetentionJobs: (runAt) => callSupabaseRPC(
      {
        supabaseURL,
        secretKey,
        fetcher,
      },
      "run_subscription_retention_jobs",
      runAt === null || runAt === undefined ? {} : { run_at: runAt }
    ),
    claimEmailEvents: (batchLimit = defaultEmailBatchLimit) => callSupabaseRPC(
      {
        supabaseURL,
        secretKey,
        fetcher,
      },
      "claim_subscription_retention_events",
      { batch_limit: boundedBatchLimit(batchLimit) }
    ),
    markEmailEventSent: (eventID) => callSupabaseRPC(
      {
        supabaseURL,
        secretKey,
        fetcher,
      },
      "mark_subscription_retention_event_sent",
      { event_id: eventID }
    ),
    markEmailEventFailed: (eventID, errorMessage) => callSupabaseRPC(
      {
        supabaseURL,
        secretKey,
        fetcher,
      },
      "mark_subscription_retention_event_failed",
      { event_id: eventID, error_message: errorMessage }
    ),
    sendEmail: (event) => sendRetentionEmail(
      {
        resendAPIKey,
        emailFrom,
        fetcher,
      },
      event
    ),
  };
}

export async function handleSubscriptionRetentionJobRequest(request, dependencies = {}) {
  if (request.method !== "POST") {
    return jsonResponse(405, {
      accepted: false,
      error: "Use POST for iChart subscription retention jobs.",
    });
  }

  if (!authorizedJobRequest(request, dependencies.jobSecret)) {
    return jsonResponse(401, {
      accepted: false,
      error: "Subscription retention job authorization failed.",
    });
  }

  if (typeof dependencies.runRetentionJobs !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "Subscription retention job runner is not configured.",
    });
  }

  const body = await optionalJSON(request, { maxBytes: 4_096 });
  if (!body.ok) {
    return jsonResponse(body.tooLarge ? 413 : 400, {
      accepted: false,
      error: body.tooLarge
        ? "Subscription retention job payload is too large."
        : "Request body must be valid JSON.",
    });
  }

  const jobResult = await dependencies.runRetentionJobs(body.value?.run_at ?? null);
  if (!dependencies.emailProviderConfigured) {
    return jsonResponse(202, {
      accepted: true,
      job: jobResult,
      email_status: "not_configured",
      emails_attempted: 0,
      emails_sent: 0,
      emails_failed: 0,
    });
  }

  if (
    typeof dependencies.claimEmailEvents !== "function"
    || typeof dependencies.sendEmail !== "function"
    || typeof dependencies.markEmailEventSent !== "function"
    || typeof dependencies.markEmailEventFailed !== "function"
  ) {
    return jsonResponse(501, {
      accepted: false,
      error: "Subscription retention email dispatcher is not configured.",
      job: jobResult,
    });
  }

  const events = await dependencies.claimEmailEvents(body.value?.batch_limit ?? defaultEmailBatchLimit);
  let emailsSent = 0;
  let emailsFailed = 0;

  for (const event of responseRows(events)) {
    try {
      await dependencies.sendEmail(event);
      await dependencies.markEmailEventSent(event.id);
      emailsSent += 1;
    } catch (error) {
      emailsFailed += 1;
      await dependencies.markEmailEventFailed(event.id, safeErrorMessage(error));
    }
  }

  return jsonResponse(202, {
    accepted: true,
    job: jobResult,
    email_status: "processed",
    emails_attempted: emailsSent + emailsFailed,
    emails_sent: emailsSent,
    emails_failed: emailsFailed,
  });
}

async function callSupabaseRPC(configuration, functionName, body) {
  const supabaseURL = normalizedString(configuration.supabaseURL);
  const secretKey = normalizedString(configuration.secretKey);
  if (supabaseURL.length === 0 || secretKey.length === 0) {
    throw new Error("Supabase service configuration is missing.");
  }

  const response = await configuration.fetcher(`${supabaseURL}/rest/v1/rpc/${functionName}`, {
    method: "POST",
    headers: {
      apikey: secretKey,
      authorization: `Bearer ${secretKey}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(body ?? {}),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Supabase RPC ${functionName} failed with status ${response.status}.`);
  }

  return parseOptionalJSON(text);
}

async function sendRetentionEmail(configuration, event) {
  const recipient = normalizedString(event?.recipient_email);
  if (recipient.length === 0) {
    throw new Error("Retention email event is missing a recipient.");
  }

  const response = await configuration.fetcher("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${configuration.resendAPIKey}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({
      from: configuration.emailFrom,
      to: [recipient],
      subject: normalizedString(event?.subject),
      text: normalizedString(event?.body),
    }),
  });

  if (!response.ok) {
    throw new Error(`Retention email provider failed with status ${response.status}.`);
  }

  return parseOptionalJSON(await response.text());
}

async function optionalJSON(request, options = {}) {
  const textResult = await readBoundedText(request, options.maxBytes ?? 4_096);
  if (!textResult.ok) {
    return {
      ok: false,
      value: null,
      tooLarge: true,
    };
  }

  const text = textResult.text.trim();
  if (text.length === 0) {
    return {
      ok: true,
      value: {},
    };
  }

  try {
    return {
      ok: true,
      value: JSON.parse(text),
    };
  } catch {
    return {
      ok: false,
      value: null,
      tooLarge: false,
    };
  }
}

async function readBoundedText(request, maxBytes) {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    return {
      ok: false,
      text: "",
    };
  }

  if (request.body === null) {
    return {
      ok: true,
      text: "",
    };
  }

  const reader = request.body.getReader();
  const chunks = [];
  let totalBytes = 0;

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    if (value === undefined) {
      continue;
    }

    const chunk = value instanceof Uint8Array ? value : new Uint8Array(value);
    totalBytes += chunk.byteLength;
    if (totalBytes > maxBytes) {
      try {
        await reader.cancel();
      } catch {
        // The response is already decided; stream cancellation is best effort.
      }
      return {
        ok: false,
        text: "",
      };
    }

    chunks.push(chunk);
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return {
    ok: true,
    text: new TextDecoder().decode(body),
  };
}

function authorizedJobRequest(request, jobSecret) {
  const expectedSecret = normalizedString(jobSecret);
  if (expectedSecret.length === 0) {
    return false;
  }

  const providedSecret = normalizedString(
    request.headers.get("x-ichart-retention-job-secret")
      ?? bearerToken(request)
  );
  return providedSecret.length > 0 && providedSecret === expectedSecret;
}

function bearerToken(request) {
  const authorization = request.headers.get("authorization") ?? "";
  return authorization.match(/^Bearer\s+(\S+)$/i)?.[1] ?? "";
}

function jsonResponse(status, body) {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
    },
  });
}

function boundedBatchLimit(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) {
    return defaultEmailBatchLimit;
  }

  return Math.min(Math.max(parsed, 0), maxEmailBatchLimit);
}

function responseRows(value) {
  if (Array.isArray(value)) {
    return value;
  }

  if (value === null || value === undefined) {
    return [];
  }

  return [value];
}

function parseOptionalJSON(text) {
  const trimmed = normalizedString(text);
  if (trimmed.length === 0) {
    return null;
  }

  return JSON.parse(trimmed);
}

function safeErrorMessage(error) {
  const message = normalizedString(error?.message);
  return message.length > 0 ? message : "Unknown subscription retention email failure.";
}

function envValue(env, key) {
  if (env && typeof env.get === "function") {
    return env.get(key);
  }

  return env?.[key];
}

function normalizedString(value) {
  if (value === null || value === undefined) {
    return "";
  }

  return String(value).trim();
}
