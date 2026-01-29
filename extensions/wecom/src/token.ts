import { DEFAULT_ACCOUNT_ID } from "clawdbot/plugin-sdk";

import type { WecomConfig, WecomTokenSource } from "./types.js";

export type WecomCredentialResolution = {
  corpId: string;
  agentId: string;
  secret: string;
  source: WecomTokenSource;
};

export function resolveWecomCredentials(
  config: WecomConfig | undefined,
  accountId?: string | null,
): WecomCredentialResolution {
  const resolvedAccountId = accountId ?? DEFAULT_ACCOUNT_ID;
  const isDefaultAccount = resolvedAccountId === DEFAULT_ACCOUNT_ID;
  const baseConfig = config;
  const accountConfig =
    resolvedAccountId !== DEFAULT_ACCOUNT_ID
      ? (baseConfig?.accounts?.[resolvedAccountId] as WecomConfig | undefined)
      : undefined;

  if (accountConfig) {
    const corpId = accountConfig.corpId?.trim();
    const agentId = accountConfig.agentId?.trim();
    const secret = accountConfig.secret?.trim();
    if (corpId && agentId && secret) {
      return { corpId, agentId, secret, source: "config" };
    }
  }

  if (isDefaultAccount) {
    const corpId = baseConfig?.corpId?.trim();
    const agentId = baseConfig?.agentId?.trim();
    const secret = baseConfig?.secret?.trim();
    if (corpId && agentId && secret) {
      return { corpId, agentId, secret, source: "config" };
    }
    // Check environment variables as fallback
    const envCorpId = process.env.WECOM_CORP_ID?.trim();
    const envAgentId = process.env.WECOM_AGENT_ID?.trim();
    const envSecret = process.env.WECOM_SECRET?.trim();
    if (envCorpId && envAgentId && envSecret) {
      return { corpId: envCorpId, agentId: envAgentId, secret: envSecret, source: "config" };
    }
  }

  return { corpId: "", agentId: "", secret: "", source: "none" };
}
