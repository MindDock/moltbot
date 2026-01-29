import type { IncomingMessage, ServerResponse } from "node:http";

import type { MoltbotConfig, MarkdownTableMode } from "clawdbot/plugin-sdk";

import type { ResolvedFeishuAccount } from "./accounts.js";
import {
  getTenantAccessToken,
  sendTextMessage,
  FeishuApiError,
  type FeishuFetch,
  type FeishuMessageEvent,
  type FeishuUrlVerificationEvent,
} from "./api.js";
import { decryptEvent } from "./crypto.js";
import { getFeishuRuntime } from "./runtime.js";

export type FeishuRuntimeEnv = {
  log?: (message: string) => void;
  error?: (message: string) => void;
};

export type FeishuMonitorOptions = {
  appId: string;
  appSecret: string;
  account: ResolvedFeishuAccount;
  config: MoltbotConfig;
  runtime: FeishuRuntimeEnv;
  abortSignal: AbortSignal;
  verificationToken?: string;
  encryptKey?: string;
  webhookUrl?: string;
  webhookPath?: string;
  fetcher?: FeishuFetch;
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void;
};

export type FeishuMonitorResult = {
  stop: () => void;
};

const FEISHU_TEXT_LIMIT = 4096;
const DEFAULT_MEDIA_MAX_MB = 5;

type FeishuCoreRuntime = ReturnType<typeof getFeishuRuntime>;

function logVerbose(core: FeishuCoreRuntime, runtime: FeishuRuntimeEnv, message: string): void {
  if (core.logging.shouldLogVerbose()) {
    runtime.log?.(`[feishu] ${message}`);
  }
}

function isSenderAllowed(senderId: string, allowFrom: string[]): boolean {
  if (allowFrom.includes("*")) return true;
  const normalizedSenderId = senderId.toLowerCase();
  return allowFrom.some((entry) => {
    const normalized = entry.toLowerCase().replace(/^(feishu|lark|fs):/i, "");
    return normalized === normalizedSenderId;
  });
}

