export type WecomAccountConfig = {
  /** Optional display name for this account (used in CLI/UI lists). */
  name?: string;
  /** If false, do not start this WeCom account. Default: true. */
  enabled?: boolean;
  /** Enterprise ID (corpId). */
  corpId?: string;
  /** Application ID (agentId). */
  agentId?: string;
  /** Application Secret. */
  secret?: string;
  /** Token for webhook verification. */
  token?: string;
  /** EncodingAESKey for message encryption/decryption. */
  encodingAesKey?: string;
  /** Webhook callback URL for receiving messages. */
  webhookUrl?: string;
  /** Webhook path for the gateway HTTP server (defaults to webhook URL path). */
  webhookPath?: string;
  /** Direct message access policy (default: pairing). */
  dmPolicy?: "pairing" | "allowlist" | "open" | "disabled";
  /** Allowlist for DM senders (WeCom user IDs). */
  allowFrom?: string[];
  /** Max inbound media size in MB. */
  mediaMaxMb?: number;
};

export type WecomConfig = {
  /** Optional per-account WeCom configuration (multi-account). */
  accounts?: Record<string, WecomAccountConfig>;
  /** Default account ID when multiple accounts are configured. */
  defaultAccount?: string;
} & WecomAccountConfig;

export type WecomTokenSource = "config" | "none";

export type ResolvedWecomAccount = {
  accountId: string;
  name?: string;
  enabled: boolean;
  corpId: string;
  agentId: string;
  secret: string;
  tokenSource: WecomTokenSource;
  config: WecomAccountConfig;
};

export type WecomAccessToken = {
  accessToken: string;
  expiresAt: number;
};
