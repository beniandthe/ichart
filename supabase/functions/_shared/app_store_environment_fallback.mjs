export async function verifyWithAppStoreEnvironmentFallback({
  primaryVerification,
  compactFallbackVerification,
  sandboxVerification,
  sandboxCompactFallbackVerification,
}) {
  try {
    return await primaryVerification();
  } catch (primaryError) {
    if (!isEnvironmentFallbackEligible(primaryError)) {
      throw primaryError;
    }

    let sandboxFailure = null;
    if (typeof sandboxVerification === "function") {
      const sandboxResult = await attemptFallbackVerification(
        sandboxVerification,
        sandboxCompactFallbackVerification
      );
      if (sandboxResult.ok) {
        return sandboxResult.value;
      }
      sandboxFailure = sandboxResult.error;
    }

    if (isGenericVerificationFailure(primaryError)) {
      try {
        return await compactFallbackVerification();
      } catch (compactError) {
        if (sandboxFailure !== null) {
          throw sandboxFailure;
        }

        throw compactError;
      }
    }

    throw sandboxFailure ?? primaryError;
  }
}

async function attemptFallbackVerification(verification, compactFallbackVerification) {
  try {
    return {
      ok: true,
      value: await verification(),
    };
  } catch (error) {
    if (typeof compactFallbackVerification === "function") {
      try {
        return {
          ok: true,
          value: await compactFallbackVerification(),
        };
      } catch (compactError) {
        return { ok: false, error: compactError };
      }
    }

    return { ok: false, error };
  }
}

function isEnvironmentFallbackEligible(error) {
  return isGenericVerificationFailure(error) || Number(error?.status) === 4;
}

function isGenericVerificationFailure(error) {
  return Number(error?.status) === 1;
}