async function readBody(req: IncomingMessage, maxBytes: number): Promise<{ ok: boolean; data?: string; error?: string }> {
  const chunks: Buffer[] = [];
  let total = 0;
  return await new Promise((resolve) => {
    req.on("data", (chunk: Buffer) => {
      total += chunk.length;
      if (total > maxBytes) {
        resolve({ ok: false, error: "payload too large" });
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      resolve({ ok: true, data: Buffer.concat(chunks).toString("utf8") });
    });
    req.on("error", (err) => {
      resolve({ ok: false, error: err instanceof Error ? err.message : String(err) });
    });
  });
}

type WebhookTarget = {
  appId: string;
  appSecret: string;
  account: ResolvedFeishuAccount;
  config: MoltbotConfig;
  runtime: FeishuRuntimeEnv;
  core: FeishuCoreRuntime;
  verificationToken: string;
  encryptKey?: string;
  path: string;
  mediaMaxMb: number;
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void;
  fetcher?: FeishuFetch;
};

const webhookTargets = new Map<string, WebhookTarget[]>();

function normalizeWebhookPath(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return "/";
  const withSlash = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  if (withSlash.length > 1 && withSlash.endsWith("/")) {
    return withSlash.slice(0, -1);
  }
  return withSlash;
}

function resolveWebhookPath(webhookPath?: string, webhookUrl?: string): string | null {
  const trimmedPath = webhookPath?.trim();
  if (trimmedPath) return normalizeWebhookPath(trimmedPath);
  if (webhookUrl?.trim()) {
    try {
      const parsed = new URL(webhookUrl);
      return normalizeWebhookPath(parsed.pathname || "/");
    } catch {
      return null;
    }
  }
  return null;
}

export function registerFeishuWebhookTarget(target: WebhookTarget): () => void {
  const key = normalizeWebhookPath(target.path);
  const normalizedTarget = { ...target, path: key };
  const existing = webhookTargets.get(key) ?? [];
  const next = [...existing, normalizedTarget];
  webhookTargets.set(key, next);
  return () => {
    const updated = (webhookTargets.get(key) ?? []).filter(
      (entry) => entry !== normalizedTarget,
    );
    if (updated.length > 0) {
      webhookTargets.set(key, updated);
    } else {
      webhookTargets.delete(key);
    }
  };
}

export async function handleFeishuWebhookRequest(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<boolean> {
  const url = new URL(req.url ?? "/", "http://localhost");
  const path = normalizeWebhookPath(url.pathname);
  const targets = webhookTargets.get(path);
  if (!targets || targets.length === 0) return false;

  if (req.method !== "POST") {
    res.statusCode = 405;
    res.setHeader("Allow", "POST");
    res.end("Method Not Allowed");
    return true;
  }

  const body = await readBody(req, 1024 * 1024);
  if (!body.ok || !body.data) {
    res.statusCode = body.error === "payload too large" ? 413 : 400;
    res.end(body.error ?? "invalid payload");
    return true;
  }

  let eventData: Record<string, unknown>;
  try {
    eventData = JSON.parse(body.data) as Record<string, unknown>;
  } catch {
    res.statusCode = 400;
    res.end("invalid JSON");
    return true;
  }

  // Handle URL verification challenge
  if (eventData.type === "url_verification") {
    const verificationEvent = eventData as unknown as FeishuUrlVerificationEvent;
    // Find matching target by verification token
    const target = targets.find((t) => t.verificationToken === verificationEvent.token);
    if (target) {
      res.statusCode = 200;
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ challenge: verificationEvent.challenge }));
      return true;
    }
    res.statusCode = 401;
    res.end("verification failed");
    return true;
  }

  // Handle encrypted events
  let decryptedData = eventData;
  if (eventData.encrypt && typeof eventData.encrypt === "string") {
    let matchedTarget: WebhookTarget | undefined;
    for (const target of targets) {
      if (target.encryptKey) {
        try {
          const decrypted = decryptEvent(eventData.encrypt as string, target.encryptKey);
          decryptedData = JSON.parse(decrypted) as Record<string, unknown>;
          matchedTarget = target;
          break;
        } catch {
          // Try next target
        }
      }
    }
    if (!matchedTarget) {
      res.statusCode = 401;
      res.end("decryption failed");
      return true;
    }
  }

  // Handle v2 events (schema "2.0")
  const schema = decryptedData.schema as string | undefined;
  const header = decryptedData.header as Record<string, unknown> | undefined;

  if (schema === "2.0" && header?.event_type === "im.message.receive_v1") {
    // Find matching target by verification token in header
    const headerToken = header.token as string | undefined;
    const target = targets.find((t) => t.verificationToken === headerToken);

    if (!target) {
      res.statusCode = 401;
      res.end("unauthorized");
      return true;
    }

    target.statusSink?.({ lastInboundAt: Date.now() });
    processMessageEvent(
      decryptedData as unknown as FeishuMessageEvent,
      target.appId,
      target.appSecret,
      target.account,
      target.config,
      target.runtime,
      target.core,
      target.mediaMaxMb,
      target.statusSink,
      target.fetcher,
    ).catch((err) => {
      target.runtime.error?.(`[${target.account.accountId}] Feishu webhook failed: ${String(err)}`);
    });

    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.end("{}");
    return true;
  }

  // Unknown event type
  res.statusCode = 200;
  res.end("ok");
  return true;
}

