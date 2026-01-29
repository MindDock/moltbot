import { MarkdownConfigSchema } from "clawdbot/plugin-sdk";
import { z } from "zod";

const feishuAccountSchema = z.object({
  name: z.string().optional(),
  enabled: z.boolean().optional(),
  markdown: MarkdownConfigSchema,
  appId: z.string().optional(),
  appSecret: z.string().optional(),
  verificationToken: z.string().optional(),
  encryptKey: z.string().optional(),
  webhookUrl: z.string().optional(),
  webhookPath: z.string().optional(),
  dmPolicy: z.enum(["pairing", "allowlist", "open", "disabled"]).optional(),
  allowFrom: z.array(z.string()).optional(),
  mediaMaxMb: z.number().optional(),
  receiveIdType: z.enum(["open_id", "user_id", "union_id", "email", "chat_id"]).optional(),
  thinkingMessage: z.string().optional(),
});

export const FeishuConfigSchema = feishuAccountSchema.extend({
  accounts: z.object({}).catchall(feishuAccountSchema).optional(),
  defaultAccount: z.string().optional(),
});
