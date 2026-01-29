import { getAccessToken, WecomApiError, type WecomFetch } from "./api.js";

export type WecomProbeResult = {
  ok: boolean;
  error?: string;
  elapsedMs: number;
};

export async function probeWecom(
  corpId: string,
  secret: string,
  timeoutMs = 5000,
  fetcher?: WecomFetch,
): Promise<WecomProbeResult> {
  if (!corpId?.trim() || !secret?.trim()) {
    return { ok: false, error: "Missing corpId or secret", elapsedMs: 0 };
  }

  const startTime = Date.now();

  try {
    // Getting access token validates the credentials
    await getAccessToken(corpId.trim(), secret.trim(), fetcher);
    const elapsedMs = Date.now() - startTime;
    return { ok: true, elapsedMs };
  } catch (err) {
    const elapsedMs = Date.now() - startTime;

    if (err instanceof WecomApiError) {
      return { ok: false, error: err.errmsg ?? err.message, elapsedMs };
    }

    if (err instanceof Error) {
      if (err.name === "AbortError") {
        return { ok: false, error: `Request timed out after ${timeoutMs}ms`, elapsedMs };
      }
      return { ok: false, error: err.message, elapsedMs };
    }

    return { ok: false, error: String(err), elapsedMs };
  }
}
