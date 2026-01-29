import { DEFAULT_ACCOUNT_ID } from "clawdbot/plugin-sdk";

import type { FeishuConfig, FeishuTokenSource } from "./types.js";

export type FeishuCredentialResolution = {
  appId: string;
  appSecret: string;
  source: FeishuTokenSource;
};

export function resolveFeishuCredentials(
  config: FeishuConfig | undefined,
  accountId?: string | null,
): FeishuCredentialResolution {
  const resolvedAccountId = accountId ?? DEFAULT_ACCOUNT_ID;
  const isDefaultAccount = resolvedAccountId === DEFAULT_ACCOUNT_ID;
  const baseConfig = config;
  const accountConfig =
    resolvedAccountId !== DEFAULT_ACCOUNT_ID
      ? (baseConfig?.accounts?.[resolvedAccountId] as FeishuConfig | undefined)
      : undefined;

  if (accountConfig) {
    const appId = accountConfig.appId?.trim();
    const appSecret = accountConfig.appSecret?.trim();
    if (appId && appSecret) {
      return { appId, appSecret, source: "config" };
    }
  }

  if (isDefaultAccount) {
    const appId = baseConfig?.appId?.trim();
    const appSecret = baseConfig?.appSecret?.trim();
    if (appId && appSecret) {
      return { appId, appSecret, source: "config" };
    }
    // Check environment variables as fallback
    const envAppId = process.env.FEISHU_APP_ID?.trim();
    const envAppSecret = process.env.FEISHU_APP_SECRET?.trim();
    if (envAppId && envAppSecret) {
      return { appId: envAppId, appSecret: envAppSecret, source: "config" };
    }
  }

  return { appId: "", appSecret: "", source: "none" };
}
