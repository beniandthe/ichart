export async function verifyWithAppStoreEnvironmentFallback({
  primaryVerification,
  compactFallbackVerification,
  sandboxVerification,
  sandboxCompactFallbackVerification,
}) {
  try {
    return await primaryVerification();
  } catch (primaryError) {
    if (!isGenericVerificationFailure(primaryError)) {
      throw primaryError;
    }

    if (typeof sandboxVerification === "function") {
      const sandboxResult = await attemptFallbackVerification(
        sandboxVerification,
        sandboxCompactFallbackVerification
      );
      if (sandboxResult.ok) {
        return sandboxResult.value;
      }
    }

    return compactFallbackVerification();
  }
}

async function attemptFallbackVerification(verification, compactFallbackVerification) {
  try {
    return {
      ok: true,
      value: await verification(),
    };
  } catch (error) {
    if (isGenericVerificationFailure(error) && typeof compactFallbackVerification === "function") {
      try {
        return {
          ok: true,
          value: await compactFallbackVerification(),
        };
      } catch {
        return { ok: false };
      }
    }

    return { ok: false };
  }
}

function isGenericVerificationFailure(error) {
  return Number(error?.status) === 1;
}
