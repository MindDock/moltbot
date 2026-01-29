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

import { listFeishuAccountIds, resolveDefaultFeishuAccountId, resolveFeishuAccount, type ResolvedFeishuAccount } from "./accounts.js";
import { FeishuConfigSchema } from "./config-schema.js";
import { feishuOnboardingAdapter } from "./onboarding.js";
import { probeFeishu } from "./probe.js";
import { sendMessageFeishu } from "./send.js";
import { collectFeishuStatusIssues } from "./status-issues.js";

const meta = {
  id: "feishu",
  label: "Feishu",
  selectionLabel: "Feishu (Lark / 飞书)",
  docsPath: "/channels/feishu",
  docsLabel: "feishu",
  blurb: "ByteDance enterprise collaboration platform for China market.",
  aliases: ["lark", "fs"],
  order: 86,
  quickstartAllowFrom: true,
};

function normalizeFeishuMessagingTarget(raw: string): string | undefined {
  const trimmed = raw?.trim();
  if (!trimmed) return undefined;
  return trimmed.replace(/^(feishu|lark|fs):/i, "");
}

export const feishuDock: ChannelDock = {
  id: "feishu",
  capabilities: {
    chatTypes: ["direct", "group"],
    media: true,
    blockStreaming: true,
  },
  outbound: { textChunkLimit: 4096 },
  config: {
    resolveAllowFrom: ({ cfg, accountId }) =>
      (resolveFeishuAccount({ cfg: cfg as MoltbotConfig, accountId }).config.allowFrom ?? []).map(
        (entry) => String(entry),
      ),
    formatAllowFrom: ({ allowFrom }) =>
      allowFrom
        .map((entry) => String(entry).trim())
        .filter(Boolean)
        .map((entry) => entry.replace(/^(feishu|lark|fs):/i, ""))
        .map((entry) => entry.toLowerCase()),
  },
  groups: {
    resolveRequireMention: () => true,
  },
  threading: {
    resolveReplyToMode: () => "off",
  },
};

