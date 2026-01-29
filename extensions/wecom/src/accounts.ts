import type { MoltbotConfig } from "clawdbot/plugin-sdk";
import { DEFAULT_ACCOUNT_ID, normalizeAccountId } from "clawdbot/plugin-sdk";

import type { ResolvedWecomAccount, WecomAccountConfig, WecomConfig } from "./types.js";
import { resolveWecomCredentials } from "./token.js";

function listConfiguredAccountIds(cfg: MoltbotConfig): string[] {
  const accounts = (cfg.channels?.wecom as WecomConfig | undefined)?.accounts;
  if (!accounts || typeof accounts !== "object") return [];
  return Object.keys(accounts).filter(Boolean);
}

export function listWecomAccountIds(cfg: MoltbotConfig): string[] {
  const ids = listConfiguredAccountIds(cfg);
  if (ids.length === 0) return [DEFAULT_ACCOUNT_ID];
  return ids.sort((a, b) => a.localeCompare(b));
}

export function resolveDefaultWecomAccountId(cfg: MoltbotConfig): string {
  const wecomConfig = cfg.channels?.wecom as WecomConfig | undefined;
  if (wecomConfig?.defaultAccount?.trim()) return wecomConfig.defaultAccount.trim();
  const ids = listWecomAccountIds(cfg);
  if (ids.includes(DEFAULT_ACCOUNT_ID)) return DEFAULT_ACCOUNT_ID;
  return ids[0] ?? DEFAULT_ACCOUNT_ID;
}

function resolveAccountConfig(
  cfg: MoltbotConfig,
  accountId: string,
): WecomAccountConfig | undefined {
  const accounts = (cfg.channels?.wecom as WecomConfig | undefined)?.accounts;
  if (!accounts || typeof accounts !== "object") return undefined;
  return accounts[accountId] as WecomAccountConfig | undefined;
}

function mergeWecomAccountConfig(cfg: MoltbotConfig, accountId: string): WecomAccountConfig {
  const raw = (cfg.channels?.wecom ?? {}) as WecomConfig;
  const { accounts: _ignored, defaultAccount: _ignored2, ...base } = raw;
  const account = resolveAccountConfig(cfg, accountId) ?? {};
  return { ...base, ...account };
}

export function resolveWecomAccount(params: {
  cfg: MoltbotConfig;
  accountId?: string | null;
}): ResolvedWecomAccount {
  const accountId = normalizeAccountId(params.accountId);
  const baseEnabled = (params.cfg.channels?.wecom as WecomConfig | undefined)?.enabled !== false;
  const merged = mergeWecomAccountConfig(params.cfg, accountId);
  const accountEnabled = merged.enabled !== false;
  const enabled = baseEnabled && accountEnabled;
  const credentialResolution = resolveWecomCredentials(
    params.cfg.channels?.wecom as WecomConfig | undefined,
    accountId,
  );

  return {
    accountId,
    name: merged.name?.trim() || undefined,
    enabled,
    corpId: credentialResolution.corpId,
    agentId: credentialResolution.agentId,
    secret: credentialResolution.secret,
    tokenSource: credentialResolution.source,
    config: merged,
  };
}

export function listEnabledWecomAccounts(cfg: MoltbotConfig): ResolvedWecomAccount[] {
  return listWecomAccountIds(cfg)
    .map((accountId) => resolveWecomAccount({ cfg, accountId }))
    .filter((account) => account.enabled);
}

export { type ResolvedWecomAccount };
