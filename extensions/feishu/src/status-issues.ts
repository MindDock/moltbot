import type { ChannelAccountStatusIssue, ChannelAccountSnapshot, MoltbotConfig } from "clawdbot/plugin-sdk";

import { resolveFeishuAccount } from "./accounts.js";

export function collectFeishuStatusIssues(params: {
  cfg: MoltbotConfig;
  snapshot: ChannelAccountSnapshot;
}): ChannelAccountStatusIssue[] {
  const { cfg, snapshot } = params;
  const issues: ChannelAccountStatusIssue[] = [];
  const account = resolveFeishuAccount({ cfg, accountId: snapshot.accountId });

  if (!account.appId || !account.appSecret) {
    issues.push({
      severity: "error",
      message: "Missing Feishu credentials (appId or appSecret)",
      hint: "Run 'moltbot onboard --channel feishu' to configure",
    });
    return issues;
  }

  if (!account.config.verificationToken) {
    issues.push({
      severity: "error",
      message: "Missing Feishu verification token",
      hint: "Configure verificationToken in channels.feishu config",
    });
  }

  if (!account.config.webhookUrl) {
    issues.push({
      severity: "warning",
      message: "No webhook URL configured",
      hint: "Set webhookUrl in channels.feishu config",
    });
  }

  return issues;
}
