import { getTenantAccessToken, getBotInfo, FeishuApiError, type FeishuFetch } from "./api.js";

export type FeishuProbeResult = {
  ok: boolean;
  bot?: { name: string; openId: string };
  error?: string;
  elapsedMs: number;
};

export async function probeFeishu(
  appId: string,
  appSecret: string,
  timeoutMs = 5000,
  fetcher?: FeishuFetch,
): Promise<FeishuProbeResult> {
  if (!appId?.trim() || !appSecret?.trim()) {
    return { ok: false, error: "Missing appId or appSecret", elapsedMs: 0 };
  }

  const startTime = Date.now();

  try {
    const accessToken = await getTenantAccessToken(appId.trim(), appSecret.trim(), fetcher);
    const botInfo = await getBotInfo(accessToken, fetcher);
    const elapsedMs = Date.now() - startTime;

    if (botInfo.data) {
      return {
        ok: true,
        bot: { name: botInfo.data.app_name, openId: botInfo.data.open_id },
        elapsedMs,
      };
    }

    return { ok: true, elapsedMs };
  } catch (err) {
    const elapsedMs = Date.now() - startTime;

    if (err instanceof FeishuApiError) {
      return { ok: false, error: err.msg ?? err.message, elapsedMs };
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