export const feishuPlugin: ChannelPlugin<ResolvedFeishuAccount> = {
  id: "feishu",
  meta,
  onboarding: feishuOnboardingAdapter,
  capabilities: {
    chatTypes: ["direct", "group"],
    media: true,
    reactions: false,
    threads: false,
    polls: false,
    nativeCommands: false,
    blockStreaming: true,
  },
  reload: { configPrefixes: ["channels.feishu"] },
  configSchema: buildChannelConfigSchema(FeishuConfigSchema),
  config: {
    listAccountIds: (cfg) => listFeishuAccountIds(cfg as MoltbotConfig),
    resolveAccount: (cfg, accountId) => resolveFeishuAccount({ cfg: cfg as MoltbotConfig, accountId }),
    defaultAccountId: (cfg) => resolveDefaultFeishuAccountId(cfg as MoltbotConfig),
    setAccountEnabled: ({ cfg, accountId, enabled }) =>
      setAccountEnabledInConfigSection({
        cfg: cfg as MoltbotConfig,
        sectionKey: "feishu",
        accountId,
        enabled,
        allowTopLevel: true,
      }),
    deleteAccount: ({ cfg, accountId }) =>
      deleteAccountFromConfigSection({
        cfg: cfg as MoltbotConfig,
        sectionKey: "feishu",
        accountId,
        clearBaseFields: ["appId", "appSecret", "verificationToken", "encryptKey", "name"],
      }),
    isConfigured: (account) => Boolean(account.appId?.trim() && account.appSecret?.trim()),
    describeAccount: (account): ChannelAccountSnapshot => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: Boolean(account.appId?.trim() && account.appSecret?.trim()),
      tokenSource: account.tokenSource,
    }),
    resolveAllowFrom: ({ cfg, accountId }) =>
      (resolveFeishuAccount({ cfg: cfg as MoltbotConfig, accountId }).config.allowFrom ?? []).map(
        (entry) => String(entry),
      ),
    formatAllowFrom: ({ allowFrom }) =>
      allowFrom
        .map((entry) => String(entry).trim())
        .filter(Boolean)
        .map((entry) => entry.replace(/^(feishu|lark|fs):/i, ""))
        .map((entry) => entry.toLowerCase()),
  },
  security: {
    resolveDmPolicy: ({ cfg, accountId, account }) => {
      const resolvedAccountId = accountId ?? account.accountId ?? DEFAULT_ACCOUNT_ID;
      const useAccountPath = Boolean(
        (cfg as MoltbotConfig).channels?.feishu?.accounts?.[resolvedAccountId],
      );
      const basePath = useAccountPath
        ? `channels.feishu.accounts.${resolvedAccountId}.`
        : "channels.feishu.";
      return {
        policy: account.config.dmPolicy ?? "pairing",
        allowFrom: account.config.allowFrom ?? [],
        policyPath: `${basePath}dmPolicy`,
        allowFromPath: basePath,
        approveHint: formatPairingApproveHint("feishu"),
        normalizeEntry: (raw) => raw.replace(/^(feishu|lark|fs):/i, ""),
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
    normalizeTarget: normalizeFeishuMessagingTarget,
    targetResolver: {
      looksLikeId: (raw) => {
        const trimmed = raw.trim();
        if (!trimmed) return false;
        // Feishu IDs typically start with ou_ (open_id), on_ (union_id), or are alphanumeric
        return /^(ou_|on_|[a-zA-Z0-9_-]+)/.test(trimmed);
      },
      hint: "<open_id|user_id|chat_id>",
    },
  },
  directory: {
    self: async () => null,
    listPeers: async ({ cfg, accountId, query, limit }) => {
      const account = resolveFeishuAccount({ cfg: cfg as MoltbotConfig, accountId });
      const q = query?.trim().toLowerCase() || "";
      const peers = Array.from(
        new Set(
          (account.config.allowFrom ?? [])
            .map((entry) => String(entry).trim())
            .filter((entry) => Boolean(entry) && entry !== "*")
            .map((entry) => entry.replace(/^(feishu|lark|fs):/i, "")),
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
        channelKey: "feishu",
        accountId,
        name,
      }),
    validateInput: ({ accountId, input }) => {
      if (!input.appId && !input.appSecret) {
        return "Feishu requires appId and appSecret.";
      }
      return null;
    },
    applyAccountConfig: ({ cfg, accountId, input }) => {
      const namedConfig = applyAccountNameToChannelSection({
        cfg: cfg as MoltbotConfig,
        channelKey: "feishu",
        accountId,
        name: input.name,
      });
      const next =
        accountId !== DEFAULT_ACCOUNT_ID
          ? migrateBaseNameToDefaultAccount({
              cfg: namedConfig,
              channelKey: "feishu",
            })
          : namedConfig;
      if (accountId === DEFAULT_ACCOUNT_ID) {
        return {
          ...next,
          channels: {
            ...next.channels,
            feishu: {
              ...next.channels?.feishu,
              enabled: true,
              ...(input.appId ? { appId: input.appId } : {}),
              ...(input.appSecret ? { appSecret: input.appSecret } : {}),
            },
          },
        } as MoltbotConfig;
      }
      return {
        ...next,
        channels: {
          ...next.channels,
          feishu: {
            ...next.channels?.feishu,
            enabled: true,
            accounts: {
              ...(next.channels?.feishu?.accounts ?? {}),
              [accountId]: {
                ...(next.channels?.feishu?.accounts?.[accountId] ?? {}),
                enabled: true,
                ...(input.appId ? { appId: input.appId } : {}),
                ...(input.appSecret ? { appSecret: input.appSecret } : {}),
              },
            },
          },
        },
      } as MoltbotConfig;
    },
  },
  pairing: {
    idLabel: "feishuOpenId",
    normalizeAllowEntry: (entry) => entry.replace(/^(feishu|lark|fs):/i, ""),
    notifyApproval: async ({ cfg, id }) => {
      const account = resolveFeishuAccount({ cfg: cfg as MoltbotConfig });
      if (!account.appId || !account.appSecret) throw new Error("Feishu credentials not configured");
      await sendMessageFeishu(id, PAIRING_APPROVED_MESSAGE, {
        appId: account.appId,
        appSecret: account.appSecret,
        receiveIdType: account.config.receiveIdType || "open_id",
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
    textChunkLimit: 4096,
    sendText: async ({ to, text, accountId, cfg }) => {
      const result = await sendMessageFeishu(to, text, {
        accountId: accountId ?? undefined,
        cfg: cfg as MoltbotConfig,
      });
      return {
        channel: "feishu",
        ok: result.ok,
        messageId: result.messageId ?? "",
        error: result.error ? new Error(result.error) : undefined,
      };
    },
    sendMedia: async ({ to, text, mediaUrl, accountId, cfg }) => {
      // TODO: Implement media upload and send
      const result = await sendMessageFeishu(to, text || "[Media not supported yet]", {
        accountId: accountId ?? undefined,
        cfg: cfg as MoltbotConfig,
      });
      return {
        channel: "feishu",
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
    collectStatusIssues: collectFeishuStatusIssues,
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
      probeFeishu(account.appId, account.appSecret, timeoutMs),
    buildAccountSnapshot: ({ account, runtime }) => {
      const configured = Boolean(account.appId?.trim() && account.appSecret?.trim());
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
      const appId = account.appId.trim();
      const appSecret = account.appSecret.trim();
      const verificationToken = account.config.verificationToken?.trim();
      const encryptKey = account.config.encryptKey?.trim();

      let botLabel = "";
      ctx.log?.info(`[${account.accountId}] starting Feishu provider`);

      try {
        const probe = await probeFeishu(appId, appSecret, 2500);
        if (probe.ok && probe.bot) {
          botLabel = ` (${probe.bot.name})`;
        }
        ctx.setStatus({
          accountId: account.accountId,
          bot: probe.bot,
        });
      } catch {
        // ignore probe errors
      }

      if (botLabel) {
        ctx.log?.info(`[${account.accountId}] Feishu bot${botLabel}`);
      }

      const { monitorFeishuProvider } = await import("./monitor.js");
      return monitorFeishuProvider({
        appId,
        appSecret,
        account,
        config: ctx.cfg as MoltbotConfig,
        runtime: ctx.runtime,
        abortSignal: ctx.abortSignal,
        verificationToken,
        encryptKey,
        webhookUrl: account.config.webhookUrl,
        webhookPath: account.config.webhookPath,
        statusSink: (patch) => ctx.setStatus({ accountId: ctx.accountId, ...patch }),
      });
    },
  },
};
