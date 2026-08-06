import assert from "node:assert/strict";
import test from "node:test";

import { verifyWithAppStoreEnvironmentFallback } from "./app_store_environment_fallback.mjs";

function verificationError(status) {
  return Object.assign(new Error(`verification ${status}`), { status });
}

test("returns primary verification results without trying sandbox fallback", async () => {
  let sandboxCalls = 0;

  const result = await verifyWithAppStoreEnvironmentFallback({
    primaryVerification: async () => ({ environment: "Production" }),
    compactFallbackVerification: async () => {
      throw new Error("compact fallback should not run");
    },
    sandboxVerification: async () => {
      sandboxCalls += 1;
      return { environment: "Sandbox" };
    },
  });

  assert.deepEqual(result, { environment: "Production" });
  assert.equal(sandboxCalls, 0);
});

test("uses sandbox verification after a generic production verification failure", async () => {
  const result = await verifyWithAppStoreEnvironmentFallback({
    primaryVerification: async () => {
      throw verificationError(1);
    },
    compactFallbackVerification: async () => {
      throw new Error("primary compact fallback should not run");
    },
    sandboxVerification: async () => ({ environment: "Sandbox" }),
  });

  assert.deepEqual(result, { environment: "Sandbox" });
});

test("uses sandbox compact fallback when sandbox library verification has the same generic failure", async () => {
  const result = await verifyWithAppStoreEnvironmentFallback({
    primaryVerification: async () => {
      throw verificationError(1);
    },
    compactFallbackVerification: async () => {
      throw new Error("primary compact fallback should not run");
    },
    sandboxVerification: async () => {
      throw verificationError(1);
    },
    sandboxCompactFallbackVerification: async () => ({ environment: "Sandbox" }),
  });

  assert.deepEqual(result, { environment: "Sandbox" });
});

test("uses sandbox compact fallback after non-generic sandbox library failure", async () => {
  const result = await verifyWithAppStoreEnvironmentFallback({
    primaryVerification: async () => {
      throw verificationError(1);
    },
    compactFallbackVerification: async () => {
      throw new Error("primary compact fallback should not run first");
    },
    sandboxVerification: async () => {
      throw verificationError(4);
    },
    sandboxCompactFallbackVerification: async () => ({ environment: "Sandbox" }),
  });

  assert.deepEqual(result, { environment: "Sandbox" });
});

test("uses sandbox fallback after primary invalid environment failure", async () => {
  const result = await verifyWithAppStoreEnvironmentFallback({
    primaryVerification: async () => {
      throw verificationError(4);
    },
    compactFallbackVerification: async () => {
      throw new Error("primary compact fallback should not run");
    },
    sandboxVerification: async () => ({ environment: "Sandbox" }),
  });

  assert.deepEqual(result, { environment: "Sandbox" });
});

test("preserves non-generic primary verification failures", async () => {
  await assert.rejects(
    () => verifyWithAppStoreEnvironmentFallback({
      primaryVerification: async () => {
        throw verificationError(3);
      },
      compactFallbackVerification: async () => ({ environment: "Fallback" }),
      sandboxVerification: async () => ({ environment: "Sandbox" }),
    }),
    /verification 3/
  );
});

test("falls back to the primary compact verifier when no sandbox fallback succeeds", async () => {
  const result = await verifyWithAppStoreEnvironmentFallback({
    primaryVerification: async () => {
      throw verificationError(1);
    },
    compactFallbackVerification: async () => ({ environment: "Compact" }),
    sandboxVerification: async () => {
      throw verificationError(4);
    },
  });

  assert.deepEqual(result, { environment: "Compact" });
});

test("surfaces sandbox fallback diagnostics when primary compact fallback also fails", async () => {
  await assert.rejects(
    () => verifyWithAppStoreEnvironmentFallback({
      primaryVerification: async () => {
        throw verificationError(1);
      },
      compactFallbackVerification: async () => {
        throw verificationError(11);
      },
      sandboxVerification: async () => {
        throw verificationError(4);
      },
      sandboxCompactFallbackVerification: async () => {
        throw verificationError(26);
      },
    }),
    /verification 26/
  );
});
