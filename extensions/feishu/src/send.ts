import type { MoltbotConfig } from "clawdbot/plugin-sdk";

import { getTenantAccessToken, sendTextMessage, type FeishuFetch } from "./api.js";
import { resolveFeishuAccount } from "./accounts.js";

export type FeishuSendOptions = {
  appId?: string;
  appSecret?: string;
  accountId?: string;
  cfg?: MoltbotConfig;
  receiveIdType?: "open_id" | "user_id" | "union_id" | "email" | "chat_id";
  verbose?: boolean;
};

export type FeishuSendResult = {
  ok: boolean;
  messageId?: string;
  error?: string;
};

function resolveSendContext(options: FeishuSendOptions): {
  appId: string;
  appSecret: string;
  receiveIdType: "open_id" | "user_id" | "union_id" | "email" | "chat_id";
  fetcher?: FeishuFetch;
} {
  if (options.cfg) {
    const account = resolveFeishuAccount({
      cfg: options.cfg,
      accountId: options.accountId,
    });
    return {
      appId: options.appId || account.appId,
      appSecret: options.appSecret || account.appSecret,
      receiveIdType: options.receiveIdType || account.config.receiveIdType || "open_id",
    };
  }

  return {
    appId: options.appId ?? "",
    appSecret: options.appSecret ?? "",
    receiveIdType: options.receiveIdType || "open_id",
  };
}

export async function sendMessageFeishu(
  receiveId: string,
  text: string,
  options: FeishuSendOptions = {},
): Promise<FeishuSendResult> {
  const { appId, appSecret, receiveIdType, fetcher } = resolveSendContext(options);

  if (!appId || !appSecret) {
    return { ok: false, error: "Feishu credentials not configured (appId, appSecret)" };
  }

  if (!receiveId?.trim()) {
    return { ok: false, error: "No receiveId provided" };
  }

  try {
    const accessToken = await getTenantAccessToken(appId, appSecret, fetcher);

    const response = await sendTextMessage(
      accessToken,
      receiveIdType,
      receiveId.trim(),
      text.slice(0, 4096), // Feishu text message limit
      fetcher,
    );

    return { ok: true, messageId: response.data?.message_id };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}
