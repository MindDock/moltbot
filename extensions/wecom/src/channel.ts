import type {
  ChannelAccountSnapshot,
  ChannelDock,
  ChannelPlugin,
  MoltbotConfig,
} from "clawdbot/plugin-sdk";
import {
  applyAccountNameToChannelSection,
  buildChannelConfigSchema,
  DEFAULT_ACCOUNT_ID,
  deleteAccountFromConfigSection,
  formatPairingApproveHint,
  migrateBaseNameToDefaultAccount,
  normalizeAccountId,
  PAIRING_APPROVED_MESSAGE,
  setAccountEnabledInConfigSection,
} from "clawdbot/plugin-sdk";

import { listWecomAccountIds, resolveDefaultWecomAccountId, resolveWecomAccount, type ResolvedWecomAccount } from "./accounts.js";
import { WecomConfigSchema } from "./config-schema.js";
import { wecomOnboardingAdapter } from "./onboarding.js";
import { probeWecom } from "./probe.js";
import { sendMessageWecom } from "./send.js";
import { collectWecomStatusIssues } from "./status-issues.js";

const meta = {
  id: "wecom",
  label: "WeCom",
  selectionLabel: "WeCom (WeChat Work)",
  docsPath: "/channels/wecom",
  docsLabel: "wecom",
  blurb: "Enterprise messaging platform for China market.",
  aliases: ["wechat-work", "wxwork"],
  order: 85,
  quickstartAllowFrom: true,
};

function normalizeWecomMessagingTarget(raw: string): string | undefined {
  const trimmed = raw?.trim();
  if (!trimmed) return undefined;
  return trimmed.replace(/^(wecom|wxwork):/i, "");
}

export const wecomDock: ChannelDock = {
  id: "wecom",
  capabilities: {
    chatTypes: ["direct"],
    media: true,
    blockStreaming: true,
  },
  outbound: { textChunkLimit: 2048 },
  config: {
    resolveAllowFrom: ({ cfg, accountId }) =>
      (resolveWecomAccount({ cfg: cfg as MoltbotConfig, accountId }).config.allowFrom ?? []).map(
        (entry) => String(entry),
      ),
    formatAllowFrom: ({ allowFrom }) =>
      allowFrom
        .map((entry) => String(entry).trim())
        .filter(Boolean)
        .map((entry) => entry.replace(/^(wecom|wxwork):/i, ""))
        .map((entry) => entry.toLowerCase()),
  },
  groups: {
    resolveRequireMention: () => true,
  },
  threading: {
    resolveReplyToMode: () => "off",
  },
};

