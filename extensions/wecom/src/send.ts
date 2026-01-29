import type { MoltbotConfig } from "clawdbot/plugin-sdk";

import { getAccessToken, sendTextMessage, type WecomFetch } from "./api.js";
import { resolveWecomAccount } from "./accounts.js";

export type WecomSendOptions = {
  corpId?: string;
  agentId?: string;
  secret?: string;
  accountId?: string;
  cfg?: MoltbotConfig;
  mediaUrl?: string;
  verbose?: boolean;
};

export type WecomSendResult = {
  ok: boolean;
  messageId?: string;
  error?: string;
};

function resolveSendContext(options: WecomSendOptions): {
  corpId: string;
  agentId: string;
  secret: string;
  fetcher?: WecomFetch;
} {
  if (options.cfg) {
    const account = resolveWecomAccount({
      cfg: options.cfg,
      accountId: options.accountId,
    });
    return {
      corpId: options.corpId || account.corpId,
      agentId: options.agentId || account.agentId,
      secret: options.secret || account.secret,
    };
  }

  return {
    corpId: options.corpId ?? "",
    agentId: options.agentId ?? "",
    secret: options.secret ?? "",
  };
}

export async function sendMessageWecom(
  userId: string,
  text: string,
  options: WecomSendOptions = {},
): Promise<WecomSendResult> {
  const { corpId, agentId, secret, fetcher } = resolveSendContext(options);

  if (!corpId || !agentId || !secret) {
    return { ok: false, error: "WeCom credentials not configured (corpId, agentId, secret)" };
  }

  if (!userId?.trim()) {
    return { ok: false, error: "No userId provided" };
  }

  try {
    const accessToken = await getAccessToken(corpId, secret, fetcher);

    const response = await sendTextMessage(
      accessToken,
      {
        touser: userId.trim(),
        msgtype: "text",
        agentid: Number.parseInt(agentId, 10),
        text: { content: text.slice(0, 2048) },
      },
      fetcher,
    );

    return { ok: true, messageId: response.msgid };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}