async function processMessageEvent(
  event: FeishuMessageEvent,
  appId: string,
  appSecret: string,
  account: ResolvedFeishuAccount,
  config: MoltbotConfig,
  runtime: FeishuRuntimeEnv,
  core: FeishuCoreRuntime,
  mediaMaxMb: number,
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void,
  fetcher?: FeishuFetch,
): Promise<void> {
  const { message, sender } = event.event;

  // Only handle text messages for now
  if (message.message_type !== "text") {
    return;
  }

  // Parse text content
  let text = "";
  try {
    const content = JSON.parse(message.content) as { text?: string };
    text = content.text?.trim() ?? "";
  } catch {
    return;
  }

  if (!text) return;

  const senderId = sender.sender_id.open_id ?? sender.sender_id.user_id ?? sender.sender_id.union_id ?? "";
  const chatId = message.chat_id;
  const isGroup = message.chat_type === "group";

  const dmPolicy = account.config.dmPolicy ?? "pairing";
  const configAllowFrom = account.config.allowFrom ?? [];
  const shouldComputeAuth = core.channel.commands.shouldComputeCommandAuthorized(text, config);
  const storeAllowFrom =
    !isGroup && (dmPolicy !== "open" || shouldComputeAuth)
      ? await core.channel.pairing.readAllowFromStore("feishu").catch(() => [])
      : [];
  const effectiveAllowFrom = [...configAllowFrom, ...storeAllowFrom];
  const useAccessGroups = config.commands?.useAccessGroups !== false;
  const senderAllowedForCommands = isSenderAllowed(senderId, effectiveAllowFrom);
  const commandAuthorized = shouldComputeAuth
    ? core.channel.commands.resolveCommandAuthorizedFromAuthorizers({
        useAccessGroups,
        authorizers: [{ configured: effectiveAllowFrom.length > 0, allowed: senderAllowedForCommands }],
      })
    : undefined;

  if (!isGroup) {
    if (dmPolicy === "disabled") {
      logVerbose(core, runtime, `Blocked feishu DM from ${senderId} (dmPolicy=disabled)`);
      return;
    }

    if (dmPolicy !== "open") {
      const allowed = senderAllowedForCommands;

      if (!allowed) {
        if (dmPolicy === "pairing") {
          const { code, created } = await core.channel.pairing.upsertPairingRequest({
            channel: "feishu",
            id: senderId,
            meta: {},
          });

          if (created) {
            logVerbose(core, runtime, `feishu pairing request sender=${senderId}`);
            try {
              const accessToken = await getTenantAccessToken(appId, appSecret, fetcher);
              const receiveIdType = account.config.receiveIdType || "open_id";
              await sendTextMessage(
                accessToken,
                receiveIdType,
                senderId,
                core.channel.pairing.buildPairingReply({
                  channel: "feishu",
                  idLine: `Your Feishu open_id: ${senderId}`,
                  code,
                }),
                fetcher,
              );
              statusSink?.({ lastOutboundAt: Date.now() });
            } catch (err) {
              logVerbose(
                core,
                runtime,
                `feishu pairing reply failed for ${senderId}: ${String(err)}`,
              );
            }
          }
        } else {
          logVerbose(
            core,
            runtime,
            `Blocked unauthorized feishu sender ${senderId} (dmPolicy=${dmPolicy})`,
          );
        }
        return;
      }
    }
  }

  const route = core.channel.routing.resolveAgentRoute({
    cfg: config,
    channel: "feishu",
    accountId: account.accountId,
    peer: {
      kind: isGroup ? "group" : "dm",
      id: chatId,
    },
  });

  if (
    isGroup &&
    core.channel.commands.isControlCommandMessage(text, config) &&
    commandAuthorized !== true
  ) {
    logVerbose(core, runtime, `feishu: drop control command from unauthorized sender ${senderId}`);
    return;
  }

  const fromLabel = isGroup ? `group:${chatId}` : `user:${senderId}`;
  const storePath = core.channel.session.resolveStorePath(config.session?.store, {
    agentId: route.agentId,
  });
  const envelopeOptions = core.channel.reply.resolveEnvelopeFormatOptions(config);
  const previousTimestamp = core.channel.session.readSessionUpdatedAt({
    storePath,
    sessionKey: route.sessionKey,
  });
  const msgTimestamp = message.create_time ? Number.parseInt(message.create_time, 10) : undefined;
  const body = core.channel.reply.formatAgentEnvelope({
    channel: "Feishu",
    from: fromLabel,
    timestamp: msgTimestamp,
    previousTimestamp,
    envelope: envelopeOptions,
    body: text,
  });

  const ctxPayload = core.channel.reply.finalizeInboundContext({
    Body: body,
    RawBody: text,
    CommandBody: text,
    From: isGroup ? `feishu:group:${chatId}` : `feishu:${senderId}`,
    To: `feishu:${chatId}`,
    SessionKey: route.sessionKey,
    AccountId: route.accountId,
    ChatType: isGroup ? "group" : "direct",
    ConversationLabel: fromLabel,
    SenderName: undefined,
    SenderId: senderId,
    CommandAuthorized: commandAuthorized,
    Provider: "feishu",
    Surface: "feishu",
    MessageSid: message.message_id,
    OriginatingChannel: "feishu",
    OriginatingTo: `feishu:${chatId}`,
  });

  await core.channel.session.recordInboundSession({
    storePath,
    sessionKey: ctxPayload.SessionKey ?? route.sessionKey,
    ctx: ctxPayload,
    onRecordError: (err) => {
      runtime.error?.(`feishu: failed updating session meta: ${String(err)}`);
    },
  });

  // Send "thinking" indicator before processing
  const thinkingMessage = account.config.thinkingMessage ?? "🤔 正在思考中，请稍候...";
  if (thinkingMessage) {
    try {
      const accessToken = await getTenantAccessToken(appId, appSecret, fetcher);
      const replyToId = isGroup ? chatId : senderId;
      const replyIdType = isGroup ? "chat_id" : (account.config.receiveIdType || "open_id");
      await sendTextMessage(accessToken, replyIdType, replyToId, thinkingMessage, fetcher);
      statusSink?.({ lastOutboundAt: Date.now() });
    } catch (err) {
      logVerbose(core, runtime, `feishu: thinking message failed: ${String(err)}`);
    }
  }

  const tableMode = core.channel.text.resolveMarkdownTableMode({
    cfg: config,
    channel: "feishu",
    accountId: account.accountId,
  });

  await core.channel.reply.dispatchReplyWithBufferedBlockDispatcher({
    ctx: ctxPayload,
    cfg: config,
    dispatcherOptions: {
      deliver: async (payload) => {
        await deliverFeishuReply({
          payload,
          appId,
          appSecret,
          chatId: isGroup ? chatId : senderId,
          receiveIdType: isGroup ? "chat_id" : (account.config.receiveIdType || "open_id"),
          runtime,
          core,
          config,
          accountId: account.accountId,
          statusSink,
          fetcher,
          tableMode,
        });
      },
      onError: (err, info) => {
        runtime.error?.(`[${account.accountId}] Feishu ${info.kind} reply failed: ${String(err)}`);
      },
    },
  });
}

