/**
 * Feishu (Lark) Open Platform API client
 * @see https://open.feishu.cn/document/
 */

import type { FeishuAccessToken } from "./types.js";

const FEISHU_API_BASE = "https://open.feishu.cn/open-apis";

export type FeishuFetch = (input: string, init?: RequestInit) => Promise<Response>;

export type FeishuApiResponse<T = unknown> = {
  code: number;
  msg: string;
  data?: T;
};

export type FeishuUserInfo = {
  open_id: string;
  user_id?: string;
  union_id?: string;
  name?: string;
  avatar_url?: string;
};

export type FeishuMessage = {
  message_id: string;
};

export type FeishuEventMessage = {
  message_id: string;
  root_id?: string;
  parent_id?: string;
  create_time: string;
  chat_id: string;
  chat_type: "p2p" | "group";
  message_type: "text" | "image" | "file" | "audio" | "video" | "interactive" | "share_chat" | "share_user";
  content: string;
  mentions?: Array<{
    key: string;
    id: {
      open_id?: string;
      user_id?: string;
      union_id?: string;
    };
    name: string;
  }>;
};

export type FeishuEventSender = {
  sender_id: {
    open_id?: string;
    user_id?: string;
    union_id?: string;
  };
  sender_type: "user" | "app";
  tenant_key?: string;
};

export type FeishuMessageEvent = {
  schema: string;
  header: {
    event_id: string;
    event_type: string;
    create_time: string;
    token: string;
    app_id: string;
    tenant_key: string;
  };
  event: {
    sender: FeishuEventSender;
    message: FeishuEventMessage;
  };
};

export type FeishuUrlVerificationEvent = {
  challenge: string;
  token: string;
  type: "url_verification";
};

export type FeishuSendMessageParams = {
  receive_id: string;
  msg_type: "text" | "image" | "interactive" | "share_chat" | "share_user" | "audio" | "media" | "file" | "sticker";
  content: string;
  uuid?: string;
};

export class FeishuApiError extends Error {
  constructor(
    message: string,
    public readonly code: number,
    public readonly msg: string,
  ) {
    super(message);
    this.name = "FeishuApiError";
  }
}

// Access token cache (keyed by appId+appSecret)
const tokenCache = new Map<string, FeishuAccessToken>();

/**
 * Get tenant access token (cached, auto-refresh)
 */
export async function getTenantAccessToken(
  appId: string,
  appSecret: string,
  fetcher?: FeishuFetch,
): Promise<string> {
  const cacheKey = `${appId}:${appSecret}`;
  const cached = tokenCache.get(cacheKey);

  // Return cached token if still valid (with 5 min buffer)
  if (cached && cached.expiresAt > Date.now() + 300_000) {
    return cached.tenantAccessToken;
  }

  const url = `${FEISHU_API_BASE}/auth/v3/tenant_access_token/internal`;
  const fetch_ = fetcher ?? fetch;

  const response = await fetch_(url, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ app_id: appId, app_secret: appSecret }),
  });

  const data = (await response.json()) as FeishuApiResponse<never> & {
    tenant_access_token?: string;
    expire?: number;
  };

  if (data.code !== 0 || !data.tenant_access_token) {
    throw new FeishuApiError(
      data.msg ?? `Failed to get tenant access token: ${data.code}`,
      data.code,
      data.msg,
    );
  }

  const token: FeishuAccessToken = {
    tenantAccessToken: data.tenant_access_token,
    expiresAt: Date.now() + (data.expire ?? 7200) * 1000,
  };
  tokenCache.set(cacheKey, token);

  return token.tenantAccessToken;
}

/**
 * Call Feishu API with tenant access token
 */
export async function callFeishuApi<T = unknown>(
  endpoint: string,
  accessToken: string,
  body?: Record<string, unknown>,
  options?: {
    timeoutMs?: number;
    fetch?: FeishuFetch;
    method?: "GET" | "POST";
    query?: Record<string, string>;
  },
): Promise<FeishuApiResponse<T>> {
  const method = options?.method ?? (body ? "POST" : "GET");
  let url = `${FEISHU_API_BASE}${endpoint}`;
  if (options?.query) {
    const params = new URLSearchParams(options.query);
    url += `?${params.toString()}`;
  }

  const controller = new AbortController();
  const timeoutId = options?.timeoutMs
    ? setTimeout(() => controller.abort(), options.timeoutMs)
    : undefined;
  const fetcher = options?.fetch ?? fetch;

  try {
    const response = await fetcher(url, {
      method,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json; charset=utf-8",
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });

    const data = (await response.json()) as FeishuApiResponse<T>;

    if (data.code !== 0) {
      throw new FeishuApiError(
        data.msg ?? `Feishu API error: ${endpoint}`,
        data.code,
        data.msg,
      );
    }

    return data;
  } finally {
    if (timeoutId) clearTimeout(timeoutId);
  }
}

/**
 * Send a message
 */
export async function sendMessage(
  accessToken: string,
  receiveIdType: "open_id" | "user_id" | "union_id" | "email" | "chat_id",
  params: FeishuSendMessageParams,
  fetcher?: FeishuFetch,
): Promise<FeishuApiResponse<FeishuMessage>> {
  return callFeishuApi<FeishuMessage>("/im/v1/messages", accessToken, params, {
    fetch: fetcher,
    query: { receive_id_type: receiveIdType },
  });
}

/**
 * Send a text message (convenience wrapper)
 */
export async function sendTextMessage(
  accessToken: string,
  receiveIdType: "open_id" | "user_id" | "union_id" | "email" | "chat_id",
  receiveId: string,
  text: string,
  fetcher?: FeishuFetch,
): Promise<FeishuApiResponse<FeishuMessage>> {
  return sendMessage(
    accessToken,
    receiveIdType,
    {
      receive_id: receiveId,
      msg_type: "text",
      content: JSON.stringify({ text }),
    },
    fetcher,
  );
}

/**
 * Reply to a message
 */
export async function replyMessage(
  accessToken: string,
  messageId: string,
  params: Omit<FeishuSendMessageParams, "receive_id">,
  fetcher?: FeishuFetch,
): Promise<FeishuApiResponse<FeishuMessage>> {
  return callFeishuApi<FeishuMessage>(`/im/v1/messages/${messageId}/reply`, accessToken, params, {
    fetch: fetcher,
  });
}

/**
 * Get bot info
 */
export async function getBotInfo(
  accessToken: string,
  fetcher?: FeishuFetch,
): Promise<FeishuApiResponse<{ app_name: string; avatar_url: string; open_id: string }>> {
  return callFeishuApi("/bot/v3/info", accessToken, undefined, {
    fetch: fetcher,
    method: "GET",
  });
}