export const wecomPlugin: ChannelPlugin<ResolvedWecomAccount> = {
  id: "wecom",
  meta,
  onboarding: wecomOnboardingAdapter,
  capabilities: {
    chatTypes: ["direct"],
    media: true,
    reactions: false,
    threads: false,
    polls: false,
    nativeCommands: false,
    blockStreaming: true,
  },
  reload: { configPrefixes: ["channels.wecom"] },
  configSchema: buildChannelConfigSchema(WecomConfigSchema),
  config: {
    listAccountIds: (cfg) => listWecomAccountIds(cfg as MoltbotConfig),
    resolveAccount: (cfg, accountId) => resolveWecomAccount({ cfg: cfg as MoltbotConfig, accountId }),
    defaultAccountId: (cfg) => resolveDefaultWecomAccountId(cfg as MoltbotConfig),
    setAccountEnabled: ({ cfg, accountId, enabled }) =>
      setAccountEnabledInConfigSection({
        cfg: cfg as MoltbotConfig,
        sectionKey: "wecom",
        accountId,
        enabled,
        allowTopLevel: true,
      }),
    deleteAccount: ({ cfg, accountId }) =>
      deleteAccountFromConfigSection({
        cfg: cfg as MoltbotConfig,
        sectionKey: "wecom",
        accountId,
        clearBaseFields: ["corpId", "agentId", "secret", "token", "encodingAesKey", "name"],
      }),
    isConfigured: (account) => Boolean(account.corpId?.trim() && account.agentId?.trim() && account.secret?.trim()),
    describeAccount: (account): ChannelAccountSnapshot => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: Boolean(account.corpId?.trim() && account.agentId?.trim() && account.secret?.trim()),
      tokenSource: account.tokenSource,
    }),
    resolveAllowFrom: ({ cfg, accountId }) =>
      (resolveWecomAccount({ cfg: cfg as MoltbotConfig, accountId }).config.allowFrom ?? []).map(
        (entry) => String(entry),
      ),
    formatAllowFrom: ({ allowFrom }) =>
      allowFrom
        .map((entry) => String(entry).trim())
        .filter(Boolean)
        .map((entry) => entry.replace(/^(wecom|wxwork):/i, ""))
        .map((entry) => entry.toLowerCase()),
  },
  security: {
    resolveDmPolicy: ({ cfg, accountId, account }) => {
      const resolvedAccountId = accountId ?? account.accountId ?? DEFAULT_ACCOUNT_ID;
      const useAccountPath = Boolean(
        (cfg as MoltbotConfig).channels?.wecom?.accounts?.[resolvedAccountId],
      );
      const basePath = useAccountPath
        ? `channels.wecom.accounts.${resolvedAccountId}.`
        : "channels.wecom.";
      return {
        policy: account.config.dmPolicy ?? "pairing",
        allowFrom: account.config.allowFrom ?? [],
        policyPath: `${basePath}dmPolicy`,
        allowFromPath: basePath,
        approveHint: formatPairingApproveHint("wecom"),
        normalizeEntry: (raw) => raw.replace(/^(wecom|wxwork):/i, ""),
      };
    },
  },
  groups: {
    resolveRequireMention: () => true,
  },
  threading: {
    resolveReplyToMode: () => "off",
  },
  messaging: {
    normalizeTarget: normalizeWecomMessagingTarget,
    targetResolver: {
      looksLikeId: (raw) => {
        const trimmed = raw.trim();
        if (!trimmed) return false;
        // WeCom user IDs are typically alphanumeric
        return /^[a-zA-Z0-9_-]+$/.test(trimmed);
      },
      hint: "<userId>",
    },
  },
  directory: {
    self: async () => null,
    listPeers: async ({ cfg, accountId, query, limit }) => {
      const account = resolveWecomAccount({ cfg: cfg as MoltbotConfig, accountId });
      const q = query?.trim().toLowerCase() || "";
      const peers = Array.from(
        new Set(
          (account.config.allowFrom ?? [])
            .map((entry) => String(entry).trim())
            .filter((entry) => Boolean(entry) && entry !== "*")
            .map((entry) => entry.replace(/^(wecom|wxwork):/i, "")),
        ),
      )
        .filter((id) => (q ? id.toLowerCase().includes(q) : true))
        .slice(0, limit && limit > 0 ? limit : undefined)
        .map((id) => ({ kind: "user", id }) as const);
      return peers;
    },
    listGroups: async () => [],
  },
  setup: {
    resolveAccountId: ({ accountId }) => normalizeAccountId(accountId),
    applyAccountName: ({ cfg, accountId, name }) =>
      applyAccountNameToChannelSection({
        cfg: cfg as MoltbotConfig,
        channelKey: "wecom",
        accountId,
        name,
      }),
    validateInput: ({ accountId, input }) => {
      if (!input.corpId && !input.agentId && !input.secret) {
        return "WeCom requires corpId, agentId, and secret.";
      }
      return null;
    },
    applyAccountConfig: ({ cfg, accountId, input }) => {
      const namedConfig = applyAccountNameToChannelSection({
        cfg: cfg as MoltbotConfig,
        channelKey: "wecom",
        accountId,
        name: input.name,
      });
      const next =
        accountId !== DEFAULT_ACCOUNT_ID
          ? migrateBaseNameToDefaultAccount({
              cfg: namedConfig,
              channelKey: "wecom",
            })
          : namedConfig;
      if (accountId === DEFAULT_ACCOUNT_ID) {
        return {
          ...next,
          channels: {
            ...next.channels,
            wecom: {
              ...next.channels?.wecom,
              enabled: true,
              ...(input.corpId ? { corpId: input.corpId } : {}),
              ...(input.agentId ? { agentId: input.agentId } : {}),
              ...(input.secret ? { secret: input.secret } : {}),
            },
          },
        } as MoltbotConfig;
      }
      return {
        ...next,
        channels: {
          ...next.channels,
          wecom: {
            ...next.channels?.wecom,
            enabled: true,
            accounts: {
              ...(next.channels?.wecom?.accounts ?? {}),
              [accountId]: {
                ...(next.channels?.wecom?.accounts?.[accountId] ?? {}),
                enabled: true,
                ...(input.corpId ? { corpId: input.corpId } : {}),
                ...(input.agentId ? { agentId: input.agentId } : {}),
                ...(input.secret ? { secret: input.secret } : {}),
              },
            },
          },
        },
      } as MoltbotConfig;
    },
  },
  pairing: {
    idLabel: "wecomUserId",
    normalizeAllowEntry: (entry) => entry.replace(/^(wecom|wxwork):/i, ""),
    notifyApproval: async ({ cfg, id }) => {
      const account = resolveWecomAccount({ cfg: cfg as MoltbotConfig });
      if (!account.corpId || !account.secret) throw new Error("WeCom credentials not configured");
      await sendMessageWecom(id, PAIRING_APPROVED_MESSAGE, {
        corpId: account.corpId,
        agentId: account.agentId,
        secret: account.secret,
      });
    },
  },
  outbound: {
    deliveryMode: "direct",
    chunker: (text, limit) => {
      if (!text) return [];
      if (limit <= 0 || text.length <= limit) return [text];
      const chunks: string[] = [];
      let remaining = text;
      while (remaining.length > limit) {
        const window = remaining.slice(0, limit);
        const lastNewline = window.lastIndexOf("\n");
        const lastSpace = window.lastIndexOf(" ");
        let breakIdx = lastNewline > 0 ? lastNewline : lastSpace;
        if (breakIdx <= 0) breakIdx = limit;
        const rawChunk = remaining.slice(0, breakIdx);
        const chunk = rawChunk.trimEnd();
        if (chunk.length > 0) chunks.push(chunk);
        const brokeOnSeparator = breakIdx < remaining.length && /\s/.test(remaining[breakIdx]);
        const nextStart = Math.min(remaining.length, breakIdx + (brokeOnSeparator ? 1 : 0));
        remaining = remaining.slice(nextStart).trimStart();
      }
      if (remaining.length) chunks.push(remaining);
      return chunks;
    },
    chunkerMode: "text",
    textChunkLimit: 2048,
    sendText: async ({ to, text, accountId, cfg }) => {
      const result = await sendMessageWecom(to, text, {
        accountId: accountId ?? undefined,
        cfg: cfg as MoltbotConfig,
      });
      return {
        channel: "wecom",
        ok: result.ok,
        messageId: result.messageId ?? "",
        error: result.error ? new Error(result.error) : undefined,
      };
    },
    sendMedia: async ({ to, text, mediaUrl, accountId, cfg }) => {
      // TODO: Implement media upload and send
      const result = await sendMessageWecom(to, text || "[Media not supported yet]", {
        accountId: accountId ?? undefined,
        cfg: cfg as MoltbotConfig,
      });
      return {
        channel: "wecom",
        ok: result.ok,
        messageId: result.messageId ?? "",
        error: result.error ? new Error(result.error) : undefined,
      };
    },
  },
  status: {
    defaultRuntime: {
      accountId: DEFAULT_ACCOUNT_ID,
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
    },
    collectStatusIssues: collectWecomStatusIssues,
    buildChannelSummary: ({ snapshot }) => ({
      configured: snapshot.configured ?? false,
      tokenSource: snapshot.tokenSource ?? "none",
      running: snapshot.running ?? false,
      mode: snapshot.mode ?? null,
      lastStartAt: snapshot.lastStartAt ?? null,
      lastStopAt: snapshot.lastStopAt ?? null,
      lastError: snapshot.lastError ?? null,
      probe: snapshot.probe,
      lastProbeAt: snapshot.lastProbeAt ?? null,
    }),
    probeAccount: async ({ account, timeoutMs }) =>
      probeWecom(account.corpId, account.secret, timeoutMs),
    buildAccountSnapshot: ({ account, runtime }) => {
      const configured = Boolean(account.corpId?.trim() && account.agentId?.trim() && account.secret?.trim());
      return {
        accountId: account.accountId,
        name: account.name,
        enabled: account.enabled,
        configured,
        tokenSource: account.tokenSource,
        running: runtime?.running ?? false,
        lastStartAt: runtime?.lastStartAt ?? null,
        lastStopAt: runtime?.lastStopAt ?? null,
        lastError: runtime?.lastError ?? null,
        mode: account.config.webhookUrl ? "webhook" : "none",
        lastInboundAt: runtime?.lastInboundAt ?? null,
        lastOutboundAt: runtime?.lastOutboundAt ?? null,
        dmPolicy: account.config.dmPolicy ?? "pairing",
      };
    },
  },
  gateway: {
    startAccount: async (ctx) => {
      const account = ctx.account;
      const corpId = account.corpId.trim();
      const agentId = account.agentId.trim();
      const secret = account.secret.trim();
      const token = account.config.token?.trim();
      const encodingAesKey = account.config.encodingAesKey?.trim();

      ctx.log?.info(`[${account.accountId}] starting WeCom provider`);

      try {
        const probe = await probeWecom(corpId, secret, 2500);
        ctx.setStatus({
          accountId: account.accountId,
          probeOk: probe.ok,
        });
      } catch {
        // ignore probe errors
      }

      const { monitorWecomProvider } = await import("./monitor.js");
      return monitorWecomProvider({
        corpId,
        agentId,
        secret,
        account,
        config: ctx.cfg as MoltbotConfig,
        runtime: ctx.runtime,
        abortSignal: ctx.abortSignal,
        token,
        encodingAesKey,
        webhookUrl: account.config.webhookUrl,
        webhookPath: account.config.webhookPath,
        statusSink: (patch) => ctx.setStatus({ accountId: ctx.accountId, ...patch }),
      });
    },
  },
};
