import type { ChannelAccountStatusIssue, ChannelAccountSnapshot, MoltbotConfig } from "clawdbot/plugin-sdk";

import { resolveWecomAccount } from "./accounts.js";

export function collectWecomStatusIssues(params: {
  cfg: MoltbotConfig;
  snapshot: ChannelAccountSnapshot;
}): ChannelAccountStatusIssue[] {
  const { cfg, snapshot } = params;
  const issues: ChannelAccountStatusIssue[] = [];
  const account = resolveWecomAccount({ cfg, accountId: snapshot.accountId });

  if (!account.corpId || !account.agentId || !account.secret) {
    issues.push({
      severity: "error",
      message: "Missing WeCom credentials (corpId, agentId, or secret)",
      hint: "Run 'moltbot onboard --channel wecom' to configure",
    });
    return issues;
  }

  if (!account.config.token || !account.config.encodingAesKey) {
    issues.push({
      severity: "error",
      message: "Missing WeCom webhook configuration (token or encodingAesKey)",
      hint: "Configure webhook settings to receive messages",
    });
  }

  if (!account.config.webhookUrl) {
    issues.push({
      severity: "warning",
      message: "No webhook URL configured",
      hint: "Set webhookUrl in channels.wecom config",
    });
  }

  return issues;
}
