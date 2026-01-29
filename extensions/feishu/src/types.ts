export type FeishuAccountConfig = {
  /** Optional display name for this account (used in CLI/UI lists). */
  name?: string;
  /** If false, do not start this Feishu account. Default: true. */
  enabled?: boolean;
  /** Application ID (app_id). */
  appId?: string;
  /** Application Secret (app_secret). */
  appSecret?: string;
  /** Verification Token for event subscription. */
  verificationToken?: string;
  /** Encrypt Key for event decryption (optional). */
  encryptKey?: string;
  /** Webhook callback URL for receiving events. */
  webhookUrl?: string;
  /** Webhook path for the gateway HTTP server (defaults to webhook URL path). */
  webhookPath?: string;
  /** Direct message access policy (default: pairing). */
  dmPolicy?: "pairing" | "allowlist" | "open" | "disabled";
  /** Allowlist for DM senders (Feishu user IDs, open_ids, or union_ids). */
  allowFrom?: string[];
  /** Max inbound media size in MB. */
  mediaMaxMb?: number;
  /** Receive ID type for sending messages (default: open_id). */
  receiveIdType?: "open_id" | "user_id" | "union_id" | "email" | "chat_id";
  /** Message shown while AI is thinking. Set to empty string to disable. */
  thinkingMessage?: string;
};

export type FeishuConfig = {
  /** Optional per-account Feishu configuration (multi-account). */
  accounts?: Record<string, FeishuAccountConfig>;
  /** Default account ID when multiple accounts are configured. */
  defaultAccount?: string;
} & FeishuAccountConfig;

export type FeishuTokenSource = "config" | "none";

export type ResolvedFeishuAccount = {
  accountId: string;
  name?: string;
  enabled: boolean;
  appId: string;
  appSecret: string;
  tokenSource: FeishuTokenSource;
  config: FeishuAccountConfig;
};

export type FeishuAccessToken = {
  tenantAccessToken: string;
  expiresAt: number;
};
