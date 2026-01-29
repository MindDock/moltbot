/**
 * WeCom (WeChat Work) API client
 * @see https://developer.work.weixin.qq.com/document/
 */

import type { WecomAccessToken } from "./types.js";

const WECOM_API_BASE = "https://qyapi.weixin.qq.com/cgi-bin";

export type WecomFetch = (input: string, init?: RequestInit) => Promise<Response>;

export type WecomApiResponse<T = unknown> = {
  errcode: number;
  errmsg: string;
} & T;

export type WecomUserInfo = {
  userid: string;
  name?: string;
  avatar?: string;
};

export type WecomMessage = {
  msgid: string;
  touser?: string;
  toparty?: string;
  totag?: string;
  msgtype: string;
  agentid: number;
  text?: { content: string };
  image?: { media_id: string };
  voice?: { media_id: string };
  video?: { media_id: string };
  file?: { media_id: string };
};

export type WecomIncomingMessage = {
  MsgId: string;
  MsgType: "text" | "image" | "voice" | "video" | "location" | "link" | "event";
  FromUserName: string;
  ToUserName: string;
  CreateTime: number;
  Content?: string;
  PicUrl?: string;
  MediaId?: string;
  Event?: string;
  EventKey?: string;
  AgentID: number;
};

export type WecomSendTextParams = {
  touser?: string;
  toparty?: string;
  totag?: string;
  msgtype: "text";
  agentid: number;
  text: { content: string };
  safe?: number;
  enable_duplicate_check?: number;
  duplicate_check_interval?: number;
};

export type WecomSendImageParams = {
  touser?: string;
  toparty?: string;
  totag?: string;
  msgtype: "image";
  agentid: number;
  image: { media_id: string };
  safe?: number;
};

export class WecomApiError extends Error {
  constructor(
    message: string,
    public readonly errcode: number,
    public readonly errmsg: string,
  ) {
    super(message);
    this.name = "WecomApiError";
  }
}

// Access token cache (keyed by corpId+secret)
const tokenCache = new Map<string, WecomAccessToken>();

/**
 * Get access token (cached, auto-refresh)
 */
export async function getAccessToken(
  corpId: string,
  secret: string,
  fetcher?: WecomFetch,
): Promise<string> {
  const cacheKey = `${corpId}:${secret}`;
  const cached = tokenCache.get(cacheKey);

  // Return cached token if still valid (with 5 min buffer)
  if (cached && cached.expiresAt > Date.now() + 300_000) {
    return cached.accessToken;
  }

  const url = `${WECOM_API_BASE}/gettoken?corpid=${encodeURIComponent(corpId)}&corpsecret=${encodeURIComponent(secret)}`;
  const fetch_ = fetcher ?? fetch;

  const response = await fetch_(url, { method: "GET" });
  const data = (await response.json()) as WecomApiResponse<{
    access_token?: string;
    expires_in?: number;
  }>;

  if (data.errcode !== 0 || !data.access_token) {
    throw new WecomApiError(
      data.errmsg ?? `Failed to get access token: ${data.errcode}`,
      data.errcode,
      data.errmsg,
    );
  }

  const token: WecomAccessToken = {
    accessToken: data.access_token,
    expiresAt: Date.now() + (data.expires_in ?? 7200) * 1000,
  };
  tokenCache.set(cacheKey, token);

  return token.accessToken;
}

/**
 * Call WeCom API with access token
 */
export async function callWecomApi<T = unknown>(
  endpoint: string,
  accessToken: string,
  body?: Record<string, unknown>,
  options?: { timeoutMs?: number; fetch?: WecomFetch; method?: "GET" | "POST" },
): Promise<WecomApiResponse<T>> {
  const method = options?.method ?? (body ? "POST" : "GET");
  const url = `${WECOM_API_BASE}${endpoint}${endpoint.includes("?") ? "&" : "?"}access_token=${encodeURIComponent(accessToken)}`;
  const controller = new AbortController();
  const timeoutId = options?.timeoutMs
    ? setTimeout(() => controller.abort(), options.timeoutMs)
    : undefined;
  const fetcher = options?.fetch ?? fetch;

  try {
    const response = await fetcher(url, {
      method,
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });

    const data = (await response.json()) as WecomApiResponse<T>;

    if (data.errcode !== 0) {
      throw new WecomApiError(
        data.errmsg ?? `WeCom API error: ${endpoint}`,
        data.errcode,
        data.errmsg,
      );
    }

    return data;
  } finally {
    if (timeoutId) clearTimeout(timeoutId);
  }
}

/**
 * Send a text message
 */
export async function sendTextMessage(
  accessToken: string,
  params: WecomSendTextParams,
  fetcher?: WecomFetch,
): Promise<WecomApiResponse<{ msgid?: string; invaliduser?: string }>> {
  return callWecomApi("/message/send", accessToken, params, { fetch: fetcher });
}

/**
 * Send an image message
 */
export async function sendImageMessage(
  accessToken: string,
  params: WecomSendImageParams,
  fetcher?: WecomFetch,
): Promise<WecomApiResponse<{ msgid?: string; invaliduser?: string }>> {
  return callWecomApi("/message/send", accessToken, params, { fetch: fetcher });
}

/**
 * Get user info by userid
 */
export async function getUserInfo(
  accessToken: string,
  userid: string,
  fetcher?: WecomFetch,
): Promise<WecomApiResponse<WecomUserInfo>> {
  return callWecomApi(`/user/get?userid=${encodeURIComponent(userid)}`, accessToken, undefined, {
    fetch: fetcher,
    method: "GET",
  });
}

/**
 * Upload temporary media (for sending images, etc.)
 */
export async function uploadMedia(
  accessToken: string,
  type: "image" | "voice" | "video" | "file",
  buffer: Buffer,
  filename: string,
  fetcher?: WecomFetch,
): Promise<WecomApiResponse<{ media_id: string; created_at: string }>> {
  const url = `${WECOM_API_BASE}/media/upload?access_token=${encodeURIComponent(accessToken)}&type=${type}`;
  const fetch_ = fetcher ?? fetch;

  const formData = new FormData();
  const blob = new Blob([buffer]);
  formData.append("media", blob, filename);

  const response = await fetch_(url, {
    method: "POST",
    body: formData,
  });

  const data = (await response.json()) as WecomApiResponse<{ media_id: string; created_at: string }>;

  if (data.errcode !== 0) {
    throw new WecomApiError(
      data.errmsg ?? "Failed to upload media",
      data.errcode,
      data.errmsg,
    );
  }

  return data;
}
