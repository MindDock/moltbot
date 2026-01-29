import type { IncomingMessage, ServerResponse } from "node:http";
import { XMLParser, XMLBuilder } from "fast-xml-parser";

import type { MoltbotConfig, MarkdownTableMode } from "clawdbot/plugin-sdk";

import type { ResolvedWecomAccount } from "./accounts.js";
import {
  getAccessToken,
  sendTextMessage,
  WecomApiError,
  type WecomFetch,
  type WecomIncomingMessage,
} from "./api.js";
import { decryptMessage, verifyMsgSignature, verifySignature } from "./crypto.js";
import { getWecomRuntime } from "./runtime.js";

export type WecomRuntimeEnv = {
  log?: (message: string) => void;
  error?: (message: string) => void;
};

export type WecomMonitorOptions = {
  corpId: string;
  agentId: string;
  secret: string;
  account: ResolvedWecomAccount;
  config: MoltbotConfig;
  runtime: WecomRuntimeEnv;
  abortSignal: AbortSignal;
  token?: string;
  encodingAesKey?: string;
  webhookUrl?: string;
  webhookPath?: string;
  fetcher?: WecomFetch;
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void;
};

export type WecomMonitorResult = {
  stop: () => void;
};

const WECOM_TEXT_LIMIT = 2048;
const DEFAULT_MEDIA_MAX_MB = 5;

type WecomCoreRuntime = ReturnType<typeof getWecomRuntime>;

function logVerbose(core: WecomCoreRuntime, runtime: WecomRuntimeEnv, message: string): void {
  if (core.logging.shouldLogVerbose()) {
    runtime.log?.(`[wecom] ${message}`);
  }
}