async function deliverFeishuReply(params: {
  payload: { text?: string; mediaUrls?: string[]; mediaUrl?: string };
  appId: string;
  appSecret: string;
  chatId: string;
  receiveIdType: "open_id" | "user_id" | "union_id" | "email" | "chat_id";
  runtime: FeishuRuntimeEnv;
  core: FeishuCoreRuntime;
  config: MoltbotConfig;
  accountId?: string;
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void;
  fetcher?: FeishuFetch;
  tableMode?: MarkdownTableMode;
}): Promise<void> {
  const { payload, appId, appSecret, chatId, receiveIdType, runtime, core, config, accountId, statusSink, fetcher } = params;
  const tableMode = params.tableMode ?? "code";
  const text = core.channel.text.convertMarkdownTables(payload.text ?? "", tableMode);

  // TODO: Handle media uploads when needed

  if (text) {
    const chunkMode = core.channel.text.resolveChunkMode(config, "feishu", accountId);
    const chunks = core.channel.text.chunkMarkdownTextWithMode(
      text,
      FEISHU_TEXT_LIMIT,
      chunkMode,
    );
    for (const chunk of chunks) {
      try {
        const accessToken = await getTenantAccessToken(appId, appSecret, fetcher);
        await sendTextMessage(accessToken, receiveIdType, chatId, chunk, fetcher);
        statusSink?.({ lastOutboundAt: Date.now() });
      } catch (err) {
        runtime.error?.(`Feishu message send failed: ${String(err)}`);
      }
    }
  }
}

export async function monitorFeishuProvider(
  options: FeishuMonitorOptions,
): Promise<FeishuMonitorResult> {
  const {
    appId,
    appSecret,
    account,
    config,
    runtime,
    abortSignal,
    verificationToken,
    encryptKey,
    webhookUrl,
    webhookPath,
    statusSink,
    fetcher,
  } = options;

  const core = getFeishuRuntime();
  const effectiveMediaMaxMb = account.config.mediaMaxMb ?? DEFAULT_MEDIA_MAX_MB;

  let stopped = false;
  const stopHandlers: Array<() => void> = [];

  const stop = () => {
    stopped = true;
    for (const handler of stopHandlers) {
      handler();
    }
  };

  // Feishu requires webhook mode with event subscription
  if (!webhookUrl || !verificationToken) {
    throw new Error("Feishu requires webhookUrl and verificationToken for receiving messages");
  }

  const path = resolveWebhookPath(webhookPath, webhookUrl);
  if (!path) {
    throw new Error("Feishu webhookPath could not be derived");
  }

  const unregister = registerFeishuWebhookTarget({
    appId,
    appSecret,
    account,
    config,
    runtime,
    core,
    path,
    verificationToken,
    encryptKey,
    statusSink: (patch) => statusSink?.(patch),
    mediaMaxMb: effectiveMediaMaxMb,
    fetcher,
  });
  stopHandlers.push(unregister);

  return { stop };
}