function isSenderAllowed(senderId: string, allowFrom: string[]): boolean {
  if (allowFrom.includes("*")) return true;
  const normalizedSenderId = senderId.toLowerCase();
  return allowFrom.some((entry) => {
    const normalized = entry.toLowerCase().replace(/^(wecom|wxwork):/i, "");
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
  corpId: string;
  agentId: string;
  secret: string;
  account: ResolvedWecomAccount;
  config: MoltbotConfig;
  runtime: WecomRuntimeEnv;
  core: WecomCoreRuntime;
  token: string;
  encodingAesKey: string;
  path: string;
  mediaMaxMb: number;
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void;
  fetcher?: WecomFetch;
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

export function registerWecomWebhookTarget(target: WebhookTarget): () => void {
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

export async function handleWecomWebhookRequest(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<boolean> {
  const url = new URL(req.url ?? "/", "http://localhost");
  const path = normalizeWebhookPath(url.pathname);
  const targets = webhookTargets.get(path);
  if (!targets || targets.length === 0) return false;

  const msgSignature = url.searchParams.get("msg_signature") ?? "";
  const timestamp = url.searchParams.get("timestamp") ?? "";
  const nonce = url.searchParams.get("nonce") ?? "";
  const echostr = url.searchParams.get("echostr") ?? "";

  // URL verification (GET request)
  if (req.method === "GET" && echostr) {
    for (const target of targets) {
      if (verifySignature(target.token, timestamp, nonce, echostr, msgSignature)) {
        // Decrypt echostr and return
        try {
          const decrypted = decryptMessage(echostr, target.encodingAesKey, target.corpId);
          res.statusCode = 200;
          res.setHeader("Content-Type", "text/plain");
          res.end(decrypted);
          return true;
        } catch {
          // try next target
        }
      }
    }
    res.statusCode = 401;
    res.end("verification failed");
    return true;
  }

  if (req.method !== "POST") {
    res.statusCode = 405;
    res.setHeader("Allow", "GET, POST");
    res.end("Method Not Allowed");
    return true;
  }

  const body = await readBody(req, 1024 * 1024);
  if (!body.ok || !body.data) {
    res.statusCode = body.error === "payload too large" ? 413 : 400;
    res.end(body.error ?? "invalid payload");
    return true;
  }

  // Parse XML body
  const parser = new XMLParser();
  let xmlData: Record<string, unknown>;
  try {
    xmlData = parser.parse(body.data) as Record<string, unknown>;
  } catch {
    res.statusCode = 400;
    res.end("invalid XML");
    return true;
  }

  const xmlRoot = (xmlData.xml ?? xmlData) as Record<string, unknown>;
  const encryptedMsg = String(xmlRoot.Encrypt ?? "");

  if (!encryptedMsg) {
    res.statusCode = 400;
    res.end("missing encrypted message");
    return true;
  }

  // Find matching target by verifying signature
  let matchedTarget: WebhookTarget | undefined;
  let decryptedXml: string | undefined;

  for (const target of targets) {
    if (verifyMsgSignature(target.token, timestamp, nonce, encryptedMsg, msgSignature)) {
      try {
        decryptedXml = decryptMessage(encryptedMsg, target.encodingAesKey, target.corpId);
        matchedTarget = target;
        break;
      } catch {
        // try next target
      }
    }
  }

  if (!matchedTarget || !decryptedXml) {
    res.statusCode = 401;
    res.end("unauthorized");
    return true;
  }

  // Parse decrypted message
  let msgData: WecomIncomingMessage;
  try {
    const parsed = parser.parse(decryptedXml) as Record<string, unknown>;
    msgData = (parsed.xml ?? parsed) as WecomIncomingMessage;
  } catch {
    res.statusCode = 400;
    res.end("invalid decrypted XML");
    return true;
  }

  matchedTarget.statusSink?.({ lastInboundAt: Date.now() });
  processMessage(
    msgData,
    matchedTarget.corpId,
    matchedTarget.agentId,
    matchedTarget.secret,
    matchedTarget.account,
    matchedTarget.config,
    matchedTarget.runtime,
    matchedTarget.core,
    matchedTarget.mediaMaxMb,
    matchedTarget.statusSink,
    matchedTarget.fetcher,
  ).catch((err) => {
    matchedTarget.runtime.error?.(`[${matchedTarget.account.accountId}] WeCom webhook failed: ${String(err)}`);
  });

  // Return success response
  res.statusCode = 200;
  res.setHeader("Content-Type", "text/plain");
  res.end("success");
  return true;
}

async function processMessage(
  msg: WecomIncomingMessage,
  corpId: string,
  agentId: string,
  secret: string,
  account: ResolvedWecomAccount,
  config: MoltbotConfig,
  runtime: WecomRuntimeEnv,
  core: WecomCoreRuntime,
  mediaMaxMb: number,
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void,
  fetcher?: WecomFetch,
): Promise<void> {
  const { MsgType, FromUserName, Content, CreateTime, MsgId, AgentID } = msg;

  // Only handle text messages for now
  if (MsgType !== "text" || !Content?.trim()) {
    return;
  }

  const senderId = FromUserName;
  const chatId = senderId; // In WeCom, DM chat ID is the user ID
  const text = Content.trim();

  const dmPolicy = account.config.dmPolicy ?? "pairing";
  const configAllowFrom = account.config.allowFrom ?? [];
  const shouldComputeAuth = core.channel.commands.shouldComputeCommandAuthorized(text, config);
  const storeAllowFrom =
    dmPolicy !== "open" || shouldComputeAuth
      ? await core.channel.pairing.readAllowFromStore("wecom").catch(() => [])
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

  if (dmPolicy === "disabled") {
    logVerbose(core, runtime, `Blocked wecom DM from ${senderId} (dmPolicy=disabled)`);
    return;
  }

  if (dmPolicy !== "open") {
    const allowed = senderAllowedForCommands;

    if (!allowed) {
      if (dmPolicy === "pairing") {
        const { code, created } = await core.channel.pairing.upsertPairingRequest({
          channel: "wecom",
          id: senderId,
          meta: {},
        });

        if (created) {
          logVerbose(core, runtime, `wecom pairing request sender=${senderId}`);
          try {
            const accessToken = await getAccessToken(corpId, secret, fetcher);
            await sendTextMessage(
              accessToken,
              {
                touser: chatId,
                msgtype: "text",
                agentid: Number.parseInt(agentId, 10),
                text: {
                  content: core.channel.pairing.buildPairingReply({
                    channel: "wecom",
                    idLine: `Your WeCom user id: ${senderId}`,
                    code,
                  }),
                },
              },
              fetcher,
            );
            statusSink?.({ lastOutboundAt: Date.now() });
          } catch (err) {
            logVerbose(
              core,
              runtime,
              `wecom pairing reply failed for ${senderId}: ${String(err)}`,
            );
          }
        }
      } else {
        logVerbose(
          core,
          runtime,
          `Blocked unauthorized wecom sender ${senderId} (dmPolicy=${dmPolicy})`,
        );
      }
      return;
    }
  }

  const route = core.channel.routing.resolveAgentRoute({
    cfg: config,
    channel: "wecom",
    accountId: account.accountId,
    peer: {
      kind: "dm",
      id: chatId,
    },
  });

  const fromLabel = `user:${senderId}`;
  const storePath = core.channel.session.resolveStorePath(config.session?.store, {
    agentId: route.agentId,
  });
  const envelopeOptions = core.channel.reply.resolveEnvelopeFormatOptions(config);
  const previousTimestamp = core.channel.session.readSessionUpdatedAt({
    storePath,
    sessionKey: route.sessionKey,
  });
  const body = core.channel.reply.formatAgentEnvelope({
    channel: "WeCom",
    from: fromLabel,
    timestamp: CreateTime ? CreateTime * 1000 : undefined,
    previousTimestamp,
    envelope: envelopeOptions,
    body: text,
  });

  const ctxPayload = core.channel.reply.finalizeInboundContext({
    Body: body,
    RawBody: text,
    CommandBody: text,
    From: `wecom:${senderId}`,
    To: `wecom:${chatId}`,
    SessionKey: route.sessionKey,
    AccountId: route.accountId,
    ChatType: "direct",
    ConversationLabel: fromLabel,
    SenderName: undefined,
    SenderId: senderId,
    CommandAuthorized: commandAuthorized,
    Provider: "wecom",
    Surface: "wecom",
    MessageSid: MsgId,
    OriginatingChannel: "wecom",
    OriginatingTo: `wecom:${chatId}`,
  });

  await core.channel.session.recordInboundSession({
    storePath,
    sessionKey: ctxPayload.SessionKey ?? route.sessionKey,
    ctx: ctxPayload,
    onRecordError: (err) => {
      runtime.error?.(`wecom: failed updating session meta: ${String(err)}`);
    },
  });

  const tableMode = core.channel.text.resolveMarkdownTableMode({
    cfg: config,
    channel: "wecom",
    accountId: account.accountId,
  });

  await core.channel.reply.dispatchReplyWithBufferedBlockDispatcher({
    ctx: ctxPayload,
    cfg: config,
    dispatcherOptions: {
      deliver: async (payload) => {
        await deliverWecomReply({
          payload,
          corpId,
          agentId,
          secret,
          chatId,
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
        runtime.error?.(`[${account.accountId}] WeCom ${info.kind} reply failed: ${String(err)}`);
      },
    },
  });
}

async function deliverWecomReply(params: {
  payload: { text?: string; mediaUrls?: string[]; mediaUrl?: string };
  corpId: string;
  agentId: string;
  secret: string;
  chatId: string;
  runtime: WecomRuntimeEnv;
  core: WecomCoreRuntime;
  config: MoltbotConfig;
  accountId?: string;
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void;
  fetcher?: WecomFetch;
  tableMode?: MarkdownTableMode;
}): Promise<void> {
  const { payload, corpId, agentId, secret, chatId, runtime, core, config, accountId, statusSink, fetcher } = params;
  const tableMode = params.tableMode ?? "code";
  const text = core.channel.text.convertMarkdownTables(payload.text ?? "", tableMode);

  // TODO: Handle media uploads when needed

  if (text) {
    const chunkMode = core.channel.text.resolveChunkMode(config, "wecom", accountId);
    const chunks = core.channel.text.chunkMarkdownTextWithMode(
      text,
      WECOM_TEXT_LIMIT,
      chunkMode,
    );
    for (const chunk of chunks) {
      try {
        const accessToken = await getAccessToken(corpId, secret, fetcher);
        await sendTextMessage(
          accessToken,
          {
            touser: chatId,
            msgtype: "text",
            agentid: Number.parseInt(agentId, 10),
            text: { content: chunk },
          },
          fetcher,
        );
        statusSink?.({ lastOutboundAt: Date.now() });
      } catch (err) {
        runtime.error?.(`WeCom message send failed: ${String(err)}`);
      }
    }
  }
}

export async function monitorWecomProvider(
  options: WecomMonitorOptions,
): Promise<WecomMonitorResult> {
  const {
    corpId,
    agentId,
    secret,
    account,
    config,
    runtime,
    abortSignal,
    token,
    encodingAesKey,
    webhookUrl,
    webhookPath,
    statusSink,
    fetcher,
  } = options;

  const core = getWecomRuntime();
  const effectiveMediaMaxMb = account.config.mediaMaxMb ?? DEFAULT_MEDIA_MAX_MB;

  let stopped = false;
  const stopHandlers: Array<() => void> = [];

  const stop = () => {
    stopped = true;
    for (const handler of stopHandlers) {
      handler();
    }
  };

  // WeCom only supports webhook mode
  if (!webhookUrl || !token || !encodingAesKey) {
    throw new Error("WeCom requires webhookUrl, token, and encodingAesKey for receiving messages");
  }

  const path = resolveWebhookPath(webhookPath, webhookUrl);
  if (!path) {
    throw new Error("WeCom webhookPath could not be derived");
  }

  const unregister = registerWecomWebhookTarget({
    corpId,
    agentId,
    secret,
    account,
    config,
    runtime,
    core,
    path,
    token,
    encodingAesKey,
    statusSink: (patch) => statusSink?.(patch),
    mediaMaxMb: effectiveMediaMaxMb,
    fetcher,
  });
  stopHandlers.push(unregister);

  return { stop };
}
